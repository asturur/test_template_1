#!/bin/sh
# Host binutils, then the existing simulator image; independent of long runs.
set -eu
out=build/sim/unit-exit-trace
mkdir -p "$out"
python3 tools/build_exit_trace.py
arm-none-eabi-gcc -c -march=armv4t -marm tests/phone/exit_trace/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 - <<'PY'
from pathlib import Path
import json,subprocess
out=Path('build/sim/unit-exit-trace');src=Path('build/firmware-overlays/exit-trace')
symbols={p[2]:int(p[0],16) for line in subprocess.check_output(['arm-none-eabi-nm',str(out/'program.elf')],text=True).splitlines() if len(p:=line.split())==3}
data=(out/'program.bin').read_bytes();assert len(data)<2044
data=data.ljust(2044,b'\0')+symbols['test_debug'].to_bytes(4,'little')
for name,data in [('program',data),('payload',(src/'trace.bin').read_bytes().ljust(4096,b'\0'))]:
 (out/(name+'.hex')).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
report=json.loads((src/'trace.json').read_text());hooks=report['hooks']
records={off:new for off,old,new in report['records']}
(out/'hooks.hex').write_text(''.join(f'{records[address-0x50000000]:08x}\n' for name,address in hooks.items() if name != 'wait_request'))
PY
docker run --rm --pull=never --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
 for waits in 0 3; do
  verilator --binary --timing --assert -j 2 -GWAIT_CYCLES=$waits -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir build/sim/unit-exit-trace/obj-$waits rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv tests/phone/exit_trace/tb.v > build/sim/unit-exit-trace/build-$waits.log 2>&1 && build/sim/unit-exit-trace/obj-$waits/Vtb > build/sim/unit-exit-trace/run-$waits.log 2>&1 || exit $?
  grep "^PASS" build/sim/unit-exit-trace/run-$waits.log
 done'
