`timescale 1ns/1ps
module tb;
parameter ORDERED=0;
reg autosave=0, flash_quiescent=1;
integer post_write_delay=0;
wire [1:0] slot_error;
reg clk=0;always #5 clk=~clk;reg inject_short=0,inject_swap=0,hold_requests=0,inject_mutation=0,saw_old_snapshot=0,first_snapshot_checked=0;
reg reset=1,flush=0,dirty=0;reg [13:0] dirty_sector=0;
tri [45:0] bus;tri [35:0] ext;tri [21:0] gamma;
reg [15:0] host_data=0;reg strobe=0,enable=0;
assign bus[31:16]=host_data;assign bus[33]=strobe;assign bus[34]=enable;assign bus[35]=0;assign bus[45:38]=0;assign ext[32]=0;
wire [2:0] mounts,rd,wr,ack;wire readonly_image;wire [63:0] size;wire [31:0] lba[3];wire [5:0] count[3];wire [12:0] ha;wire [15:0] hd,hi[3];wire hwe;
wire mounted,saving,saved,error,busy,mv,mw,mdone;wire [31:0] ma,mdata,mr;wire [3:0] mbe;
reg [31:0] ram[0:639];reg [15:0] disk[0:1][0:767];
reg verified=0,warm_request=0;wire phone_reset;
wire warm_pending;
ngage_reset_gate gate(.clk(clk),.cold_reset(reset),.reset_request(warm_request),
 .block_reset(busy||saving),.reset_pending(warm_pending),.phone_reset(phone_reset));
reg host_busy=0; integer checks=0, ordered_writes=0; integer write_order[0:127];
reg [31:0] memory_read=0;reg memory_done=0;integer idx,part,n,requests=0,reads=0,writes=0;reg [15:0] status_word,snapshot_word0;reg [31:0] current_lba;reg [31:0] stable_lba0,stable_lba1;reg stable_req0,stable_req1;
assign count[0]=0;assign count[1]=0;assign count[2]=0;
assign rd[2]=0;assign wr[2]=0;assign lba[2]=0;assign hi[2]=16'hffff;
assign hi[1]=hi[0];assign mr=memory_read;assign mdone=memory_done;
hps_io #(.CONF_STR("test"),.WIDE(1),.VDNUM(3),.PS2DIV(1)) hps(.clk_sys(clk),.HPS_BUS(bus),.EXT_BUS(ext),.gamma_bus(gamma),
 .img_mounted(mounts),.img_readonly(readonly_image),.img_size(size),.sd_lba(lba),.sd_blk_cnt(count),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),
 .sd_buff_addr(ha),.sd_buff_dout(hd),.sd_buff_din(hi),.sd_buff_wr(hwe),.ioctl_wait(1'b0),.ioctl_upload_req(1'b0),.ioctl_upload_index(8'b0),.ioctl_din(16'b0),
 .status_in(128'b0),.status_set(1'b0),.status_menumask(16'b0),.info_req(1'b0),.info(8'b0),.video_rotated(1'b0),.new_vmode(1'b0),
 .joystick_0_rumble(16'b0),.joystick_1_rumble(16'b0),.joystick_2_rumble(16'b0),.joystick_3_rumble(16'b0),.joystick_4_rumble(16'b0),.joystick_5_rumble(16'b0));
ngage_raw_save_manager #(.C_SECTORS(3),.PMM_SECTORS(2),.SD_TIMEOUT(100000),.ORDERED(ORDERED),
 .AUTO_QUIET_CYCLES(40),.AUTO_MAX_AGE_CYCLES(120),.AUTO_BATCH_SECTORS(2)) save(.clk(clk),.reset(reset),.mount(mounts[1:0]),.readonly_image(readonly_image),.image_size(size),.bundle_verified(verified),
 .autosave_enable(autosave),.pause_autosave(warm_pending||phone_reset),.slot_error(slot_error),
 .dirty_valid(dirty),.dirty_sector(dirty_sector),.flush_start(flush),.mounted(mounted),.saving(saving),.saved(saved),.error(error),.busy(busy),
 .mem_valid(mv),.mem_ready(1'b1),.mem_write(mw),.mem_addr(ma),.mem_data(mdata),.mem_be(mbe),.mem_done(mdone),.mem_rdata(mr),
 .sd_lba0(lba[0]),.sd_lba1(lba[1]),.sd_rd(rd[1:0]),.sd_wr(wr[1:0]),.sd_ack(ack[1:0]),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hi[0]),.flash_quiescent(flash_quiescent));
always @(posedge clk)begin
 memory_done<=0;
 if(mv && !memory_done)begin
  if(ma>=32'h31400000 && ma<32'h31400600)idx=(ma-32'h31400000)>>2;
  else if(ma>=32'h31800000 && ma<32'h31800400)idx=384+((ma-32'h31800000)>>2);
  else $fatal(1,"unexpected DDR address %h",ma);
  memory_read<=ram[idx];if(mw)for(integer j=0;j<4;j=j+1)if(mbe[j])ram[idx][j*8+:8]<=mdata[j*8+:8];memory_done<=1;
 end
end
task word_out(input [15:0] v);begin @(negedge clk);host_data=v;strobe=1;@(negedge clk);strobe=0;repeat(2)@(negedge clk);end endtask
task begin_io;begin @(negedge clk);enable=1;end endtask
task end_io;begin @(negedge clk);enable=0;strobe=0;repeat(3)@(negedge clk);end endtask
task mount_image(input [15:0] mask,input bit ro,input [63:0] length);begin
 begin_io();word_out('h1d);word_out(length[15:0]);word_out(length[31:16]);word_out(length[47:32]);word_out(length[63:48]);end_io();
 begin_io();word_out('h1c);word_out(mask | (ro?'h80:0));end_io();
end endtask
// Service standard HPS commands, leaving the request unchanged for a delay.
initial begin: host
 wait(!reset);
 forever begin
  wait((|rd || |wr) && !enable);
  wait(!hold_requests);host_busy=1;stable_req0=rd[0]||wr[0];stable_req1=rd[1]||wr[1];stable_lba0=lba[0];stable_lba1=lba[1];
  repeat(8)begin @(negedge clk);
   if(stable_req0 && (!(rd[0]||wr[0]) || lba[0]!==stable_lba0))$fatal(1,"S0 request not stable before ack");
   if(stable_req1 && (!(rd[1]||wr[1]) || lba[1]!==stable_lba1))$fatal(1,"S1 request not stable before ack");
  end
  begin_io();word_out('h16);#1;status_word=bus[15:0];part=status_word[5:2];
  if(!status_word[1:0] || part>1)$fatal(1,"bad request status %h",status_word);
  word_out(0);word_out(0);#1;current_lba=bus[15:0];word_out(0);#1;current_lba=current_lba | (bus[15:0]<<16);end_io();
  if((part==0 && current_lba>2) || (part==1 && current_lba>1))$fatal(1,"bad LBA");
  requests=requests+1;
  if(status_word[0])begin
   reads=reads+1;begin_io();word_out((part<<8)|'h17);
   if(inject_short && part==0)begin
    for(n=0;n<128;n=n+1)word_out(disk[part][current_lba*256+n]);inject_short=0;
   end else for(n=0;n<256;n=n+1)word_out(disk[part][current_lba*256+n]);
   repeat(4)@(negedge clk);end_io();
  end else begin
   if (part < 2) begin
    write_order[ordered_writes]=(part==0 ? 0 : 3)+current_lba;
    ordered_writes=ordered_writes+1;
   end
   writes=writes+1;if(part==0)snapshot_word0=save.bridge.sector.buffer.memory[0];begin_io();word_out((part<<8)|'h18);
   if(inject_swap && part==0)begin
    for(n=0;n<8;n=n+1)word_out(0);end_io();inject_swap=0;mount_image(1,0,1536);
   end else begin
    for(n=0;n<256;n=n+1)begin
     word_out(0);#1;disk[part][current_lba*256+n]=bus[15:0];
     if(inject_mutation && part==0 && current_lba==0 && n==100)begin
      @(negedge clk);ram[0]=32'haabbccdd;dirty_sector=0;dirty=1;@(negedge clk);dirty=0;inject_mutation=0;saw_old_snapshot=1;
     end
    end
    if(saw_old_snapshot && !first_snapshot_checked && part==0 && current_lba==0)begin
     if(disk[0][0]!==16'hbe00)$fatal(1,"first snapshot did not retain old data");first_snapshot_checked=1;
    end
    if(part==0)repeat(4)begin @(negedge clk);if(save.bridge.sector.buffer.memory[0]!==snapshot_word0)$fatal(1,"sector buffer changed before HPS ack release");end
    if(saved)$fatal(1,"Saved before final ACK fall");
    end_io();
   end
  end
  if(!status_word[0] && post_write_delay!=0)repeat(post_write_delay)@(negedge clk);
  host_busy=0;
 end
end

always @(posedge clk) if(!reset)begin
 if((rd[0]||wr[0]) && (rd[1]||wr[1]))$fatal(1,"raw transport not serialized");
 if(rd[2]||wr[2])$fatal(1,"reserved slot traffic");
end

task pause_host;begin hold_requests=1;wait(!host_busy && !enable);end endtask
task resume_host;begin hold_requests=0;end endtask
task cold;begin pause_host();@(negedge clk);reset=1;repeat(4)@(negedge clk);reset=0;repeat(12)@(negedge clk);end endtask
task wait_mounted;begin resume_host();wait(mounted||error);if(error)$fatal(1,"mount error state=%d cursor=%d",save.state,save.cursor);wait(!busy);checks=checks+1;end endtask
task verify_ram;begin
 for(integer k=0;k<384;k=k+1)if(ram[k]!=={disk[0][k*2+1],disk[0][k*2]})$fatal(1,"C raw restore %d",k);
 for(integer k=0;k<256;k=k+1)if(ram[k+384]!=={disk[1][k*2+1],disk[1][k*2]})$fatal(1,"PMM raw restore %d",k);
 checks=checks+1;
end endtask
task mark(input integer sector,input [31:0] value);begin
 @(negedge clk);ram[sector*128]=value;dirty_sector=sector;dirty=1;@(negedge clk);dirty=0;
end endtask
task do_flush;begin @(negedge clk);flush=1;@(negedge clk);flush=0;wait((saved&&!saving)||error);if(error)$fatal(1,"flush failed");checks=checks+1;end endtask
initial begin: test
 hold_requests=1;
 for(integer d=0;d<2;d=d+1)for(integer k=0;k<768;k=k+1)disk[d][k]=16'h1000*d+k;
 for(integer k=0;k<640;k=k+1)ram[k]=32'hdeadbeef;
 repeat(4)@(negedge clk);reset=0;repeat(12)@(negedge clk);
 mount_image(1,1,1536);if(!error||mounted)$fatal(1,"readonly accepted");
 mount_image(2,0,1025);if(!error||mounted)$fatal(1,"oversize PMM accepted");
 mount_image(1,0,1535);if(!error||mounted)$fatal(1,"short C accepted");checks=checks+3;
 // Both automatic mount events precede firmware verification. Shared size/RO
 // then changes for S2; the raw manager must retain per-event geometry.
 mount_image(1,0,1536);if(!error)$fatal(1,"valid C masked invalid PMM");checks=checks+1;
 mount_image(2,0,1024);if(error)$fatal(1,"corrected peer error retained");
 mount_image(4,1,999);
 repeat(20)@(negedge clk);if(mounted||busy||(|rd)||(|wr))$fatal(1,"release/request before firmware gate");
 verified=1;wait_mounted();verify_ram();
 // C/PMM first and last LBAs through the shared HPS buffer.
 for(integer k=0;k<5;k=k+1)mark(k,32'hbeefbe00+k);
 do_flush();
 for(integer k=0;k<5;k=k+1)begin
  if({disk[k<3?0:1][(k<3?k:k-3)*256+1],disk[k<3?0:1][(k<3?k:k-3)*256]}!==32'hbeefbe00+k)$fatal(1,"flush LBA%d",k);
 end
 // Mutation while HPS reads a captured snapshot forces a second sector pass.
 inject_mutation=1;mark(0,32'hbeefbe00);do_flush();
 if(!saw_old_snapshot||!first_snapshot_checked||{disk[0][1],disk[0][0]}!==32'haabbccdd)$fatal(1,"lost concurrent mutation");checks=checks+1;
 // Clean independent unmounts stop CPU release, and remount restores exactly.
 pause_host();mount_image(1,0,0);if(mounted||error)$fatal(1,"zero unmount");
 mount_image(1,0,1536);wait_mounted();verify_ram();
 // PMM first, C arrives during pending PMM load while requests are delayed.
 cold();verified=1;mount_image(2,0,1024);wait(rd[1]);if(mounted)$fatal(1,"single image released CPU");
 // Unsolicited reserved-slot buffer writes cannot enter the PMM buffer.
 begin_io();word_out('h217);for(integer k=0;k<256;k=k+1)word_out(16'hbad0+k);end_io();
 if(save.bridge.sector.read_count!=0)$fatal(1,"reserved slot contaminated PMM buffer");checks=checks+1;
 mount_image(1,0,1536);warm_request=1;repeat(3)@(negedge clk);warm_request=0;
 if(phone_reset)$fatal(1,"warm reset not deferred during restore");wait_mounted();verify_ram();
 // C first, PMM arrives during C load. No double ownership.
 cold();mount_image(1,0,1536);wait(rd[0]);mount_image(2,0,1024);wait_mounted();verify_ram();
 // Transport reset during load cancels it, both mounts required again.
 cold();mount_image(1,0,1536);wait(rd[0]);@(negedge clk);reset=1;repeat(3)@(negedge clk);reset=0;repeat(12)@(negedge clk);
 if(mounted||(|rd)||(|wr))$fatal(1,"cold reset retained partial restore");
 mount_image(1,0,1536);mount_image(2,0,1024);wait_mounted();verify_ram();
 // Dirty media replacement aborts without writing old data to new media.
 mark(0,32'hfeedbeef);pause_host();mount_image(2,0,1024);if(!error||mounted||saved||ram[0]!==32'hfeedbeef)$fatal(1,"dirty media protection");checks=checks+1;
 // Replace media during a live HPS write: stop before any later sector,
 // retaining dirty RAM even though the interrupted sector is uncertain.
 cold();mount_image(1,0,1536);mount_image(2,0,1024);wait_mounted();
 mark(0,32'hfeedbeef);mark(1,32'hfeed1234);inject_swap=1;
 @(negedge clk);flush=1;@(negedge clk);flush=0;wait(error);wait(!host_busy);
 if(mounted||saved||ram[0]!==32'hfeedbeef||ram[128]!==32'hfeed1234)$fatal(1,"live replacement lost DDR");checks=checks+1;
 // Warm reset during a held save waits for the complete flush/ACK drop.
 cold();mount_image(1,0,1536);mount_image(2,0,1024);wait_mounted();mark(0,32'habcddcba);pause_host();
 @(negedge clk);flush=1;@(negedge clk);flush=0;wait(wr[0]);
 warm_request=1;repeat(3)@(negedge clk);warm_request=0;if(phone_reset)$fatal(1,"save reset not deferred");
 resume_host();wait(saved&&!saving);wait(phone_reset);checks=checks+1;
 // Cold transport reset cancels a not-yet-acknowledged save; pending dirty
 // data has no durability promise across this explicit cold reset.
 pause_host();mark(0,32'h55aa55aa);@(negedge clk);flush=1;@(negedge clk);flush=0;wait(wr[0]);
 reset=1;repeat(3)@(negedge clk);reset=0;repeat(12)@(negedge clk);
 if(mounted||saving||(|rd)||(|wr)||saved)$fatal(1,"cold save cancellation");checks=checks+1;
 // Short actual-HPS read fails closed.
 cold();inject_short=1;mount_image(1,0,1536);resume_host();wait(error);if(mounted||saved)$fatal(1,"short read accepted");checks=checks+1;
 if (ORDERED != 0) begin
  integer first_write, age_start, latest;
  cold();mount_image(1,0,1536);mount_image(2,0,1024);wait_mounted();
  autosave=1;
  pause_host();first_write=ordered_writes;
  mark(3,32'h2233aabb);mark(2,32'h4466ccdd);mark(0,32'h11227788);
  repeat(20)begin @(negedge clk);if(saving||(|wr))$fatal(1,"quiet timer started early");end
  wait(wr[1]);
  @(negedge clk);warm_request=1;@(negedge clk);warm_request=0;
  if(phone_reset)$fatal(1,"warm reset interrupted an automatic save");
  resume_host();
  wait(phone_reset);
  if(ordered_writes!=first_write+2 || saved || !save.tracker_pending)
      $fatal(1,"warm reset did not run between finite batches");
  wait(saved&&!saving);
  if(ordered_writes!=first_write+3 || write_order[first_write]!=3 ||
     write_order[first_write+1]!=2 || write_order[first_write+2]!=0)
      $fatal(1,"first-dirty order crossed C/PMM incorrectly");
  if({disk[1][1],disk[1][0]}!==32'h2233aabb ||
     {disk[0][513],disk[0][512]}!==32'h4466ccdd ||
     {disk[0][1],disk[0][0]}!==32'h11227788)
      $fatal(1,"automatic save bytes");
  checks=checks+1;
  // Continuous committed changes keep the quiet timer at zero. The max age
  // starts a batch, then the manual action drains the work left behind it.
  pause_host();
  first_write=ordered_writes;
  mark(3,32'h1111aa55);mark(2,32'h2222bb66);
  age_start=0;latest=0;
  while(!saving && age_start<160)begin
   latest=latest+1;
   mark(0,32'h3333cc00+latest);
   repeat(8)@(negedge clk);
   age_start=age_start+9;
  end
  if(!saving || age_start<100 || age_start>=140)
      $fatal(1,"continuous writes max age %0d",age_start);
  autosave=0;
  @(negedge clk);flush=1;@(negedge clk);flush=0;
  resume_host();
  wait(saved&&!saving);
  if(ordered_writes!=first_write+3 || {disk[0][1],disk[0][0]}!==32'h3333cc00+latest)
      $fatal(1,"manual save during background batch did not drain");
  checks=checks+1;
  $display("PASS S3 actual HPS ordered autosave, quiet/max age, finite warm reset and manual drain");
 end
 // A manual request can remain pending before any HPS request when the
 // NOR command/program/erase boundary is not quiescent. Report SAVING while
 // pending, then drain when safe; do not misclassify this as an ACK timeout.
 autosave=0;
 cold();mount_image(1,0,1536);mount_image(2,0,1024);wait_mounted();
 mark(0,32'h600df00d);flash_quiescent=0;
 @(negedge clk);flush=1;@(negedge clk);flush=0;
 repeat(200)@(negedge clk);
 if(!saving||busy||(|rd)||(|wr)||mv||error||!save.flush_pending)
  $fatal(1,"manual quiescence wait started unsafe transfer or lost request");
 flash_quiescent=1;wait(saved&&!saving);
 if({disk[0][1],disk[0][0]}!==32'h600df00d)$fatal(1,"manual quiescence wait lost data");
 checks=checks+1;
 // A stalled host times out, retaining all RAM contents and reporting error.
 cold();mount_image(1,0,1536);mount_image(2,0,1024);wait_mounted();mark(ORDERED != 0 ? 3 : 0,32'h10203040);pause_host();
 @(negedge clk);flush=1;@(negedge clk);flush=0;wait(error);repeat(4)@(negedge clk);if(saved||!mounted||phone_reset||saving||busy||ram[ORDERED != 0 ? 384 : 0]!==32'h10203040 ||
     slot_error!==(ORDERED != 0 ? 2'b10 : 2'b01))
     $fatal(1,"timeout discarded dirty RAM or mislabeled the device");checks=checks+1;
 // Main drops the FPGA ACK before its O_SYNC file write. While Main is
 // blocked on that write, the next sector can exceed our request deadline.
 for(integer mode=0;mode<(ORDERED ? 2 : 1);mode=mode+1)begin
  integer before_writes;
  autosave=0;post_write_delay=0;
  cold();mount_image(1,0,1536);mount_image(2,0,1024);wait_mounted();
  before_writes=writes;
  post_write_delay=100500;
  mark(0,32'hc001cafe);mark(3,32'hd002beef);
  if(mode==1)autosave=1;
  else begin @(negedge clk);flush=1;@(negedge clk);flush=0;end
  wait(error);repeat(4)@(negedge clk);
  if(!mounted||phone_reset||saving||busy||saved||slot_error!=2'b10 ||
     ram[384]!==32'hd002beef||{disk[0][1],disk[0][0]}!==32'hc001cafe)
   $fatal(1,"slow host reset phone/lost resident data or reported false save mode%0d",mode);
  wait(!host_busy);post_write_delay=0;before_writes=writes;
  // No uncertain automatic retry; another manual click must not latch SAVING.
  @(negedge clk);flush=1;@(negedge clk);flush=0;
  repeat(20)@(negedge clk);
  if(saving||busy||(|wr)||(|rd)||writes!=before_writes||!mounted)
   $fatal(1,"failed persistence retried/stuck saving=%b busy=%b wr=%h rd=%h writes=%0d before=%0d mounted=%b state=%0d",saving,busy,wr,rd,writes,before_writes,mounted,save.state);
  checks=checks+1;
  // Resident DDR may keep running, but replacing uncertain media is unsafe.
  mount_image(1,0,1536);
  if(mounted||!error||(|rd)||(|wr))$fatal(1,"failed-save replacement released CPU gate");
 end
 $display("PASS delayed Main file write: manual/auto errors preserve CPU release and DDR, no retry or stuck SAVING");
 $display("PASS actual three-slot hps_io raw C/PMM, S2 reserve, mount order/reset/error/mutation (%0d checks, %0d reads, %0d writes)",checks,reads,writes);$finish;
end
initial begin #20000000;$fatal(1,"timeout state=%d restored=%b pending=%b cursor=%d",save.state,save.restored,save.pending,save.cursor);end
endmodule
