#!/bin/sh
# Restore the disposable mtools cache; the rebuild itself needs no network.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
mkdir -p "$project_root/build/tools/packages"
docker run --rm -v "$project_root/build/tools:/tools" -w /tools/packages \
    --entrypoint sh jotego/simulator:arm64 -c \
    'apt-get update -qq && apt-get download mtools && dpkg-deb -x mtools_*.deb /tools/mtools'
