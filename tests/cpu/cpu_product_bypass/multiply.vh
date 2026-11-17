`define MC dut.u_zap.u_zap_core
`define MM `MC.u_zap_shifter_main.u_zap_multiply
integer mul_busy_clocks=0,mul_low_results=0,mul_high_results=0,mul_zero_addends=0;
always @(negedge clk) if (!reset && start_cycle>=0) begin
    if (windows==2) begin
        if (`MM.o_busy) mul_busy_clocks=mul_busy_clocks+1;
        if (`MM.state_ff==5'b10000 && !`MM.i_data_stall) begin
            if (`MM.higher) mul_high_results=mul_high_results+1;
            else begin
                mul_low_results=mul_low_results+1;
                if (`MM.i_rn==0 && `MM.i_rh==0) mul_zero_addends=mul_zero_addends+1;
            end
        end
        if (`MC.issue_pc_plus_8_ff>=32'h100011cc && `MC.issue_pc_plus_8_ff<=32'h100011ec ||
            `MC.shifter_pc_plus_8_ff>=32'h100011cc && `MC.shifter_pc_plus_8_ff<=32'h100011ec ||
            `MC.memory_pc_plus_8_ff>=32'h100011cc && `MC.memory_pc_plus_8_ff<=32'h100011ec)
            $display("MUL_EDGE e=%0d opc=%h pop=%0d ipc=%h spc=%h state=%0d next=%0d op=%0d higher=%0d rm=%h rs=%h rn=%h rh=%h fa=%h fb=%h product=%h x=%h busy=%0d result=%h hold=%0d alu=%h mem=%h wen=%0d dest=%0d data=%h dest_a=%0d data_a=%h shsrc=%h shlen=%h ret=%0d rpc=%h shlock=%0d",cycles,`MC.u_zap_issue_main.operand_pc_plus_8_ff-8,`MC.u_zap_issue_main.operand_pop,`MC.issue_pc_plus_8_ff-8,`MC.shifter_pc_plus_8_ff-8,`MM.state_ff,`MM.state_nxt,`MM.i_alu_operation_ff,`MM.higher,`MM.i_rm,`MM.i_rs,`MM.i_rn,`MM.i_rh,`MM.factor_a,`MM.factor_b,`MM.full_product,`MM.x_ff,`MM.o_busy,`MM.o_rd,`MM.i_data_stall,`MC.alu_pc_plus_8_ff-8,`MC.memory_pc_plus_8_ff-8,`MC.rf_wen,`MC.rf_wr_addr_b,`MC.rf_wr_data_b,`MC.rf_wr_addr_a,`MC.u_zap_writeback.o_rf_wr_data_a,`MC.u_zap_shifter_main.i_shift_source_value_ff,`MC.u_zap_shifter_main.i_shift_length_value_ff,retire,retire_pc,`MC.u_zap_issue_main.shift_lock);
    end
end
final $display("MUL_SUMMARY busy=%0d low_results=%0d high_results=%0d zero_addends=%0d",mul_busy_clocks,mul_low_results,mul_high_results,mul_zero_addends);
`undef MM
`undef MC
