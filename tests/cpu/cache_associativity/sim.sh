#!/bin/sh
# Production cache must retain all64 conflicting ways.
set -eu
CPU_PROGRAM=cache_associativity "$(dirname "$0")/../core/sim.sh"
