#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
mkdir -p build/sim/unit-core
program=${CPU_PROGRAM:-thumb_return_dependency}
arm-none-eabi-gcc -c -mcpu=arm920t -marm ${CPU_ASM_DEFINES:-} "sim/programs/$program.S" -o build/sim/unit-core/program.o
arm-none-eabi-ld -T sim/programs/link.ld build/sim/unit-core/program.o -o build/sim/unit-core/program.elf
arm-none-eabi-objcopy -O binary build/sim/unit-core/program.elf build/sim/unit-core/program.bin
python3 - <<'PY'
from pathlib import Path
b=Path('build/sim/unit-core/program.bin').read_bytes();b+=bytes((-len(b))%4)
Path('build/sim/unit-core/program.hex').write_text(''.join(f'{int.from_bytes(b[i:i+4],"little"):08x}\n' for i in range(0,len(b),4)))
PY
# Tests may select a preserved source snapshot without duplicating production RTL.
arm_rtl=""
for source in rtl/arm/*.sv; do
 if [ -n "${CPU_REFERENCE_DIR:-}" ] && [ -f "$CPU_REFERENCE_DIR/$(basename "$source")" ]; then
  arm_rtl="$arm_rtl $CPU_REFERENCE_DIR/$(basename "$source")"
 else
  arm_rtl="$arm_rtl $source"
 fi
done
extra_rtl=""
extra_define=""
if [ -n "${CPU_REFERENCE_DIR:-}" ]; then extra_define="-DNGAGE_OPERAND_REFERENCE"; fi
if [ "${CPU_ASSOC_EXPERIMENT:-1}" = 1 ]; then
 extra_rtl="rtl/arm920/tlb_bus_gate.sv rtl/arm920/write_buffer.sv rtl/arm920/cache_tags.sv rtl/ngage_bram.v rtl/arm920/cache_lines.sv rtl/arm920/cache_bank.sv rtl/arm920/cache_transfer.sv rtl/arm920/cache_refill.sv rtl/arm920/cache_maintenance.sv rtl/arm920/cache_access.sv rtl/arm920/zap_dcache_adapter.sv"
 extra_define="$extra_define -DNGAGE_ASSOC_EXPERIMENT"
fi
if [ "${CPU_SDRAM_PATH:-0}" = 1 ]; then
 extra_rtl="$extra_rtl rtl/ngage_sdram_adapter.v rtl/ngage_sdram_arbiter.v"
 extra_define="$extra_define -DNGAGE_SDRAM_PATH"
fi
if [ "${CPU_BUS_BRIDGE:-0}" = 1 ]; then
 extra_rtl="$extra_rtl rtl/ngage_upp.v"
 extra_define="$extra_define -DNGAGE_TEST_BUS_BRIDGE"
fi
docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint verilator jotego/simulator:arm64 \
 --binary --timing --assert $extra_define -DNGAGE_RUNTIME_TRACE -Wno-fatal -Wno-lint -Irtl/arm --top-module test --Mdir build/sim/unit-core \
 rtl/ngage_cpu.sv $arm_rtl $extra_rtl tests/cpu/core/test.sv > build/sim/unit-core/build.log 2>&1
extra="${CPU_RUN_ARGS:-}"
if [ "$program" = cpu_timing ] || [ "$program" = operand_timing ]; then
 first=$(arm-none-eabi-nm build/sim/unit-core/program.elf | awk '$3=="timing_first" {print $1}')
 last=$(arm-none-eabi-nm build/sim/unit-core/program.elf | awk '$3=="timing_last" {print $1}')
 extra="$extra +pc_first=$first +pc_last=$last"
 for marker in init_branch init_target; do
  address=$(arm-none-eabi-nm build/sim/unit-core/program.elf | awk -v symbol="measure_$marker" '$3==symbol {print $1}')
  extra="$extra +measure_$marker=$address"
 done
fi
if [ "$program" = operand_timing ]; then
 for marker in load use branch target; do
  address=$(arm-none-eabi-nm build/sim/unit-core/program.elf | awk -v symbol="measure_$marker" '$3==symbol {print $1}')
  extra="$extra +measure_$marker=$address"
 done
fi
if [ "$program" = cache_associativity ]; then extra="+cache_conflict"; fi
if [ "$program" = swp_basic ]; then extra="+swp_tags +swp_dma"; fi
if [ "$program" = fiq_privileged_store ]; then extra="+fiq_privileged_store"; fi
if [ "$program" = fiq_privileged_ldrt ] || [ "$program" = fiq_flash_sequence ] || [ "$program" = fiq_store_return ] || [ "$program" = fiq_flash_return ]; then extra="$extra +fiq_privileged_store +fiq_during_usrt"; fi
if [ "$program" = swp_cached ]; then extra="+swp_cached"; fi
if [ "$program" = swp_cached_irq ]; then extra="+swp_cached_irq"; fi
if [ "$program" = swp_bufferable ]; then extra="+swp_bufferable"; fi
if [ "$program" = swp_mmu_abort ]; then extra="+swp_mmu_abort"; fi
if [ "$program" = cache_irq_refill ]; then extra="+irq_refill"; fi
if [ "$program" = swp_irq ]; then extra="+swp_irq"; fi
if [ "$program" = swp_irq_core ]; then extra="+swp_irq_core"; fi
if [ "$program" = swp_abort_irq ]; then extra="+swp_irq_abort"; fi
if [ "$program" = swp_fiq ]; then extra="+swp_fiq"; fi
if [ "$program" = cache_irq_writeback ]; then extra="+irq_writeback"; fi
if [ "$program" = cpu_wfi ]; then
 extra="+wfi_test"
 if [ "${CPU_WFI_FIQ:-0}" = 1 ]; then extra="$extra +wfi_fiq"; fi
fi
if [ "$program" = cache_instruction_associativity ] || [ "$program" = icache_lockdown ] || [ "$program" = icache_prefetch_lockdown ] || [ "$program" = icache_prefetch_uncached ] || [ "$program" = icache_prefetch_translated ]; then
 first=$(arm-none-eabi-nm build/sim/unit-core/program.elf | awk '$3=="icache_function_a" {print $1}')
 extra="+icache_first=$first"
 if [ "$program" = icache_prefetch_lockdown ] || [ "$program" = icache_prefetch_translated ]; then extra="$extra +check_prefetch"; fi
 if [ "$program" = icache_prefetch_uncached ]; then extra="$extra +check_prefetch +prefetch_expected=0"; fi
fi
if [ -n "${CPU_MAX_CYCLES:-}" ]; then extra="$extra +max_cycles=$CPU_MAX_CYCLES"; fi
if [ -n "${CPU_FAULT_ADDR:-}" ]; then extra="$extra +fault_addr=$CPU_FAULT_ADDR"; fi
if [ "${CPU_SWP_ABORT:-0}" = 1 ]; then extra="$extra +fault_read_only +swp_abort_check"; fi
if [ "${CPU_SWP_BOTH_ABORT:-0}" = 1 ]; then extra="$extra +swp_abort_check"; fi
if [ "${CPU_FAULT_WRITE_ONLY:-0}" = 1 ]; then extra="$extra +fault_write_only"; fi
if [ "${CPU_TLB_ORDER:-0}" = 1 ]; then extra="$extra +tlb_order"; fi
if [ "${CPU_TLB_ORDER:-0}" = i ]; then extra="$extra +tlb_order_i"; fi
for delay in ${CPU_DELAYS:-0 3}; do
 if ! docker run --rm --network none --platform linux/arm64 -v "$root:/work" -w /work --entrypoint /work/build/sim/unit-core/Vtest jotego/simulator:arm64 +ngage-compact-trace +latency="$delay" $extra > "build/sim/unit-core/run-$delay.log" 2>&1; then
  tail -30 "build/sim/unit-core/run-$delay.log"
  exit 1
 fi
 grep -E '^(PASS|TIMING|STALL|COUNTERS|METRICS|PHASES|INIT_EDGES):' "build/sim/unit-core/run-$delay.log"
done
