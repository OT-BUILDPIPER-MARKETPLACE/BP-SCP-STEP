#!/bin/bash
set -euo pipefail
[[ "${DEBUG:-false}" == "true" ]] && set -x

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
        key)        scp -r -i "$KEY_FILE" -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        password)   sshpass -p "$SSH_PASSWORD" scp -r -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
        public_key) scp -r -P "$SSH_PORT" -o StrictHostKeyChecking=no $SOURCES "$SSH_USER@$SSH_HOST:$REMOTE_TARGET_PATH" ;;
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
cd "$CODEBASE_LOCATION" || { echo "❌ Failed to change directory"; exit 1; }

KEY_FILE="key.pem"
[[ "$AUTH_MODE" == "key" && -f "$KEY_FILE" ]] && chmod 400 "$KEY_FILE"

SSH_BASE_OPTS="-p ${SSH_PORT} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# --------------------------------------------------
# Resolve source paths
# --------------------------------------------------
case "$SCP_SOURCE_MODE" in
    codebase) SOURCES="${CODEBASE_LOCATION}/" ;;
    single)
        [[ -z "$SCP_SINGLE_FILE" ]] && { echo "SCP_SINGLE_FILE missing"; exit 1; }
        SOURCES="${CODEBASE_LOCATION}/${SCP_SINGLE_FILE}"
        ;;
    multiple)
        [[ -z "$SCP_MULTIPLE_FILES" ]] && { echo "SCP_MULTIPLE_FILES missing"; exit 1; }
        SOURCES=""
        for f in $SCP_MULTIPLE_FILES; do
            SOURCES+=" ${CODEBASE_LOCATION}/${f}"
        done
        ;;
    *) echo "Invalid SCP_SOURCE_MODE"; exit 1 ;;
esac

# --------------------------------------------------
# Ensure tools
# --------------------------------------------------
ensure_tools

# --------------------------------------------------
# Connectivity check
# --------------------------------------------------
run_ssh "echo connected" || { echo "❌ SSH connection failed"; exit 1; }

# --------------------------------------------------
# Execute transfer
# --------------------------------------------------
case "$TRANSFER_TOOL" in
    scp)   echo "📦 Using SCP transfer"; run_scp ;;
    rsync) echo "🚀 Using RSYNC transfer"; run_rsync ;;
    *) echo "❌ Invalid TRANSFER_TOOL"; exit 1 ;;
esac

echo "✅ Deployment completed successfully"
