// Production geometry: no-save full occupancy, duplicate coalescing and drain.
`timescale 1ns/1ps
module fullsize_tb;
 parameter integer SECTORS=8320;
 reg clk=0,reset=1,dirty=0,flush=0,accept=0,done=0;
 reg [13:0] index=0;
 wire ready,flushing,error,fault,pending,valid;
 wire [31:0] debug_state;
 wire [13:0] sector;
 integer j,pass;
 always #5 clk=~clk;
 ngage_ordered_dirty_queue #(.SECTORS(SECTORS),.AW(14)) dut(
  .clk(clk),.cold_reset(reset),.dirty_valid(dirty),.dirty_sector(index),
  .flush_start(flush),.flush_limit(15'b0),.abort_flush(1'b0),
  .init_done(ready),.flushing(flushing),.flush_error(error),.queue_fault(fault),
  .debug_state(debug_state),.pending(pending),.sector_valid(valid),.sector_index(sector),
  .sector_accept(accept),.sector_done(done),.sector_ok(1'b1));
 task mark;
  input integer n;
  begin @(negedge clk);index=n;dirty=1;@(negedge clk);dirty=0;end
 endtask
 initial begin
  repeat(4)@(negedge clk);reset=0;wait(ready);repeat(4)@(negedge clk);
  if(pending||fault||error||flushing)$fatal(1,"fresh production queue not empty");
  for(j=0;j<SECTORS;j=j+1)mark(j);
  for(pass=0;pass<3;pass=pass+1)for(j=0;j<SECTORS;j=j+1)mark((j*17)%SECTORS);
  @(negedge clk);index=8192;dirty=1;repeat(20000)@(negedge clk);dirty=0;
  repeat(4)@(negedge clk);
  if(fault||error||flushing||debug_state[23:9]!=SECTORS)$fatal(1,"full production queue duplicate/overflow count=%0d",debug_state[23:9]);
  @(negedge clk);flush=1;@(negedge clk);flush=0;
  for(j=0;j<SECTORS;j=j+1)begin
   wait(valid);@(negedge clk);
   if(sector!=j||fault||error)$fatal(1,"full production order %0d got%0d",j,sector);
   accept=1;@(negedge clk);accept=0;done=1;@(negedge clk);done=0;
  end
  wait(!flushing);repeat(4)@(negedge clk);
  if(pending||fault||error)$fatal(1,"full production queue did not drain");
  $display("PASS full8320-sector queue: clean init, full no-save occupancy, 44960 repeated marks, ordered drain");$finish;
 end
 initial begin #10000000;$fatal(1,"fullsize timeout");end
endmodule
