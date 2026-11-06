`timescale 1ns/1ps
module tb;
reg clk=0,reset=1,req=0,commit=0,we=0;reg [31:0] addr=0,din=0;reg [3:0] sel=15;
wire tclaim,tbad,iclaim,ibad,p0,p1,p60,rearm,irq,fiq;wire [31:0] td,id;wire [95:0] clear;
integer f,n,active,write_flag,expected_irq,expected_fiq,expected_ok,line;reg [31:0] repeat_count;reg [31:0] expected_data;integer rc;
always #5 clk=~clk;
ngage_timers #(.BOOT_DELAY(3)) timers(clk,reset,req,commit,we,addr,din,sel,clear[1],tclaim,tbad,td,p0,p1,p60,rearm,,1'b0);
ngage_icu icu(clk,reset,req,commit,we,addr,din,sel,{94'b0,p1,p0},{92'b0,p60,3'b0},iclaim,ibad,id,irq,fiq,clear,rearm);
initial begin
 f=$fopen("build/sim/unit-timer-conformance/reference.tsv","r");if(!f)begin $display("FAIL fixture missing");$finish;end
 @(negedge clk);reset=0;line=0;
 while(!$feof(f))begin
  rc=$fscanf(f,"%d %h %h %d %h %d %d %d\n",active,addr,din,write_flag,expected_data,expected_irq,expected_fiq,expected_ok);
  if(rc==8)begin
   line=line+1;
   if(active==2)begin
    req=0;commit=0;we=0;repeat_count=addr;
    while(repeat_count>1)begin @(posedge clk);@(negedge clk);repeat_count=repeat_count-1;end
    active=0;
   end
   req=active;commit=0;we=write_flag;#1;
   if(active && (!iclaim && !tclaim))begin $display("FAIL unclaimed line %0d",line);$finish;end
   if(active && ((tclaim ? tbad : ibad)===expected_ok[0]))begin $display("FAIL accept mismatch line %0d",line);$finish;end
   if(active && expected_ok && !we && (tclaim ? td : id)!==expected_data)begin $display("FAIL data mismatch line %0d",line);$finish;end
   commit=active && expected_ok;@(posedge clk);#1;
   if(irq!==expected_irq[0])begin $display("FAIL IRQ mismatch line %0d got %b expected %b",line,irq,expected_irq[0]);$finish;end
   if(fiq!==expected_fiq[0])begin $display("FAIL FIQ mismatch line %0d got %b expected %b",line,fiq,expected_fiq[0]);$finish;end
   @(negedge clk);
  end
 end
 $display("PASS timer IRQ edges against C++");$finish;
end
endmodule
