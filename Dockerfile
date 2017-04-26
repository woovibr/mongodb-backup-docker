FROM debian:jessie-slim

ENV MONGO_MAJOR 3.4
ENV MONGO_VERSION 3.4.4

# MongoDB Enviroment
# MongoDB Source Database
ENV MONGO_DBNAME=my-db
ENV MONGO_HOST=localhost

# S3 bucket that the backup will be stored
ENV AWS_TARGET_BUCKET=s3-bucket-name
ENV AWS_ACCESS_KEY_ID=AAAAAAA
ENV AWS_SECRET_ACCESS_KEY=BBBBBB

COPY backup-mongodb-to-s3.sh /scripts/

# Setup links to mongoDB client
RUN echo "deb http://repo.mongodb.org/apt/debian jessie/mongodb-org/$MONGO_MAJOR main" > /etc/apt/sources.list.d/mongodb-org.list
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6

# Preparate update
RUN apt-get update

# Install Mongodump from MongoDB-org-tools pacakge
RUN apt-get install -y mongodb-org-tools=$MONGO_VERSION

# Install the AWS Cli
RUN apt-get install -y awscli

#Cleanup
RUN rm -rf /var/lib/apt/lists/*

#Execute Backup
CMD ["/bin/sh", "/scripts/backup-mongodb-to-s3.sh"]