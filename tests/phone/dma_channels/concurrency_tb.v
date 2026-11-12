`timescale 1ns/1ps
// Production worker-count experiment. Exact router, LCD RAM mux and CPU/DMA
// SDRAM arbiter; synthetic memory timing, FIFO endpoint and CPU request stream.
module concurrency_tb;
parameter integer ENGINES=3;
localparam integer FRAME_WORDS=18304;
reg clk=0,reset=1;always #5 clk=~clk;
reg req=0,commit=0,we=0;reg [31:0] addr=0,din=0;
wire claim,bad,ready;wire [31:0] dout;wire [7:0] irq,errors,active;
wire cv,cr,cw,rv,re;wire [31:0] ca,cd,rd;wire [3:0] cb;
wire lr,la,lk,pv;wire [24:0] lad;wire [31:0] ld,pd;
wire gr,gw,gack;wire [24:0] ga;wire [31:0] gd,grd;wire [3:0] gb;
wire local_valid,local_write;wire [31:0] local_addr,local_data;wire [3:0] local_be;
wire mr,mw,macc,mack;wire [24:0] ma;wire [31:0] md,mrd;wire [3:0] mb;
wire phys_req,phys_we,cpu_ack;wire [24:0] phys_addr;wire [31:0] phys_data;wire [3:0] phys_be;
integer memory_delay=0,cycles=0,mode=0,pixels=0,copy_writes=0,mmc_bytes=0,mmc_reads=0;
integer cpu_acks=0,last_cpu=0,max_cpu_gap=0,lcd_start=0,lcd_done=0,release_cycle=0;
integer copy_at_frame=0,cpu_at_frame=0,stall_frame=0;
reg release_fifo=0;
wire fifo_slot=release_fifo;
wire phys_ack=phys_req && memory_delay==2;
function [31:0] memory_word;
 input [24:0] address;
 begin memory_word=32'h5a000000 ^ {7'd0,address};end
endfunction
assign mrd=memory_word(phys_addr);
ngage_dma_channels #(.ENGINES(ENGINES),.PRODUCTION(1)) dut(
 .clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(4'hf),
 .claim(claim),.bad(bad),.ready(ready),.dout(dout),.irq_pending(irq),.error_pending(errors),.active_channels(active),
 .lcd_mem_req(lr),.lcd_mem_addr(lad),.lcd_mem_accept(la),.lcd_mem_ack(lk),.lcd_mem_data(ld),
 .lcd_pixel_valid(pv),.lcd_pixel_data(pd),.lcd_pixel_ready(1'b1),.lcd_pixel_error(1'b0),
 .lcd_ready(1'b1),.lcd_drained(1'b1),.mmc_rx_ready(1'b0),.mmc_tx_ready(release_fifo),.mmc_ready(fifo_slot),
 .source_ready(8'hff),.destination_ready(8'hff),.cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),
 .cmd_addr(ca),.cmd_data(cd),.cmd_be(cb),.rsp_valid(rv),.rsp_error(re),.rsp_data(rd));
ngage_dma_route route(.clk(clk),.reset(reset),.cpu_lock(1'b0),
 .cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),.cmd_addr(ca),.cmd_data(cd),.cmd_be(cb),
 .rsp_valid(rv),.rsp_error(re),.rsp_data(rd),.ram_req(gr),.ram_write(gw),.ram_addr(ga),.ram_data(gd),.ram_be(gb),.ram_ack(gack),.ram_rdata(grd),
 .local_valid(local_valid),.local_ready(fifo_slot),.local_write(local_write),.local_addr(local_addr),.local_data(local_data),.local_be(local_be),
 .local_done(local_valid&&fifo_slot),.local_error(1'b0),.local_rdata(32'd0));
ngage_dma_ram_mux mux(.clk(clk),.reset(reset),.lcd_req(lr),.lcd_addr(lad),.lcd_accept(la),.lcd_ack(lk),.lcd_rdata(ld),
 .dma_req(gr),.dma_write(gw),.dma_addr(ga),.dma_data(gd),.dma_be(gb),.dma_ack(gack),.dma_rdata(grd),
 .mem_req(mr),.mem_write(mw),.mem_addr(ma),.mem_data(md),.mem_be(mb),.mem_accept(macc),.mem_ack(mack),.mem_rdata(mrd));
ngage_sdram_arbiter arb(.clk(clk),.reset(reset),.cpu_lock(1'b0),
 .cpu_req(!reset),.cpu_we(1'b0),.cpu_addr(25'h400000),.cpu_data(32'd0),.cpu_be(4'hf),.cpu_ack(cpu_ack),.cpu_rdata(),
 .dma_req(mr),.dma_we(mw),.dma_addr(ma),.dma_data(md),.dma_be(mb),.dma_ack(mack),.dma_rdata(),.dma_accept(macc),.cpu_accept(),
 .mem_req(phys_req),.mem_we(phys_we),.mem_addr(phys_addr),.mem_data(phys_data),.mem_be(phys_be),.mem_ack(phys_ack),.mem_rdata(mrd));
`ifdef DMA_BASELINE
wire bc,bb,bv,bw,blr,bpv;wire [7:0] bi,be,ba;wire [31:0] bd,bca,bcd,bpd;wire [24:0] blad;wire [3:0] bcb;
ngage_dma_channels_baseline #(.ENGINES(ENGINES),.PRODUCTION(1)) baseline(
 .clk(clk),.reset(reset),.req(req),.commit(commit),.we(we),.addr(addr),.din(din),.sel(4'hf),
 .claim(bc),.bad(bb),.dout(bd),.irq_pending(bi),.error_pending(be),.active_channels(ba),
 .lcd_mem_req(blr),.lcd_mem_addr(blad),.lcd_mem_accept(la),.lcd_mem_ack(lk),.lcd_mem_data(ld),
 .lcd_pixel_valid(bpv),.lcd_pixel_data(bpd),.lcd_pixel_ready(1'b1),.lcd_pixel_error(1'b0),
 .lcd_ready(1'b1),.lcd_drained(1'b1),.mmc_rx_ready(1'b0),.mmc_tx_ready(release_fifo),.mmc_ready(fifo_slot),
 .source_ready(8'hff),.destination_ready(8'hff),.cmd_valid(bv),.cmd_ready(cr),.cmd_write(bw),
 .cmd_addr(bca),.cmd_data(bcd),.cmd_be(bcb),.rsp_valid(rv),.rsp_error(re),.rsp_data(rd));
always @(negedge clk)begin
 #2;
 if(!reset)begin
  if({claim,bad,irq,errors,active,cv,lr,pv}!=={bc,bb,bi,be,ba,bv,blr,bpv})$fatal(1,"production baseline state mismatch");
  if(cv&&{cw,ca,cd,cb}!=={bw,bca,bcd,bcb})$fatal(1,"production baseline generic packet mismatch");
  if(lr&&lad!==blad)$fatal(1,"production baseline LCD address mismatch");
  if(pv&&pd!==bpd)$fatal(1,"production baseline LCD pixel mismatch");
 end
end
`endif
always @(posedge clk)begin
 if(reset)memory_delay<=0;
 else begin
  cycles=cycles+1;
  if(!phys_req||phys_ack)memory_delay<=0;else memory_delay<=memory_delay+1;
  if(cycles>400000)$fatal(1,"concurrency timeout mode%0d engines%0d active%h irq%h pixels%0d mmc%0d copy%0d release%0d route%0d cv%0d cr%0d ca%h",mode,ENGINES,active,irq,pixels,mmc_bytes,copy_writes,release_fifo,route.state,cv,cr,ca);
  if(cpu_ack)begin
   cpu_acks=cpu_acks+1;
   if(last_cpu && cycles-last_cpu>max_cpu_gap)max_cpu_gap=cycles-last_cpu;
   last_cpu=cycles;
  end
  if(phys_ack && !phys_we && phys_addr[24:16]==3)mmc_reads=mmc_reads+1;
  if(phys_ack && phys_we && phys_addr[24:16]==2)begin
   if(phys_be!=15 || phys_data!==memory_word(25'h10000+phys_addr-25'h20000))$fatal(1,"memory copy payload");
   copy_writes=copy_writes+1;
  end
  if(pv)begin
   if(pd!==memory_word(25'h100000+pixels*4))$fatal(1,"LCD word%0d got%h",pixels,pd);
   pixels=pixels+1;
  end
  if(local_valid && fifo_slot)begin
   if(!local_write||local_addr!=32'h0c120624||local_be!=1||
      local_data[7:0]!==((memory_word(25'h30000+(mmc_bytes/4)*4) >> ((mmc_bytes%4)*8))&255))$fatal(1,"MMC byte%0d",mmc_bytes);
   mmc_bytes=mmc_bytes+1;
  end
  if(commit&&req&&we&&addr==32'h0c120388&&din==2)lcd_start=cycles;
 end
end
task wr(input [31:0] a,d);
 begin
  @(negedge clk);req=1;commit=0;we=1;addr=a;din=d;#1;
  while(!ready)begin @(negedge clk);#1;end
  commit=1;
  if(!claim||bad||!ready)$fatal(1,"programming rejected %h",a);
  @(negedge clk);req=0;commit=0;we=0;
 end
endtask
task program_channel(input integer ch,input [31:0] source,destination,count,sw,dw,si,di);
 begin
  wr(32'h0c120304+ch*64,1);wr(32'h0c120314+ch*64,source);wr(32'h0c120318+ch*64,si);
  wr(32'h0c12031c+ch*64,sw);wr(32'h0c120320+ch*64,destination);wr(32'h0c120324+ch*64,di);
  wr(32'h0c120328+ch*64,dw);wr(32'h0c12032c+ch*64,count);
 end
endtask
initial begin
 if($value$plusargs("mode=%d",mode))begin end
 repeat(4)@(negedge clk);reset=0;
 wr(32'h0c120064,32'h702);
 program_channel(0,32'h0a030000,32'h10120624,255,32,8,4,0);
 program_channel(1,32'h0a010000,32'h0a020000,255,32,32,4,4);
 program_channel(2,32'h0a100000,32'h10121208,FRAME_WORDS-1,32,32,4,0);
 if(mode==1)begin
  release_fifo=1;release_cycle=cycles;wr(32'h0c120308,2);wait(irq[0]);
  if(mmc_bytes!=256||errors||active)$fatal(1,"normal MMC completion");
  $display("PASS concurrency engines=%0d mode=mmc bytes=%0d clocks=%0d cpu_acks=%0d max_cpu_gap=%0d",ENGINES,mmc_bytes,cycles-release_cycle,cpu_acks,max_cpu_gap);
 end else begin
  if(mode==0)begin
   wr(32'h0c120308,2);wait(mmc_reads>0);repeat(8)@(negedge clk);
   wr(32'h0c120348,1);
  end
  wr(32'h0c120388,2);wait(irq[2]);lcd_done=cycles;
  if(pixels!=FRAME_WORDS||errors||mmc_bytes)$fatal(1,"LCD/stall completion");
  if(mode==0)begin
   copy_at_frame=copy_writes;cpu_at_frame=cpu_acks;stall_frame=lcd_done-lcd_start;
   if(ENGINES==1 ? copy_writes!=0 : (copy_writes!=128||!irq[1]))$fatal(1,"worker concurrency");
   release_cycle=cycles;release_fifo=1;wait(irq[0]);wait(!active[1]);
   if(mmc_bytes!=256||copy_writes!=128||errors)$fatal(1,"released MMC/copy completion");
   $display("PASS concurrency engines=%0d mode=stalled frame_clocks=%0d copy_words_at_frame=%0d cpu_acks_at_frame=%0d max_cpu_gap=%0d release_to_all_done=%0d",ENGINES,stall_frame,copy_at_frame,cpu_at_frame,max_cpu_gap,cycles-release_cycle);
  end else $display("PASS concurrency engines=%0d mode=lcd frame_clocks=%0d cpu_acks=%0d max_cpu_gap=%0d",ENGINES,lcd_done-lcd_start,cpu_acks,max_cpu_gap);
 end
 if(max_cpu_gap>8)$fatal(1,"CPU memory requests starved");
 $finish;
end
endmodule
