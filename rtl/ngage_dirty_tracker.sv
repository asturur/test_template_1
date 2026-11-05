// 512-byte C:/PMM sector dirtiness. A write arriving during a flush keeps
// that sector dirty, including one coincident with the completion pulse.
// A failed flush leaves it dirty and stops the scan for explicit retry.
module ngage_dirty_tracker #(
 parameter integer SECTORS=8320,
 parameter integer AW=$clog2(SECTORS)
)(input wire clk,input wire cold_reset,
 input wire dirty_valid,input wire [AW-1:0] dirty_sector,
 input wire flush_start,output reg flushing,output reg flush_error,output reg init_done,
 output reg sector_valid,input wire sector_accept,output reg [AW-1:0] sector_index,
 input wire sector_done,input wire sector_ok,input wire abort_flush);
 reg dirty[0:SECTORS-1];
 reg [AW:0] cursor=0;reg active=0,again=0,rescan=0;
 reg [1:0] state=0;
 localparam CLEAR=0, IDLE=1, SCAN=2, WAIT=3;
 localparam [AW:0] NUM_SECTORS=SECTORS;
 always @(posedge clk) begin
  if(cold_reset) begin state<=CLEAR;cursor<=0;init_done<=0;flushing<=0;flush_error<=0;sector_valid<=0;active<=0;again<=0;rescan<=0;end
  else if(abort_flush && state!=CLEAR) begin
   if(dirty_valid && {1'b0,dirty_sector}<NUM_SECTORS) dirty[dirty_sector]<=1;
   state<=IDLE;flushing<=0;flush_error<=1;sector_valid<=0;active<=0;again<=0;rescan<=0;
  end else case(state)
   CLEAR: begin
    dirty[cursor[AW-1:0]]<=0;
    if(cursor==NUM_SECTORS-1'b1) begin cursor<=0;init_done<=1;state<=IDLE;end
    else cursor<=cursor+1'b1;
   end
   default: begin
    if(dirty_valid && {1'b0,dirty_sector}<NUM_SECTORS) begin
     dirty[dirty_sector]<=1;
     if(flushing) rescan<=1;
     if(active && dirty_sector==sector_index) again<=1;
    end
    case(state)
     IDLE: if(flush_start) begin flushing<=1;flush_error<=0;cursor<=0;rescan<=0;state<=SCAN;end
     SCAN: begin
      if(cursor==NUM_SECTORS) begin
       if(rescan || dirty_valid) begin cursor<=0;rescan<=0;end
       else begin flushing<=0;state<=IDLE;end
      end
      else if(dirty[cursor[AW-1:0]]) begin sector_index<=cursor[AW-1:0];sector_valid<=1;active<=1;again<=0;state<=WAIT;end
      else cursor<=cursor+1'b1;
     end
     WAIT: begin
      if(sector_valid && sector_accept) sector_valid<=0;
      if(!sector_valid && sector_done) begin
       active<=0;
       if(!sector_ok) begin flushing<=0;flush_error<=1;state<=IDLE;end
       else begin
        if(!again && !(dirty_valid && dirty_sector==sector_index)) dirty[sector_index]<=0;
        cursor<=cursor+1'b1;state<=SCAN;
       end
      end
     end
     default: state<=IDLE;
    endcase
   end
  endcase
 end
endmodule
