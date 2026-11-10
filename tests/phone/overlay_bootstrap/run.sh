#!/bin/sh
# Host ARM binutils + existing simulator image. Never uses the long-run builds.
set -eu
out=build/sim/unit-overlay-bootstrap
mkdir -p "$out"
arm-none-eabi-gcc -c -march=armv4t -marm tests/phone/overlay_bootstrap/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 - "$1" <<'PY'
from pathlib import Path
import sys
out=Path('build/sim/unit-overlay-bootstrap')
for name,path,words in [('program',out/'program.bin',256),('bootstrap',Path(sys.argv[1]),128)]:
 data=path.read_bytes();assert len(data)<=words*4;data=data.ljust(words*4,b'\0')
 (out/(name+'.hex')).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4)))
PY
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'verilator --binary --timing --assert -j 2 -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir build/sim/unit-overlay-bootstrap/obj rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv tests/phone/overlay_bootstrap/tb.sv > build/sim/unit-overlay-bootstrap/build.log 2>&1 && build/sim/unit-overlay-bootstrap/obj/Vtb +bootstrap=build/sim/unit-overlay-bootstrap/bootstrap.hex'
