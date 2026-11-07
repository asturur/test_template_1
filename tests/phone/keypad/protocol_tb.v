`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,req=1,commit=0,we=0,genio=0;
reg [25:0] keys=0;reg [31:0] addr=0,din=0,base=32'h80001080;reg [3:0] sel=15;
wire [31:0] value;wire irq;integer k,r,c;reg [31:0] expected;
always #5 clk=~clk;
ngage_keypad dut(.clk(clk),.reset(reset),.keys(keys),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),.base(base),.genio1_driven(genio),.value(value),.irq(irq));
task wr;input [31:0] a,d;input [3:0] lanes;begin
 @(negedge clk);addr=a;din=d;sel=lanes;we=1;commit=1;
 @(negedge clk);we=0;commit=0;
end endtask
task rd;input [31:0] a,mask,want;begin
 addr=a;sel=15;#1;if((value&mask)!==want)$fatal(1,"read %h got %h want %h mask %h",a,value,want,mask);
end endtask
task settle;begin repeat(2)@(negedge clk);end endtask
task floats;begin wr('h0c150400,'h1f000000,8);wr('h0c15040c,'h3f000000,8);wr('h0c120c14,'h80000,15);end endtask
initial begin
 settle();reset=0;settle();
 rd('h0c150400,'h1f,0);rd('h0c15040c,'h3f,'h3f);rd('h0c120c04,'h80000,0);
 floats();
 for(k=5;k<=24;k=k+1)begin
  // Public key map translated from the pinned reference by key name.
  case(k)
   5:begin r=0;c=0;end 6:begin r=1;c=0;end
   7:begin r=0;c=1;end 8:begin r=1;c=1;end
   9,10,11:begin r=k-7;c=2;end
   12,13,14:begin r=k-10;c=3;end
   15,16,17:begin r=k-13;c=4;end
   18,19,20:begin r=k-16;c=5;end
   default:begin r=5;c=k-19;end
  endcase
  keys=26'b1<<k;settle();
  rd('h0c150400,'h1f,'h1f);rd('h0c15040c,'h3f,'h3f);
  wr('h0c15040c,32'b1<<(16+c),4);
  if(r<5)rd('h0c150400,'h1f,31 & ~(1<<r));
  else rd('h0c120c04,'h80000,0);
  wr('h0c15040c,32'b1<<(24+c),8);
  if(r<5)wr('h0c150400,32'b1<<(16+r),4);else wr('h0c120c14,0,15);
  rd('h0c15040c,'h3f,63 & ~(1<<c));
  keys=0;settle();rd('h0c15040c,'h3f,'h3f);floats();
 end
 // Status overlays preserve the unrelated NOS/timer bits.
 wr('h0c150100,'h00ee0004,15);if(irq)$fatal(1,"clear matrix events");
 keys[5]=1;settle();rd('h0c150100,'h80ffffff,'h80001084);if(!irq)$fatal(1,"matrix IRQ");
 addr='h0c150100;sel=4;#1;if(value[2])$fatal(1,"status low bit leaks into upper-byte read");
 wr('h0c150100,4,4);if(!irq)$fatal(1,"wrong-lane W1C");
 wr('h0c150100,4,1);settle();if(irq)$fatal(1,"held key reasserted");
 keys=0;settle();if(irq)$fatal(1,"release event");
 // Press beats simultaneous W1C.
 @(negedge clk);keys[5]=1;addr='h0c150100;din=4;sel=1;we=1;commit=1;
 @(negedge clk);we=0;commit=0;if(!irq)$fatal(1,"press lost to clear");
 keys=0;settle();wr('h0c150100,4,1);
 for(k=0;k<6;k=k+1)begin
  case(k)
   0:begin keys=1;expected='h00200000;end
   1:begin keys=2;expected='h00020000;end
   2:begin keys=4;expected='h00080000;end
   3:begin keys=8;expected='h00800000;end
   4:begin keys=16;expected='h00040000;end
   5:begin keys=26'b1<<25;expected='h00400000;end
  endcase
  settle();rd('h0c150100,'h00ee0004,expected);
  wr('h0c150100,expected,1);if(!irq)$fatal(1,"direct wrong lane");
  wr('h0c150100,expected,4);settle();if(irq)$fatal(1,"direct held key");
  keys=0;settle();
 end
 // Routed GENIO1 remains separate from the matrix drivers.
 genio=1;base=0;rd('h0c150208,'h20000,0);base='h20000;rd('h0c150208,'h20000,'h20000);
 keys=1;rd('h0c150208,'h20000,0);
 $display("PASS keypad drive banks, bidirectional 20-key scan, press/W1C, lanes and routed GENIO");$finish;
end
endmodule
