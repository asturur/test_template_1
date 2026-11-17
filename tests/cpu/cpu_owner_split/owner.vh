// Every offered packet must be byte-identical to the qualified5A selection.
// Idle payload preselection is private; its safety is checked in the cache,
// TLB, fault/kill and SWP fixtures, rather than assuming idle fields are ignored.
`define OWN dut.u_zap.u_zap_core
integer own_offers=0,own_private=0,own_held_late=0;
always @(negedge clk) if (!reset) begin
    if (`OWN.o_data_swp_tag !== (`OWN.completion_next ? `OWN.postalu1_swp_tag : `OWN.postalu_swp_tag))
        $fatal(1,"SWP identity changed");
    if (`OWN.completion_valid && !`OWN.completion_next) begin
        own_private=own_private+1;
        if (`OWN.o_data_wb_cyc || `OWN.o_data_wb_stb) $fatal(1,"private P1 escaped offer qualification");
        if (`OWN.postalu1_store_late && !`OWN.late_p1_ready) own_held_late=own_held_late+1;
    end
    if (`OWN.completion_offer) begin
        own_offers=own_offers+1;
        if (`OWN.completion_valid !== `OWN.completion_next) $fatal(1,"offered owner differs from5A");
        if (`OWN.o_data_wb_adr !== (`OWN.completion_next ? {`OWN.postalu1_address_ff[31:2],2'b0} : {`OWN.postalu_address_ff[31:2],2'b0}) ||
            `OWN.o_data_wb_we !== (`OWN.completion_next ? `OWN.postalu1_data_wb_we : `OWN.postalu_data_wb_we) ||
            `OWN.o_data_wb_sel !== (`OWN.completion_next ? `OWN.postalu1_data_wb_sel : `OWN.postalu_data_wb_sel) ||
            `OWN.o_data_cpsr !== (`OWN.completion_next ? `OWN.postalu1_flags_ff[4:0] : `OWN.postalu_flags_ff[4:0]) ||
            `OWN.o_mem_translate !== (`OWN.completion_next ? `OWN.postalu1_mem_translate_ff : `OWN.postalu_mem_translate_ff))
            $fatal(1,"qualified owner payload mismatch");
    end
end
final $display("OWNER_CHECK offers=%0d private_no_offer=%0d private_late_hold=%0d",own_offers,own_private,own_held_late);
`undef OWN
