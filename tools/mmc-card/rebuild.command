#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
if [ "$#" -ne 0 ] && [ "$#" -ne 2 ]; then
    echo 'Usage: rebuild.command [INPUT_FOLDER_UNDER_RUNTIME_MMC OUTPUT_STEM]' >&2
    exit 1
fi
if [ "$#" -eq 2 ]; then
    set -- "/repo/runtime/mmc/$1" "/repo/build/mmc/$2"
fi
docker run --rm --network none -v "$project_root:/repo" -w /repo \
    -e PYTHONDONTWRITEBYTECODE=1 \
    -e PATH=/repo/build/tools/mtools/usr/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --entrypoint python3 jotego/simulator:arm64 /repo/tools/mmc-card/build-card.py "$@"
