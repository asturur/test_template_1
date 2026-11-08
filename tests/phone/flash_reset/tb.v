`timescale 1ns/1ps
module ngage_cpu(output [31:0] debug_pc,debug_cpsr,debug_instruction,output debug_fetch,input clk,reset,irq,fiq,input wb_ack,wb_error,input [31:0] wb_read_data,
 output wire wb_code,output reg wb_cyc=0,wb_lock=0,wb_stb=0,wb_write=0,output reg [31:0] wb_address=0,wb_write_data=0,output reg [3:0] wb_byte_enable=15,output [2:0] wb_cycle_type,output [1:0] wb_burst_type);
 assign debug_pc=0;assign debug_cpsr=0;assign debug_instruction=0;assign debug_fetch=0;
 assign wb_code=1'b0;assign wb_cycle_type=0;assign wb_burst_type=0;
endmodule
module tb;
 reg clk=0,reset=1,cold=1;always #5 clk=~clk;
 wire init_done;wire [31:0] da;wire dr,dw;reg accepted=0,done=0;integer accepts=0;
 ngage_mister dut(.clk_sys(clk),.reset(reset),.cold_reset(cold),.debug_freeze_trace(1'b0),.sim_present(1'b0),.board_init_done(init_done),
 .sdram_dout(32'b0),.sdram_ack(1'b0),.ddram_addr(da),.ddram_rd(dr),.ddram_wr(dw),.ddram_dout(32'hdeadbeef),.ddram_dout_ready(done),.ddram_accept((dr||dw)&&!accepted),.keys(27'b0));
 always @(posedge clk)if((dr||dw)&&!accepted)begin accepted<=1;accepts<=accepts+1;end
 task tick;begin @(posedge clk);#1;end endtask
 task scenario;input [31:0] oldaddr;input integer coincident;integer old_count;begin
 @(negedge clk);accepted=0;dut.board.upp.cpu_inside.cpu.wb_cyc=1;dut.board.upp.cpu_inside.cpu.wb_stb=1;dut.board.upp.cpu_inside.cpu.wb_address=oldaddr;
 old_count=accepts;wait(accepts==old_count+1);tick();
 @(negedge clk);reset=1;dut.board.upp.cpu_inside.cpu.wb_cyc=0;dut.board.upp.cpu_inside.cpu.wb_stb=0;done=coincident;tick();
 @(negedge clk);reset=0;done=0;dut.board.upp.cpu_inside.cpu.wb_cyc=1;dut.board.upp.cpu_inside.cpu.wb_stb=1;dut.board.upp.cpu_inside.cpu.wb_address=0;
 if(!coincident)begin repeat(3)tick();@(negedge clk);done=1;tick();done=0;end
 if(dut.wb_ack || dut.wb_err) $fatal(1,"old response reached new request");
 @(negedge clk);accepted=0;wait(accepts==old_count+2);tick();
 @(negedge clk);done=1;tick();done=0;
 if(!dut.wb_ack) $fatal(1,"new response did not complete new request");
 @(negedge clk);dut.board.upp.cpu_inside.cpu.wb_cyc=0;dut.board.upp.cpu_inside.cpu.wb_stb=0;tick();
 end endtask
 initial begin
 repeat(3)tick();cold=0;wait(init_done);tick();reset=0;
 scenario(32'h200,0);scenario(32'h02400000,0);scenario(32'h007f0000,0);scenario(32'h200,1);
 // A short warm-reset pulse between clocks must assert cancellation and
 // remain held until a synchronous drain/release edge.
 @(negedge clk);reset=1;#1;if(!dut.core_reset)$fatal(1,"reset did not assert between clocks");
 reset=0;#1;if(!dut.core_reset)$fatal(1,"reset released without a clock");
 tick();if(dut.core_reset)$fatal(1,"idle reset did not release synchronously");
 $display("PASS reset drains old flash response before restarted request (code, C, PMM, response collision)");$finish;
 end
 initial begin #5000000;$fatal(1,"reset test timeout");end
endmodule
