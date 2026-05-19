#!/bin/bash

# ---------------------------------------------------------------
# NOTE: ACTIVITY_SUB_TASK_CODE is managed by the BuildPiper
#       environment. Do NOT override it here to ensure events
#       appear correctly in the UI.
# ---------------------------------------------------------------

SHELL_FUNCTIONS_PATH="/opt/buildpiper/shell-functions"
source "${SHELL_FUNCTIONS_PATH}/functions.sh"
source "${SHELL_FUNCTIONS_PATH}/log-functions.sh"
source "${SHELL_FUNCTIONS_PATH}/str-functions.sh"
source "${SHELL_FUNCTIONS_PATH}/file-functions.sh"
source "${SHELL_FUNCTIONS_PATH}/aws-functions.sh"

if [ "$DEBUG" = true ]; then
    set -x
fi

# ---------------------------------------------------------------
# Defaults / Inputs
# ---------------------------------------------------------------
WORKSPACE="${WORKSPACE:-/bp/workspace}"
CODEBASE_DIR="${CODEBASE_DIR:-}"
SSH_USER="${SSH_USER:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_TARGET_PATH="${REMOTE_TARGET_PATH:-}"
TRANSFER_TOOL="${TRANSFER_TOOL:-scp}"
SCP_SOURCE_MODE="${SCP_SOURCE_MODE:-codebase}"
SCP_SINGLE_FILE="${SCP_SINGLE_FILE:-}"
SCP_MULTIPLE_FILES="${SCP_MULTIPLE_FILES:-}"
RSYNC_DELETE="${RSYNC_DELETE:-false}"
RSYNC_EXTRA_OPTS="${RSYNC_EXTRA_OPTS:-}"
RSYNC_EXCLUDES=(${RSYNC_EXCLUDES:-.git})
AUTH_MODE="${AUTH_MODE:-key}"
SSH_PASSWORD="${SSH_PASSWORD:-}"
TASK_STATUS=0
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"

# ---------------------------------------------------------------
# 1. Initialization
# ---------------------------------------------------------------
logInfoMessage "> Starting step: scp_transfer"
logInfoMessage "> Codebase location: ${CODEBASE_LOCATION}"
logInfoMessage "> Target: ${SSH_USER}@${SSH_HOST}:${SSH_PORT} → ${REMOTE_TARGET_PATH}"

add_event "INITIALIZATION" "Successful" \
    "SCP Transfer step initialized" \
    "Tool: ${TRANSFER_TOOL} | Auth: ${AUTH_MODE} | Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"

# ---------------------------------------------------------------
# 2. Tool Verification
# ---------------------------------------------------------------
logInfoMessage "> Verifying required tools..."

check_tools() {
    local tools=("rsync" "scp" "ssh" "sshpass")
    local missing=()
    for t in "${tools[@]}"; do
        if ! command -v "$t" > /dev/null 2>&1; then
            missing+=("$t")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        logInfoMessage "> Installing missing tools: ${missing[*]}"
        apt-get update -qq && apt-get install -y "${missing[@]}" > /dev/null 2>&1
        # Re-check after install
        local still_missing=()
        for t in "${missing[@]}"; do
            command -v "$t" > /dev/null 2>&1 || still_missing+=("$t")
        done
        if [ ${#still_missing[@]} -gt 0 ]; then
            logErrorMessage "> Required tools still missing after install: ${still_missing[*]}"
            add_event "TOOL_VERIFICATION" "Failed" \
                "Required tools could not be installed" \
                "Missing: ${still_missing[*]}"
            saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
            exit 1
        fi
    fi

    logInfoMessage "> All required tools are available: rsync, scp, ssh, sshpass"
}

check_tools
add_event "TOOL_VERIFICATION" "Successful" \
    "All required tools are available" \
    "Tools: rsync, scp, ssh, sshpass"

# ---------------------------------------------------------------
# SSH / SCP / RSYNC Wrappers
# ---------------------------------------------------------------
SSH_BASE_OPTS="-p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

run_ssh() {
    local cmd="$1"
    case "$AUTH_MODE" in
        key)        ssh -i "$KEY_FILE" $SSH_BASE_OPTS "$SSH_USER@$SSH_HOST" "$cmd" ;;
        password)   sshpass -p "$SSH_PASSWORD" ssh $SSH_BASE_OPTS "$SSH_USER@$SSH_HOST" "$cmd" ;;
        public_key) ssh $SSH_BASE_OPTS "$SSH_USER@$SSH_HOST" "$cmd" ;;
    esac
}

run_scp() {
    case "$AUTH_MODE" in
        key)        scp -rv -i "$KEY_FILE" -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        password)   sshpass -p "$SSH_PASSWORD" scp -r -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        public_key) scp -rv -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
    esac
}

run_rsync() {
    local opts="-azpL --no-perms --no-owner --no-group"
    [[ "$RSYNC_DELETE" == "true" ]] && opts+=" --delete"
    [[ -n "$RSYNC_EXTRA_OPTS" ]] && opts+=" $RSYNC_EXTRA_OPTS"
    for ex in "${RSYNC_EXCLUDES[@]}"; do
        opts+=" --exclude=${ex}"
    done
    case "$AUTH_MODE" in
        key)        rsync $opts -e "ssh -i $KEY_FILE $SSH_BASE_OPTS" $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        password)   rsync $opts -e "sshpass -p $SSH_PASSWORD ssh $SSH_BASE_OPTS" $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        public_key) rsync $opts -e "ssh $SSH_BASE_OPTS" $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
    esac
}

# ---------------------------------------------------------------
# 3. Input Validation
# ---------------------------------------------------------------
logInfoMessage "> Validating inputs..."

VALIDATION_ERRORS=""
[[ -z "$WORKSPACE" ]]          && VALIDATION_ERRORS+="WORKSPACE is not set. "
[[ -z "$CODEBASE_DIR" ]]       && VALIDATION_ERRORS+="CODEBASE_DIR is not set. "
[[ -z "$SSH_USER" ]]           && VALIDATION_ERRORS+="SSH_USER is not set. "
[[ -z "$SSH_HOST" ]]           && VALIDATION_ERRORS+="SSH_HOST is not set. "
[[ -z "$REMOTE_TARGET_PATH" ]] && VALIDATION_ERRORS+="REMOTE_TARGET_PATH is not set. "

if [[ -n "$VALIDATION_ERRORS" ]]; then
    logErrorMessage "> Missing required variables: ${VALIDATION_ERRORS}"
    add_event "INPUT_VALIDATION" "Failed" \
        "Required environment variables are missing" \
        "${VALIDATION_ERRORS}"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

case "$AUTH_MODE" in
    key|password|public_key) ;;
    *)
        logErrorMessage "> Invalid AUTH_MODE: ${AUTH_MODE} — allowed: key, password, public_key"
        add_event "INPUT_VALIDATION" "Failed" \
            "Invalid AUTH_MODE: ${AUTH_MODE}" \
            "Allowed values: key | password | public_key"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
        ;;
esac

add_event "INPUT_VALIDATION" "Successful" \
    "All required inputs validated" \
    "Host: ${SSH_HOST}:${SSH_PORT} | Auth: ${AUTH_MODE} | Tool: ${TRANSFER_TOOL}"

# ---------------------------------------------------------------
# 4. Execution Summary
# ---------------------------------------------------------------
echo ""
echo "> SCP Transfer Execution Summary"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Parameter" "Value"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Codebase" "${CODEBASE_DIR}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Remote Host" "${SSH_HOST}:${SSH_PORT}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "SSH User" "${SSH_USER}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Auth Mode" "${AUTH_MODE}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Transfer Tool" "${TRANSFER_TOOL}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Source Mode" "${SCP_SOURCE_MODE}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
printf '| %-28s | %-48s |\n' "Remote Target" "${REMOTE_TARGET_PATH}"
printf '+%-30s+%-50s+\n' '------------------------------' '--------------------------------------------------'
echo ""

# ---------------------------------------------------------------
# 5. Workspace Navigation
# ---------------------------------------------------------------
logInfoMessage "> Navigating to codebase directory..."

cd "${CODEBASE_LOCATION}" || {
    logErrorMessage "> Failed to navigate to codebase directory: ${CODEBASE_LOCATION}"
    add_event "WORKSPACE_NAVIGATION" "Failed" \
        "Cannot change to codebase directory" \
        "Path: ${CODEBASE_LOCATION} | Verify WORKSPACE and CODEBASE_DIR"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
}

logInfoMessage "> Successfully navigated to: ${CODEBASE_LOCATION}"
add_event "WORKSPACE_NAVIGATION" "Successful" \
    "Navigated to codebase directory" \
    "Path: ${CODEBASE_LOCATION}"

# ---------------------------------------------------------------
# 6. SSH Key Setup (key auth mode only)
# ---------------------------------------------------------------
KEY_FILE="key.pem"
if [[ "$AUTH_MODE" == "key" ]]; then
    logInfoMessage "> Verifying SSH key file: ${KEY_FILE}"
    if [[ ! -f "$KEY_FILE" ]]; then
        logErrorMessage "> SSH key file not found: ${KEY_FILE}"
        add_event "SSH_KEY_SETUP" "Failed" \
            "SSH key file is missing in codebase" \
            "Expected file: ${KEY_FILE} in ${CODEBASE_LOCATION}"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
    fi
    chmod 400 "$KEY_FILE"
    logInfoMessage "> SSH key file verified and permissions set (400)"
    add_event "SSH_KEY_SETUP" "Successful" \
        "SSH key file verified and permissions set" \
        "Key file: ${KEY_FILE}"
else
    logInfoMessage "> SSH key not required for auth mode: ${AUTH_MODE}"
    add_event "SSH_KEY_SETUP" "Successful" \
        "SSH key setup skipped — not required for ${AUTH_MODE} mode" \
        "Auth Mode: ${AUTH_MODE}"
fi

# ---------------------------------------------------------------
# 7. Source Path Resolution
# ---------------------------------------------------------------
logInfoMessage "> Resolving source paths (mode: ${SCP_SOURCE_MODE})..."

case "$SCP_SOURCE_MODE" in
    codebase)
        SOURCES="${CODEBASE_LOCATION}/"
        ;;
    single)
        if [[ -z "$SCP_SINGLE_FILE" ]]; then
            logErrorMessage "> SCP_SINGLE_FILE is not set (required for mode: single)"
            add_event "SOURCE_RESOLUTION" "Failed" \
                "SCP_SINGLE_FILE variable is not set" \
                "Mode: single | Set SCP_SINGLE_FILE to the file path relative to codebase"
            saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
            exit 1
        fi
        SOURCES="${CODEBASE_LOCATION}/${SCP_SINGLE_FILE}"
        ;;
    multiple)
        if [[ -z "$SCP_MULTIPLE_FILES" ]]; then
            logErrorMessage "> SCP_MULTIPLE_FILES is not set (required for mode: multiple)"
            add_event "SOURCE_RESOLUTION" "Failed" \
                "SCP_MULTIPLE_FILES variable is not set" \
                "Mode: multiple | Set SCP_MULTIPLE_FILES to space-separated file paths"
            saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
            exit 1
        fi
        SOURCES=""
        for f in $SCP_MULTIPLE_FILES; do
            SOURCES+=" ${CODEBASE_LOCATION}/${f}"
        done
        ;;
    *)
        logErrorMessage "> Invalid SCP_SOURCE_MODE: ${SCP_SOURCE_MODE}"
        add_event "SOURCE_RESOLUTION" "Failed" \
            "Invalid SCP_SOURCE_MODE: ${SCP_SOURCE_MODE}" \
            "Supported modes: codebase | single | multiple"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
        ;;
esac

logInfoMessage "> Sources resolved: ${SOURCES}"
add_event "SOURCE_RESOLUTION" "Successful" \
    "Source paths resolved successfully" \
    "Mode: ${SCP_SOURCE_MODE} | Sources: ${SOURCES}"

# ---------------------------------------------------------------
# 8. SSH Connectivity Check
# ---------------------------------------------------------------
logInfoMessage "> Testing SSH connectivity to ${SSH_HOST}:${SSH_PORT}..."

if run_ssh "echo connected" > /dev/null 2>&1; then
    logInfoMessage "> SSH connectivity confirmed — connected to ${SSH_HOST} as ${SSH_USER}"
    add_event "SSH_CONNECTIVITY" "Successful" \
        "SSH connection established with remote host" \
        "Host: ${SSH_HOST}:${SSH_PORT} | User: ${SSH_USER}"
else
    logErrorMessage "> SSH connectivity check failed — cannot connect to ${SSH_HOST}"
    add_event "SSH_CONNECTIVITY" "Failed" \
        "SSH connection could not be established" \
        "Host: ${SSH_HOST}:${SSH_PORT} | Verify host, port, and credentials"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

# ---------------------------------------------------------------
# 9. Remote Directory Preparation
# ---------------------------------------------------------------
logInfoMessage "> Ensuring remote target directory exists: ${REMOTE_TARGET_PATH}"

if run_ssh "mkdir -p '${REMOTE_TARGET_PATH}'"; then
    logInfoMessage "> Remote directory ready: ${REMOTE_TARGET_PATH}"
    add_event "REMOTE_DIR_PREPARATION" "Successful" \
        "Remote target directory is ready" \
        "Path: ${REMOTE_TARGET_PATH} on ${SSH_HOST}"
else
    logErrorMessage "> Failed to create remote directory: ${REMOTE_TARGET_PATH}"
    add_event "REMOTE_DIR_PREPARATION" "Failed" \
        "Could not create remote target directory" \
        "Path: ${REMOTE_TARGET_PATH} on ${SSH_HOST} | Check permissions"
    saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
    exit 1
fi

# ---------------------------------------------------------------
# 10. File Transfer
# ---------------------------------------------------------------
logInfoMessage "> Starting file transfer using ${TRANSFER_TOOL}..."
add_event "TRANSFER_START" "Successful" \
    "File transfer initiated" \
    "Tool: ${TRANSFER_TOOL} | Source Mode: ${SCP_SOURCE_MODE} | Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"

case "$TRANSFER_TOOL" in
    scp)
        logInfoMessage "> Running SCP transfer..."
        if run_scp; then
            logInfoMessage "> SCP transfer completed successfully"
            add_event "TRANSFER_RESULT" "Successful" \
                "SCP file transfer completed successfully" \
                "Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"
        else
            logErrorMessage "> SCP transfer failed"
            add_event "TRANSFER_RESULT" "Failed" \
                "SCP file transfer failed" \
                "Target: ${SSH_HOST}:${REMOTE_TARGET_PATH} | Check source files and remote permissions"
            saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
            exit 1
        fi
        ;;
    rsync)
        logInfoMessage "> Running RSYNC transfer..."
        if run_rsync; then
            logInfoMessage "> RSYNC transfer completed successfully"
            add_event "TRANSFER_RESULT" "Successful" \
                "RSYNC file transfer completed successfully" \
                "Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"
        else
            logErrorMessage "> RSYNC transfer failed"
            add_event "TRANSFER_RESULT" "Failed" \
                "RSYNC file transfer failed" \
                "Target: ${SSH_HOST}:${REMOTE_TARGET_PATH} | Check source files and remote permissions"
            saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
            exit 1
        fi
        ;;
    *)
        logErrorMessage "> Invalid TRANSFER_TOOL: ${TRANSFER_TOOL} — allowed: scp, rsync"
        add_event "TRANSFER_RESULT" "Failed" \
            "Invalid TRANSFER_TOOL: ${TRANSFER_TOOL}" \
            "Allowed values: scp | rsync"
        saveTaskStatus 1 "${ACTIVITY_SUB_TASK_CODE}"
        exit 1
        ;;
esac

# ---------------------------------------------------------------
# 11. Final Status
# ---------------------------------------------------------------
logInfoMessage "> SCP Transfer step completed successfully"
saveTaskStatus 0 "${ACTIVITY_SUB_TASK_CODE}"
exit 0
