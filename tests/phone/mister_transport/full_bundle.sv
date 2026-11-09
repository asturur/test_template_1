module full_bundle(input wire clk, reset, download, wr, input wire [26:0] addr,
 input wire [15:0] data, output wire wait_req, valid, failed,
 input wire cpu_valid, input wire [31:0] cpu_addr, output wire cpu_ready, cpu_done, output wire [31:0] cpu_data,
 output wire [1:0] image_profile, output wire known_firmware,
 input wire busy, input wire [63:0] ddr_dout, input wire ddr_dout_ready,
 output wire [28:0] ddr_addr, output wire [63:0] ddr_din,
 output wire [7:0] ddr_be, output wire ddr_rd, ddr_we);
wire lv,lr,ld,av,ar,aw,rsp; wire [31:0] la,ldata,aa,ad,rd; wire [3:0] lb,ab;
ngage_loader loader(clk,reset,download,wr,addr,data,wait_req,valid,failed,lv,lr,la,ldata,lb,ld,image_profile,known_firmware);
ngage_ddr_arbiter arb(clk,reset,1'b0,lv,lr,la,ldata,lb,ld,cpu_valid,cpu_ready,1'b0,cpu_addr,32'b0,4'hf,cpu_done,cpu_data,
 av,ar,aw,aa,ad,ab,rsp,rd,1'b1,);
ngage_ddr_adapter ddr(clk,reset,av,ar,aw,aa,ad,ab,rsp,rd,ddr_addr,ddr_din,ddr_be,ddr_rd,ddr_we,busy,ddr_dout,ddr_dout_ready,1'b0,);
endmodule
