`define PC dut.u_zap.u_zap_core
`define PM `PC.u_zap_shifter_main.u_zap_multiply
`define PS `PC.u_zap_shifter_main
integer pair_edges=0,pair_busy=0,pair_shift_holds=0;
// Sample before the active edge: advancing means the real shifter captures the
// current issued instruction, with no data hold, multiply busy or older kill.
always @(posedge clk) if(!reset && start_cycle>=0 && windows==2) begin
    if(`PM.o_busy)pair_busy=pair_busy+1;
    if(`PC.u_zap_issue_main.operand_valid && `PC.u_zap_issue_main.shift_lock && !`PC.data_stall && !`PC.stall_from_shifter)pair_shift_holds=pair_shift_holds+1;
    if(retire)$display("RET5D pc=%h",retire_pc);
    if((`PC.issue_pc_plus_8_ff>=32'h100011cc && `PC.issue_pc_plus_8_ff<=32'h100011ec) ||
       (`PC.memory_pc_plus_8_ff>=32'h100011cc && `PC.memory_pc_plus_8_ff<=32'h100011ec))begin
        pair_edges=pair_edges+1;
        $display("PAIR5D e=%0d ipc=%h cc=%h advance=%0d opc=%h oval=%0d pop=%0d lock=%0d shiftlock=%0d loadlock=%0d busy=%0d datahold=%0d killwb=%0d killalu=%0d state=%0d next=%0d op=%0d high=%0d rm=%h rs=%h rn=%h rh=%h product=%h saved=%h result=%h shsrc=%h shifted=%h nozero=%0d mempc=%h last=%0d wen=%0d wa=%0d wd=%h wb=%0d wdb=%h ret=%0d rpc=%h",cycles,`PC.issue_pc_plus_8_ff-8,`PC.issue_condition_code_ff,`PC.issue_condition_code_ff!=15 && !`PC.data_stall && !`PM.o_busy && !`PC.clear_from_writeback && !`PC.clear_from_alu,`PC.u_zap_issue_main.operand_pc_plus_8_ff-8,`PC.u_zap_issue_main.operand_valid,`PC.u_zap_issue_main.operand_pop,`PC.u_zap_issue_main.lock,`PC.u_zap_issue_main.shift_lock,`PC.u_zap_issue_main.load_lock,`PM.o_busy,`PC.data_stall,`PC.clear_from_writeback,`PC.clear_from_alu,`PM.state_ff,`PM.state_nxt,`PM.i_alu_operation_ff,`PM.higher,`PM.i_rm,`PM.i_rs,`PM.i_rn,`PM.i_rh,`PM.full_product,`PM.x_ff,`PM.o_rd,`PS.i_shift_source_value_ff,`PS.rm,`PM.o_nozero,`PC.memory_pc_plus_8_ff-8,`PC.u_zap_writeback.i_uop_last,`PC.rf_wen,`PC.rf_wr_addr_a,`PC.u_zap_writeback.o_rf_wr_data_a,`PC.rf_wr_addr_b,`PC.rf_wr_data_b,retire,retire_pc);
    end
end
final $display("PAIR5D_SUMMARY edges=%0d busy=%0d unhidden_shift_holds=%0d",pair_edges,pair_busy,pair_shift_holds);
`undef PC
`undef PM
`undef PS
