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
        echo "❌ Missing required tools: ${missing[*]}"
        echo "Please install them or rebuild the Docker image with them."
        exit 1
    fi

    echo "✅ All required tools are installed: ${tools[*]}"
}

# Call it early
check_tools

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
WORKSPACE="${WORKSPACE:?WORKSPACE missing}"
CODEBASE_DIR="${CODEBASE_DIR:?CODEBASE_DIR missing}"

SSH_USER="${SSH_USER:?SSH_USER missing}"
SSH_HOST="${SSH_HOST:?SSH_HOST missing}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_TARGET_PATH="${REMOTE_TARGET_PATH:?REMOTE_TARGET_PATH missing}"

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
# Paths & SSH setup
# --------------------------------------------------
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
cd "${CODEBASE_LOCATION}" || {
    logErrorMessage "Failed to change directory to ${CODEBASE_LOCATION}"
    add_event "DIRECTORY PROCESSING" "Failed" \
          "Failed to change directory" \
          "Directory: ${CODEBASE_LOCATION}"
    exit 1
}
add_event "DIRECTORY PROCESSING" "Successful" \
      "Changed to codebase directory" \
      "Directory: ${CODEBASE_LOCATION}"

KEY_FILE="key.pem"
[[ "$AUTH_MODE" == "key" && -f "$KEY_FILE" ]] && chmod 400 "$KEY_FILE"

SSH_BASE_OPTS="-p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# --------------------------------------------------
# Resolve source paths
# --------------------------------------------------
case "$SCP_SOURCE_MODE" in
    codebase) SOURCES="${CODEBASE_LOCATION}/" ;;
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
        add_event "SOURCE RESOLUTION" "Failed" \
              "Invalid SCP_SOURCE_MODE" \
              "Mode: ${SCP_SOURCE_MODE}"
        exit 1
        ;;
esac

# --------------------------------------------------
# Ensure tools
# --------------------------------------------------
ensure_tools
add_event "TOOLS ENSURED" "Successful" \
      "Required tools are installed" \
      "Tools: rsync, ssh, scp, sshpass"

# --------------------------------------------------
# Connectivity check
# --------------------------------------------------
if ! run_ssh "echo connected"; then
    logErrorMessage "SSH connection failed to ${SSH_HOST}"
    add_event "SSH CONNECTIVITY" "Failed" \
          "SSH connection could not be established" \
          "Host: ${SSH_HOST}"
    exit 1
fi
add_event "SSH CONNECTIVITY" "Successful" \
      "SSH connection established" \
      "Host: ${SSH_HOST}"

# --------------------------------------------------
# Execute transfer
# --------------------------------------------------
case "$TRANSFER_TOOL" in
    scp)
        logInfoMessage "Using SCP transfer"
        if ! run_scp; then
            add_event "TRANSFER EXECUTED" "Failed" \
                  "SCP file transfer failed" \
                  "Tool: scp Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"
            exit 1
        fi
        ;;
    rsync)
        logInfoMessage "Using RSYNC transfer"
        if ! run_rsync; then
            add_event "TRANSFER EXECUTED" "Failed" \
                  "RSYNC file transfer failed" \
                  "Tool: rsync Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"
            exit 1
        fi
        ;;
    *)
        logErrorMessage "Invalid TRANSFER_TOOL: ${TRANSFER_TOOL}"
        add_event "TRANSFER EXECUTED" "Failed" \
              "Invalid TRANSFER_TOOL specified" \
              "Tool: ${TRANSFER_TOOL}"
        exit 1
        ;;
esac

add_event "TRANSFER EXECUTED" "Successful" \
      "File transfer completed successfully" \
      "Tool: ${TRANSFER_TOOL} Target: ${SSH_HOST}:${REMOTE_TARGET_PATH}"

logInfoMessage "Deployment completed successfully"
