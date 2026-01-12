# -------------------------------
# Base image
# -------------------------------
FROM ubuntu:22.04

# -------------------------------
# Set environment variables
# -------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}" \
    SHELL_FUNCTIONS_PATH="/opt/buildpiper/shell-functions" \
    SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
    SLEEP_DURATION=5s \
    ACTIVITY_SUB_TASK_CODE="SCP_REMOTE_PROCESS" \
    VALIDATION_FAILURE_ACTION="FAILURE"

# -------------------------------
# Install system dependencies
# -------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        rsync \
        openssh-client \
        sshpass \
        git \
        jq \
        ca-certificates \
        passwd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -------------------------------
# Install Python packages
# -------------------------------
RUN python3 -m pip install --no-cache-dir cryptography

# -------------------------------
# Create buildpiper user & group
# -------------------------------
RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 -g buildpiper -m -d /home/buildpiper buildpiper

# -------------------------------
# Create directories and set permissions
# -------------------------------
RUN mkdir -p \
        /bp/data \
        /bp/execution_dir \
        /bp/workspace \
        /opt/buildpiper/shell-functions \
        /home/buildpiper/reports \
    && chown -R buildpiper:buildpiper \
        /bp \
        /opt/buildpiper \
        /home/buildpiper

# -------------------------------
# Copy build scripts and shell functions
# -------------------------------
COPY --chown=buildpiper:buildpiper build.sh /home/buildpiper/build.sh
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/ /opt/buildpiper/shell-functions/

# -------------------------------
# Fix line endings and make build.sh executable
# -------------------------------
RUN sed -i 's/\r$//' /home/buildpiper/build.sh && \
    sed -i '1s/^\xEF\xBB\xBF//' /home/buildpiper/build.sh && \
    chmod +x /home/buildpiper/build.sh

# -------------------------------
# Switch to non-root user
# -------------------------------
USER buildpiper
WORKDIR /home/buildpiper

# -------------------------------
# Entrypoint
# -------------------------------
ENTRYPOINT ["bash", "-c", "exec /home/buildpiper/build.sh"]
