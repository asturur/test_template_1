#!/bin/sh
# Rebuild ZAP from pristine upstream + this patch series and check that the
# result is byte-identical to third_party/zap (the only ZAP copy used by both
# the Verilator simulations and the Quartus build).
#
# Pristine upstream krevanth/ZAP@fc7bd75 is taken from repository commit
# 5342c3f (its file hashes are pinned in third_party/zap/UPSTREAM.json), so
# no network access and no clean checkout in the working tree are needed.
# The rebuilt tree is deleted again on success.
set -eu
root=$(git rev-parse --show-toplevel)
out="$root/scratch/zap-upstream-rebuild"
rm -rf "$out"
mkdir -p "$out"
git -C "$root" archive 5342c3f third_party/zap | tar -x -C "$out"
cd "$out/third_party/zap"
for p in "$root"/patches/zap/[0-9]*.patch; do
    patch -p1 -s --no-backup-if-mismatch < "$p"
    echo "applied $(basename "$p")"
done
diff -r -x UPSTREAM.json "$out/third_party/zap" "$root/third_party/zap"
rm -rf "$out"
echo "OK: third_party/zap == upstream fc7bd75 + patches/zap"
