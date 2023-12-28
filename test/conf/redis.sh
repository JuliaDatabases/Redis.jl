#!/bin/bash

SCRIPT_PATH=$(cd "$(dirname "$0")"; pwd)
TEST_PATH=$(dirname "$SCRIPT_PATH")

docker run -d --name redis \
    --hostname redis \
    -p 6379:6379 \
    -p 16379:16379 \
    -v "${TEST_PATH}/conf/redis.conf":/usr/local/etc/redis/redis.conf \
    -v "${TEST_PATH}/certs":/certs \
    redis:7.2.3-bookworm redis-server /usr/local/etc/redis/redis.conf

