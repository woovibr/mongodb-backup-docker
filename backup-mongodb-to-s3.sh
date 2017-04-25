#From https://gist.github.com/eladnava/96bd9771cd2e01fb4427230563991c8d
#!/bin/sh

# Make sure to:
# 1) Name this file `backup.sh` and place it in /home/ubuntu
# 2) Run sudo apt-get install awscli to install the AWSCLI
# 3) Run aws configure (enter s3-authorized IAM user and specify region)
# 4) Fill in DB host + name
# 5) Create S3 bucket for the backups and fill it in below (set a lifecycle rule to expire files older than X days in the bucket)
# 6) Run chmod +x backup.sh
# 7) Test it out via ./backup.sh
# 8) Set up a daily backup at midnight via `crontab -e`:
#    0 0 * * * /home/ubuntu/backup.sh > /home/ubuntu/backup.log


# Current time
TIME=`/bin/date +%Y-%m-%d-%Hh%Ms%S`

# Backup directory
DEST=/volume/tmp

# Create backup dir (-p to avoid warning if already exists)
/bin/mkdir -p $DEST

# Tar file of backup directory
TAR=$DEST/../$TIME.tar


# Log
echo "Backing up $MONGO_HOST/MONGO_DBNAME to s3://$BUCKET/ on $TIME";

# Dump from mongodb host into backup directory
/usr/bin/mongodump -h $MONGO_HOST -d $MONGO_DBNAME -o $DEST

# Create tar of backup directory
/bin/tar cvf $TAR -C $DEST .

# Upload tar to s3
/usr/bin/aws s3 cp $TAR s3://$AWS_BUCKET/

# Remove tar file locally
/bin/rm -f $TAR

## Remove backup directory
#/bin/rm -rf $DEST

# All done
echo "Backup available at https://s3.amazonaws.com/$AWS_BUCKET/$TIME.tar"