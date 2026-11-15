// Simulation-only owner checks. Compare P1 before the transfer with the actual
// P2 packet one clock later, independently of the outgoing request muxes.
`define F2C dut.u_zap.u_zap_core
integer overlap_count=0, overlap_read=0, overlap_write=0, overlap_ack=0;
integer overlap_narrow=0, overlap_user=0;
reg overlap_pending=0;
reg [121:0] overlap_packet;
wire [121:0] overlap_p1={
  `F2C.postalu1_address_ff, `F2C.postalu1_data_wb_dat,
  `F2C.postalu1_data_wb_sel, `F2C.postalu1_data_wb_we,
  `F2C.postalu1_flags_ff[4:0], `F2C.postalu1_mem_translate_ff,
  `F2C.postalu1_swp_tag, `F2C.postalu1_mem_srcdest_index_ff,
  `F2C.postalu1_sbyte_ff, `F2C.postalu1_ubyte_ff,
  `F2C.postalu1_shalf_ff, `F2C.postalu1_uhalf_ff,
  `F2C.postalu1_pc_plus_8_ff, `F2C.postalu1_dav_ff,
  `F2C.postalu1_data_wb_cyc, `F2C.postalu1_data_wb_stb};
wire [121:0] overlap_p2={
  `F2C.postalu_address_ff, `F2C.postalu_data_wb_dat,
  `F2C.postalu_data_wb_sel, `F2C.postalu_data_wb_we,
  `F2C.postalu_flags_ff[4:0], `F2C.postalu_mem_translate_ff,
  `F2C.postalu_swp_tag, `F2C.postalu_mem_srcdest_index_ff,
  `F2C.postalu_sbyte_ff, `F2C.postalu_ubyte_ff,
  `F2C.postalu_shalf_ff, `F2C.postalu_uhalf_ff,
  `F2C.postalu_pc_plus_8_ff, `F2C.postalu_dav_ff,
  `F2C.postalu_request_cyc, `F2C.postalu_request_stb};
always @(posedge clk)begin
  if(reset)overlap_pending<=0;
  else begin
    if(overlap_pending && overlap_p2!==overlap_packet)
      $fatal(1,"completion overlap lost next P2 owner");
    overlap_pending<=`F2C.completion_next;
    if(`F2C.completion_next)begin
      if(`F2C.data_stall || `F2C.clear_from_writeback ||
         !`F2C.completion_valid || `F2C.completion_fault!=0 ||
         `F2C.postalu_swp_tag!=0 || `F2C.postalu1_swp_tag!=0 ||
         `F2C.postalu_mem_srcdest_index_ff==15 ||
         `F2C.postalu_destination_index_ff==15 ||
         `F2C.postalu_irq_ff || `F2C.postalu_fiq_ff || `F2C.postalu_abt_ff ||
         `F2C.postalu_swi_ff || `F2C.postalu_und_ff)
        $fatal(1,"unsafe completion overlap");
      if({`F2C.o_data_wb_adr,`F2C.o_data_wb_dat,`F2C.o_data_wb_sel,
          `F2C.o_data_wb_we,`F2C.o_data_cpsr,`F2C.o_mem_translate,
          `F2C.o_data_swp_tag,`F2C.o_dc_reg_idx_bin,`F2C.o_dc_load_info}
         !=={`F2C.postalu1_address_ff[31:2],2'b00,`F2C.postalu1_data_wb_dat,
          `F2C.postalu1_data_wb_sel,`F2C.postalu1_data_wb_we,
          `F2C.postalu1_flags_ff[4:0],`F2C.postalu1_mem_translate_ff,
          `F2C.postalu1_swp_tag,`F2C.postalu1_mem_srcdest_index_ff,
          `F2C.postalu1_sbyte_ff,`F2C.postalu1_ubyte_ff,
          `F2C.postalu1_shalf_ff,`F2C.postalu1_uhalf_ff,
          `F2C.postalu1_address_ff[1:0]})
        $fatal(1,"completion overlap mixed request fields");
      if(`F2C.o_data_alignment_far!==`F2C.postalu1_address_ff)
        $fatal(1,"completion overlap lost unaligned FAR");
      overlap_packet<=overlap_p1;
      overlap_count++;
      if(`F2C.o_data_wb_we)overlap_write++;else overlap_read++;
      if(`F2C.i_data_wb_ack)overlap_ack++;
      if(|`F2C.o_dc_load_info[5:2])overlap_narrow++;
      if(`F2C.o_mem_translate)overlap_user++;
    end
  end
end
final begin
  $display("COMPLETION_OVERLAP: total=%0d read=%0d write=%0d immediate=%0d narrow=%0d force_user=%0d",
    overlap_count,overlap_read,overlap_write,overlap_ack,overlap_narrow,overlap_user);
  if($test$plusargs("completion_overlap_check") &&
     (overlap_read<10 || overlap_write<10 || overlap_narrow<5 || overlap_user<1))
    $fatal(1,"completion overlap coverage missing");
end
`undef F2C
