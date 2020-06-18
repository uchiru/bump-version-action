FROM alpine

COPY ./src/bump ./src/bump
RUN install ./src/bump /usr/local/bin
COPY entrypoint.sh /entrypoint.sh

RUN apk update && apk add bash git curl jq

ENTRYPOINT ["/entrypoint.sh"]
