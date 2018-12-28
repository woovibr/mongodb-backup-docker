#From https://gist.github.com/eladnava/96bd9771cd2e01fb4427230563991c8d
#!/bin/sh

# Current time, this will be the file name
FILENAME=`/bin/date +%Y-%m-%d-%Hh%Ms%S`
# Separate Uploads using date as folders
TIMEPATH=`/bin/date +"%Y/%m/%d"` 

# Backup directory
DEST=/volume/tmp

# Create backup dir (-p to avoid warning if already exists)
/bin/mkdir -p $DEST

# Tar file of backup directory
TAR=$DEST/../$FILENAME.tar

# Log
echo "Backing up $MONGO_URI to $AWS_TARGET_BUCKET/$TIMEPATH on $FILENAME";

# Dump from mongodb host into backup directory
/usr/bin/mongodump --uri $MONGO_URI -o $DEST

# Create tar of backup directory
/bin/tar cvf $TAR -C $DEST .

# Upload tar to s3
/usr/bin/aws s3 cp $TAR $AWS_TARGET_BUCKET/$TIMEPATH/$FILENAME.tar

# Remove tar file locally
/bin/rm -f $TAR

## Remove backup directory
/bin/rm -rf $DEST

# All done
echo "Backup available at $AWS_TARGET_BUCKET/$TIMEPATH/$FILENAME.tar"