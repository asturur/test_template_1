`timescale 1ns/1ps
module tb;
integer test_cycles=0;
reg clk=0,reset=1,req=1,commit=0,we=0,genio=0,genio_level=0;
reg [25:0] keys=0;reg [31:0] addr=0,din=0,base=32'h80001080;reg [3:0] sel=15;
wire [31:0] value;wire irq;integer k,r,c;reg [31:0] expected;
always #5 clk=~clk;
always @(posedge clk)test_cycles<=test_cycles+1;
ngage_keypad dut(.clk(clk),.reset(reset),.keys(keys),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),.base(base),.genio1_driven(genio),.genio1_level(genio_level),.value(value),.irq(irq));
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
 // Original NEM-4 idle setup: clear data (op0), float E (op3),
 // drive D low (op2), enable E interrupts (op4). GENIO op4 writes +16.
 wr('h0c150400,0,3);wr('h0c15040c,0,3);
 wr('h0c15040c,'h3f000000,8);wr('h0c150400,'h001f0000,4);
 wr('h0c120c14,0,15);wr('h0c150410,'h3f,1);
 wr('h0c150014,'h00ee0000,4);
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
 // Direction and individual enable bits gate falling pins, not logical keys.
 // A floating E contact cannot interrupt when neither bank drives low.
 floats();wr('h0c150100,'h00ee0004,15);keys=26'b1<<5;settle();
 if(irq)$fatal(1,"floating held contact interrupted");
 // Mask before scanning; changes to output direction/latches do not interrupt.
 wr('h0c150410,'h3f00,2);wr('h0c150400,'h001f0000,4);settle();
 if(irq)$fatal(1,"masked scan interrupted");
 wr('h0c150410,1,1);settle();if(irq)$fatal(1,"enable held low replayed edge");
 keys=0;settle();keys[5]=1;settle();if(!irq)$fatal(1,"repress after enable");
 wr('h0c150100,4,1);keys=0;settle();
 // E0 mask does not admit E1. Key7 reaches E1 through driven D0.
 keys[7]=1;settle();if(irq)$fatal(1,"per-pin mask ignored");
 wr('h0c150410,2,1);settle();if(irq)$fatal(1,"enable held E1 replayed");
 keys=0;settle();keys[7]=1;settle();if(!irq)$fatal(1,"E1 rearmed");
 wr('h0c150100,4,1);keys=0;settle();
 // An output E pin reads its latch and never contributes an input IRQ.
 wr('h0c15040c,'h00020000,4);keys[7]=1;settle();if(irq)$fatal(1,"output E interrupt");
 wr('h0c15040c,2,1);rd('h0c15040c,2,2);
 keys=0;settle();floats();
 // GPIO30 uses independent clear/set data aliases, with direction at +c14.
 wr('h0c150410,'h3f00,2);wr('h0c150100,4,1);
 wr('h0c120c14,0,15);wr('h0c120c0c,'h80000,4);
 keys=26'b1<<21;settle();rd('h0c15040c,4,4);rd('h0c120c04,'h80000,'h80000);
 wr('h0c120c10,'h80000,4);rd('h0c15040c,4,0);rd('h0c120c04,'h80000,0);
 keys=0;settle();floats();
 // GENIO direction and +14/+16 masking use the NEM-4 mappings.
 wr('h0c150014,'h20,1);keys=1;settle();if(irq)$fatal(1,"GENIO mask ignored");
 wr('h0c150014,'h00200000,4);settle();if(irq)$fatal(1,"GENIO enable replayed");
 keys=0;settle();wr('h0c15020c,'h00020000,4);keys=1;settle();
 if(irq)$fatal(1,"GENIO output interrupt");keys=0;settle();
 wr('h0c15020c,0,12);settle();keys=1;settle();if(!irq)$fatal(1,"GENIO input rearm");
 wr('h0c150100,'h00200000,4);keys=0;settle();
 // Music direction is GENIO28 at +210; GPIO30 remains the separate KPC line.
 wr('h0c150210,'h1000,3);keys=26'b1<<25;settle();if(irq)$fatal(1,"music output interrupt");
 keys=0;settle();wr('h0c150210,0,3);settle();keys=26'b1<<25;settle();
 if(!irq)$fatal(1,"music input rearm");wr('h0c150100,'h00400000,4);keys=0;settle();
 // Routed GENIO1 remains separate from the matrix drivers.
 genio=1;genio_level=0;base=0;rd('h0c150208,'h20000,0);
 genio_level=1;base='h20000;rd('h0c150208,'h20000,'h20000);
 settle();wr('h0c150100,'h00ee0004,15);
 // Bus reads/base-data changes must not become GPIO input edges.
 base=0;rd('h0c150400,'h1f,'h1f);settle();
 base='hffffffff;rd('h0c150410,'h3f,0);settle();
 if(irq)$fatal(1,"read mux produced GENIO edge");
 keys=1;rd('h0c150208,'h20000,0);
 $display("PASS keypad drive banks, bidirectional 20-key scan, press/W1C, lanes and routed GENIO cycles=%0d",test_cycles);$finish;
end
endmodule
