#!/bin/bash
set -e
# Enable debug mode if DEBUG=true is set
if [ "$DEBUG" = "true" ]; then
    set -x
fi

# --------------------------------------------------
# Load shell functions
# --------------------------------------------------
SHELL_FUNCTIONS_PATH="/opt/buildpiper/shell-functions"

source "$SHELL_FUNCTIONS_PATH/functions.sh"
source "$SHELL_FUNCTIONS_PATH/log-functions.sh"
source "$SHELL_FUNCTIONS_PATH/str-functions.sh"
source "$SHELL_FUNCTIONS_PATH/file-functions.sh"
source "$SHELL_FUNCTIONS_PATH/aws-functions.sh"

# --------------------------------------------------
# Signal step startup
# --------------------------------------------------
add_event "STEP STARTUP" "Successful" \
      "SCP transfer step has initiated" \
      "Initializing environment and validating configuration..."

# Install missing tools
ensure_tools() {
    local tools=("rsync" "ssh" "scp" "sshpass")
    for t in "${tools[@]}"; do
        command -v "$t" >/dev/null 2>&1 || {
            echo "🔧 $t not found, installing..."
            apt-get update && apt-get install -y "$t"
        }
    done
}

check_tools() {
    local tools=("rsync" "scp" "ssh" "sshpass")
    local missing=()
    for t in "${tools[@]}"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            missing+=("$t")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        logErrorMessage "Missing required tools: ${missing[*]}"
        add_event "ENVIRONMENT VERIFICATION" "Failed" \
              "One or more required tools are missing" \
              "Please ensure the following are installed: ${missing[*]}"
        exit 1
    fi

    logInfoMessage "All required tools are installed: ${tools[*]}"
}

# Call it early
check_tools
add_event "ENVIRONMENT VERIFICATION" "Successful" \
      "All required tools are available in the environment" \
      "Tools: rsync, scp, ssh, sshpass"

# Run SSH command
run_ssh() {
    local cmd="$1"
    case "$AUTH_MODE" in
        key)        ssh -i "$KEY_FILE" $SSH_BASE_OPTS "$SSH_USER@$SSH_HOST" "$cmd" ;;
        password)   sshpass -p "$SSH_PASSWORD" ssh $SSH_BASE_OPTS "$SSH_USER@$SSH_HOST" "$cmd" ;;
        public_key) ssh $SSH_BASE_OPTS "$SSH_USER@$SSH_HOST" "$cmd" ;;
        *) echo "Invalid AUTH_MODE"; exit 1 ;;
    esac
}

# Run SCP
run_scp() {
    case "$AUTH_MODE" in
        key)        scp -rv -i "$KEY_FILE" -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        password)   sshpass -p "$SSH_PASSWORD" scp -r -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        public_key) scp -rv -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        *) echo "Invalid AUTH_MODE"; exit 1 ;;
    esac
}

# Run RSYNC
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
        *) echo "Invalid AUTH_MODE"; exit 1 ;;
    esac
}

# --------------------------------------------------
# Defaults / Inputs
# --------------------------------------------------
WORKSPACE="${WORKSPACE:-}"
CODEBASE_DIR="${CODEBASE_DIR:-}"

SSH_USER="${SSH_USER:-}"
SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_TARGET_PATH="${REMOTE_TARGET_PATH:-}"

TRANSFER_TOOL="${TRANSFER_TOOL:-scp}"           # scp | rsync
SCP_SOURCE_MODE="${SCP_SOURCE_MODE:-codebase}" # codebase | single | multiple
SCP_SINGLE_FILE="${SCP_SINGLE_FILE:-}"
SCP_MULTIPLE_FILES="${SCP_MULTIPLE_FILES:-}"

RSYNC_DELETE="${RSYNC_DELETE:-false}"
RSYNC_EXTRA_OPTS="${RSYNC_EXTRA_OPTS:-}"
RSYNC_EXCLUDES=(${RSYNC_EXCLUDES:-".git"})

AUTH_MODE="${AUTH_MODE:-key}"   # key | password | public_key
SSH_PASSWORD="${SSH_PASSWORD:-}"

DEBUG="${DEBUG:-false}"
TASK_STATUS=0

# --------------------------------------------------
# Validate auth mode
# --------------------------------------------------
case "$AUTH_MODE" in
    key|password|public_key)
        logInfoMessage "Auth mode: ${AUTH_MODE}"
        ;;
    *)
        logErrorMessage "Invalid AUTH_MODE: ${AUTH_MODE}. Allowed: key, password, public_key"
        add_event "AUTH MODE VALIDATION" "Failed" \
              "Invalid authentication mode specified" \
              "AUTH_MODE: ${AUTH_MODE} is not supported. Use: key, password, or public_key"
        exit 1
        ;;
esac
add_event "AUTH MODE VALIDATION" "Successful" \
      "Authentication mode is valid" \
      "AUTH_MODE: ${AUTH_MODE}"

# --------------------------------------------------
# Validate required inputs
# --------------------------------------------------
VALIDATION_ERRORS=""
[[ -z "$WORKSPACE" ]]           && VALIDATION_ERRORS+="WORKSPACE is not set. "
[[ -z "$CODEBASE_DIR" ]]        && VALIDATION_ERRORS+="CODEBASE_DIR is not set. "
[[ -z "$SSH_USER" ]]            && VALIDATION_ERRORS+="SSH_USER is not set. "
[[ -z "$SSH_HOST" ]]            && VALIDATION_ERRORS+="SSH_HOST is not set. "
[[ -z "$REMOTE_TARGET_PATH" ]]  && VALIDATION_ERRORS+="REMOTE_TARGET_PATH is not set. "

if [[ -n "$VALIDATION_ERRORS" ]]; then
    logErrorMessage "Missing required variables: $VALIDATION_ERRORS"
    add_event "INPUT VARIABLE VALIDATION" "Failed" \
          "Required environment variables are missing" \
          "Please provide: $VALIDATION_ERRORS"
    exit 1
fi

add_event "INPUT VARIABLE VALIDATION" "Successful" \
      "All required input variables are verified" \
      "Target Host: ${SSH_HOST}, Port: ${SSH_PORT}"


# --------------------------------------------------
# Paths & SSH setup
# --------------------------------------------------
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
cd "${CODEBASE_LOCATION}" || {
    logErrorMessage "Failed to change directory to ${CODEBASE_LOCATION}"
    add_event "WORKSPACE VERIFICATION" "Failed" \
          "Failed to access codebase directory" \
          "Directory: ${CODEBASE_LOCATION}. Please verify WORKSPACE and CODEBASE_DIR variables."
    exit 1
}
add_event "WORKSPACE VERIFICATION" "Successful" \
      "Codebase directory accessed successfully" \
      "Directory: ${CODEBASE_LOCATION}"

KEY_FILE="key.pem"
if [[ "$AUTH_MODE" == "key" ]]; then
    if [[ ! -f "$KEY_FILE" ]]; then
        logErrorMessage "SSH key file not found: ${KEY_FILE}"
        add_event "SSH KEY SETUP" "Failed" \
              "SSH key file is missing" \
              "The file '${KEY_FILE}' was not found in the codebase. This is required for 'key' auth mode."
        exit 1
    fi
    chmod 400 "$KEY_FILE"
    add_event "SSH KEY SETUP" "Successful" \
          "SSH key file verified and permissions set" \
          "Key file: ${KEY_FILE}"
else
    add_event "SSH KEY SETUP" "Successful" \
          "Key file skip: Not required for ${AUTH_MODE} mode" \
          "Auth Mode: ${AUTH_MODE}"
fi

SSH_BASE_OPTS="-p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# --------------------------------------------------
# Resolve source paths
# --------------------------------------------------
case "$SCP_SOURCE_MODE" in
    codebase)
        SOURCES="${CODEBASE_LOCATION}/"
        ;;
    single)
        if [[ -z "$SCP_SINGLE_FILE" ]]; then
            logErrorMessage "SCP_SINGLE_FILE missing"
            add_event "SOURCE RESOLUTION" "Failed" \
                  "SCP_SINGLE_FILE variable is not set" \
                  "Mode: single"
            exit 1
        fi
        SOURCES="${CODEBASE_LOCATION}/${SCP_SINGLE_FILE}"
        ;;
    multiple)
        if [[ -z "$SCP_MULTIPLE_FILES" ]]; then
            logErrorMessage "SCP_MULTIPLE_FILES missing"
            add_event "SOURCE RESOLUTION" "Failed" \
                  "SCP_MULTIPLE_FILES variable is not set" \
                  "Mode: multiple"
            exit 1
        fi
        SOURCES=""
        for f in $SCP_MULTIPLE_FILES; do
            SOURCES+=" ${CODEBASE_LOCATION}/${f}"
        done
        ;;
    *)
        logErrorMessage "Invalid SCP_SOURCE_MODE: ${SCP_SOURCE_MODE}"
        add_event "SOURCE PATH RESOLUTION" "Failed" \
              "Invalid source mode specified" \
              "Mode: ${SCP_SOURCE_MODE}. Supported: codebase, single, multiple"
        exit 1
        ;;
esac
add_event "SOURCE PATH RESOLUTION" "Successful" \
      "Source paths resolved successfully" \
      "Mode: ${SCP_SOURCE_MODE}, Sources: ${SOURCES}"

# --------------------------------------------------
# Tools verification (Final check)
# --------------------------------------------------
ensure_tools
add_event "ENVIRONMENT VERIFICATION" "Successful" \
      "Required tools are confirmed installed" \
      "Tools: rsync, ssh, scp, sshpass"

# --------------------------------------------------
# Connectivity check
# --------------------------------------------------
if ! run_ssh "echo connected"; then
    logErrorMessage "SSH connection failed to ${SSH_HOST}"
    add_event "SSH CONNECTIVITY" "Failed" \
          "SSH connection could not be established" \
          "Host: ${SSH_HOST}. Please verify host, port, and credentials."
    exit 1
fi
add_event "SSH CONNECTIVITY" "Successful" \
      "SSH connection established with remote host" \
      "Host: ${SSH_HOST}, Port: ${SSH_PORT}"

# --------------------------------------------------
# Remote target preparation
# --------------------------------------------------
logInfoMessage "Ensuring remote target directory exists: ${REMOTE_TARGET_PATH}"
if ! run_ssh "mkdir -p ${REMOTE_TARGET_PATH}"; then
    logErrorMessage "Failed to create remote directory: ${REMOTE_TARGET_PATH}"
    add_event "REMOTE TARGET PREPARATION" "Failed" \
          "Could not ensure remote directory existence" \
          "Target Path: ${REMOTE_TARGET_PATH}"
    exit 1
fi
add_event "REMOTE TARGET PREPARATION" "Successful" \
      "Remote target directory is ready" \
      "Path: ${REMOTE_TARGET_PATH}"

# --------------------------------------------------
# Execute transfer
# --------------------------------------------------
case "$TRANSFER_TOOL" in
    scp)
        logInfoMessage "Using SCP transfer"
        if ! run_scp; then
            add_event "DATA TRANSFER" "Failed" \
                  "SCP file transfer failed" \
                  "Tool: scp, Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"
            exit 1
        fi
        ;;
    rsync)
        logInfoMessage "Using RSYNC transfer"
        if ! run_rsync; then
            add_event "DATA TRANSFER" "Failed" \
                  "RSYNC file transfer failed" \
                  "Tool: rsync, Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"
            exit 1
        fi
        ;;
    *)
        logErrorMessage "Invalid TRANSFER_TOOL: ${TRANSFER_TOOL}"
        add_event "DATA TRANSFER" "Failed" \
              "Invalid TRANSFER_TOOL specified" \
              "Tool: ${TRANSFER_TOOL}"
        exit 1
        ;;
esac

add_event "DATA TRANSFER" "Successful" \
      "File transfer completed successfully" \
      "Tool: ${TRANSFER_TOOL}, Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"

# --------------------------------------------------
# Final status
# --------------------------------------------------
add_event "STEP COMPLETION" "Successful" \
      "All tasks completed successfully" \
      "Step: SCP Transfer, Host: ${SSH_HOST}"

logInfoMessage "Deployment completed successfully"
