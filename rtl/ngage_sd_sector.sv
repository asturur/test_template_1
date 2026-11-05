// One 512-byte HPS virtual-disk sector. The caller fills/drains the buffer
// only while idle. Completion means the HPS ack asserted and deasserted; it
// does not prove media-level durability after sudden power loss.
module ngage_sd_sector #(parameter integer TIMEOUT=104000000)(
 input wire clk,input wire reset,
 input wire start,input wire write_sector,input wire [31:0] start_lba,
 output wire ready,output reg done,output reg error,
 input wire [7:0] local_addr,input wire [15:0] local_din,input wire local_we,
 output wire [15:0] local_dout,
 output reg [31:0] sd_lba,output reg sd_rd,output reg sd_wr,input wire sd_ack,
 input wire [12:0] hps_addr,input wire [15:0] hps_dout,input wire hps_we,
 output wire [15:0] hps_din
);
 localparam IDLE=0,WAIT_ACK=1,WAIT_END=2,FAILED=3;
 reg [1:0] state=IDLE;reg [15:0] bufmem[0:255];reg op_write=0;integer timer=0;
 reg [8:0] read_count=0;reg read_error=0;
 assign ready=state==IDLE && !reset;
 assign local_dout=bufmem[local_addr];
 assign hps_din=(hps_addr<256) ? bufmem[hps_addr[7:0]] : 16'hffff;
 always @(posedge clk) begin
  done<=0;error<=0;
  if(reset) begin state<=IDLE;sd_rd<=0;sd_wr<=0;timer<=0;end
  else begin
   if(local_we && state==IDLE) bufmem[local_addr]<=local_din;
   if(hps_we && !op_write && (state==WAIT_ACK || state==WAIT_END)) begin
    if(hps_addr>=256 || hps_addr!={4'b0,read_count}) read_error<=1;
    else begin bufmem[hps_addr[7:0]]<=hps_dout;read_count<=read_count+1'b1;end
   end
   case(state)
    IDLE:if(start && ready) begin
     if(sd_ack) begin done<=1;error<=1;state<=FAILED;end
     else begin sd_lba<=start_lba;op_write<=write_sector;sd_rd<=!write_sector;sd_wr<=write_sector;timer<=0;read_count<=0;read_error<=0;state<=WAIT_ACK;end
    end
    WAIT_ACK:if(sd_ack) begin sd_rd<=0;sd_wr<=0;timer<=0;state<=WAIT_END;end
     else if(timer>=TIMEOUT-1) begin sd_rd<=0;sd_wr<=0;done<=1;error<=1;state<=FAILED;end
     else timer<=timer+1;
    WAIT_END:if(!sd_ack) begin
      done<=1;
      if(!op_write && (read_error || (hps_we && (hps_addr>=256 || hps_addr!={4'b0,read_count})) ||
         (read_count + (hps_we ? 9'd1 : 9'd0) != 9'd256))) begin error<=1;state<=FAILED;end
      else state<=IDLE;
     end
     else if(timer>=TIMEOUT-1) begin done<=1;error<=1;state<=FAILED;end
     else timer<=timer+1;
    FAILED: begin sd_rd<=0;sd_wr<=0;end
    default:state<=FAILED;
   endcase
  end
 end
endmodule
