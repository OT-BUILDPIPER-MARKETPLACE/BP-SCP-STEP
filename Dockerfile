# -------------------------------
# Base image
# -------------------------------
FROM python:3.12-slim

# -------------------------------
# Install dependencies
# -------------------------------
# -------------------------------
# Install dependencies
# -------------------------------
RUN apt-get update && apt-get install -y \
        jq \
        passwd \
        openssh-client \
        && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir cryptography


# -------------------------------
# Create buildpiper user & group
# -------------------------------
RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 -g buildpiper -d /home/buildpiper -m buildpiper

# -------------------------------
# Create directories and set permissions
# -------------------------------
RUN mkdir -p \
    /bp/data \
    /bp/execution_dir \
    /bp/workspace \
    /opt/buildpiper/shell-functions \
    /home/buildpiper/reports && \
    chown -R buildpiper:buildpiper \
        /bp \
        /opt/buildpiper \
        /home/buildpiper

# -------------------------------
# Set environment defaults
# -------------------------------
ENV SLEEP_DURATION=5s \
    ACTIVITY_SUB_TASK_CODE="MANAGE_REMOTE_PROCESS" \
    VALIDATION_FAILURE_ACTION="FAILURE" \
    SHELL_FUNCTIONS_PATH="/opt/buildpiper/shell-functions"

# -------------------------------
# Copy scripts and submodule
# -------------------------------
COPY --chown=buildpiper:buildpiper build.sh /home/buildpiper/build.sh
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS/ /opt/buildpiper/shell-functions/

# -------------------------------
# Make build script executable
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
ENTRYPOINT ["/bin/bash", "/home/buildpiper/build.sh"]
