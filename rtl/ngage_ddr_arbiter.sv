// Two requesters, one outstanding transaction; responses return to its owner.
// A CPU lock reserves the bus across the gap between SWP read and write.
module ngage_ddr_arbiter(
 input wire clk, input wire reset, input wire cpu_lock,
 input wire l_valid, output wire l_ready, input wire [31:0] l_addr,
 input wire [31:0] l_data, input wire [3:0] l_be, output wire l_done,
 input wire c_valid, output wire c_ready, input wire c_write,
 input wire [31:0] c_addr, input wire [31:0] c_data, input wire [3:0] c_be,
 output wire c_done, output wire [31:0] c_rdata,
 output wire req_valid, input wire req_ready, output wire req_write,
 output wire [31:0] req_addr, output wire [31:0] req_data, output wire [3:0] req_be,
 input wire rsp_valid, input wire [31:0] rsp_data
);
 reg outstanding=0, owner=0, prefer_cpu=0;
 wire choose_cpu = c_valid && (cpu_lock || !l_valid || prefer_cpu);
 wire choose_loader = l_valid && !cpu_lock && !choose_cpu;
 assign req_valid = !outstanding && (choose_cpu || choose_loader);
 assign req_write = choose_cpu ? c_write : 1'b1;
 assign req_addr = choose_cpu ? c_addr : l_addr;
 assign req_data = choose_cpu ? c_data : l_data;
 assign req_be = choose_cpu ? c_be : l_be;
 assign c_ready = req_valid && choose_cpu && req_ready;
 assign l_ready = req_valid && choose_loader && req_ready;
 assign c_done = outstanding && owner && rsp_valid;
 assign l_done = outstanding && !owner && rsp_valid;
 assign c_rdata = rsp_data;
 always @(posedge clk) begin
  if (reset) begin outstanding<=0; owner<=0; prefer_cpu<=0; end
  else begin
   if(req_valid && req_ready) begin outstanding<=1; owner<=choose_cpu; prefer_cpu<=!choose_cpu; end
   if(outstanding && rsp_valid) outstanding<=0;
  end
 end
endmodule
