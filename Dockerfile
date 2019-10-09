FROM alpine:3.9.3

RUN apk --update add --no-cache python py-pip groff bash curl wget mongodb-tools && \
    mkdir /backup && \
    pip install --upgrade awscli && \
    apk -v --purge del py-pip && \
    rm /var/cache/apk/*

ADD run.sh /run.sh
VOLUME ["/backup"]
CMD ["/run.sh"]
