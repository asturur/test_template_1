#!/bin/sh
# Structural lint only: the script explicitly stubs HPS and PLL IP.
# It does not replace Quartus timing, resource, or CDC reports.
set -eu
docker run --pull never --rm --network none --platform linux/arm64 \
 -v "$PWD:/work" -w /work --entrypoint sh jotego/linter:arm64 \
 -c 'sh tests/phone/mister_transport/lint-top.sh'
