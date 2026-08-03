# mongodb-backup-docker
MongoDB Backup Docker

This Image is intended to be used in a Kubernetes environment to automatically backup MongoDB to a S3 bucket.

The dump is **streamed** straight to S3 (`mongodump --archive | aws s3 cp -`). Nothing is
staged on local disk, so the container needs no volume and no meaningful
ephemeral-storage budget, and the upload overlaps with the dump instead of waiting
for it to finish.

# Available at
https://hub.docker.com/r/entria/mongodb-backup-docker

# Configuration

| Variable | Required | Default | Notes |
| --- | --- | --- | --- |
| `MONGO_URI` | yes | — | Source database. Include `readPreference=secondaryPreferred` to keep load off the primary. |
| `AWS_TARGET_BUCKET` | yes | — | e.g. `s3://my-bucket/my-db/backup-daily`. A trailing slash is fine. |
| `AWS_ACCESS_KEY_ID` | yes | — | |
| `AWS_SECRET_ACCESS_KEY` | yes | — | |
| `BACKUP_EXPECTED_SIZE` | no | `250000000000` (250GB) | Upper bound on the archive size, in bytes. |
| `BACKUP_PARALLEL_COLLECTIONS` | no | `4` | `mongodump --numParallelCollections`. |

The object lands at `$AWS_TARGET_BUCKET/YYYY/MM/DD/YYYY-MM-DD-HHhMMsSS.tar.gz`, with a
success marker alongside it at `<archive>.ok`.

`MONGO_URI` is redacted before being logged, since container stdout usually ends up in
a log store that outlives and out-reaches the secret itself.

## `BACKUP_EXPECTED_SIZE`

This is not a tuning knob you can ignore on a large database. When awscli uploads
from stdin it cannot know the size ahead of time, so it falls back to 8MB multipart
chunks — and S3 caps a multipart upload at 10000 parts. That puts a hard ceiling of
roughly **80GB** on an unsized stream, and the upload fails partway through.

Passing a size makes awscli scale the part size to `size/10000` instead.
Overshooting only costs you larger parts; undershooting fails the upload. Keep this
comfortably above the largest archive you expect.

Memory stays bounded regardless: awscli holds at most
`max_in_memory_upload_chunks` (10) chunks in flight and backpressures the pipe, so
at a 250GB expected size that is ~250MB of buffered data, not the whole archive.

## `BACKUP_PARALLEL_COLLECTIONS`

With `--archive --gzip`, mongodump compresses each collection's stream in-process,
so this controls gzip parallelism as much as dump parallelism — it is what makes the
job CPU-bound. **Set the pod's CPU limit at or above this value**, or the container
will simply be throttled; at 200m CPU a ~100GB dump was throttled in 98% of
scheduling periods and took days.

A single collection is still dumped by one worker, so the floor on wall-clock time
is however long the largest collection takes.

# Failure handling: the `.ok` marker

**A backup is only valid if its `<archive>.ok` marker object exists. Restore tooling
must check for the marker and refuse an unmarked archive.**

This matters because a `mongodump` that dies mid-dump closes the pipe cleanly, so
awscli sees EOF and finalizes a *truncated* archive as a perfectly successful
multipart upload. The bad object is indistinguishable from a good one by size or
status alone.

Deleting the bad object is not a reliable fix. Backup credentials are normally
write-only — no `s3:DeleteObject`, no `s3:ListBucket` — precisely so a compromised
backup key cannot destroy backup history. Under that policy the archive can be
neither deleted nor renamed (a rename is a copy plus a delete). The
production credential for this image is write-only, and the delete is denied.

So success is signalled out-of-band: the marker is written only after both
`mongodump` and `aws s3 cp` have exited 0 (checked via `PIPESTATUS`). No marker means
do not trust the archive. This is strictly stronger than delete-on-failure because it
also covers the cases no cleanup path can handle — `SIGKILL`, OOM kill, node death.

A best-effort delete is still attempted on failure for setups that do grant
`s3:DeleteObject`, but its failure is not treated as fatal. If the archive uploads
but the marker cannot be written, the run exits non-zero rather than reporting a
success nobody is allowed to trust.

`SIGTERM` — what Kubernetes sends when `activeDeadlineSeconds` fires or the pod is
evicted — is handled too, and it needs care. Kubernetes signals PID 1 only, and bash
defers trap handlers until the current foreground command returns, so a foreground
pipeline would ignore the signal until the grace period expired and `SIGKILL` landed.
The script runs the pipeline as a background job under `set -m` and signals the whole
process group, so it aborts immediately instead of burning the grace period.

Add an S3 lifecycle rule to expire incomplete multipart uploads: a denied
`AbortMultipartUpload` leaves orphaned parts accruing storage cost.

# Recommended CronJob shape

```yaml
spec:
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 300
  jobTemplate:
    spec:
      # kill a hung backup instead of letting it block future schedules forever
      activeDeadlineSeconds: 43200
      template:
        spec:
          containers:
            - name: mongodbbackups3
              image: entria/mongodb-backup-docker:latest
              env:
                - name: BACKUP_PARALLEL_COLLECTIONS
                  value: "8"
              envFrom:
                - secretRef:
                    name: mongodb-backup-secrets
              resources:
                requests:
                  cpu: "4"
                  memory: 2Gi
                  ephemeral-storage: 256Mi
                limits:
                  # at or above BACKUP_PARALLEL_COLLECTIONS
                  cpu: "8"
                  memory: 6Gi
                  ephemeral-storage: 1Gi
          restartPolicy: Never
```

# Caveats

`mongodump` is not point-in-time consistent. Over a multi-hour dump, collections
written at the start and end of the run are mutually inconsistent. `--oplog` +
`mongorestore --oplogReplay` fixes this, but `--oplog` cannot be combined with a
database-scoped URI — it requires a full-instance dump. For a database where that
matters, consider Percona Backup for MongoDB or filesystem snapshots instead.

# upload

Pushed automatically by `.github/workflows/publish-to-docker-hub.yaml` on release.

Manually:

```
docker login
docker build . -t entria/mongodb-backup-docker
docker push entria/mongodb-backup-docker
```

# Powered by
[Woovi](https://woovi.com)
[OpenPix](https://openpix.om)
[Entria](https://entria.com.br)

# Inspired by
https://gist.github.com/eladnava/96bd9771cd2e01fb4427230563991c8d
