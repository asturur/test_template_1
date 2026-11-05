// Diagnostic C: NOR command model. The backing store is a separate DDR byte
// array; no command changes it until a backend write is acknowledged.
// Semantics intentionally follow BootProfile::cdrive_access (including its
// first-program_pending 0->1 behavior), which is not a verified physical NOR model.
module ngage_cflash #(
 parameter [31:0] BASE=32'h31400000
)(input wire clk, input wire reset,
 input wire req_valid, output wire req_ready, input wire req_write,
 input wire [21:0] req_offset, input wire [31:0] req_data, input wire [3:0] req_be,
 output reg rsp_valid, output reg rsp_error, output reg [31:0] rsp_data,
 output wire mem_valid, input wire mem_ready, output reg mem_write,
 output reg [31:0] mem_addr, output reg [31:0] mem_wdata, output reg [3:0] mem_be,
 input wire mem_done, input wire [31:0] mem_rdata,
 output reg dirty_valid, output reg [12:0] dirty_sector, output wire pending);
 localparam IDLE=0, ISSUE=1, WAIT_MEM=2;
 localparam OP_READ=0, OP_PROGRAM_READ=1, OP_PROGRAM_WRITE=2, OP_ERASE_READ=3, OP_ERASE_WRITE=4;
 reg [1:0] state=IDLE, unlock=0; reg [2:0] op=OP_READ;
 reg autoselect=0, program_pending=0, erase_armed=0, erase_pending=0, erase_polled=0;
 reg [21:0] erase_base=0, erase_end=0, erase_cursor=0;
 reg [3:0] read_mask=0;reg array_read=0;reg [31:0] erase_result=0;
 wire [31:0] mem_offset=mem_addr-BASE;
 wire half_ok=(req_be==4'h3 || req_be==4'hc);
 wire [21:0] half_off={req_offset[21:2],2'b00} + (req_be==4'hc ? 22'd2 : 22'd0);
 wire [15:0] value=req_be==4'hc ? req_data[31:16] : req_data[15:0];
 wire [21:0] erase_sector_base = (half_off[20:16]==5'h1f) ?
    {half_off[21],5'h1f,half_off[15:14],14'b0} : {half_off[21:16],16'b0};
 wire [21:0] erase_sector_last = erase_sector_base + ((half_off[20:16]==5'h1f) ? 22'h003ffc : 22'h00fffc);
 assign pending=(state!=IDLE) || program_pending || erase_pending || erase_armed || unlock!=0;
 assign req_ready=(state==IDLE) && !reset;
 assign mem_valid=(state==ISSUE);
 function automatic [31:0] mask_bytes(input [3:0] b);
  begin mask_bytes={{8{b[3]}},{8{b[2]}},{8{b[1]}},{8{b[0]}}}; end
 endfunction
 always @(posedge clk) begin
  rsp_valid<=0; rsp_error<=0; dirty_valid<=0;
  if(reset && state==IDLE) begin
   if(erase_pending) begin
    erase_cursor<=erase_base;mem_addr<=BASE+{10'b0,erase_base};mem_wdata<=32'hffffffff;mem_be<=15;mem_write<=0;op<=OP_ERASE_READ;erase_result<=0;state<=ISSUE;
   end else begin
    state<=IDLE; unlock<=0; autoselect<=0;program_pending<=0;erase_armed<=0;erase_polled<=0;
   end
  end else case(state)
   IDLE: if(req_valid && req_ready) begin
    rsp_data<=0;
    if(!req_write && !autoselect && unlock==0 && !erase_pending) begin
     op<=OP_READ; array_read<=1;read_mask<=req_be;mem_write<=0;
     mem_addr<=BASE+{10'b0,req_offset[21:2],2'b00};mem_be<=4'hf; state<=ISSUE;
    end else if(req_write && req_be==4'hf && !program_pending && unlock==0 && !autoselect && !erase_armed && !erase_pending) begin
     rsp_valid<=1; // ordinary 32-bit write in read mode is ignored
    end else if(!half_ok) begin rsp_valid<=1;rsp_error<=1; end
    else if(req_write) begin
     if(program_pending) begin
      program_pending<=0;unlock<=0;op<=OP_PROGRAM_READ;mem_write<=0;
      mem_addr<=BASE+{10'b0,req_offset[21:2],2'b00};mem_wdata<=req_data;mem_be<=req_be;state<=ISSUE;
     end else if(value==16'hf0 || value==16'hff) begin
      unlock<=0;autoselect<=0;erase_armed<=0;rsp_valid<=1;
     end else if(value==16'h60) rsp_valid<=1;
     else if(value==16'hb0) begin
      if(erase_pending) begin
       erase_cursor<=erase_base;mem_addr<=BASE+{10'b0,erase_base};mem_wdata<=32'hffffffff;mem_be<=15;mem_write<=0;op<=OP_ERASE_READ;erase_result<=0;state<=ISSUE;
      end else rsp_valid<=1;
     end else if(value==16'h30 && erase_armed && unlock==2) begin
      erase_base<=erase_sector_base;erase_end<=erase_sector_last;erase_pending<=1;erase_polled<=0;erase_armed<=0;unlock<=0;rsp_valid<=1;
     end else if((half_off & 22'h000fff)==22'h000aaa && value==16'haa) begin unlock<=1;rsp_valid<=1;end
     else if(unlock==1 && (half_off & 22'h000fff)==22'h000554 && value==16'h55) begin unlock<=2;rsp_valid<=1;end
     else if(unlock==2 && (half_off & 22'h000fff)==22'h000aaa && value==16'h90) begin autoselect<=1;unlock<=0;rsp_valid<=1;end
     else if(unlock==2 && value==16'ha0) begin program_pending<=1;unlock<=0;rsp_valid<=1;end
     else if(unlock==2 && (half_off & 22'h000fff)==22'h000aaa && value==16'h80) begin erase_armed<=1;unlock<=0;rsp_valid<=1;end
     else begin rsp_valid<=1;rsp_error<=1;end
    end else if(autoselect) begin
     case(half_off[3:0])
      0: rsp_data<=req_be==12 ? 32'h00010000 : 32'h00000001;
      2: rsp_data<=req_be==12 ? 32'h257e0000 : 32'h0000257e;
      default: rsp_data<=0;
     endcase
     rsp_valid<=1;
    end else if(erase_pending && half_off>=erase_base && half_off<=erase_end+3) begin
     if(!erase_polled) begin erase_polled<=1;rsp_valid<=1;rsp_data<=req_be==12 ? 32'h00080000 : 32'h00000008;end
     else begin
      erase_cursor<=erase_base;mem_addr<=BASE+{10'b0,erase_base};mem_wdata<=32'hffffffff;mem_be<=15;mem_write<=0;op<=OP_ERASE_READ;erase_result<=req_be==12 ? 32'hffff0000 : 32'h0000ffff;state<=ISSUE;
     end
    end else begin
     op<=OP_READ;array_read<=0;read_mask<=req_be;mem_write<=0;
     mem_addr<=BASE+{10'b0,req_offset[21:2],2'b00};mem_be<=15;state<=ISSUE;
    end
   end
   ISSUE: if(mem_ready) state<=WAIT_MEM;
   WAIT_MEM: if(mem_done) begin
    if(op==OP_READ) begin rsp_data<=array_read ? mem_rdata : (mem_rdata & mask_bytes(read_mask));rsp_valid<=1;state<=IDLE;end
    else if(op==OP_PROGRAM_READ) begin
     if((mem_rdata & mask_bytes(mem_be))==(mem_wdata & mask_bytes(mem_be))) begin rsp_valid<=1;state<=IDLE;end
     else begin mem_write<=1;op<=OP_PROGRAM_WRITE;state<=ISSUE;end
    end else if(op==OP_PROGRAM_WRITE) begin
     dirty_valid<=1;dirty_sector<=mem_offset[21:9];rsp_valid<=1;state<=IDLE;
    end else if(op==OP_ERASE_READ && mem_rdata!=32'hffffffff) begin
     mem_write<=1;op<=OP_ERASE_WRITE;state<=ISSUE;
    end else begin
     if(op==OP_ERASE_WRITE) begin dirty_valid<=1;dirty_sector<=mem_offset[21:9];end
     if(erase_cursor==erase_end) begin erase_pending<=0;erase_polled<=0;rsp_data<=erase_result;rsp_valid<=1;state<=IDLE;end
     else begin erase_cursor<=erase_cursor+4;mem_addr<=mem_addr+4;mem_write<=0;op<=OP_ERASE_READ;state<=ISSUE;end
    end
   end
   default: state<=IDLE;
  endcase
 end
endmodule
