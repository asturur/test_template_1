// Mount a pre-created working save, validate its header, restore C:/PMM,
// then snapshot dirty sectors on explicit flush. A save is acknowledged only
// after the HPS sector handshake completes. No power-loss journal is implied.
module ngage_save_manager #(
 parameter integer C_SECTORS=8192, PMM_SECTORS=128, SD_TIMEOUT=104000000
)(input wire clk,input wire reset,
 input wire mount,input wire readonly_image,input wire [63:0] image_size,
 input wire bundle_verified,input wire [1:0] profile,
 input wire [255:0] core_sha_le,input wire [255:0] extension_sha_le,
 input wire dirty_valid,input wire [13:0] dirty_sector,input wire flush_start,
 output reg mounted,output wire saving,output reg saved,output reg error,output wire busy,
 output wire mem_valid,input wire mem_ready,output wire mem_write,
 output wire [31:0] mem_addr,output wire [31:0] mem_data,output wire [3:0] mem_be,
 input wire mem_done,input wire [31:0] mem_rdata,
 output wire [31:0] sd_lba,output wire sd_rd,output wire sd_wr,input wire sd_ack,
 input wire [12:0] hps_addr,input wire [15:0] hps_dout,input wire hps_we,output wire [15:0] hps_din, input wire flash_quiescent);
 localparam IDLE=0,HEADER_START=1,HEADER_WAIT=2,CHECK_START=3,CHECK_WAIT=4,LOAD_START=5,LOAD_WAIT=6,FLUSH_WAIT=7,FAILED=8;
 reg [3:0] state=IDLE;reg [13:0] cursor=0;reg was_flushing=0,flush_pending=0;
 wire h_ready,h_done,h_error,h_rd,h_wr;wire [31:0] h_lba;wire [15:0] h_din,h_local;
 wire [7:0] h_addr;wire check_busy,check_done,check_valid;
 wire header_owner=(state==HEADER_START || state==HEADER_WAIT || state==CHECK_START || state==CHECK_WAIT);
 ngage_sd_sector #(.TIMEOUT(SD_TIMEOUT)) header_sector(
  .clk(clk),.reset(reset),.start(state==HEADER_START),.write_sector(1'b0),.start_lba(32'b0),
  .ready(h_ready),.done(h_done),.error(h_error),.local_addr(h_addr),.local_din(16'b0),.local_we(1'b0),.local_dout(h_local),
  .sd_lba(h_lba),.sd_rd(h_rd),.sd_wr(h_wr),.sd_ack(sd_ack),
  .hps_addr(hps_addr),.hps_dout(hps_dout),.hps_we(hps_we && header_owner),.hps_din(h_din)
 );
 ngage_save_header #(.C_BYTES(C_SECTORS*512),.PMM_BYTES(PMM_SECTORS*512)) check_header(
  .clk(clk),.reset(reset),.start(state==CHECK_START),.profile(profile),.core_sha_le(core_sha_le),.extension_sha_le(extension_sha_le),
  .address(h_addr),.word_data(h_local),.busy(check_busy),.done(check_done),.valid(check_valid)
 );
 wire b_ready,b_done,b_error,b_rd,b_wr;wire [31:0] b_lba;wire [15:0] b_din;
 wire tracker_flushing,tracker_error,tracker_init,tracker_valid;wire [13:0] tracker_index;
 wire accept_dirty=(state==IDLE && mounted && tracker_valid && b_ready);
 wire start_bridge=(state==LOAD_START || accept_dirty);
 ngage_save_sector_bridge #(.C_SECTORS(C_SECTORS),.PMM_SECTORS(PMM_SECTORS),.SD_TIMEOUT(SD_TIMEOUT)) bridge(
  .clk(clk),.reset(reset),.start(start_bridge),.load_from_disk(state==LOAD_START),.sector_index(state==LOAD_START?cursor:tracker_index),
  .ready(b_ready),.done(b_done),.error(b_error),.mem_valid(mem_valid),.mem_ready(mem_ready),.mem_write(mem_write),
  .mem_addr(mem_addr),.mem_data(mem_data),.mem_be(mem_be),.mem_done(mem_done),.mem_rdata(mem_rdata),
  .sd_lba(b_lba),.sd_rd(b_rd),.sd_wr(b_wr),.sd_ack(sd_ack),.hps_addr(hps_addr),.hps_dout(hps_dout),.hps_we(hps_we && !header_owner),.hps_din(b_din)
 );
 ngage_dirty_tracker #(.SECTORS(C_SECTORS+PMM_SECTORS),.AW(14)) tracker(
  .clk(clk),.cold_reset(reset),.dirty_valid(dirty_valid),.dirty_sector(dirty_sector),
  .flush_start(flush_pending && flash_quiescent && mounted && state==IDLE),.flushing(tracker_flushing),.flush_error(tracker_error),.init_done(tracker_init),
  .sector_valid(tracker_valid),.sector_accept(accept_dirty),.sector_index(tracker_index),
  .sector_done(state==FLUSH_WAIT && b_done),.sector_ok(!b_error),
  .abort_flush(mount && (state!=IDLE || (mounted && (!saved || dirty_valid || tracker_flushing || tracker_valid || flush_pending || !flash_quiescent))))
 );
 assign sd_lba=header_owner?h_lba:b_lba;
 // A mount event changes the backing medium immediately. Abort and report an
 // uncertain transfer rather than letting subsequent sectors hit a new image.
 assign sd_rd=(state==FAILED || mount) ? 1'b0 : (header_owner?h_rd:b_rd);
 assign sd_wr=(state==FAILED || mount) ? 1'b0 : (header_owner?h_wr:b_wr);assign hps_din=header_owner?h_din:b_din;
 assign saving=tracker_flushing || state==FLUSH_WAIT || flush_pending;
 assign busy=state!=IDLE && state!=FAILED;
 always @(posedge clk)begin
  if(reset)begin state<=IDLE;mounted<=0;saved<=0;error<=0;cursor<=0;was_flushing<=0;flush_pending<=0;end
  else begin
   was_flushing<=tracker_flushing;
   if(dirty_valid || (mounted && !flash_quiescent) || (flush_start && mounted)) saved<=0;
   if(flush_start && mounted) flush_pending<=1;
   if(flush_pending && flash_quiescent && mounted && state==IDLE) flush_pending<=0;
   if(was_flushing && !tracker_flushing && !tracker_error && mounted) begin
    if(flash_quiescent && !dirty_valid && !flush_start && !flush_pending) saved<=1;
    else flush_pending<=1;
   end
   if(flush_start && mounted && state==IDLE) error<=0;
   if(mount && state!=IDLE) begin mounted<=0;saved<=0;error<=1;state<=FAILED;end
   else case(state)
    IDLE:begin
     if(mount && mounted && (!saved || dirty_valid || tracker_flushing || tracker_valid || flush_pending || !flash_quiescent)) begin
      mounted<=0;saved<=0;error<=1;state<=FAILED; // Media already changed; preserve RAM and stop.
     end else if(mount)begin
      mounted<=0;saved<=0;error<=0;cursor<=0;
      if(!tracker_init || !bundle_verified || readonly_image || image_size!=512+(C_SECTORS+PMM_SECTORS)*512)begin error<=1;state<=IDLE;end
      else state<=HEADER_START;
     end else if(accept_dirty)state<=FLUSH_WAIT;
    end
    HEADER_START:if(h_ready)state<=HEADER_WAIT;
    HEADER_WAIT:if(h_done)begin if(h_error)begin error<=1;state<=FAILED;end else state<=CHECK_START;end
    CHECK_START:state<=CHECK_WAIT;
    CHECK_WAIT:if(check_done)begin if(!check_valid)begin error<=1;state<=IDLE;end else state<=LOAD_START;end
    LOAD_START:if(b_ready)state<=LOAD_WAIT;
    LOAD_WAIT:if(b_done)begin
     if(b_error)begin error<=1;state<=FAILED;end
     else if(cursor==C_SECTORS+PMM_SECTORS-1)begin mounted<=1;saved<=1;state<=IDLE;end
     else begin cursor<=cursor+1'b1;state<=LOAD_START;end
    end
    FLUSH_WAIT:if(b_done)begin if(b_error)begin error<=1;mounted<=0;saved<=0;state<=FAILED;end else state<=IDLE;end
    FAILED:state<=FAILED; // Explicit transport reset/remount required.
    default:state<=FAILED;
   endcase
  end
 end
endmodule
