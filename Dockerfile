FROM mongo:4.0.4-xenial

# Preparate update
RUN apt-get update
RUN apt-get install -y awscli

COPY backup-mongodb-to-s3.sh /scripts/

# MongoDB Source Database
ENV MONGO_URI="mongodb://localhost/test"

# S3 bucket that the backup will be stored
ENV AWS_TARGET_BUCKET="s3://mybucket/folder/"
ENV AWS_ACCESS_KEY_ID=AAAAAAA
ENV AWS_SECRET_ACCESS_KEY=BBBBBB

#Execute Backup
CMD ["/bin/sh", "/scripts/backup-mongodb-to-s3.sh"]