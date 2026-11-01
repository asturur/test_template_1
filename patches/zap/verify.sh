#!/bin/sh
# Check that rtl/arm (the only ZAP copy used by the simulations and the
# Quartus build) is exactly pinned upstream krevanth/ZAP + this patch series.
#
# The original upstream is downloaded on demand to scratch/zap-upstream/
# (git-ignored, reference only) and checked against the file hashes pinned in
# rtl/arm/UPSTREAM.json. Patches are upstream-relative (-p1, src/rtl/...).
set -eu
root=$(git rev-parse --show-toplevel)
commit=$(python3 -c "import json;print(json.load(open('$root/rtl/arm/UPSTREAM.json'))['commit'])")
upstream="$root/scratch/zap-upstream"
work="$root/scratch/zap-upstream-patched"

if [ ! -f "$upstream/.commit" ] || [ "$(cat "$upstream/.commit")" != "$commit" ]; then
    rm -rf "$upstream"
    mkdir -p "$upstream"
    curl -sfL "https://github.com/krevanth/ZAP/archive/$commit.tar.gz" |
        tar -xz -C "$upstream" --strip-components=1
    echo "$commit" > "$upstream/.commit"
fi
python3 - "$root/rtl/arm/UPSTREAM.json" "$upstream" <<'EOF'
import hashlib, json, sys
pin, tree = json.load(open(sys.argv[1])), sys.argv[2]
bad = [f for f, h in pin["files"].items()
       if hashlib.sha256(open(f"{tree}/{f}", "rb").read()).hexdigest() != h]
if bad: sys.exit(f"downloaded upstream differs from pin: {bad}")
EOF

rm -rf "$work"
cp -R "$upstream" "$work"
for p in "$root"/patches/zap/[0-9]*.patch; do
    patch -d "$work" -p1 -s --no-backup-if-mismatch < "$p"
    echo "applied $(basename "$p")"
done
diff -r "$work/src/rtl" "$root/rtl/arm" -x LICENSE -x UPSTREAM.json -x README.md
rm -rf "$work"
echo "OK: rtl/arm == upstream $commit + patches/zap"
