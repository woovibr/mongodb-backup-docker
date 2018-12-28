#From https://gist.github.com/eladnava/96bd9771cd2e01fb4427230563991c8d
#!/bin/sh

# Current time
TIME=`/bin/date +%Y-%m-%d-%Hh%Ms%S`

# Backup directory
DEST=/volume/tmp

# Create backup dir (-p to avoid warning if already exists)
/bin/mkdir -p $DEST

# Tar file of backup directory
TAR=$DEST/../$TIME.tar

# Log
echo "Backing up $MONGO_URI to $AWS_TARGET_BUCKET on $TIME";

# Dump from mongodb host into backup directory
/usr/bin/mongodump --uri $MONGO_URI -o $DEST

# Create tar of backup directory
/bin/tar cvf $TAR -C $DEST .

# Upload tar to s3
/usr/bin/aws s3 cp $TAR $AWS_TARGET_BUCKET

# Remove tar file locally
/bin/rm -f $TAR

## Remove backup directory
/bin/rm -rf $DEST

# All done
echo "Backup available at $AWS_TARGET_BUCKET/$TIME.tar"