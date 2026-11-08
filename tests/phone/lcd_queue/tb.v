`timescale 1ns/1ps
module tb;
 reg clk=0,reset=1,hold=0,valid=0;
 reg [31:0] addr=0,data=0;
 wire ready,out_valid;wire [31:0] out_addr,out_data;
 integer n,accepted=0,applied=0,canceled=0;
 reg pending=0;reg [31:0] expected_addr,expected_data;
 reg [31:0] rng=32'h7391ac02;
 always #5 clk=~clk;
 ngage_lcd_bus_queue dut(clk,reset,hold,valid,ready,addr,data,out_valid,out_addr,out_data);
 always @(posedge clk)begin
  if(reset)begin if(pending)canceled=canceled+1;pending=0;end
  else begin
   if(out_valid)begin
    if(!pending || out_addr!==expected_addr || out_data!==expected_data)$fatal(1,"LCD command lost, duplicated or skewed");
    if(hold)$fatal(1,"DMA collision");
    applied=applied+1;pending=0;
   end
   if(valid && ready)begin
    if(pending)$fatal(1,"queue overwrite");
    pending=1;expected_addr=addr;expected_data=data;accepted=accepted+1;
   end
  end
 end
 task step;begin @(negedge clk);#1;end endtask
 initial begin
  step();reset=0;hold=1;valid=1;addr='h0c121200;data='h09200000;step();
  valid=0;repeat(20)begin addr=addr+4;data=~data;step();if(ready || out_valid)$fatal(1,"queued command not held during DMA");end
  hold=0;valid=1;addr='h0c121208;data='haf;step();valid=0;step();
  // Random producer gaps, consecutive header/data writes, long consumer holds and
  // reset with a pending entry. The producer changes its payload every cycle.
  for(n=0;n<4000;n=n+1)begin
   rng=rng ^ (rng<<13);rng=rng ^ (rng>>17);rng=rng ^ (rng<<5);
   valid=rng[0];hold=rng[1] || (n%83<30);reset=n%137==19;
   addr='h0c121200 | ((n%3)*4);data=rng;step();
  end
  reset=0;valid=0;hold=0;repeat(3)step();
  if(pending || accepted!=applied+canceled || applied<100)$fatal(1,"queue did not drain");
  $display("PASS LCD registered command queue: payload/order, replacement, consumer backpressure and reset (%0d applied, %0d canceled)",applied,canceled);$finish;
 end
endmodule
