#!/usr/bin/env bash
#
# Dump a MongoDB database straight into S3, without staging the archive on disk.
#
# The previous version wrote the whole archive to /volume/tmp first, which on
# Kubernetes means the node's overlay filesystem -- ~70-100GB for woovi-prd, and
# the upload could not start until the dump had finished. Streaming removes the
# write entirely and overlaps the upload with the dump.

set -uo pipefail
# job control, so the backup pipeline below gets its own process group and we can
# signal mongodump and aws together. see the TERM trap.
set -m

: "${MONGO_URI:?MONGO_URI is required}"
: "${AWS_TARGET_BUCKET:?AWS_TARGET_BUCKET is required}"

# awscli reads stdin in multipart_chunksize pieces (8MB by default) and S3 caps a
# multipart upload at 10000 parts, so an unsized stream dies partway through
# anything over ~80GB. Passing a size makes awscli scale the part size to
# size/10000 instead. Overshooting only costs bigger parts, undershooting fails
# the upload, so keep this comfortably above the largest archive you expect.
EXPECTED_SIZE="${BACKUP_EXPECTED_SIZE:-250000000000}"

# mongodump gzips each collection's stream in-process, so this is the compression
# parallelism as much as the dump parallelism -- it is what makes the job
# CPU-bound. Keep the pod's CPU limit at or above this or it will just throttle.
# A single collection is still dumped by one worker, so the floor on wall-clock is
# the largest collection.
PARALLEL_COLLECTIONS="${BACKUP_PARALLEL_COLLECTIONS:-4}"

FILENAME="$(date +%Y-%m-%d-%Hh%Ms%S).tar.gz"
TIMEPATH="$(date +%Y/%m/%d)"
DEST="${AWS_TARGET_BUCKET%/}/${TIMEPATH}/${FILENAME}"
# Presence of this marker is what makes a backup trustworthy -- see below.
MARKER="${DEST}.ok"

# Never log MONGO_URI directly: it carries the password, and container stdout is
# usually shipped to a log store (Loki, CloudWatch, ...) where it persists far longer
# and is readable by far more people than the secret itself. The previous version of
# this script echoed the raw URI on every run.
redact_uri() {
  sed -u -E 's#(mongodb(\+srv)?://)[^/?[:space:]]*@#\1***:***@#g'
}

MONGO_URI_SAFE="$(printf '%s' "${MONGO_URI}" | redact_uri)"

# A mongodump that dies mid-dump closes the pipe cleanly, so awscli sees EOF and
# finalizes a *truncated* archive as a successful multipart upload. There is no way
# to make the archive object itself trustworthy after the fact: backup credentials
# are typically write-only (no s3:DeleteObject, no s3:ListBucket) so that a
# compromised backup key cannot destroy history, which means we can neither delete
# the bad object nor rename it (a rename is a copy plus a delete).
#
# So success is signalled out-of-band instead: on a clean run we write a small
# marker object next to the archive. An archive with no marker must be treated as
# unusable. This is stronger than deleting on failure, because it also covers the
# cases no cleanup path can ever handle -- SIGKILL, OOM kill, node death.
#
# RESTORE TOOLING MUST CHECK FOR THE MARKER. Do not restore an unmarked archive.
write_success_marker() {
  echo "mongodump=0 aws=0 uri=${MONGO_URI_SAFE} archive=${FILENAME}" \
    | aws s3 cp - "${MARKER}"
}

# Best-effort only, and expected to fail with AccessDenied under a write-only
# policy. Attempted anyway because it does help where the credential allows it.
# The missing marker, not this, is the authoritative failure signal.
remove_partial_object() {
  echo "no success marker will be written for ${DEST}"
  echo "attempting best-effort delete of the partial object (may be denied)"
  aws s3 rm "${DEST}" || echo "could not delete partial object; it is unmarked and must be ignored"
}

run_backup() {
  mongodump \
    --uri "${MONGO_URI}" \
    --archive \
    --gzip \
    --numParallelCollections="${PARALLEL_COLLECTIONS}" \
    2> >(redact_uri >&2) \
    | aws s3 cp - "${DEST}" --expected-size "${EXPECTED_SIZE}"

  local status=("${PIPESTATUS[@]}")
  if [ "${status[0]}" -ne 0 ]; then
    echo "mongodump failed (exit ${status[0]})" >&2
    return 1
  fi
  if [ "${status[1]}" -ne 0 ]; then
    echo "aws s3 cp failed (exit ${status[1]})" >&2
    return 1
  fi
}

echo "Streaming ${MONGO_URI_SAFE} to ${DEST}"

# Run the pipeline as a background job rather than in the foreground: bash defers
# trap handlers until the current foreground command returns, so a foreground
# pipeline would swallow SIGTERM until it finished -- which is never, since
# Kubernetes signals PID 1 only and mongodump/aws would keep running until the
# grace period expired and SIGKILL landed. That is exactly the
# activeDeadlineSeconds path, and it would leave a truncated object behind.
run_backup &
BACKUP_PGID=$!

on_signal() {
  echo "signal received, aborting backup"
  # negative pid signals the job's whole process group (mongodump + aws), which
  # `set -m` above gave us.
  kill -TERM -"${BACKUP_PGID}" 2>/dev/null
  wait "${BACKUP_PGID}"
  remove_partial_object
  exit 143
}
trap on_signal TERM INT

wait "${BACKUP_PGID}"
BACKUP_STATUS=$?
trap - TERM INT

if [ "${BACKUP_STATUS}" -ne 0 ]; then
  remove_partial_object
  exit 1
fi

if ! write_success_marker; then
  # The archive is fine but unmarked, so restore tooling will refuse it. Fail loudly
  # rather than report a success nobody is allowed to trust.
  echo "archive uploaded but success marker failed to write; treat this run as failed" >&2
  exit 1
fi

echo "Backup available at ${DEST} (marker ${MARKER})"
