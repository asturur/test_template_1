"""Step5M: registered demand permission, on the exact retained Step5L overlay."""
from pathlib import Path
import importlib.util
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
BASE='ccba54f60a2c6f4741e74428b3306a19717ea58d'
spec=importlib.util.spec_from_file_location('step5l_overlay',ROOT/'tests/cpu/cpu_late_operand/setup.py');late=importlib.util.module_from_spec(spec);spec.loader.exec_module(late)
MODE='admission'
def overlay(destination,candidate):
    late.overlay(destination,True)
    if not candidate:return
    p=destination/'rtl/arm/zap_cp15_cb.sv';s=p.read_text()
    s=s.replace('    output logic [31:0] o_baddr,','    output logic [31:0] o_baddr,\n    output reg o_context_change,',1)
    s=s.replace('  // Ties registers to output ports via a register.', '''  // Change event is registered on the SAME edge as the exported context.
  // Wide comparisons end at this flop, never at demand ACK/token consumption.
  always @(posedge i_clk) begin
      if (i_reset) o_context_change <= 1'b1;
      else o_context_change <= o_baddr != r[2] || o_dac != r[3] ||
          o_sr != {r[1][8],r[1][9]} || o_mmu_en != r[1][0] ||
          o_alignment_en != r[1][1] || o_dcache_en != r[1][2] ||
          o_pid != {1'b0,r[13][31:25]};
  end
  // Ties registers to output ports via a register.''',1);p.write_text(s)
    p=destination/'rtl/arm/zap_core.sv';s=p.read_text()
    s=s.replace('    output logic [31:0] o_baddr,','    output logic [31:0] o_baddr,\n    output wire o_data_context_change,\n    output wire o_data_admission_clear,',1)
    s=s.replace('      .o_baddr          (o_baddr),','      .o_baddr          (o_baddr),\n      .o_context_change (o_data_context_change),',1)
    s=s.replace('  wire issue_late_rn,','  assign o_data_admission_clear = clear_from_writeback;\n  wire issue_late_rn,',1);p.write_text(s)
    p=destination/'rtl/arm/zap_top.sv';s=p.read_text()
    s=s.replace('  logic [31:0] cpu_baddr, cpu_dac_reg;', '  wire data_context_change, data_admission_clear;\n  logic [31:0] cpu_baddr, cpu_dac_reg;',1)
    s=s.replace('      .o_baddr               (cpu_baddr),','      .o_baddr               (cpu_baddr),\n      .o_data_context_change(data_context_change),\n      .o_data_admission_clear(data_admission_clear),',1)
    s=s.replace('          .i_stall          (1\'d0),', '          .i_context_change(data_context_change),\n          .i_admission_clear(data_admission_clear),\n          .i_stall          (1\'d0),',1);p.write_text(s)
    p=destination/'rtl/arm/zap_dcache.sv';s=p.read_text()
    s=s.replace('    input logic i_stall,','    input wire i_context_change,\n    input wire i_admission_clear,\n    input logic i_stall,',1)
    # Revoke retained translation/resync along with the admission owner.
    s=s.replace("if (i_reset || !(i_rd || i_wr) || o_ack)", "if (i_reset || admission_revoke || !(i_rd || i_wr) || o_ack)",1)
    s=s.replace("if (i_reset) begin\n      lookup_resync", "if (i_reset || admission_revoke) begin\n      lookup_resync",1)
    s=s.replace("if (i_reset) checked_request_prev", "if (i_reset || admission_revoke) checked_request_prev",1)
    marker='  arm920_cache_adapter #('
    block='''  wire admission_idle_ack;
  assign o_ack = !(i_rd || i_wr) ? admission_idle_ack : o_request_ack;
  // Permission belongs to ONE actual demand, not a speculative hint.
  // Payload and permission/fault cross this boundary together. The private
  // BRAM lookup continues to prepare lines without external authority.
  reg admission_valid;
  reg [31:0] admission_va, admission_pa, admission_far, admission_align_far;
  reg [7:0] admission_fsr, admission_external_fsr;
  reg [4:0] admission_mode;
  reg [3:0] admission_ben;
  reg [1:0] admission_swp;
  reg admission_rd, admission_wr, admission_fault, admission_busy;
  reg admission_cacheable, admission_bufferable, admission_cache_enable;
  reg admission_alignment;
  wire admission_revoke = i_context_change || i_admission_clear || i_tlb_inv ||
      i_tlb_lock_write || i_cache_inv_req || i_cache_clean_req || i_cache_lock_write;
  wire admitted = admission_valid && !admission_revoke &&
      admission_va == i_address && admission_rd == i_rd && admission_wr == i_wr &&
      admission_mode == i_cpsr && admission_ben == i_ben && admission_swp == i_swp_tag &&
      admission_align_far[1:0] == i_alignment_far[1:0];
  wire admission_settled = !translation_wait;
  always @(posedge i_clk) begin
      if (i_reset || admission_revoke) admission_valid <= 1'b0;
      else admission_valid <= (i_rd || i_wr) && !o_request_ack && admission_settled;
      if ((i_rd || i_wr) && admission_settled) begin
          admission_va <= i_address;
          admission_rd <= i_rd; admission_wr <= i_wr;
          admission_mode <= i_cpsr; admission_ben <= i_ben; admission_swp <= i_swp_tag;
          admission_pa <= pending_translation ? pending_pa : tlb_phy_addr;
          admission_far <= pending_translation ? pending_far : tlb_far;
          admission_fsr <= pending_translation ? pending_fsr : tlb_fsr;
          admission_external_fsr <= pending_translation ? pending_external_fsr : tlb_external_fsr;
          admission_fault <= pending_translation ? pending_fault : (tlb_busy ? 1'b0 : tlb_fault);
          admission_busy <= pending_translation ? 1'b0 : tlb_busy;
          admission_cacheable <= pending_translation ? pending_cacheable : tlb_cacheable;
          admission_bufferable <= pending_translation ? pending_bufferable : tlb_bufferable;
          admission_cache_enable <= i_cache_en;
          admission_alignment <= i_alignment_fault;
          admission_align_far <= i_alignment_far;
      end
  end
`ifndef SYNTHESIS
  // Context can only mutate before admission or after a serialized transaction.
  // No live wide context comparison participates in admitted/ACK selection.
  always @(posedge i_clk) if (!i_reset && admitted) begin
      if (admission_fault && cache_adapter.req_valid)
          $fatal(1,"faulted admission issued cache request");
  end
`endif
'''
    s=s.replace(marker,block+marker,1)
    # Restrict replacements to adapter instance; raw TLB and retained-translation
    # state still see current controls and feed only the permission register.
    a=s.index('  ) cache_adapter (');b=s.index('\n  logic tlb_raw_stb',a)
    head=s[:a];t=s[a:b];tail=s[b:]
    replacements={
      '.physical(pending_translation ? pending_pa : tlb_phy_addr)':'.physical(admission_pa)',
      '.rd(i_rd)':'.rd(i_rd && admitted)', '.wr(i_wr)':'.wr(i_wr && admitted)',
      '.far_in(pending_translation ? pending_far : tlb_far)':'.far_in(admission_far)',
      '.alignment_fault(i_alignment_fault)':'.alignment_fault(admitted && admission_alignment)',
      '.alignment_far(i_alignment_far)':'.alignment_far(admission_align_far)',
      '.fault(pending_translation ? pending_fault : (tlb_busy ? 1\'b0 : tlb_fault))':'.fault(admitted && admission_fault)',
      '.fsr_in(pending_translation ? pending_fsr : tlb_fsr)':'.fsr_in(admission_fsr)',
      '.external_fsr(pending_translation ? pending_external_fsr : tlb_external_fsr)':'.external_fsr(admission_external_fsr)',
      '.tlb_busy(pending_translation ? 1\'b0 : tlb_busy)':'.tlb_busy(admitted && admission_busy)',
      '.translation_wait(translation_wait)':'.translation_wait(!admitted)',
      '.cache_enable(i_cache_en)':'.cache_enable(admission_cache_enable)',
      '.cacheable(pending_translation ? pending_cacheable : tlb_cacheable)':'.cacheable(admission_cacheable)',
      '.bufferable(pending_translation ? pending_bufferable : tlb_bufferable)':'.bufferable(admission_bufferable)',
      '.ack(o_ack)':'.ack(admission_idle_ack)',
    }
    for old,new in replacements.items():
        assert old in t,old;t=t.replace(old,new,1)
    # Idle ACK cannot complete a live CPU request waiting for permission.
    p.write_text(head+t+tail)
