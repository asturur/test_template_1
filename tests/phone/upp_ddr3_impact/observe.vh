 `define UP dut.board.upp.peripherals
 always @(posedge clk) if (!`UP.clearing && `UP.local_ready && `UP.local_access) begin
  if (`UP.upload_selected && `UP.valid_lanes)
   $display("UPP_ACCESS %0d upload %b %h %h %h", cycles,`UP.we,`UP.a,`UP.sel,`UP.we ? `UP.din : `UP.upload_q);
  if (`UP.nosmem_selected && `UP.valid_lanes)
   $display("UPP_ACCESS %0d nos %b %h %h %h", cycles,`UP.we,`UP.a,`UP.sel,`UP.we ? `UP.din : `UP.nosmem_q);
  if (`UP.mdi_claim && !`UP.mdi_bad)
   $display("UPP_ACCESS %0d mdi %b %h %h %h", cycles,`UP.we,`UP.a,`UP.sel,`UP.we ? `UP.din : `UP.mdi_data);
 end
 `undef UP
