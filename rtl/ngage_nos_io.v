// Staged-model NOS timer and interrupt-status hypothesis. The 16-bit counter
// advances every TICK_DIV model clocks; the calibration counter uses FAST_DIV.
// These separate rates match the current staged model and remain hypotheses.
module ngage_nos_io #(parameter integer TICK_DIV=104000, FAST_DIV=3174)(
 input wire clk,input wire reset,input wire req,input wire commit,input wire we,
 input wire [31:0] addr,input wire [31:0] din,input wire [3:0] sel,
 output reg claim,output reg bad,output reg [31:0] dout,output wire irq
);
 wire [31:0] a={addr[31:2],2'b00};
 wire [31:0] mask={{8{sel[3]}},{8{sel[2]}},{8{sel[1]}},{8{sel[0]}}};
 reg [31:0] enable_reg,status_reg,counter_lo,window_reg,compare_reg;
 reg [15:0] counter,fast_counter,enable_bits;reg compare_valid;integer divider,fast_divider;
 reg [31:0] next_enable,next_status,next_compare;
 wire valid_sel=(sel==1 || sel==2 || sel==4 || sel==8 || sel==3 || sel==12 || sel==15);
 assign irq=|(status_reg[15:0] & enable_bits);
 always @* begin
  claim=req && (a==32'h0c150010 || a==32'h0c150100 || a==32'h0c150110 || a==32'h0c150114 || a==32'h0c150118);
  bad=claim && !valid_sel;dout=0;
  case(a)
   32'h0c150010:dout=enable_reg;
   32'h0c150100:dout=status_reg;
   32'h0c150110:dout={fast_counter,counter_lo[15:0]};
   32'h0c150114:dout={counter,(window_reg[15:0]==0?16'h0080:window_reg[15:0])};
   32'h0c150118:dout=compare_reg;
  endcase
  dout=dout & mask;
  next_enable=(enable_reg & ~mask)|(din & mask);
  next_enable[31:16]=(enable_bits | (din[31:16]&mask[31:16])) & ~(din[15:0]&mask[15:0]);
  next_status=(status_reg & ~mask)|(din & mask);
  if(|mask[15:0])next_status[15:0]=(next_status[15:0] & ~16'h3680) | (status_reg[15:0]&16'h3680&~(din[15:0]&mask[15:0]));
  next_compare=(compare_reg & ~mask)|(din & mask);
 end
 always @(posedge clk)begin
  if(reset)begin enable_reg<=0;status_reg<=0;counter_lo<=0;window_reg<=0;compare_reg<=0;counter<=0;fast_counter<=0;enable_bits<=0;compare_valid<=0;divider<=0;fast_divider<=0;end
  else begin
   if(fast_divider==FAST_DIV-1)begin fast_divider<=0;fast_counter<=fast_counter+1'b1;end else fast_divider<=fast_divider+1;
   if(divider==TICK_DIV-1)begin
    divider<=0;counter<=counter+1'b1;
    if(compare_valid && counter+1'b1==compare_reg[15:0])status_reg[7]<=1;
   end else divider<=divider+1;
   if(commit && claim && !bad && we)case(a)
    32'h0c150010:begin
     enable_reg<=next_enable;enable_bits<=next_enable[31:16];
     status_reg[13:12]<=(status_reg[13:12] | (din[29:28]&mask[29:28])) & ~(din[13:12]&mask[13:12]);
    end
    32'h0c150100:status_reg<=next_status;
    32'h0c150110:counter_lo<=(counter_lo&~mask)|(din&mask);
    32'h0c150114:window_reg<=(window_reg&~mask)|(din&mask);
    32'h0c150118:begin
     compare_reg<=next_compare;
     if(|mask[15:0])begin compare_valid<=1;if(counter==next_compare[15:0])status_reg[7]<=1;end
    end
   endcase
  end
 end
endmodule
