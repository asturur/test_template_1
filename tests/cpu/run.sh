#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"
sh tests/cpu/cp15_rf/sim.sh
sh tests/cpu/completion_owner/sim.sh
sh tests/cpu/completion_owner/format.sh
sh tests/cpu/operands/reference.sh
tests/cpu/operands/sim.sh
tests/cpu/demand_completion/sim.sh
tests/cpu/cp15/sim.sh
tests/cpu/tlb_attributes/sim.sh
tests/cpu/tlb_bus_gate/sim.sh
tests/cpu/write_buffer/sim.sh
tests/cpu/cache_tags/sim.sh
tests/cpu/cache_lines/sim.sh
tests/cpu/cache_bank/sim.sh
tests/cpu/cache_transfer/sim.sh
tests/cpu/cache_refill/sim.sh
tests/cpu/cache_maintenance/sim.sh
tests/cpu/cache_access/sim.sh
tests/cpu/cache_buffer_integration/sim.sh
tests/cpu/core/sim.sh
CPU_PROGRAM=cache_write_miss tests/cpu/core/sim.sh
CPU_PROGRAM=cache_disable_reenable tests/cpu/core/sim.sh
CPU_ASM_DEFINES='-DNONIDENTITY -DUSER_CONTEXT -DSMALLPAGE' tests/cpu/core/sim.sh
CPU_PROGRAM=cpu_timing tests/cpu/core/sim.sh
CPU_PROGRAM=operand_timing tests/cpu/core/sim.sh
CPU_PROGRAM=fiq_privileged_store tests/cpu/core/sim.sh
CPU_PROGRAM=fiq_privileged_ldrt tests/cpu/core/sim.sh
CPU_PROGRAM=fiq_flash_sequence tests/cpu/core/sim.sh
CPU_PROGRAM=fiq_store_return tests/cpu/core/sim.sh
CPU_PROGRAM=swp_basic tests/cpu/core/sim.sh
CPU_PROGRAM=swp_cached tests/cpu/core/sim.sh
CPU_PROGRAM=swp_cached_irq tests/cpu/core/sim.sh
CPU_PROGRAM=swp_bufferable tests/cpu/core/sim.sh
CPU_PROGRAM=swp_mmu_abort tests/cpu/core/sim.sh
CPU_PROGRAM=swp_write_abort CPU_FAULT_ADDR=80001000 CPU_FAULT_WRITE_ONLY=1 tests/cpu/core/sim.sh
CPU_PROGRAM=swp_irq tests/cpu/core/sim.sh
CPU_PROGRAM=swp_irq_core tests/cpu/core/sim.sh
CPU_PROGRAM=swp_fiq tests/cpu/core/sim.sh
tests/cpu/swp_abort/sim.sh
CPU_PROGRAM=swp_read_abort CPU_FAULT_ADDR=80001000 CPU_SWP_BOTH_ABORT=1 tests/cpu/core/sim.sh
CPU_PROGRAM=swp_abort_irq CPU_FAULT_ADDR=80001000 CPU_SWP_ABORT=1 tests/cpu/core/sim.sh
tests/cpu/cache_associativity/sim.sh
# Associative-cache CPU integration; previous direct-mapped implementation is an explicit XFAIL above.
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_associativity tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_instruction_associativity tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_lockdown tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=icache_lockdown tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=icache_prefetch_lockdown tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=icache_prefetch_uncached tests/cpu/core/sim.sh
CPU_PROGRAM=icache_prefetch_translated tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_fcse tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_irq_refill tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_irq_writeback tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_single_maintenance tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=icache_single_invalidate tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=icache_buffer_order tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_write_through tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_drain tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_ASM_DEFINES='-DNONIDENTITY -DUSER_CONTEXT -DSMALLPAGE' tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_external_abort CPU_FAULT_ADDR=80030100 tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_external_abort CPU_FAULT_ADDR=80032000 CPU_ASM_DEFINES=-DPAGE_ABORT tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=ldm_base_fault3650 CPU_ASM_DEFINES=-DCOLD_CACHE tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cpu_wfi tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cpu_wfi CPU_ASM_DEFINES=-DWFI_FIQ CPU_WFI_FIQ=1 tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cpu_wfi CPU_ASM_DEFINES=-DWFI_MASKED tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=cache_tlb_write_order CPU_DELAYS=20 CPU_TLB_ORDER=1 tests/cpu/core/sim.sh
CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM=icache_tlb_write_order CPU_DELAYS=20 CPU_TLB_ORDER=i tests/cpu/core/sim.sh
for program in cache_load_widths ldm_base_coldcache ldm_base_mmu ldm_base_smallpage ldm_cold_base_last ldm_cold_base_not_loaded ldm_base_fault3650 alignment_cases mmu_fcse; do
 CPU_ASSOC_EXPERIMENT=1 CPU_PROGRAM="$program" tests/cpu/core/sim.sh
done

sh tests/cpu/operand_edges/sim.sh
