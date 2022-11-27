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

case ${ACTION} in
    LOCAL_TO_REMOTE)
        logInfoMessage "Have to do copy operation from local system to remote"
    ;;
    REMOTE_TO_LOCAL)
        logInfoMessage "Have to do copy operation from remote system to local"
    ;;
    REMOTE_TO_REMOTE)
        logInfoMessage "Have to do copy operation from remote system to remote"
    ;;

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}