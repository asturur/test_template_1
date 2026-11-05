module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,req=0,commit=0,we=0,clear1=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire claim,bad,p0,p1,p60,rearm;wire [31:0] dout;
ngage_timers #(.BOOT_DELAY(5),.UNIT60_DELAY(8)) dut(clk,reset,req,commit,we,addr,din,sel,clear1,claim,bad,dout,p0,p1,p60,rearm,);
task tick;begin @(posedge clk);#1;end endtask
task wr(input [31:0] a,input [31:0] d);begin @(negedge clk);req=1;we=1;commit=1;addr=a;din=d;#1;if(!claim||bad)$fatal(1,"decode %h",a);tick();@(negedge clk);req=0;commit=0;end endtask
initial begin
 tick();reset=0;wr('h0c120a04,2);wr('h0c120a18,'h0115b5c0);repeat(6)tick();if(!p0)$fatal(1,"boot timer");wr('h0c120a08,1);if(p0)$fatal(1,"timer ack");
 wr('h0c120a30,4);wr('h0c120a24,1);repeat(5)tick();if(!p1)$fatal(1,"unit1 timer");clear1=1;tick();clear1=0;if(p1)$fatal(1,"unit1 clear");
 wr('h0c120a64,2);repeat(9)tick();if(!p60)$fatal(1,"unit60 timer");wr('h0c120a68,0);if(p60)$fatal(1,"unit60 clear");repeat(9)tick();if(!p60)$fatal(1,"unit60 rearm");
 @(negedge clk);req=1;we=1;commit=0;addr='h0c120a68;din=0;tick();if(!p60)$fatal(1,"uncommitted timer write");
 sel=3;commit=1;#1;if(!bad)$fatal(1,"width");tick();if(!p60)$fatal(1,"bad write committed");
 $display("PASS staged boot and unit timers");$finish;
end
endmodule
