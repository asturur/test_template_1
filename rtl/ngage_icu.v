// IRQ/FIQ bank model derived from staged BootProfile. Inputs are pending
// device levels; clear outputs request device acknowledgement. Global enable
// is a diagnostic latch in that model, not a verified hardware master gate.
module ngage_icu(
 input wire clk,input wire reset,input wire req,input wire commit,input wire we,
 input wire [31:0] addr,input wire [31:0] din,input wire [3:0] sel,
 input wire [95:0] irq_pending,input wire [95:0] fiq_pending,
 output reg claim,output reg bad,output reg [31:0] dout,
 output wire irq,output wire fiq,output reg [95:0] irq_clear, input wire timer0_rearm
);
 reg [31:0] irq_enable[0:2],fiq_enable[0:2],cfg0[0:2],cfg1[0:2],global_enable;
 integer bank,slot,i; reg is_irq,is_fiq,is_global,is_fast;reg [31:0] raw_irq,raw_fiq,masked_irq;
 wire [31:0] a={addr[31:2],2'b00};
 assign irq=|(irq_pending[31:0]&irq_enable[0]) || |(irq_pending[63:32]&irq_enable[1]) || |(irq_pending[95:64]&irq_enable[2]);
 assign fiq=|(fiq_pending[31:0]&fiq_enable[0]) || |(fiq_pending[63:32]&fiq_enable[1]) || |(fiq_pending[95:64]&fiq_enable[2]);
 always @* begin
  bank=0;slot=0;is_irq=0;is_fiq=0;is_global=0;is_fast=0;claim=0;bad=0;dout=0;raw_irq=0;raw_fiq=0;masked_irq=0;
  if(req && (a==32'h0c120064 || a==32'h0c120068))begin is_global=1;claim=1;dout=global_enable;end
  else if(req && a==32'h0c120050)begin is_fast=1;claim=1;dout=0;end
  else if(req && a>=32'h0c120100 && a<32'h0c1201c0)begin
   bank=(a-32'h0c120100)>>6;slot=a[5:0];
   if(slot==0 || slot==4 || slot==8 || slot==12 || slot==16 || slot==20)begin
    is_irq=1;claim=1;raw_irq=irq_pending[bank*32+:32];masked_irq=raw_irq & irq_enable[bank];
    case(slot)
     0:dout=cfg0[bank];4:dout=cfg1[bank];8,12:dout=irq_enable[bank];
     16:dout=(bank==0 && raw_irq[7]) ? 32'h80 : 0;
     20:begin
      if(bank==0) begin
       if(masked_irq[0])dout=1;else if(masked_irq[1])dout=2;
       else if(masked_irq[7])dout=8;else if(masked_irq[25])dout=26;
      end
     end
    endcase
   end
  end else if(req && a>=32'h0c1201c0 && a<32'h0c120260)begin
   bank=(a-32'h0c1201c0)>>6;slot=a[5:0];
   if(slot==8 || slot==12 || slot==16 || slot==20)begin
    is_fiq=1;claim=1;raw_fiq=fiq_pending[bank*32+:32];
    case(slot)
     8,12:dout=fiq_enable[bank];16:dout=raw_fiq;
     20:if(raw_fiq[3])dout=4;else if(raw_fiq[26])dout=27;
    endcase
   end
  end
  if(claim && sel!=4'hf)bad=1;
 end
 always @(posedge clk)begin
  irq_clear<=0;
  if(reset)begin global_enable<=0;for(i=0;i<3;i=i+1)begin irq_enable[i]<=0;fiq_enable[i]<=0;cfg0[i]<=0;cfg1[i]<=0;end end
  else begin
   if(timer0_rearm)irq_enable[0][0]<=0;
   if(commit && claim && !bad && we)begin
   if(is_global)begin if(a==32'h0c120068)global_enable<=global_enable|din;else global_enable<=global_enable&~din;end
   else if(is_irq)case(slot)
    0:cfg0[bank]<=din;4:cfg1[bank]<=din;
    8:irq_enable[bank]<=irq_enable[bank]|din;
    12:begin irq_enable[bank]<=irq_enable[bank]&~din;irq_clear[bank*32+:32]<=din;end
   endcase
   else if(is_fiq)case(slot)
    8:fiq_enable[bank]<=fiq_enable[bank]|din;
    12:fiq_enable[bank]<=fiq_enable[bank]&~din;
   endcase
   end
  end
 end
endmodule
