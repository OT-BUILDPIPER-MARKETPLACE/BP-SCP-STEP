FROM alpine:3.20

RUN apk add --no-cache \
    bash \
    curl \
    python3 \
    sed \
    openssh-client \
    openssh \
    jq \
    aws-cli \
    py3-cryptography

RUN addgroup -g 65522 buildpiper && \
    adduser -D -h /home/buildpiper -u 65522 -G buildpiper buildpiper

RUN mkdir -p \
    /src/reports \
    /bp/data \
    /bp/execution_dir \
    /opt/buildpiper/shell-functions \
    /opt/buildpiper/data \
    /bp/workspace && \
    chown -R buildpiper:buildpiper /src /bp /opt /home/buildpiper

COPY --chown=buildpiper:buildpiper build.sh /home/buildpiper/build.sh
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/

RUN chmod +x /home/buildpiper/build.sh

USER buildpiper
WORKDIR /home/buildpiper

ENV SSH_CREDENTIAL_NAME=SSH_KEY
ENV PROXY_OPTION=""
ENV SSH_USERNAME=""
ENV SSH_IP=""
ENV SSH_PORT=22
ENV SLEEP_DURATION=5s
ENV ACTIVITY_SUB_TASK_CODE=SCP
ENV VALIDATION_FAILURE_ACTION=WARNING
ENV ACTION=LOCAL_TO_REMOTE

ENTRYPOINT ["./build.sh"]
