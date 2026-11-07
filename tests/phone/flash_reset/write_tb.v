`timescale 1ns/1ps
module ngage_cpu(input clk,reset,irq,fiq,input wb_ack,wb_error,input [31:0] wb_read_data,
 output wire wb_code,output reg wb_cyc=0,wb_lock=0,wb_stb=0,wb_write=0,output reg [31:0] wb_address=0,wb_write_data=0,output reg [3:0] wb_byte_enable=15,output [2:0] wb_cycle_type,output [1:0] wb_burst_type);
 assign wb_code=1'b0;assign wb_cycle_type=0;assign wb_burst_type=0;
endmodule
module tb;
reg clk=0,reset=1,cold=1;always #5 clk=~clk;
wire init_done;wire [31:0] da,wd,back;wire [3:0] be;wire dr,dw,accept,done,dirty;wire [13:0] sector;
wire rv,rr,rw,rsp;wire [31:0] ra,rd,rdata;wire [3:0] rb;
wire [28:0] pa;wire [63:0] pd;wire [7:0] pb;wire pr,pw;reg busy=0,ready=0;reg [63:0] mem=64'hffffffffffffffff;integer writes=0,dirty_count=0;reg [13:0] last_dirty=0;
wire tracker_init,sector_valid;wire [13:0] sector_index;reg flush=0,sector_accept=0,sector_done=0;
ngage_mister dut(.clk_sys(clk),.reset(reset),.cold_reset(cold),.debug_freeze_trace(1'b0),.sim_present(1'b0),.board_init_done(init_done),
 .sdram_dout(32'b0),.sdram_ack(1'b0),.ddram_addr(da),.ddram_din(wd),.ddram_be(be),.ddram_rd(dr),.ddram_wr(dw),
 .ddram_dout(back),.ddram_dout_ready(done),.ddram_accept(accept),.flash_dirty(dirty),.flash_dirty_sector(sector),.keys(27'b0));
ngage_ddr_arbiter arb(.clk(clk),.reset(cold),.cpu_lock(1'b0),.l_valid(1'b0),.l_addr(32'b0),.l_data(32'b0),.l_be(4'b0),.l_write(1'b0),
 .c_valid(dr||dw),.c_ready(accept),.c_write(dw),.c_addr(da),.c_data(wd),.c_be(be),.c_done(done),.c_rdata(back),
 .req_valid(rv),.req_ready(rr),.req_write(rw),.req_addr(ra),.req_data(rd),.req_be(rb),.rsp_valid(rsp),.rsp_data(rdata));
ngage_ddr_adapter adapter(.clk(clk),.reset(cold),.req_valid(rv),.req_ready(rr),.req_write(rw),.req_addr(ra),.req_wdata(rd),.req_be(rb),
 .rsp_valid(rsp),.rsp_data(rdata),.ddr_addr(pa),.ddr_din(pd),.ddr_be(pb),.ddr_rd(pr),.ddr_we(pw),.ddr_busy(busy),.ddr_dout(mem),.ddr_dout_ready(ready));
ngage_dirty_tracker tracker(.clk(clk),.cold_reset(cold),.dirty_valid(dirty),.dirty_sector(sector),.flush_start(flush),.flushing(),.flush_error(),.init_done(tracker_init),
 .sector_valid(sector_valid),.sector_accept(sector_accept),.sector_index(sector_index),.sector_done(sector_done),.sector_ok(1'b1),.abort_flush(1'b0));
integer j;always @(posedge clk)begin
 ready<=0;if(pr && !busy)ready<=1;
 if(pw && !busy)begin for(j=0;j<8;j=j+1)if(pb[j])mem[j*8+:8]<=pd[j*8+:8];writes<=writes+1;end
 if(dirty)begin dirty_count<=dirty_count+1;last_dirty<=sector;end
end
task tick;begin @(posedge clk);#1;end endtask
task cpu_cmd;input [31:0] a;input [15:0] v;integer n;begin
 @(negedge clk);dut.board.upp.cpu_inside.cpu.wb_cyc=1;dut.board.upp.cpu_inside.cpu.wb_stb=1;dut.board.upp.cpu_inside.cpu.wb_write=1;dut.board.upp.cpu_inside.cpu.wb_address=a;
 dut.board.upp.cpu_inside.cpu.wb_byte_enable=a[1]?12:3;dut.board.upp.cpu_inside.cpu.wb_write_data=a[1]?{v,16'b0}:{16'b0,v};
 n=0;while(!dut.wb_ack && !dut.wb_err && n<200)begin tick();n=n+1;end
 if(!dut.wb_ack || dut.wb_err)$fatal(1,"command failed %h",a);
 @(negedge clk);dut.board.upp.cpu_inside.cpu.wb_cyc=0;dut.board.upp.cpu_inside.cpu.wb_stb=0;tick();
end endtask
task start_program;input [31:0] address;input [15:0] val;begin
 @(negedge clk);dut.board.upp.cpu_inside.cpu.wb_cyc=1;dut.board.upp.cpu_inside.cpu.wb_stb=1;dut.board.upp.cpu_inside.cpu.wb_write=1;
 dut.board.upp.cpu_inside.cpu.wb_address=address;dut.board.upp.cpu_inside.cpu.wb_byte_enable=3;dut.board.upp.cpu_inside.cpu.wb_write_data={16'b0,val};
 wait(dw);busy=1;wait(accept);tick();@(negedge clk);reset=1;dut.board.upp.cpu_inside.cpu.wb_cyc=0;dut.board.upp.cpu_inside.cpu.wb_stb=0;tick();
 @(negedge clk);reset=0;repeat(3)tick();if(!dut.core_reset)$fatal(1,"CPU released before accepted write drains");
 @(negedge clk);busy=0;wait(dirty);tick();wait(!dut.core_reset);tick();
end endtask
initial begin
 repeat(3)tick();cold=0;wait(init_done && tracker_init);tick();reset=0;
 cpu_cmd(32'h02400aaa,16'haa);cpu_cmd(32'h02400554,16'h55);cpu_cmd(32'h02400aaa,16'ha0);
 start_program(32'h02400100,16'h1234);if(mem[15:0]!==16'h1234 || last_dirty!==0)$fatal(1,"C drive dirty/write mismatch mem=%h sector=%d writes=%d dirty=%d",mem,last_dirty,writes,dirty_count);
 mem=64'hffffffffffffffff;cpu_cmd(32'h007f0008,16'h40);start_program(32'h007f0008,16'h5678);
 if(mem[15:0]!==16'h5678 || last_dirty!==8192 || writes!=2 || dirty_count!=2)$fatal(1,"PMM dirty/write mismatch writes=%0d dirty=%0d",writes,dirty_count);
 // Accepted 16 KiB C: erase must complete after a short reset pulse.
 mem=64'hffffffff00000000;
 cpu_cmd(32'h02400aaa,16'haa);cpu_cmd(32'h02400554,16'h55);cpu_cmd(32'h02400aaa,16'h80);
 cpu_cmd(32'h02400aaa,16'haa);cpu_cmd(32'h02400554,16'h55);cpu_cmd(32'h025fc000,16'h30);
 @(negedge clk);reset=1;tick();@(negedge clk);reset=0;tick();
 if(!dut.core_reset)$fatal(1,"reset released before accepted erase drains");
 wait(!dut.core_reset);repeat(2)tick();
 if(mem!==64'hffffffffffffffff || last_dirty!==4064 || dirty_count!=3)$fatal(1,"erase/dirty mismatch mem=%h sector=%d dirty=%d",mem,last_dirty,dirty_count);
 // Dirty sectors must survive phone reset and be exposed by the tracker.
 @(negedge clk);flush=1;@(negedge clk);flush=0;
 wait(sector_valid);if(sector_index!==0)$fatal(1,"missing C dirty sector");
 @(negedge clk);sector_accept=1;@(negedge clk);sector_accept=0;sector_done=1;@(negedge clk);sector_done=0;
 wait(sector_valid);if(sector_index!==4064)$fatal(1,"missing erase dirty sector");
 @(negedge clk);sector_accept=1;@(negedge clk);sector_accept=0;sector_done=1;@(negedge clk);sector_done=0;
 wait(sector_valid);if(sector_index!==8192)$fatal(1,"missing PMM dirty sector");
 // Cold transport reset cancels a request accepted by the adapter but not
 // yet physically accepted by DDR. A later request must still work.
 mem=64'hffffffffffffffff;
 cpu_cmd(32'h02400aaa,16'haa);cpu_cmd(32'h02400554,16'h55);cpu_cmd(32'h02400aaa,16'ha0);
 @(negedge clk);dut.board.upp.cpu_inside.cpu.wb_cyc=1;dut.board.upp.cpu_inside.cpu.wb_stb=1;dut.board.upp.cpu_inside.cpu.wb_write=1;
 dut.board.upp.cpu_inside.cpu.wb_address=32'h02400200;dut.board.upp.cpu_inside.cpu.wb_byte_enable=3;dut.board.upp.cpu_inside.cpu.wb_write_data='h0000abcd;
 wait(dw);busy=1;wait(accept);tick();@(negedge clk);cold=1;reset=1;dut.board.upp.cpu_inside.cpu.wb_cyc=0;dut.board.upp.cpu_inside.cpu.wb_stb=0;tick();
 @(negedge clk);cold=0;busy=0;wait(init_done && tracker_init);repeat(3)tick();
 if(mem!==64'hffffffffffffffff || dirty_count!=3 || writes!=3)$fatal(1,"cold reset failed to cancel uncommitted DDR write");
 @(negedge clk);reset=0;cpu_cmd(32'h007f0010,16'h40);start_program(32'h007f0010,16'h4567);
 if(mem[15:0]!==16'h4567 || dirty_count!=4)$fatal(1,"program did not recover after cold reset");
 $display("PASS integrated C, PMM and erase reset writes, DDR drain and dirty tracking");$finish;
end
initial begin #10000000;$fatal(1,"write reset timeout");end
endmodule
