FROM alpine:3.9.3

RUN apk --update add --no-cache mongodb python py-pip groff bash curl wget jq mongodb-tools && \
    mkdir /backup && \
    pip install --upgrade awscli && \
    apk -v --purge del py-pip

ADD run.sh /run.sh
VOLUME ["/backup"]
CMD ["/run.sh"]
