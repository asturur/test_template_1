#!/bin/sh
# Short comparison, not a phone boot: uses local firmware inputs and writes
# only the dedicated smoke directory. Build with build.py --hdl-board first.
set -eu
mode=${1:-shadow}
case "$mode" in
 shadow) option="";;
 exclusive) option=hdl-exclusive;;
 *) echo "usage: $0 [shadow|exclusive] [cycles]" >&2;exit 2;;
esac
cycles=${2:-20000000}
out="build/sim/unit-hdl-$mode-$cycles"
mkdir -p "$out"
set +e
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint /work/build/sim/obj-current-hdl-board/Vngage_cpu_sim jotego/simulator:arm64 /work/build/firmware/nem4-factory/core.bin "$cycles" 0 /work/"$out"/instructions.tsv /work/"$out"/bus.tsv /work/"$out"/cp15.tsv /work/"$out"/result.json amd16 ideal-clocks lcd-probe boot-io-probe keypad-gpio icu-banks timer-units epbus-clkblk timer-irq-delay=18200000 $option descramble-window rom-extension=/work/build/firmware/nem4-factory/extension.bin +ngage-compact-trace > "$out/run.log" 2>&1
set -e
python3 - "$out/result.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); print({k:r.get(k) for k in ('status','cycles','blocked_address','blocked_reason','hdl_board_claims','hdl_memory_fallback_devices')})
PY
# A bounded timeout is expected; all other diagnostic stops remain failures.
python3 - "$out/result.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
if r['status']!='timeout': raise SystemExit(1)
PY
