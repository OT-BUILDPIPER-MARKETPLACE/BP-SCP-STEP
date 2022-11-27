FROM alpine
RUN apk add --no-cache --upgrade bash
RUN apk add jq
RUN apk add openssh-client
COPY build.sh . 

ADD BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/

ENV SLEEP_DURATION 5s
ENV ACTIVITY_SUB_TASK_CODE SCP
ENV VALIDATION_FAILURE_ACTION WARNING
ENV ACTION LOCAL_TO_REMOTE

ENTRYPOINT [ "./build.sh" ]