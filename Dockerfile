FROM debian:jessie-slim

ENV MONGO_MAJOR 3.4
ENV MONGO_VERSION 3.4.4

# MongoDB Enviroment
# MongoDB Source Database
ENV MONGO_DBNAME=my-db
ENV MONGO_HOST=mongo

# S3 bucket name that backup will be stored
ENV AWS_BUCKET=s3-bucket-name
ENV AWS_KEY=AAAAAAA
ENV AWS_KEY_SECRET=BBBBBB

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
CMD backup-mongodb-to-sr.sh