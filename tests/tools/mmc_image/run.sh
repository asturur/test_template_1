#!/bin/sh
set -eu
PYTHONDONTWRITEBYTECODE=1 python3 -B tests/tools/mmc_image/test_mmc_image.py
