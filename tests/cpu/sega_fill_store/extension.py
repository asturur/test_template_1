"""Reuse the registered store class and resident credit for ARM register STRH."""
from build import replace


def apply(source):
    predecode = source / 'rtl/arm/zap_predecode_main.sv'
    original = predecode.read_text()
    text = replace(original,
        '      // Classify the original ARM instruction before macro-op expansion:',
        '''      // Classify the original ARM instruction before macro-op expansion.
      // Also allow unconditional register-offset STRH with no writeback.
      // Data for this halfword must pass the normal operand scoreboard.''')
    text = replace(text,
        '            mode32_instruction[19:16] != mode32_instruction[15:12])) &&',
        '''            mode32_instruction[19:16] != mode32_instruction[15:12]) ||
           ((mode32_instruction[31:0] & 32'hff700ff0) == 32'he10000b0 &&
            mode32_instruction[3:0] != 4'd15)) &&''')
    predecode.write_text(text)

    issue = source / 'rtl/arm/zap_issue_main.sv'
    text = issue.read_text()
    # These two older word-store forwarding paths bypass the ALU formatter.
    # Never bypass format or source readiness for the widened store class.
    for kind in ('late', 'second'):
        anchor = f'  wire {kind}_store_eligible = operand_store_overlap && operand_mem_store_ff &&'
        text = replace(text, anchor, anchor + '\n      !operand_mem_unsigned_halfword_enable_ff &&')
    issue.write_text(text)

    core = source / 'rtl/arm/zap_core.sv'
    text = replace(core.read_text(),
        '''  wire store_selected_aligned = data_select_p1 ? postalu1_address_ff[1:0] == 0 : postalu_address_ff[1:0] == 0;
  assign o_data_store_overlap = store_selected_class && store_selected_valid && store_selected_aligned &&
      !store_selected_exception && !older_memory_exception && !clear_from_writeback &&
      !reset && o_data_wb_we && o_data_wb_sel == 4'hf && !o_data_alignment_fault;''',
        '''  wire [1:0] store_selected_offset = data_select_p1 ? postalu1_address_ff[1:0] : postalu_address_ff[1:0];
  wire store_selected_halfword = data_select_p1 ? postalu1_uhalf_ff : postalu_uhalf_ff;
  wire store_selected_lanes = store_selected_halfword ?
      !store_selected_offset[0] && o_data_wb_sel == (store_selected_offset[1] ? 4'b1100 : 4'b0011) :
      store_selected_offset == 2'b00 && o_data_wb_sel == 4'b1111;
  assign o_data_store_overlap = store_selected_class && store_selected_valid && store_selected_lanes &&
      !store_selected_exception && !older_memory_exception && !clear_from_writeback &&
      !reset && o_data_wb_we && !o_data_alignment_fault;''')
    core.write_text(text)
