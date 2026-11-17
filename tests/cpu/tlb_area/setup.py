"""Isolated banked main-TLB area candidate, preserving exact offline5L CPU."""
from pathlib import Path
import importlib.util,shutil
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
BASE='ccba54f60a2c6f4741e74428b3306a19717ea58d'
spec=importlib.util.spec_from_file_location('area_late',ROOT/'tests/cpu/cpu_late_operand/setup.py');late=importlib.util.module_from_spec(spec);spec.loader.exec_module(late)
def overlay(destination,candidate):
    late.overlay(destination,True)
    if not candidate:return
    shutil.copyfile(HERE/'rtl/tlb_bank.sv',destination/'rtl/arm920/tlb_bank.sv')
    p=destination/'rtl/arm920/tlb.sv';s=p.read_text()
    s=s.replace('    output wire [31:0] o_lock_read,','    output wire [31:0] o_lock_read,\n    output wire o_mutation_busy,',1)
    s=s.replace('INSTALL=6;','INSTALL=6, INSTALL_WAIT=7;',1)
    s=s.replace('if (bank_fill || token_cpsr', 'if (bank_fill || state==INSTALL_WAIT || token_cpsr',1)
    s=s.replace('wire bank_lookup =','wire bank_busy;\n  assign o_mutation_busy = bank_busy || mutation;\n  wire bank_lookup =',1)
    s=s.replace('&& !owner && !mutation;','&& !owner && !mutation && !bank_busy;',1)
    s=s.replace('      .clk(i_clk),','      .clk(i_clk),\n      .busy(bank_busy),\n      .cancel_fill(state==INSTALL_WAIT && (!i_mmu_en || request_baddr!=i_baddr)),',1)
    s=s.replace('(state != IDLE || (request && !owner) || mutation)', '(state != IDLE || bank_busy || (request && !owner) || mutation)',1)
    old='''        INSTALL: begin
          if (!obsolete)
            publish_mapping(fill_payload);
          state <= IDLE;
        end'''
    new='''        INSTALL: begin
          // One fill pulse; publish only after overlap invalidation and RAM
          // commit. CP15 mutations revoke this owner and drain after the fill.
          state <= obsolete ? IDLE : INSTALL_WAIT;
        end
        INSTALL_WAIT: begin
          if (!bank_busy) begin
            if (!obsolete) publish_mapping(fill_payload);
            state <= IDLE;
          end
        end'''
    assert old in s;s=s.replace(old,new);p.write_text(s)
    for name in ['zap_cache.sv','zap_dcache.sv']:
        p=destination/'rtl/arm'/name;s=p.read_text()
        s=s.replace('    output wire  [       31:0] o_tlb_lock_read,','    output wire  [       31:0] o_tlb_lock_read,\n    output wire o_tlb_mutation_busy,',1)
        assert 'output wire o_tlb_mutation_busy' in s,name
        s=s.replace('      .o_lock_read     (o_tlb_lock_read),','      .o_lock_read     (o_tlb_lock_read),\n      .o_mutation_busy(o_tlb_mutation_busy),',1);p.write_text(s)
    p=destination/'rtl/arm/zap_top.sv';s=p.read_text()
    s=s.replace('  logic [31:0] cpu_baddr, cpu_dac_reg;','  wire dtlb_mutation_busy,itlb_mutation_busy;\n  logic [31:0] cpu_baddr, cpu_dac_reg;',1)
    s=s.replace('      .i_dtlb_lock_read      (dtlb_lock_read),','      .i_dtlb_lock_read      (dtlb_lock_read),\n      .i_dtlb_mutation_busy(dtlb_mutation_busy),\n      .i_itlb_mutation_busy(itlb_mutation_busy),',1)
    s=s.replace('          .o_tlb_lock_read     (dtlb_lock_read),','          .o_tlb_lock_read     (dtlb_lock_read),\n          .o_tlb_mutation_busy(dtlb_mutation_busy),',1)
    s=s.replace('          .o_tlb_lock_read      (itlb_lock_read),','          .o_tlb_lock_read      (itlb_lock_read),\n          .o_tlb_mutation_busy(itlb_mutation_busy),',1);p.write_text(s)
    p=destination/'rtl/arm/zap_core.sv';s=p.read_text()
    s=s.replace('    input  wire  [31:0] i_dtlb_lock_read,','    input wire i_dtlb_mutation_busy, i_itlb_mutation_busy,\n    input  wire  [31:0] i_dtlb_lock_read,',1)
    s=s.replace('      .i_dtlb_lock_read (i_dtlb_lock_read),','      .i_dtlb_lock_read (i_dtlb_lock_read),\n      .i_dtlb_mutation_busy(i_dtlb_mutation_busy),\n      .i_itlb_mutation_busy(i_itlb_mutation_busy),',1);p.write_text(s)
    p=destination/'rtl/arm/zap_cp15_cb.sv';s=p.read_text()
    s=s.replace('    input  wire  [31:0] i_dtlb_lock_read,','    input wire i_dtlb_mutation_busy, i_itlb_mutation_busy,\n    input  wire  [31:0] i_dtlb_lock_read,',1)
    s=s.replace('  localparam [4:0] ICACHE_PREFETCH         = 16;','  localparam [4:0] ICACHE_PREFETCH         = 16;\n  localparam [4:0] WAIT_TLB_MUTATION = 17;',1)
    s=s.replace('            o_tlb_lock_data   <= i_reg_rd_data;','            state <= WAIT_TLB_MUTATION;\n            o_tlb_lock_data   <= i_reg_rd_data;',1)
    s=s.replace('            o_tlb_inv_mva <= i_cp_word.ZAP_OPCODE_2[0];','            state <= WAIT_TLB_MUTATION;\n            o_tlb_inv_mva <= i_cp_word.ZAP_OPCODE_2[0];',1)
    s=s.replace('        LOCK_D_CACHE: begin','''        WAIT_TLB_MUTATION: begin
          // Includes the current registered request pulse, so the first edge
          // cannot finish before the selected bank accepts its mutation.
          if (!i_dtlb_mutation_busy && !i_itlb_mutation_busy) state <= DONE;
        end
        LOCK_D_CACHE: begin''',1);p.write_text(s)
