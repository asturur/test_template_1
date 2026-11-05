// SPDX-License-Identifier: GPL-3.0-or-later
// A page-table walk must not overtake older buffered writes. Once offered,
// keep a request enabled until its own bus acknowledgement or error, even if
// a younger write arrives before arbitration grants the walk.
module arm920_tlb_bus_gate(
 input logic clk,reset,write_buffer_empty,
 input logic in_cyc,in_stb,
 output logic out_cyc,out_stb,
 input logic ack,err
);
 logic started;
 wire allow=write_buffer_empty || started;
 assign out_cyc=in_cyc && allow;
 assign out_stb=in_stb && allow;
 always_ff @(posedge clk) begin
  if(reset)started<=0;
  else if(started && (ack || err))started<=0;
  else if(out_stb)started<=1;
 end
endmodule
