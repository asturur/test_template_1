`timescale 1ns/1ps
module ngage_cpu #(parameter LINE_REFILL=0)(
 output wire line_req, output wire [31:0] line_addr,
 input wire line_ready,line_reject,line_valid,input wire [63:0] line_data,
 input wire line_wide,line_last,line_error,output [31:0] debug_pc,debug_cpsr,debug_instruction,output debug_fetch,input clk,reset,irq,fiq,input wb_ack,wb_error,input [31:0] wb_read_data,
 output wire wb_code,output reg wb_cyc=0,wb_lock=0,wb_stb=0,wb_write=0,output reg [31:0] wb_address=0,wb_write_data=0,output reg [3:0] wb_byte_enable=15,output [2:0] wb_cycle_type,output [1:0] wb_burst_type);
 assign line_req=0;assign line_addr=0;
 assign debug_pc=0;assign debug_cpsr=0;assign debug_instruction=0;assign debug_fetch=0;
 assign wb_code=1'b0;assign wb_cycle_type=0;assign wb_burst_type=0;
endmodule
module tb;
reg clk=0,reset=1,cold=1;always #5 clk=~clk;
wire init_done;wire [31:0] da,wd,back;wire [3:0] be;wire dr,dw,accept,done;
wire [28:0] phyaddr;wire [63:0] phydata;wire [7:0] phybe;wire phyrd,phywr;reg phyready=0;reg [63:0] read_data=64'hfeedbeefdeadbeef;integer reads=0;
ngage_mister #(.DIRECT_SDRAM(0)) dut(.clk_sys(clk),.reset(reset),.cold_reset(cold),.debug_freeze_trace(1'b0),.sim_present(1'b0),.board_init_done(init_done),
 .sdram_dout(32'b0),.sdram_ack(1'b0),.ddram_addr(da),.ddram_din(wd),.ddram_be(be),.ddram_rd(dr),.ddram_wr(dw),
 .ddram_dout(back),.ddram_dout_ready(done),.ddram_accept(accept),.keys(27'b0));
ngage_ddr_adapter adapter(.clk(clk),.reset(cold),.req_valid(dr||dw),.req_ready(accept),.req_write(dw),.req_addr(da),.req_wdata(wd),.req_be(be),
 .rsp_valid(done),.rsp_data(back),.ddr_addr(phyaddr),.ddr_din(phydata),.ddr_be(phybe),.ddr_rd(phyrd),.ddr_we(phywr),.ddr_busy(1'b0),.ddr_dout(read_data),.ddr_dout_ready(phyready));
always @(posedge clk)if(phyrd)reads<=reads+1;
task tick;begin @(posedge clk);#1;end endtask
initial begin
 repeat(3)tick();cold=0;wait(init_done);tick();reset=0;
 @(negedge clk);dut.board.upp.cpu_inside.cpu.wb_cyc=1;dut.board.upp.cpu_inside.cpu.wb_stb=1;dut.board.upp.cpu_inside.cpu.wb_address='h200;
 wait(reads==1);tick();@(negedge clk);cold=1;reset=1;dut.board.upp.cpu_inside.cpu.wb_cyc=0;dut.board.upp.cpu_inside.cpu.wb_stb=0;tick();
 @(negedge clk);cold=0;phyready=1;tick();@(negedge clk);phyready=0;wait(init_done);tick();reset=0;
 @(negedge clk);dut.board.upp.cpu_inside.cpu.wb_cyc=1;dut.board.upp.cpu_inside.cpu.wb_stb=1;dut.board.upp.cpu_inside.cpu.wb_address=0;
 repeat(2)tick();if(dut.wb_ack || dut.wb_err)$fatal(1,"stale cold response escaped");
 wait(reads==2);tick();@(negedge clk);phyready=1;tick();@(negedge clk);phyready=0;
 wait(dut.wb_ack);if(dut.wb_dat_i!==32'hdeadbeef)$fatal(1,"new read data");
 $display("PASS cold reset drains actual DDR adapter and restarts flash request");$finish;
end
initial begin #5000000;$fatal(1,"cold reset timeout");end
endmodule
