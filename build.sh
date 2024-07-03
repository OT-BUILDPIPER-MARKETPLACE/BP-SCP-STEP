#!/bin/bash

source functions.sh
source log-functions.sh
source str-functions.sh
source file-functions.sh
source aws-functions.sh

CODEBASE_LOCATION="${WORKSPACE}"/"${CODEBASE_DIR}"
logInfoMessage "I'll do processing at [$CODEBASE_LOCATION]"
# sleep  $SLEEP_DURATION

cd "${CODEBASE_LOCATION}"

TASK_STATUS=0

logInfoMessage "I'll perform [action: ${ACTION}]" 

ENCRYPTED_CREDENTIAL_SSH_KEY=$(getEncryptedCredential "$CREDENTIAL_MANAGEMENT" "$SSH_CREDENTIAL_NAME.CREDENTIAL_ACCESS_TOKEN_OR_KEY")
CREDENTIAL_SSH_KEY=$(getDecryptedCredential "$FERNET_KEY" "$ENCRYPTED_CREDENTIAL_SSH_KEY")

if [ ! -f "key.pem" ]; then
   echo "$CREDENTIAL_SSH_KEY" > key.pem && chmod 400 key.pem
fi

if [ -z "$ACTION" ] || [ -z "$SSH_USERNAME" ] || [ -z "$SSH_IP" ] || [ -z "$SSH_PORT" ]; then
   [ -z "$ACTION" ] && logErrorMessage "ACTION is not set. Please set the INSTANCE_ID environment variable."
   [ -z "$SSH_USERNAME" ] && logErrorMessage "SSH_USERNAME is not set. Please set the INSTANCE_ID environment variable."
   [ -z "$SSH_IP" ] && logErrorMessage "SSH_IP is not set. Please set the SSH_IP environment variable."
   [ -z "$SSH_PORT" ] && logErrorMessage "SSH_PORT is not set. Please set the SSH_IP environment variable."
   exit 1
fi

SSH_OPTIONS="-i key.pem -P $SSH_PORT $PROXY_OPTION -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
REMOTE_SERVER="$SSH_USERNAME@$SSH_IP"

case ${ACTION} in
    LOCAL_TO_REMOTE)
        logInfoMessage "Have to do copy operation from local system to remote"
        if [ `isStrNonEmpty $LOCAL_FILE_PATH` -ne 0 ]
        then
            TASK_STATUS=1
            logErrorMessage "Local file path not provided please check"
        elif [ `isStrNonEmpty $REMOTE_SERVER` -ne 0 ]
        then
            TASK_STATUS=1
            logErrorMessage "Remote server not provided please check"
        elif [ `isStrNonEmpty $REMOTE_TARGET_PATH` -ne 0 ]
        then
            TASK_STATUS=1
            logErrorMessage "Remote file path provided please check"
        fi   
        logInfoMessage "Received below arguments"
        logInfoMessage "Action to be performed: ${ACTION}"
        logInfoMessage "Local file path: ${LOCAL_FILE_PATH}"
        logInfoMessage "Remote server: ${REMOTE_SERVER}"
        logInfoMessage "Remote file path: ${REMOTE_TARGET_PATH}"
        logInfoMessage "Command to be executed: scp -rv $SSH_OPTIONS ${LOCAL_FILE_PATH} ${REMOTE_SERVER}:${REMOTE_TARGET_PATH}"
        scp -rv $SSH_OPTIONS ${LOCAL_FILE_PATH} ${REMOTE_SERVER}:${REMOTE_TARGET_PATH} 2>&1
        SCP_EXIT_CODE=$?

        if [ $SCP_EXIT_CODE -ne 0 ]; then
            logErrorMessage "SCP command failed with exit code $SCP_EXIT_CODE."
            exit 1
        else
            logInfoMessage "SCP command executed successfully."
        fi
    ;;
    REMOTE_TO_LOCAL)
        logInfoMessage "Have to do copy operation from remote system to local"
    ;;
    REMOTE_TO_REMOTE)
        logInfoMessage "Have to do copy operation from remote system to remote"
    ;;
esac

 saveTaskStatus ${TASK_STATUS} ${ACTIVITY_SUB_TASK_CODE}