#!/bin/sh
# Check that rtl/arm (the only ZAP copy used by the simulations and the
# Quartus build) is exactly pinned upstream krevanth/ZAP + this patch series.
#
# Downloaded pristine tool caches live under build/. Legacy scratch trees may
# hold other experiments and are never overwritten by this verification.
set -eu
root=$(git rev-parse --show-toplevel)
commit=$(python3 -c "import json;print(json.load(open('$root/rtl/arm/UPSTREAM.json'))['commit'])")
upstream="$root/build/tool-cache/zap-upstream-$commit"
mkdir -p "$root/build/tool-cache"
work=$(mktemp -d "$root/build/zap-patch-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

if [ ! -f "$upstream/.commit" ]; then
    archive="$work/upstream.tar.gz"
    gh api "repos/krevanth/ZAP/tarball/$commit" > "$archive"
    mkdir -p "$upstream"
    tar -xzf "$archive" -C "$upstream" --strip-components=1
    echo "$commit" > "$upstream/.commit"
fi
python3 - "$root/rtl/arm/UPSTREAM.json" "$upstream" <<'EOF'
import hashlib, json, sys
pin, tree = json.load(open(sys.argv[1])), sys.argv[2]
bad = [f for f, h in pin["files"].items()
       if hashlib.sha256(open(f"{tree}/{f}", "rb").read()).hexdigest() != h]
if bad: sys.exit(f"downloaded upstream differs from pin: {bad}")
EOF

cp -R "$upstream/." "$work/"
for p in "$root"/patches/zap/[0-9]*.patch; do
    patch -d "$work" -p1 -s -E --no-backup-if-mismatch < "$p"
    echo "applied $(basename "$p")"
done
diff -r "$work/src/rtl" "$root/rtl/arm" -x LICENSE -x UPSTREAM.json -x README.md
echo "OK: rtl/arm == upstream $commit + patches/zap"
