module full_bundle(input wire clk, reset, download, wr, input wire [26:0] addr,
 input wire [15:0] data, output wire wait_req, valid, failed,
 input wire cpu_valid, input wire [31:0] cpu_addr, output wire cpu_ready, cpu_done, output wire [31:0] cpu_data,
 output wire [1:0] image_profile, output wire known_firmware,
 input wire busy, input wire [63:0] ddr_dout, input wire ddr_dout_ready,
 output wire [28:0] ddr_addr, output wire [63:0] ddr_din,
 output wire [7:0] ddr_be, output wire ddr_rd, ddr_we);
wire lv,lr,ld,av,ar,aw,rsp; wire [31:0] la,ldata,aa,ad,rd; wire [3:0] lb,ab;
ngage_loader loader(clk,reset,download,wr,addr,data,wait_req,valid,failed,lv,lr,la,ldata,lb,ld,image_profile,known_firmware);
ngage_ddr_arbiter arb(.clk(clk),.reset(reset),.cpu_lock(1'b0),.l_valid(lv),.l_ready(lr),.l_addr(la),.l_data(ldata),.l_be(lb),.l_done(ld),.c_valid(cpu_valid),.c_ready(cpu_ready),.c_write(1'b0),.c_addr(cpu_addr),.c_data(32'b0),.c_be(4'hf),.c_done(cpu_done),.c_rdata(cpu_data),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_data(ad),.req_be(ab),.rsp_valid(rsp),.rsp_data(rd),.l_write(1'b1),.l_rdata());
ngage_ddr_adapter ddr(.clk(clk),.reset(reset),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_wdata(ad),.req_be(ab),.rsp_valid(rsp),.rsp_data(rd),.ddr_addr(ddr_addr),.ddr_din(ddr_din),.ddr_be(ddr_be),.ddr_rd(ddr_rd),.ddr_we(ddr_we),.ddr_busy(busy),.ddr_dout(ddr_dout),.ddr_dout_ready(ddr_dout_ready),.req_fetch(1'b0),.ddr_burstcount());
endmodule
