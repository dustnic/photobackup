#!/bin/bash
while getopts "p:b:s:" opt; do
  case $opt in
    p) SYNC_PATH="$OPTARG"
    ;;
    b) BUCKET_NAME="$OPTARG"                                                                                                                                                                 
    ;;
    s) SNS_TOPIC="$OPTARG"                                                                                                                                                                 
    ;;
    \?) echo "Invalid option -$OPTARG" >&2                                                                                                                                                   
    ;;
  esac
done

#=================================================#
# Set variables
#=================================================#
SCRIPT_NAME=$(basename $0)
LOCKFOLDER="/tmp/run"
LOCK="${LOCKFOLDER}/${SCRIPT_NAME}"
COUNT_FILE="/tmp/photobackup-count.file"

# Export specific AWS CLI profile
export AWS_PROFILE=photobackup

# Create lockfolder if required
mkdir -p $LOCKFOLDER
# Clear countfile
rm -rf "$COUNT_FILE"

#=================================================#
# Notify that backup is starting
#=================================================#
message="Starting S3 backup of $SYNC_PATH on $BUCKET_NAME - (pid:$$)" 
logger -i -t $SCRIPT_NAME $message
aws sns publish --subject "$SCRIPT_NAME - Notification" --topic-arn $SNS_TOPIC --message "$message" > /dev/null

#=================================================#
# Execute backup
#=================================================#
(
flock -n 9 || exit 2
  aws s3 sync $SYNC_PATH s3://$BUCKET_NAME --no-progress --storage-class REDUCED_REDUNDANCY --exclude "*/.*" --exclude ".*" 2>&1 | tee -a $COUNT_FILE | logger -s -i -t $SCRIPT_NAME
) 9>$LOCK

#=================================================#
# A lock file was found - aborting
#=================================================#
if [ $? -eq 2 ]; then
  message="Backup operation aborted - lock file found"
  logger -s -i -t $SCRIPT_NAME $message
  aws sns publish --subject "$SCRIPT_NAME - Error" --topic-arn $SNS_TOPIC --message "$message" > /dev/null
fi

SUCCESS_FILE_COUNT=`grep 'upload:' $COUNT_FILE | wc -l `
FAILED_FILE_COUNT=`grep 'upload failed:' $COUNT_FILE | wc -l `
message=$(printf "%s\n%s\n%s" "Completed S3 backup of $SYNC_PATH on $BUCKET_NAME (pid:$$)." "Total files backed up: $SUCCESS_FILE_COUNT" "Total files failed: $FAILED_FILE_COUNT")
logger -i -t $SCRIPT_NAME $message
aws sns publish --subject "$SCRIPT_NAME - Notification" --topic-arn $SNS_TOPIC --message "$message" > /dev/null
