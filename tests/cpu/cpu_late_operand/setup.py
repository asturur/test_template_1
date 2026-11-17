"""Original Step5L overlay; production RTL is never edited."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
BASE='ccba54f60a2c6f4741e74428b3306a19717ea58d'
MODE='late'
def overlay(destination,candidate):
    if not candidate:return
    p=destination/'rtl/arm/zap_issue_main.sv';s=p.read_text()
    s=s.replace('    // UOP\n','''    input wire i_late_owner,
    input wire [5:0] i_late_rd,
    output reg o_late_rn,
    output reg o_late_rm,
    // UOP
''',1)
    # Single P1 owner transfers to P2 on acceptance. Reject every younger writer,
    # even predicated writers whose eventual condition has not resolved yet.
    marker='  assign load_lock = determine_load_lock('
    checks=[]
    for valid,dest,load,rd in [('o_condition_code_ff != NV','o_destination_index_ff','o_mem_load_ff','o_mem_srcdest_index_ff'),('i_shifter_dav_ff','i_shifter_destination_index_ff','i_shifter_mem_load_ff','i_shifter_mem_srcdest_index_ff'),('i_alu_dav_ff','i_alu_destination_index_ff','i_alu_mem_load_ff','i_alu_mem_srcdest_index_ff')]:
        checks.append(f'!(({valid}) && ({dest} == i_late_rd || ({load} && {rd} == i_late_rd)))')
    s=s.replace(marker,'''  wire late_rn_match = operand_alu_source_ff[32] != IMMED_EN && operand_alu_source_ff[5:0] == i_late_rd;
  wire late_rm_match = operand_shift_source_ff[32] != IMMED_EN && operand_shift_source_ff[5:0] == i_late_rd;
  wire late_eligible = i_late_owner && operand_condition_code_ff == AL &&
      (operand_alu_operation_ff == ADD || operand_alu_operation_ff == CMP) &&
      operand_is_lsl_0 && !operand_mem_load_ff && !operand_mem_store_ff &&
      operand_destination_index_ff != PHY_PC && !operand_switch_ff &&
      !(operand_irq_ff || operand_fiq_ff || operand_abt_ff || operand_swi_ff || operand_und_ff) &&
      (late_rn_match ^ late_rm_match) &&
      '''+' &&\n      '.join(checks)+''' &&
      i_dc_lock == 0 && !clear && !i_reset;
  always @(posedge i_clk) begin
      if (i_reset || clear) begin o_late_rn <= 0; o_late_rm <= 0; end
      else if (!stall) begin
          o_late_rn <= !issue_block && late_eligible && late_rn_match;
          o_late_rm <= !issue_block && late_eligible && late_rm_match;
      end
  end
  assign load_lock = (!(late_eligible && late_rn_match) && determine_load_lock(''',1)
    # Close RN bypass and open RM bypass; close RM before shift-length term.
    start=s.index('  assign load_lock =')
    head=s[:start];tail=s[start:]
    tail=tail.replace('      ) || determine_load_lock(\n          operand_shift_source_ff,','      )) || (!(late_eligible && late_rm_match) && determine_load_lock(\n          operand_shift_source_ff,',1)
    tail=tail.replace('      ) || determine_load_lock(\n          operand_shift_length_ff,','      )) || determine_load_lock(\n          operand_shift_length_ff,',1)
    p.write_text(head+tail)
    p=destination/'rtl/arm/zap_core.sv';s=p.read_text()
    s=s.replace('  wire issue_store_late,', '  wire issue_late_rn, issue_late_rm;\n  wire issue_store_late,',1)
    s=s.replace('      .o_store_late(issue_store_late),','''      .i_late_owner(p1_load_start),
      .i_late_rd(postalu1_mem_srcdest_index_ff),
      .o_late_rn(issue_late_rn),
      .o_late_rm(issue_late_rm),
      .o_store_late(issue_store_late),''',1)
    # P1 cannot change owner without pipeline advance; P2 and completion hold
    # until the consumer leaves Issue. Capture only the registered completion.
    s=s.replace('.i_alu_source_value_ff            (issue_alu_source_value_ff),','.i_alu_source_value_ff            (issue_late_rn ? completion_data : issue_alu_source_value_ff),',1)
    s=s.replace('.i_shift_source_value_ff          (issue_shift_source_value_ff),','.i_shift_source_value_ff          (issue_late_rm ? completion_data : issue_shift_source_value_ff),',1)
    s=s.replace('  // ALU Stage.','''  // ALU Stage.
`ifndef SYNTHESIS
  always @(posedge i_clk) begin
      if (!reset && !clear_from_writeback && !clear_from_alu && !data_stall &&
          (issue_late_rn || issue_late_rm)) begin
          if ((!issue_word_load_ready && !(completion_valid && completion_fault != 0)) ||
              postalu_mem_srcdest_index_ff != (issue_late_rn ? issue_alu_source_ff[5:0] : issue_shift_source_ff[5:0]))
              $fatal(1, "late arithmetic operand lost P1/P2 owner");
      end
  end
`endif''',1)
    p.write_text(s)
