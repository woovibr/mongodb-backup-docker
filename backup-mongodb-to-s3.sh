#!/bin/sh

# Current time, this will be the file name
FILENAME=`/bin/date +%Y-%m-%d-%Hh%Ms%S`.gz
# Separate Uploads using date as folders
TIMEPATH=`/bin/date +"%Y/%m/%d"` 

# temp directory
DEST=/volume/tmp
# Create backup dir (-p to avoid warning if already exists)
/bin/mkdir -p $DEST

FILENAME_FULL=$DEST/$FILENAME

# Log
echo "Backing up $MONGO_URI to $AWS_TARGET_BUCKET/$TIMEPATH on $FILENAME";

# Dump from mongodb host into backup directory
/usr/bin/mongodump --uri $MONGO_URI --archive=$FILENAME_FULL --gzip

# Upload tar to s3
/usr/bin/aws s3 cp $FILENAME_FULL $AWS_TARGET_BUCKET/$TIMEPATH/$FILENAME

# Remove tar file locally
/bin/rm -f $FILENAME_FULL

# All done
echo "Backup available at $AWS_TARGET_BUCKET/$TIMEPATH/$FILENAME"