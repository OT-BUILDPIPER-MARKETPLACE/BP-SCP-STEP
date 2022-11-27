#!/bin/bash

source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/aws-functions.sh

sleep  $SLEEP_DURATION

TASK_STATUS=0

if [ `isStrNonEmpty $ACTION` -ne 0 ]
then
    TASK_STATUS=1
    logErrorMessage "Action details are not provided please check"
fi    

logInfoMessage "I'll perform [action: ${ACTION}]" 

logInfoMessage "Received below arguments"
logInfoMessage "Action to be performed: ${ACTION}"

ssh ${HOST} "sudo systemctl $ACTION ${PROCESS}"

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}