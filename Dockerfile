FROM alpine:3.7

RUN apk add --no-cache bash curl wget mongodb-tools && \
    mkdir /backup

ENV CRON_TIME="0 0 * * *"

ADD run.sh /run.sh
VOLUME ["/backup"]
CMD ["/run.sh"]
