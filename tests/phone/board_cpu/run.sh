#!/bin/sh
set -eu
mkdir -p build/sim/unit-board-cpu
arm-none-eabi-gcc -c -mcpu=arm920t -marm tests/phone/board_cpu/irq_fiq.S -o build/sim/unit-board-cpu/program.o
arm-none-eabi-ld -T sim/programs/link.ld build/sim/unit-board-cpu/program.o -o build/sim/unit-board-cpu/program.elf
arm-none-eabi-objcopy -O binary build/sim/unit-board-cpu/program.elf build/sim/unit-board-cpu/program.bin
python3 - <<'PY'
from pathlib import Path
p=Path('build/sim/unit-board-cpu/program.bin').read_bytes();p+=bytes((-len(p))%4)
Path('build/sim/unit-board-cpu/program.hex').write_text(''.join(f'{int.from_bytes(p[i:i+4],"little"):08x}\n' for i in range(0,len(p),4)))
PY
docker run --rm --network none --platform linux/arm64 -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c 'verilator --binary --timing --assert -Wno-fatal -Wno-lint -Irtl/arm --top-module tb --Mdir build/sim/unit-board-cpu/obj rtl/ngage_cpu.sv rtl/arm/*.sv rtl/ngage_bram.v rtl/arm920/*.sv rtl/ngage_mmc_host.v rtl/ngage_mmc_card.v rtl/ngage_mmc_dpram.v rtl/ngage_board.v rtl/ngage_upp.v rtl/ngage_upp_peripherals.v rtl/ngage_upp_euart.v rtl/ngage_uem.v rtl/ngage_adsp.v rtl/ngage_lrb2.v rtl/ngage_mjoelner.v rtl/ngage_bram_be.v rtl/ngage_sparse_regs.v rtl/ngage_icu.v rtl/ngage_icu_extra.v rtl/ngage_timers.v rtl/ngage_nos_io.v rtl/ngage_mdi_stub.v rtl/ngage_upp_dsp_peer.v rtl/ngage_upp_mdi.v rtl/ngage_cbus_uem.v rtl/ngage_gpio_loopback.v rtl/ngage_boot_regs.v rtl/ngage_trace_sink.v tests/phone/board_cpu/tb.sv > build/sim/unit-board-cpu/build.log 2>&1 && build/sim/unit-board-cpu/obj/Vtb > build/sim/unit-board-cpu/run.log 2>&1 && grep ^PASS build/sim/unit-board-cpu/run.log'
