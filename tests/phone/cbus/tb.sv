module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0,periodic=0,clear_irq=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire claim,bad,irq;wire [31:0] dout;
ngage_cbus_uem #(.SECOND_TICKS(40),.ALARM_TICKS(8),.ALARM_INTERVAL(1)) dut(clk,reset,req,commit,we,addr,din,sel,periodic,clear_irq,claim,bad,dout,irq,,,);
task tick;begin @(posedge clk);#1;end endtask
task wr(input [31:0] a,input [15:0] d,input [3:0] b);begin @(negedge clk);req=1;we=1;commit=1;addr=a;sel=b;din=b==12?{d,16'b0}:{16'b0,d};#1;if(!claim||bad)$fatal(1,"write %h %h",a,d);tick();@(negedge clk);req=0;commit=0;end endtask
task rd(input [31:0] a,input [15:0] expect_value);begin @(negedge clk);req=1;we=0;addr=a;sel=12;#1;if(!claim||bad||dout[31:16]!==expect_value)$fatal(1,"read %h got %h expected %h",a,dout,expect_value);@(negedge clk);req=0;end endtask
task cfg(input [15:0] d);begin wr('h0c150420,d,3);end endtask
task command(input [15:0] d);begin wr('h0c150420,d,12);end endtask
task payload(input [15:0] d);begin wr('h0c150424,d,12);end endtask
initial begin
 tick();reset=0;tick();
 @(negedge clk);req=1;we=1;addr='h0c150424;sel=12;din='h12340000;#1;if(!bad)$fatal(1,"payload without command");req=0;
 cfg(7);command('h135);rd('h0c150420,'h535);rd('h0c150424,'h18);
 cfg('hf);command('h36);payload('hfff7);repeat(9)tick();if(!irq)$fatal(1,"alarm irq");
 clear_irq=1;tick();clear_irq=0;if(irq)$fatal(1,"irq clear");
 cfg(7);command('h135);rd('h0c150424,'h8);
 cfg(7);command('h39);payload('h6800);cfg(7);command('h13a);rd('h0c150424,512);
 cfg(7);command('h32);payload('h20);cfg(7);command('h132);rd('h0c150424,0);
 periodic=1;repeat(41)tick();if(!irq)$fatal(1,"periodic RTC irq");
 $display("PASS CBUS sequencing, RTC and ADC hypotheses");$finish;
end
endmodule
