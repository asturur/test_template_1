// One 32-bit request at a time, split into 16-bit jtframe_sdram64 operations.
// rdy, not ack, qualifies the registered controller output. The initial scrub
// is a cold-start operation; phone_reset discards CPU responses, not RAM.
module ngage_sdram_adapter #(
 parameter [24:0] RAM_BYTES=25'h1000000,
 parameter integer REFRESH_PERIOD=6800
)(input wire clk, input wire rst, input wire phone_reset, input wire init,
 input wire req, input wire we, input wire [24:0] addr, input wire [31:0] din,
 input wire [3:0] be, output reg ack, output reg [31:0] dout,
 output reg scrub_done,
 output wire [21:0] ba_addr, output wire [15:0] ba_din, output wire [1:0] ba_dsn,
 output wire [3:0] rd, output wire [3:0] wr,
 input wire [3:0] ba_ack, input wire [3:0] ba_rdy, input wire [15:0] ba_dout,
 output reg rfsh);
 localparam IDLE=0, ISSUE=1, WAIT_READY=2, GAP=3, RESP=4, WAIT_DROP=5;
 reg [2:0] state=IDLE;
 reg [24:0] address=0, scrub_address=0;
 reg [31:0] data=0; reg [3:0] mask=0;
 reg write_op=0, high=0, scrub=0, discard=0;
 reg [1:0] gap=0;
 integer refresh_count=0;
 wire bank=address[23];
 wire selected_ack=ba_ack[bank];
 wire selected_rdy=ba_rdy[bank];
 assign ba_addr={address[22:2],high};
 assign ba_din=high ? data[31:16] : data[15:0];
 assign ba_dsn=high ? ~mask[3:2] : ~mask[1:0];
 assign rd=(state==ISSUE && !write_op) ? (bank ? 4'b0010 : 4'b0001) : 0;
 assign wr=(state==ISSUE && write_op) ? (bank ? 4'b0010 : 4'b0001) : 0;
 always @(posedge clk) begin
  ack<=0; rfsh<=0;
  if(rst || init) begin
   state<=IDLE; scrub_done<=0; scrub_address<=0; refresh_count<=0; discard<=0;
  end else begin
   if(refresh_count==REFRESH_PERIOD-1) begin refresh_count<=0; rfsh<=1; end
   else refresh_count<=refresh_count+1;
   if(phone_reset && !scrub && state!=IDLE) discard<=1;
   case(state)
    IDLE: begin
     high<=0; discard<=0;
     if(!scrub_done) begin
      scrub<=1; address<=scrub_address; data<=0; mask<=4'hf; write_op<=1; state<=ISSUE;
     end else if(req && !phone_reset) begin
      scrub<=0; address<={addr[24:2],2'b00}; data<=din; mask<=be; write_op<=we; state<=ISSUE;
     end
    end
    ISSUE: if(selected_ack) state<=WAIT_READY;
    WAIT_READY: if(selected_rdy) begin
     if(!write_op) begin
      if(high) dout[31:16]<=ba_dout; else dout[15:0]<=ba_dout;
     end
     gap<=2; state<=GAP;
    end
    GAP: if(gap!=0) gap<=gap-1'b1;
     else if(!high) begin high<=1; state<=ISSUE; end
     else if(scrub) begin
      if(scrub_address+4>=RAM_BYTES) scrub_done<=1;
      else scrub_address<=scrub_address+4;
      state<=IDLE;
     end else state<=RESP;
    RESP: begin
     if(discard || phone_reset) state<=IDLE;
     else begin ack<=1; state<=WAIT_DROP; end
    end
    WAIT_DROP: if(!req || phone_reset) state<=IDLE;
    default: state<=IDLE;
   endcase
  end
 end
endmodule
