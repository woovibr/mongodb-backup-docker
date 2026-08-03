FROM mongo:7.0.5

RUN apt-get update \
  && apt-get install -y --no-install-recommends awscli \
  && rm -rf /var/lib/apt/lists/*

COPY backup-mongodb-to-s3.sh /scripts/
RUN chmod +x /scripts/backup-mongodb-to-s3.sh

# MONGO_URI and AWS_TARGET_BUCKET are required at runtime and deliberately have no
# default. The old placeholders ("mongodb://localhost/test", "s3://mybucket/folder/")
# meant a misconfigured pod would quietly dump the wrong database instead of
# failing, since an ENV default satisfies the script's ${VAR:?} guards.

# Upper bound on the archive size, used to pick the S3 multipart part size.
# See the comments in backup-mongodb-to-s3.sh -- this must not be under the real
# archive size or the upload fails past 10000 parts.
ENV BACKUP_EXPECTED_SIZE="250000000000"

# mongodump --numParallelCollections. Also controls gzip parallelism, so the pod's
# CPU limit should be at least this.
ENV BACKUP_PARALLEL_COLLECTIONS="4"

# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY are deliberately not defaulted here:
# placeholder values turn "no credentials supplied" into a confusing auth error.

# Execute Backup
CMD ["/bin/bash", "/scripts/backup-mongodb-to-s3.sh"]
