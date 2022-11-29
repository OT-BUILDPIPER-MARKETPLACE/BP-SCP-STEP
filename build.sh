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



case ${ACTION} in
    LOCAL_TO_REMOTE)
        logInfoMessage "Have to do copy operation from local system to remote"
        if [ `isStrNonEmpty $LOCAL_FILE_PATH` -ne 0 ]
        then
            TASK_STATUS=1
            logErrorMessage "Local file path not provided please check"
        elif [ `isStrNonEmpty $TARGET_SERVER_ALIAS` -ne 0 ]
        then
            TASK_STATUS=1
            logErrorMessage "Target server not provided please check"
        elif [ `isStrNonEmpty $TARGET_FILE_PATH` -ne 0 ]
        then
            TASK_STATUS=1
            logErrorMessage "Target file path provided please check"
        fi   
        logInfoMessage "Received below arguments"
        logInfoMessage "Action to be performed: ${ACTION}"
        logInfoMessage "Local file path: ${LOCAL_FILE_PATH}"
        logInfoMessage "Target server alias: ${TARGET_SERVER_ALIAS}"
        logInfoMessage "Target file path: ${TARGET_FILE_PATH}"
        logInfoMessage "Command to be executed: scp ${LOCAL_FILE_PATH} ${TARGET_SERVER_ALIAS}:${TARGET_FILE_PATH}"
        scp ${LOCAL_FILE_PATH} ${TARGET_SERVER_ALIAS}:${TARGET_FILE_PATH}
    ;;
    REMOTE_TO_LOCAL)
        logInfoMessage "Have to do copy operation from remote system to local"
    ;;
    REMOTE_TO_REMOTE)
        logInfoMessage "Have to do copy operation from remote system to remote"
    ;;
esac

saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}