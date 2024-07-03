FROM alpine

RUN apk add --no-cache --upgrade bash \
    bash \
    curl \
    python3 \
    py3-pip \
    sed \
    openssh-client \
    openssh \
    jq && \
    pip3 install --upgrade pip && \
    pip3 install awscli cryptography

COPY build.sh . 

ADD BP-BASE-SHELL-STEPS .

ENV SSH_CREDENTIAL_NAME="SSH_KEY"
ENV PROXY_OPTION=""
ENV SSH_USERNAME=""
ENV SSH_IP=""
ENV SSH_PORT="22"

ENV SLEEP_DURATION 5s
ENV ACTIVITY_SUB_TASK_CODE SCP
ENV VALIDATION_FAILURE_ACTION WARNING
ENV ACTION LOCAL_TO_REMOTE

ENTRYPOINT [ "./build.sh" ]

