`timescale 1ns/1ps
module tb;
integer test_cycles=0;
reg clk=0,reset=1,inhibit=0,req=1,commit=0,we=0;reg [31:0] addr=0,din=0,base=0;reg [3:0] sel=15;reg [10:0] ps2=0;reg [31:0] joy=0;wire [26:0] keys;wire [31:0] value;reg [25:0] direct=0;wire [31:0] value2;integer k,row,col;
always #5 clk=~clk;
always @(posedge clk)test_cycles<=test_cycles+1;
ngage_keys input_keys(.clk(clk),.reset(reset),.inhibit(inhibit),.ps2_key(ps2),.joystick(joy),.keys(keys));
ngage_keypad dut(.clk(clk),.reset(reset),.keys(keys[25:0]),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),.base(base),.genio1_driven(1'b0),.genio1_level(1'b0),.value(value));
ngage_keypad direct_dut(.clk(clk),.reset(reset),.keys(direct),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(sel),.base(base),.genio1_driven(1'b0),.genio1_level(1'b0),.value(value2));
task event_key;input [7:0] code;input ext,down;begin @(negedge clk);ps2={~ps2[10],down,ext,code};@(negedge clk);end endtask
initial begin
 repeat(2)@(negedge clk);reset=0;
 addr='h0c150400;we=1;commit=1;din='h1f000000;
 @(negedge clk);we=0;commit=0;
 addr='h0c120c14;we=1;commit=1;din='h00080000;
 @(negedge clk);we=0;commit=0;
 addr='h0c150208;#1;if((value&'h2c060000)!=='h2c060000)begin $display("FAIL stick idle");$finish;end
 joy[3]=1;#1;if(value[17]!==0)begin $display("FAIL stick up");$finish;end
 joy[3]=0;#1;if(value[17]!==1)begin $display("FAIL stick release");$finish;end
 event_key('h05,0,1);addr='h0c150400;we=1;commit=1;din='h00010000;@(negedge clk);we=0;commit=0;addr='h0c15040c;#1;if(value[0]!==0)begin $display("FAIL soft key row");$finish;end
 addr='h0c150400;we=1;commit=1;din='h01000000;@(negedge clk);we=0;commit=0;
 addr='h0c15040c;we=1;din='h00010000;commit=1;@(negedge clk);commit=0;we=0;addr='h0c150400;#1;
 if(value[0]!==0)begin $display("FAIL soft key column");$finish;end
 repeat(4)@(negedge clk);if(value[0]!==0)begin $display("FAIL key hold");$finish;end
 event_key('h05,0,0);#1;if(value[0]!==1)begin $display("FAIL key release");$finish;end
 event_key('h75,1,1);addr='h0c150208;#1;if(value[17]!==0)begin $display("FAIL extended up");$finish;end
 joy[3]=1;event_key('h75,1,0);#1;if(value[17]!==0)begin $display("FAIL mixed keyboard/controller hold");$finish;end
 joy[3]=0;#1;if(value[17]!==1)begin $display("FAIL extended up release");$finish;end
 event_key('h05,0,1);joy[3]=1;inhibit=1;@(negedge clk);#1;
 if(keys!==0)begin $display("FAIL OSD input suppression");$finish;end
 joy=0;inhibit=0;@(negedge clk);#1;if(keys!==0)begin $display("FAIL OSD key release");$finish;end
 event_key('h12,0,1);event_key('h26,0,1);if(!keys[11] || keys[14])begin $display("FAIL keyboard hash chord");$finish;end
 event_key('h12,0,0);event_key('h26,0,0);if(keys[11] || keys[14])begin $display("FAIL hash chord release");$finish;end
 event_key('h59,0,1);event_key('h3e,0,1);if(!keys[10] || keys[19])begin $display("FAIL keyboard star chord");$finish;end
 event_key('h7c,0,1);event_key('h3e,0,0);if(!keys[10])begin $display("FAIL simultaneous star sources");$finish;end
 event_key('h7c,0,0);event_key('h59,0,0);
 event_key('h09,0,1);if(keys[26]!==1)begin $display("FAIL power press");$finish;end
 event_key('h09,0,0);if(keys[26]!==0)begin $display("FAIL power release");$finish;end
 for(k=5;k<=24;k=k+1)begin
  if(k<7)begin row=0;col=k-5;end
  else if(k<9)begin row=1;col=k-7;end
  else if(k<21)begin row=2+(k-9)/3;col=2+(k-9)%3;end
  else begin row=2+k-21;col=5;end
  direct=26'b1<<k;addr='h0c15040c;we=1;din=1<<(row+16);commit=1;
  @(negedge clk);commit=0;we=0;addr=col==5?'h0c120c04:'h0c150400;#1;
  if((col==5 && value2[19]!==0) || (col<5 && value2[col]!==0))begin $display("FAIL matrix key %0d row %0d col %0d",k,row,col);$finish;end
  direct=0;#1;if((col==5 && value2[19]!==1) || (col<5 && value2[col]!==1))begin $display("FAIL matrix release %0d",k);$finish;end
 end
 direct=(26'b1<<9)|(26'b1<<10);addr='h0c15040c;we=1;din=1<<18;commit=1;@(negedge clk);commit=0;we=0;addr='h0c150400;#1;
 if(value2[3:2]!==0)begin $display("FAIL simultaneous keys");$finish;end
 // Exercise bank writes independently of the existing key mapping tests.
 // Key 9 uses row 2 / col 2; key 13 uses row 3 / col 3.
 direct=(26'b1<<9)|(26'b1<<13);
 addr='h0c15040c;we=1;commit=1;sel=8;din='h3f000000;
 @(negedge clk);commit=0;we=0;sel=3;addr='h0c150400;#1;
 if(value2[3:2]!==2'b11)$fatal(1,"drive clear all");
 addr='h0c15040c;we=1;commit=1;sel=4;din='h00040000;
 @(negedge clk);commit=0;we=0;sel=3;addr='h0c150400;#1;
 if(value2[3:2]!==2'b10)$fatal(1,"drive set row2");
 addr='h0c15040c;we=1;commit=1;sel=4;din='h00080000;
 @(negedge clk);commit=0;we=0;sel=3;addr='h0c150400;#1;
 if(value2[3:2]!==2'b00)$fatal(1,"drive set preserves row2");
 addr='h0c15040c;we=1;commit=1;sel=8;din='h04000000;
 @(negedge clk);commit=0;we=0;sel=3;addr='h0c150400;#1;
 if(value2[3:2]!==2'b01)$fatal(1,"drive clear preserves row3");
 // Wrong byte enables and a request without commit must not alter drive.
 addr='h0c15040c;we=1;commit=1;sel=3;din='h08040000;
 @(negedge clk);commit=0;sel=12;
 @(negedge clk);we=0;sel=3;addr='h0c150400;#1;
 if(value2[3:2]!==2'b01)$fatal(1,"drive byte enable or commit");
 addr='h0c15040c;we=1;commit=1;sel=12;din='h080c0000;
 @(negedge clk);commit=0;we=0;sel=3;addr='h0c150400;#1;
 if(value2[3:2]!==2'b10)$fatal(1,"drive simultaneous clear wins");
 // Zero set/clear masks leave selected drive lines intact.
 addr='h0c15040c;we=1;commit=1;sel=12;din=0;
 @(negedge clk);commit=0;we=0;sel=3;addr='h0c150400;#1;
 if(value2[3:2]!==2'b10)$fatal(1,"drive zero masks");
 // Every MiSTer J1 binding has one documented Nokia key, including numbers.
 for(k=0;k<27;k=k+1)begin
  joy=32'b1<<k;
  case(k)
   0:row=3;1:row=2;2:row=1;3:row=0;4:row=4;5:row=7;
   6:row=24;7:row=6;8:row=5;9:row=9;10:row=23;11:row=26;
   12:row=25;13:row=8;14:row=21;15:row=10;16:row=11;
   26:row=22;default:row=k-5;
  endcase
  #1;if(keys!==(27'b1<<row))$fatal(1,"controller binding bit %0d -> Nokia %0d got %h",k,row,keys);
 end
 joy=32'hffffffff;inhibit=1;#1;if(keys!==0)$fatal(1,"OSD controller suppression");
 joy=0;inhibit=0;
 $display("PASS keypad matrix, rocker and held/released host controls cycles=%0d",test_cycles);$finish;
end
endmodule
