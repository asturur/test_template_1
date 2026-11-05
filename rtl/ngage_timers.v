// Tick-level port of the staged board's timer hypotheses. UNIT60_DELAY is an
// observed-model constant, not a claim about the physical timer prescaler.
module ngage_timers #(parameter [31:0] BOOT_DELAY=32'd18200000, UNIT60_DELAY=32'd128)(
 input wire clk,input wire reset,input wire req,input wire commit,input wire we,
 input wire [31:0] addr,input wire [31:0] din,input wire [3:0] sel,
 input wire clear_unit1,output reg claim,output reg bad,output reg [31:0] dout,
 output reg timer0_pending,output reg unit1_pending,output reg unit60_pending,
 output reg timer0_rearm,output wire periodic_active
);
 wire [31:0] a={addr[31:2],2'b00};
 wire timer0=(a==32'h0c120a04 || a==32'h0c120a08 || a==32'h0c120a10 || a==32'h0c120a18);
 wire units=(a>=32'h0c120a20 && a<32'h0c120ac0);
 reg [31:0] unit_regs[0:39];reg [31:0] control0,compare0,reload0,status0;
 reg [31:0] boot_left,period,period_left,unit1_elapsed,unit1_compare,unit60_left;
 reg unit1_running,boot_started;integer index,slot,i;
 assign periodic_active=(period!=0);
 always @* begin
  claim=req && (timer0||units);bad=claim && sel!=15;dout=0;index=0;slot=0;
  if(timer0)case(a)
   32'h0c120a04:dout=control0;32'h0c120a08:dout=status0;
   32'h0c120a10:dout=compare0;32'h0c120a18:dout=reload0;
  endcase
  else if(units)begin
   index=(a-32'h0c120a20)>>2;slot=a[4:0];
   if(slot==8 && a[7:5]==1)dout=unit1_pending?1:0;
   else if(slot==8 && a[7:5]==3)dout=unit60_pending?1:0;
   else if(slot==8)dout=0;else dout=unit_regs[index];
  end
 end
 always @(posedge clk) begin
  timer0_rearm<=0;
  if(reset)begin
   timer0_pending<=0;unit1_pending<=0;unit60_pending<=0;
   control0<=0;compare0<=0;reload0<=0;status0<=0;
   boot_left<=0;period<=0;period_left<=0;unit1_elapsed<=0;unit1_compare<=0;unit60_left<=0;unit1_running<=0;boot_started<=0;
   for(i=0;i<40;i=i+1)unit_regs[i]<=0;
  end else begin
   if(boot_left!=0)begin boot_left<=boot_left-1'b1;if(boot_left==1)begin timer0_pending<=1;status0<=1;end end
   if(period_left!=0)begin period_left<=period_left-1'b1;if(period_left==1)begin timer0_pending<=1;status0<=1;period_left<=period;end end
   if(unit60_left!=0)begin unit60_left<=unit60_left-1'b1;if(unit60_left==1)unit60_pending<=1;end
   if(unit1_running)begin
    if(unit1_elapsed+1>=unit1_compare)begin unit1_running<=0;unit1_elapsed<=0;unit1_pending<=1;end
    else unit1_elapsed<=unit1_elapsed+1'b1;
   end
   if(clear_unit1)unit1_pending<=0;
   if(commit && claim && !bad && we)begin
    if(timer0)case(a)
     32'h0c120a04:begin control0<=din;if(din==2)boot_started<=1;end
     32'h0c120a08:begin status0<=din;timer0_pending<=0;end
     32'h0c120a10:compare0<=din;
     32'h0c120a18:begin
      reload0<=din;
      if(boot_started && din==32'h0115b5c0)boot_left<=BOOT_DELAY;
      if(din==32'h000632ea && control0==2)begin period<=din;period_left<=din;timer0_rearm<=1;end
     end
    endcase
    else if(units)begin
     unit_regs[index]<=din;
     if(a>=32'h0c120a60 && a<32'h0c120a80)begin
      unit60_pending<=0;
      if(slot==4)unit60_left<=din==2?UNIT60_DELAY:0;
      else if(slot==8 && unit_regs[(32'h0c120a64-32'h0c120a20)>>2]==2)unit60_left<=UNIT60_DELAY;
     end
     if(a>=32'h0c120a20 && a<32'h0c120a40)begin
      if(slot==4)begin unit1_running<=din!=0;unit1_elapsed<=0;end
      if(slot==16)begin unit1_compare<=din;unit1_elapsed<=0;end
     end
    end
   end
  end
 end
endmodule
