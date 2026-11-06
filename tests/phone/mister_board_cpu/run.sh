#!/bin/sh
set -eu
out=build/sim/unit-mister-board-cpu
mkdir -p "$out"
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/mister_board_cpu/program.S -o "$out/program.o"
arm-none-eabi-ld -T sim/programs/link.ld "$out/program.o" -o "$out/program.elf"
arm-none-eabi-objcopy -O binary "$out/program.elf" "$out/program.bin"
python3 - <<'PY'
from pathlib import Path
p=Path('build/sim/unit-mister-board-cpu/program.bin').read_bytes();p+=bytes((-len(p))%4)
Path('build/sim/unit-mister-board-cpu/program.hex').write_text(''.join(f'{int.from_bytes(p[i:i+4],"little"):08x}\n' for i in range(0,len(p),4)))
PY
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'verilator --binary --timing --assert -DNGAGE_ASSOC_EXPERIMENT -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir build/sim/unit-mister-board-cpu/obj rtl/ngage_cpu.sv rtl/arm/*.sv rtl/arm920/*.sv rtl/ngage_mister.v rtl/ngage_board.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v rtl/ngage_rom_map.sv rtl/ngage_codeflash.sv rtl/ngage_cflash.sv rtl/ngage_flash_read_decode.v rtl/ngage_descramble.v tests/phone/mister_board_cpu/tb.v > build/sim/unit-mister-board-cpu/build.log 2>&1 && build/sim/unit-mister-board-cpu/obj/Vtb > build/sim/unit-mister-board-cpu/run.log 2>&1 && grep "^PASS" build/sim/unit-mister-board-cpu/run.log'
