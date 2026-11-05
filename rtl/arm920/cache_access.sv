// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental ARM920-shaped cache with serialized CPU requests and buffered writes.
// One request at a time. The caller supplies already translated addresses and
// attributes; MMU checks, CP15 maintenance, CPU pipeline and Wishbone adapting
// remain outside this block. Cached and buffered operations retry a bus
// error; they never report it as
// an architectural external abort. Persistent errors hold progress.
module arm920_cache_access (
 input logic clk, reset,
 input logic req_valid, output logic req_ready,
 input logic [31:0] req_mva, req_physical,
 input logic req_write, req_cache_enable, req_cacheable, req_bufferable,
 input logic [31:0] req_wdata, input logic [3:0] req_byte_enable,
 output logic response_valid, response_error, output logic [31:0] response_data,
 output logic write_buffer_empty,write_buffer_error,
 input logic fast_lookup_enable,input logic [31:0] fast_lookup_address,
 output logic fast_lookup_valid,output logic [31:0] fast_lookup_checked,
 output logic [255:0] fast_lookup_line,
 input logic invalidate_all, lock_write, input logic [5:0] lock_base_in,
 input logic round_robin,
 input logic maint_valid,maint_clean,maint_invalidate,maint_all,maint_by_mva,
 input logic [31:0] maint_address,
 input logic [5:0] maint_way,input logic [2:0] maint_segment,
 output logic maint_ready,maint_done,maint_error,
 output logic bus_valid,bus_write, output logic [31:0] bus_address,bus_wdata,
 output logic [3:0] bus_byte_enable,
 input logic bus_ack,bus_error, input logic [31:0] bus_rdata
);
 typedef enum logic [3:0] {IDLE, LOOKUP, READ_LINE, STORE_HIT, BYPASS, WAIT_REFILL, MAINTAIN, MAINT_LOOKUP, BUFFER_STORE, WAIT_DRAIN} state_t;
 state_t state;
 logic [31:0] mva,pa,wdata;
 logic [3:0] ben;
 logic wr,enabled,cacheable,bufferable;
 logic hit,victim_valid,need,refill_ready,read_valid;
 logic [5:0] hit_way,lock_base;
 logic [1:0] victim_dirty;
 logic [31:0] victim_pa, refill_mva,fill_pa;
 logic [255:0] line,fill_line;
 logic read_victim,fill,wb_done,refill_busy,refill_done,refill_error;
 logic refill_bus_valid,refill_bus_write;
 logic [31:0] refill_bus_address,refill_bus_data;
 logic store_commit;
 logic scan_read,scan_valid,scan_clean,scan_invalidate,maint_bus_valid;
 logic [5:0] scan_way;logic [2:0] scan_segment;logic [1:0] scan_dirty;
 logic [31:0] scan_pa,maint_bus_address,maint_bus_data;
 logic maintenance_busy,maintenance_done,maintenance_error;
 logic saved_maint_clean,saved_maint_invalidate,saved_maint_all,saved_maint_by_mva;
 logic [31:0] saved_maint_address;logic [5:0] saved_maint_way;logic [2:0] saved_maint_segment;
 wire fast_read=fast_lookup_enable && state==IDLE && !maint_valid && !invalidate_all && !lock_write;
 wire [31:0] bank_mva=(state==MAINT_LOOKUP || state==MAINTAIN) && saved_maint_by_mva ? saved_maint_address : fast_read ? fast_lookup_address : mva;
 assign fast_lookup_line=line;
 always_ff @(posedge clk) begin
  if(reset)begin fast_lookup_valid<=0;fast_lookup_checked<=0;end
  else begin fast_lookup_valid<=fast_read && hit;fast_lookup_checked<=fast_lookup_address;end
 end
 assign maint_done=(maintenance_done && !maintenance_error) || (state==MAINT_LOOKUP && saved_maint_by_mva && !hit);
 assign maint_error=maintenance_error;

 logic [31:0] store_mask;
 logic buffer_ready,buffer_bus_valid,buffer_full,buffer_line_hazard;
 logic bus_held,bus_held_refill;
 // Queue dirty replacement data before allowing the refill read to issue.
 wire refill_buffer_push = state==WAIT_REFILL && refill_bus_valid && refill_bus_write;
 logic [2:0] buffer_entries;
 logic [31:0] buffer_bus_address,buffer_bus_data;
 logic [3:0] buffer_bus_sel;
 arm920_write_buffer write_buffer(.clk(clk),.reset(reset),
  .push_valid(state==BUFFER_STORE || (state==MAINTAIN && maint_bus_valid) || refill_buffer_push),.push_ready(buffer_ready),
  .push_address(state==MAINTAIN ? maint_bus_address : refill_buffer_push ? refill_bus_address : pa),.push_words(3'd1),
  .push_data({96'b0,(state==MAINTAIN ? maint_bus_data : refill_buffer_push ? refill_bus_data : wdata)}),
  .push_byte_enable({12'b0,((state==MAINTAIN || refill_buffer_push) ? 4'hf : ben)}),.empty(write_buffer_empty),
  .full(buffer_full),.entries(buffer_entries),.query_line_address(pa),.query_line_pending(buffer_line_hazard),.bus_valid(buffer_bus_valid),
  .bus_address(buffer_bus_address),.bus_data(buffer_bus_data),.bus_byte_enable(buffer_bus_sel),
  .bus_ack(bus_ack && buffer_bus_valid && !choose_refill),.bus_error(bus_error && buffer_bus_valid && !choose_refill),
  .error_latched(write_buffer_error),.clear_error(1'b1));
 assign maint_ready=(state==IDLE) && write_buffer_empty && !invalidate_all && !lock_write;
 // Cached CPU hits can proceed while buffered writes drain; maintenance waits.
 assign req_ready=(state==IDLE) && !invalidate_all && !lock_write && !maint_valid;
 assign store_commit=(state==STORE_HIT) || (state==BUFFER_STORE && buffer_ready && wr && enabled && cacheable && !bufferable && hit);
 assign store_mask={28'b0,ben} << {mva[4:2],2'b00};
 // Never switch an offered beat until it has completed. Between beats an
 // unrelated replacement read can precede queued writes; an overlapping line
 // must wait until those writes retire.
 wire refill_read = state==WAIT_REFILL && refill_bus_valid && !refill_bus_write && !buffer_line_hazard;
 wire choose_refill = bus_held ? bus_held_refill : refill_read;
 assign bus_valid=choose_refill ? refill_read : (buffer_bus_valid || state==BYPASS);
 assign bus_write=choose_refill ? 1'b0 : buffer_bus_valid ? 1'b1 : wr;
 assign bus_address=choose_refill ? refill_bus_address : buffer_bus_valid ? buffer_bus_address : pa;
 assign bus_wdata=choose_refill ? refill_bus_data : buffer_bus_valid ? buffer_bus_data : wdata;
 assign bus_byte_enable=choose_refill ? 4'hf : buffer_bus_valid ? buffer_bus_sel : ben;
 always_ff @(posedge clk) begin
  if(reset) begin bus_held<=0;bus_held_refill<=0;end
  else if(bus_valid && (bus_ack || bus_error)) bus_held<=0;
  else if(bus_valid && !bus_held) begin bus_held<=1;bus_held_refill<=choose_refill;end
 end
 arm920_cache_bank bank(.clk(clk),.reset(reset),.mva(bank_mva),.hit(hit),.hit_way(hit_way),
  .read_victim(read_victim),.read_valid(read_valid),.read_line(line),.victim_valid(victim_valid),
  .victim_dirty(victim_dirty),.victim_physical_line(victim_pa),.needs_writeback(need),
  .writeback_done(wb_done),.refill(fill),.refill_physical(fill_pa),.refill_line(fill_line),
  .refill_ready(refill_ready),.store(store_commit),.store_dirty(bufferable),
  .store_enable(store_mask),.store_line({8{wdata}}),.invalidate_all(invalidate_all),
  .lock_write(lock_write),.lock_base_in(lock_base_in),.lock_base(lock_base),.round_robin(round_robin),.scan_read(scan_read),.scan_segment(scan_segment),.scan_way(scan_way),
  .scan_valid(scan_valid),.scan_dirty(scan_dirty),.scan_physical_line(scan_pa),.scan_clean(scan_clean),.scan_invalidate(scan_invalidate));
 // A maintenance write is acknowledged when the write buffer accepts it,
 // not when external memory eventually accepts the corresponding bus beat.
 arm920_cache_maintenance maintenance(.clk(clk),.reset(reset),.start(state==MAINT_LOOKUP && (!saved_maint_by_mva || hit)),
  .clean(saved_maint_clean),.invalidate(saved_maint_invalidate),.all(saved_maint_all),
  .index_way(saved_maint_by_mva ? hit_way : saved_maint_way),
  .index_segment(saved_maint_by_mva ? saved_maint_address[7:5] : saved_maint_segment),
  .busy(maintenance_busy),.done(maintenance_done),.error(maintenance_error),.scan_read(scan_read),.scan_way(scan_way),
  .scan_segment(scan_segment),.scan_valid(scan_valid),.scan_dirty(scan_dirty),.scan_physical_line(scan_pa),
  .scan_line(line),.scan_clean(scan_clean),.scan_invalidate(scan_invalidate),.bus_valid(maint_bus_valid),
  .bus_address(maint_bus_address),.bus_wdata(maint_bus_data),.bus_ack(state==MAINTAIN && buffer_ready),
  .bus_error(1'b0));
 arm920_cache_refill refill(.clk(clk),.reset(reset),
  .start(state==LOOKUP && enabled && cacheable && !wr && !hit && !buffer_line_hazard),
  .request_mva(mva),.request_physical(pa),.busy(refill_busy),.done(refill_done),.error(refill_error),
  .bank_mva(refill_mva),.bank_hit(hit),.bank_victim_valid(victim_valid),.bank_victim_dirty(victim_dirty),
  .bank_victim_physical(victim_pa),.bank_read_line(line),.bank_read_victim(read_victim),
  .bank_refill(fill),.bank_writeback_done(wb_done),.bank_refill_physical(fill_pa),
  .bank_refill_line(fill_line),.bank_refill_ready(refill_ready),
  .bus_valid(refill_bus_valid),.bus_write(refill_bus_write),.bus_address(refill_bus_address),
  .bus_wdata(refill_bus_data),.bus_ack(state==WAIT_REFILL && (refill_bus_write ? buffer_ready : (choose_refill && bus_ack))),
  .bus_error(state==WAIT_REFILL && !refill_bus_write && choose_refill && bus_error),.bus_rdata(bus_rdata));
 always_ff @(posedge clk) begin
  if(reset) begin state<=IDLE;response_valid<=0;response_error<=0;response_data<=0;
   mva<=0;pa<=0;wdata<=0;ben<=0;wr<=0;enabled<=0;cacheable<=0;bufferable<=0;
   saved_maint_clean<=0;saved_maint_invalidate<=0;saved_maint_all<=0;saved_maint_by_mva<=0;saved_maint_address<=0;saved_maint_way<=0;saved_maint_segment<=0;end
  else begin
   response_valid<=0;response_error<=0;
   case(state)
    IDLE: if(maint_valid && maint_ready) begin
     saved_maint_clean<=maint_clean;saved_maint_invalidate<=maint_invalidate;saved_maint_all<=maint_all;
     saved_maint_by_mva<=maint_by_mva;saved_maint_address<=maint_address;
     saved_maint_way<=maint_way;saved_maint_segment<=maint_segment;state<=MAINT_LOOKUP;
    end
    else if(req_valid && req_ready) begin
     mva<=req_mva;pa<=req_physical;wdata<=req_wdata;ben<=req_byte_enable;
     wr<=req_write;enabled<=req_cache_enable;cacheable<=req_cacheable;bufferable<=req_bufferable;
     state<=LOOKUP;
    end
    LOOKUP: if(wr) begin
      if(enabled && cacheable && hit && bufferable) state<=STORE_HIT;
      else if(bufferable || (enabled && cacheable)) state<=BUFFER_STORE;
      else if(!write_buffer_empty) state<=WAIT_DRAIN;
      else state<=BYPASS;
     end else if(enabled && cacheable && hit) state<=READ_LINE;
     else if(enabled && cacheable && !buffer_line_hazard) state<=WAIT_REFILL;
     else if(!write_buffer_empty) state<=WAIT_DRAIN;
     else if(enabled && cacheable) state<=WAIT_REFILL;
     else state<=BYPASS;
    READ_LINE: begin response_data<=line[mva[4:2]*32+:32];response_valid<=1;state<=IDLE;end
    STORE_HIT: begin response_valid<=1;state<=IDLE;end
    BUFFER_STORE: if(buffer_ready) begin response_valid<=1;state<=IDLE;end
    WAIT_DRAIN: if(write_buffer_empty) state<=LOOKUP;
    BYPASS: if((bus_ack || bus_error) && !buffer_bus_valid) begin
     response_data<=bus_rdata;response_error<=bus_error;response_valid<=1;state<=IDLE;
    end
    MAINT_LOOKUP: if(saved_maint_by_mva && !hit) state<=IDLE;else state<=MAINTAIN;
    MAINTAIN: if(maintenance_done) begin
     if(maintenance_error) state<=MAINT_LOOKUP;else state<=IDLE;
    end
    WAIT_REFILL: if(refill_done) begin
     // Cacheable accesses and writebacks cannot produce an ARM920 external
     // abort. Keep the old victim on failure and retry instead of committing.
     if(refill_error) state<=LOOKUP;
     else state<=READ_LINE;
    end
    default: state<=IDLE;
   endcase
  end
 end
`ifndef SYNTHESIS
 always @(posedge clk) if(!reset && state!=IDLE && (invalidate_all || lock_write))
  $fatal(1,"cache maintenance must not overlap an access");
`endif
endmodule
