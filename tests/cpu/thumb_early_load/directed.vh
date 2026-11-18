`define C dut.u_zap.u_zap_core
`define U `C.u_zap_issue_main
wire [31:0] directed_owner_pc=
    (`C.data_select_p1 ? `C.postalu1_pc_plus_8_ff : `C.postalu_pc_plus_8_ff)-4;
wire directed_thumb_owner=`C.data_select_p1 ? `C.postalu1_flags_ff[5] : `C.postalu_flags_ff[5];
always @(posedge clk) if (!reset) begin
    if (`C.alu_dav_ff && `C.alu_mem_load_ff && !`C.data_stall && `C.alu_flags_ff[5])
        $display("CHECK_EXEC pc=%08h class=%0d hint=%0d",`C.alu_pc_plus_8_ff-4,
            `C.alu_load_pair_class,`C.lookup_alu_hint);
    if (`C.completion_offer && directed_thumb_owner)
        $display("CHECK_OFFER pc=%08h early=%0d ack=%0d address=%08h",
            directed_owner_pc,`C.p1_load_start,`C.i_data_wb_ack,`C.o_data_wb_adr);
    if (`C.completion_valid && `C.postalu_flags_ff[5] && `C.completion_fault!=0)
        $display("CHECK_FAULT pc=%08h far=%08h fsr=%08h",
            `C.postalu_pc_plus_8_ff-4,`C.completion_far,`C.completion_fsr);
    if (`U.operand_pop && `U.late_eligible && `C.postalu1_flags_ff[5])
        $display("CHECK_LATE pc=%08h producer=%08h",
            `U.operand_pc_plus_8_ff-4,`C.postalu1_pc_plus_8_ff-4);
    if (retire && retire_pc>=32'h90)
        $display("CHECK_RET pc=%08h",retire_pc+
            (dut.u_zap.u_zap_core.u_zap_writeback.i_flags[5] ? 32'd4 : 32'd0));
end
`undef U
`undef C
