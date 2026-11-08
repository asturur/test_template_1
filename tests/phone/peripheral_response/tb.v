`timescale 1ns/1ps
module tb;
 reg clk=0,rst=1,cold=1,req=0,we=0,authorize=0,legacy_done=0;
 reg [31:0] addr=0,din=0;reg [3:0] sel=15;
 wire [1:0] claim,ready,bad,init,trace_valid;
 wire [31:0] dout[0:1];
 integer traces0=0,traces1=0,checks=0;
 always #5 clk=~clk;
 genvar n;
 generate for(n=0;n<2;n=n+1)begin:g
  ngage_board #(.SIMIF_ENABLE(1),.KEYPAD_ENABLE(1)) dut(
   .clk(clk),.rst(rst),.init_rst(cold),.cyc(req),.stb(req),.we(we),.adr(addr),.din(din),.sel(sel),
   .commit(authorize && (n==1 || (!legacy_done && ready[n]))),
   .cfg_lcd(1'b1),.cfg_keypad(1'b1),.cfg_clocks(1'b1),.keys(27'b0),.sim_present(1'b1),
   .dma_irq_pending(1'b0),.sim_fiq_pending(1'b0),.claim(claim[n]),.ready(ready[n]),
   .unmodeled(bad[n]),.dout(dout[n]),.init_done(init[n]),.trace_valid(trace_valid[n]));
  defparam dut.upp.peripherals.REGISTER_RESPONSES=n;
 end endgenerate
 always @(posedge clk)begin
  if(trace_valid[0])traces0=traces0+1;
  if(trace_valid[1])traces1=traces1+1;
 end
 task tick;begin @(negedge clk);#1;end endtask
 task transfer;input wr;input [31:0] a,d;input [3:0] lanes;
 reg [31:0] expected;reg expected_bad;integer waits;
 begin
  tick();req=1;we=wr;addr=a;din=d;sel=lanes;authorize=0;legacy_done=0;#1;
  // Lookup may run before authorization, but neither response nor effects
  // can be published by the registered boundary until accepted.
  repeat(2)tick();if(ready[1])$fatal(1,"response before authorization");
  waits=0;while(!ready[0])begin tick();waits=waits+1;if(waits>80)$fatal(1,"local timeout %h",a);end
  expected=dout[0];expected_bad=bad[0];authorize=1;
  tick();legacy_done=1;
  if(!ready[1] || !claim[1] || bad[1]!==expected_bad || (!wr && dout[1]!==expected))
   $fatal(1,"response mismatch a=%h ready=%b bad=%b/%b data=%h/%h",a,ready[1],bad[1],expected_bad,dout[1],expected);
  expected=dout[1];
  repeat(5)begin tick();if(!ready[1] || !claim[1] || bad[1]!==expected_bad || dout[1]!==expected)$fatal(1,"held result changed %h",a);end
  authorize=0;req=0;tick();checks=checks+1;
 end endtask
 integer i;
 initial begin
  repeat(2)tick();cold=0;wait(&init);tick();rst=0;repeat(65)tick();
  transfer(1,'h08000014,'h12345678,15);transfer(0,'h08000014,0,15);
  transfer(1,'h0c030220,'h12345678,15);transfer(1,'h0c030220,'habcd0000,12);transfer(0,'h0c030220,0,15);
  transfer(1,'h0c120340,'h55112233,15);transfer(0,'h0c120340,0,15);
  transfer(1,'h0c120348,2,15);transfer(0,'h0c120348,0,15);
  transfer(1,'h0c120600,'haabbccdd,15);transfer(0,'h0c120600,0,15);
  transfer(1,'h0c120600,0,3);transfer(0,'h0c120600,0,15);
  transfer(1,'h0c121204,1,15);transfer(1,'h0c121200,'h49200000,15);transfer(0,'h0c121200,0,15);
  transfer(1,'h0c121200,'hdeadbeef,15);transfer(0,'h0c121200,0,15);
  transfer(1,'h0c120004,12,15);transfer(0,'h0c120020,0,15);
  transfer(0,'h0c150100,0,15);transfer(0,'h0c150208,0,15);transfer(0,'h0c150400,0,15);
  transfer(0,'h0c150800,0,3);transfer(0,'h0c150800,0,15);
  transfer(1,'h0d123400,'habcdef01,15);transfer(0,'h0d123400,0,15);
  transfer(1,'h0def0000,'h12345678,15);transfer(1,'h0de00000,'h41,1);
  transfer(0,'h0c15080c,0,3);
  if(g[1].dut.upp.peripherals.simif_enabled.simif.position!==1)$fatal(1,"SIM read repeated");
  // A changing live timer must not alter an accepted held read response.
  transfer(0,'h0c150110,0,15);
  // Ownership may change after acceptance. Retain the sampled owner and
  // result even when the live low-bank claim disappears with periodic mode.
  force g[0].dut.upp.peripherals.timers.period=1;
  force g[1].dut.upp.peripherals.timers.period=1;
  tick();req=1;we=0;addr='h0c120040;sel=15;authorize=1;legacy_done=0;
  while(!ready[1])tick();legacy_done=1;
  force g[0].dut.upp.peripherals.timers.period=0;
  force g[1].dut.upp.peripherals.timers.period=0;
  #1;if(!claim[1] || bad[1] || dout[1]!==0)$fatal(1,"accepted owner changed with state");
  repeat(3)tick();req=0;authorize=0;tick();
  release g[0].dut.upp.peripherals.timers.period;
  release g[1].dut.upp.peripherals.timers.period;
  // Warm reset releases independently of cold init_done, then scrub completes.
  rst=1;tick();rst=0;repeat(65)tick();
  transfer(0,'h0c120340,0,15);if(dout[1]!==0)$fatal(1,"DMA warm zero");
  transfer(0,'h0c120600,0,15);if(dout[1]!==0)$fatal(1,"epbus warm zero");
  if(traces0!=2 || traces1!=2)$fatal(1,"duplicate trace effects");
  $display("PASS peripheral registered responses: %0d coherent/held/authorized transactions, masks, faults, keypad, SIM, sparse and warm reset",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
