`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg inject_short=0,inject_swap=0,hold_requests=0,inject_mutation=0,saw_old_snapshot=0,first_snapshot_checked=0;
reg reset=1,start=0,flush=0,dirty=0;reg [13:0] dirty_sector=0;
tri [45:0] bus;tri [35:0] ext;tri [21:0] gamma;
reg [15:0] host_data=0;reg strobe=0,enable=0;
assign bus[31:16]=host_data;assign bus[33]=strobe;assign bus[34]=enable;assign bus[35]=0;assign bus[45:38]=0;assign ext[32]=0;
wire [1:0] mounts,rd,wr,ack;wire readonly_image;wire [63:0] size;wire [31:0] lba[2];wire [5:0] count[2];wire [12:0] ha;wire [15:0] hd,hi[2];wire hwe;
wire mounted,saving,saved,error,busy,mv,mw,mdone;wire [31:0] ma,mdata,mr;wire [3:0] mbe;
reg [31:0] ram[0:511];reg [15:0] disk[0:1279],diag_disk[0:511],header[0:255];reg [255:0] core,extension;
reg [31:0] memory_read=0;reg memory_done=0;integer idx,part,n,requests=0,reads=0,writes=0;reg [15:0] status_word,snapshot_word0;reg [31:0] current_lba;reg [31:0] stable_lba0,stable_lba1;reg stable_req0,stable_req1;
wire [10:0] debug_word;wire [15:0] debug_data=16'h5000|debug_word;wire debug_mounted,debug_busy,debug_error,debug_done,freeze;
assign count[0]=0;assign count[1]=0;assign mr=memory_read;assign mdone=memory_done;
hps_io #(.CONF_STR("test"),.WIDE(1),.VDNUM(2),.PS2DIV(1)) hps(.clk_sys(clk),.HPS_BUS(bus),.EXT_BUS(ext),.gamma_bus(gamma),
 .img_mounted(mounts),.img_readonly(readonly_image),.img_size(size),.sd_lba(lba),.sd_blk_cnt(count),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),
 .sd_buff_addr(ha),.sd_buff_dout(hd),.sd_buff_din(hi),.sd_buff_wr(hwe),.ioctl_wait(1'b0),.ioctl_upload_req(1'b0),.ioctl_upload_index(8'b0),.ioctl_din(16'b0),
 .status_in(128'b0),.status_set(1'b0),.status_menumask(16'b0),.info_req(1'b0),.info(8'b0),.video_rotated(1'b0),.new_vmode(1'b0),
 .joystick_0_rumble(16'b0),.joystick_1_rumble(16'b0),.joystick_2_rumble(16'b0),.joystick_3_rumble(16'b0),.joystick_4_rumble(16'b0),.joystick_5_rumble(16'b0));
ngage_save_manager #(.C_SECTORS(2),.PMM_SECTORS(2),.SD_TIMEOUT(100000)) save(.clk(clk),.reset(reset),.mount(mounts[0]),.readonly_image(readonly_image),.image_size(size),.bundle_verified(1'b1),.profile(2'd1),.core_sha_le(core),.extension_sha_le(extension),
 .dirty_valid(dirty),.dirty_sector(dirty_sector),.flush_start(flush),.mounted(mounted),.saving(saving),.saved(saved),.error(error),.busy(busy),
 .mem_valid(mv),.mem_ready(1'b1),.mem_write(mw),.mem_addr(ma),.mem_data(mdata),.mem_be(mbe),.mem_done(mdone),.mem_rdata(mr),
 .sd_lba(lba[0]),.sd_rd(rd[0]),.sd_wr(wr[0]),.sd_ack(ack[0]),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hi[0]),.flash_quiescent(1'b1));
ngage_diag_export #(.TIMEOUT(100000)) diag(.clk(clk),.reset(reset),.mount(mounts[1]),.readonly_image(readonly_image),.image_size(size),.start(start),.mounted(debug_mounted),.busy(debug_busy),.error(debug_error),.done(debug_done),.freeze_trace(freeze),.debug_word(debug_word),.debug_data(debug_data),.sd_lba(lba[1]),.sd_rd(rd[1]),.sd_wr(wr[1]),.sd_ack(ack[1]),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hi[1]));
always @(posedge clk)begin
 if(save.h_done && save.h_error)$display("HEADER_READ_ERROR count=%0d order_error=%b addr=%0d ack=%b hwe=%b",save.header_sector.read_count,save.header_sector.read_error,ha,ack[0],hwe);
 memory_done<=0;
 if(mv && !memory_done)begin
  if(ma>=32'h31400000 && ma<32'h31400400)idx=(ma-32'h31400000)>>2;
  else if(ma>=32'h31800000 && ma<32'h31800400)idx=256+((ma-32'h31800000)>>2);
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
  wait(!hold_requests);stable_req0=rd[0]||wr[0];stable_req1=rd[1]||wr[1];stable_lba0=lba[0];stable_lba1=lba[1];
  repeat(8)begin @(negedge clk);
   if(stable_req0 && (!(rd[0]||wr[0]) || lba[0]!==stable_lba0))$fatal(1,"S0 request not stable before ack");
   if(stable_req1 && (!(rd[1]||wr[1]) || lba[1]!==stable_lba1))$fatal(1,"S1 request not stable before ack");
  end
  begin_io();word_out('h16);#1;status_word=bus[15:0];part=status_word[5:2];
  if(!status_word[1:0] || part>1)$fatal(1,"bad request status %h",status_word);
  word_out(0);word_out(0);#1;current_lba=bus[15:0];word_out(0);#1;current_lba=current_lba | (bus[15:0]<<16);end_io();
  if((part==0 && current_lba>4) || (part==1 && current_lba>1))$fatal(1,"bad LBA");
  requests=requests+1;
  if(status_word[0])begin
   reads=reads+1;begin_io();word_out((part<<8)|'h17);
   if(inject_short && part==0)begin
    for(n=0;n<128;n=n+1)word_out(disk[current_lba*256+n]);inject_short=0;
   end else for(n=0;n<256;n=n+1)word_out(part==0?disk[current_lba*256+n]:diag_disk[current_lba*256+n]);
   repeat(4)@(negedge clk);end_io();
  end else begin
   writes=writes+1;if(part==0)snapshot_word0=save.bridge.sector.buffer.memory[0];begin_io();word_out((part<<8)|'h18);
   if(inject_swap && part==0)begin
    for(n=0;n<8;n=n+1)word_out(0);end_io();inject_swap=0;mount_image(1,0,2560);
   end else begin
    for(n=0;n<256;n=n+1)begin
     word_out(0);#1;if(part==0)disk[current_lba*256+n]=bus[15:0];else diag_disk[current_lba*256+n]=bus[15:0];
     if(inject_mutation && part==0 && current_lba==1 && n==100)begin
      @(negedge clk);ram[0]=32'haabbccdd;dirty_sector=0;dirty=1;@(negedge clk);dirty=0;inject_mutation=0;saw_old_snapshot=1;
     end
    end
    if(saw_old_snapshot && !first_snapshot_checked && part==0 && current_lba==1)begin
     if(disk[256]!==16'h0000)$fatal(1,"first snapshot did not retain old data");first_snapshot_checked=1;
    end
    if(part==0)repeat(4)begin @(negedge clk);if(save.bridge.sector.buffer.memory[0]!==snapshot_word0)$fatal(1,"sector buffer changed before HPS ack release");end
    end_io();
   end
  end
 end
end
initial begin: test
 for(integer k=0;k<32;k=k+1)begin core[k*8+:8]=k;extension[k*8+:8]=k+32;end
 $readmemh("build/sim/unit-save-hps/header.hex",header);
 for(integer k=0;k<1280;k=k+1)disk[k]=k<256?header[k]:(16'h1000+k);
 for(integer k=0;k<512;k=k+1)begin ram[k]=32'hdeadbeef;diag_disk[k]=0;end
 repeat(4)@(negedge clk);reset=0;repeat(12)@(negedge clk);
 mount_image(1,1,2560);if(!error || mounted)$fatal(1,"readonly accepted");
 inject_short=1;mount_image(1,0,2560);wait(error);if(mounted || save.header_sector.read_count!=128)$fatal(1,"incomplete actual-HPS read accepted");
 @(negedge clk);reset=1;repeat(3)@(negedge clk);reset=0;repeat(12)@(negedge clk);
 disk[0]=disk[0]^1;mount_image(1,0,2560);wait(error);if(mounted)$fatal(1,"corrupted header accepted");disk[0]=disk[0]^1;
 mount_image(1,0,2560);wait(mounted || error);if(error)$fatal(1,"actual HPS mount failed state=%d size=%d ro=%b init=%b mounts=%b req=%d",save.state,size,readonly_image,save.tracker_init,mounts,requests);
 for(integer k=0;k<256;k=k+1)begin
  if(ram[k]!=={disk[257+k*2],disk[256+k*2]})$fatal(1,"C restore mismatch %d",k);
  if(ram[256+k]!=={disk[769+k*2],disk[768+k*2]})$fatal(1,"PMM restore mismatch %d",k);
 end
 // Change first/last C and PMM sectors and request S1 concurrently.
 for(integer k=0;k<4;k=k+1)begin
  @(negedge clk);ram[k*128]=32'hbeef0000+k;dirty_sector=k;dirty=1;@(negedge clk);dirty=0;
 end
 mount_image(2,0,1024);if(!debug_mounted)$fatal(1,"S1 mount failed");
 @(negedge clk);start=1;flush=1;@(negedge clk);start=0;flush=0;
 wait((saved && !saving && !debug_busy) || error || debug_error);
 if(error || debug_error || !saved)$fatal(1,"concurrent flush/export failed");
 for(integer k=0;k<4;k=k+1)if({disk[257+k*256],disk[256+k*256]}!==(32'hbeef0000+k))$fatal(1,"saved sector %d",k);
 for(integer k=0;k<512;k=k+1)if(diag_disk[k]!==(16'h5000|k))$fatal(1,"diagnostic isolation %d",k);
 // A guest write during the HPS sector transfer must force a second pass.
 @(negedge clk);dirty_sector=0;dirty=1;@(negedge clk);dirty=0;inject_mutation=1;flush=1;@(negedge clk);flush=0;
 wait((saved && !saving) || error);if(error || !saw_old_snapshot || !first_snapshot_checked || {disk[257],disk[256]}!==32'haabbccdd)$fatal(1,"concurrent mutation was not saved");
 for(integer k=0;k<512;k=k+1)ram[k]=0;
 mount_image(1,0,2560);wait(mounted || error);if(error)$fatal(1,"remount failed");
 for(integer k=0;k<4;k=k+1)if(ram[k*128]!==(k==0?32'haabbccdd:(32'hbeef0000+k)))$fatal(1,"remount sector %d",k);
 mount_image(1,0,0);if(mounted || error)$fatal(1,"clean unmount failed");
 mount_image(1,0,2560);wait(mounted || error);if(error)$fatal(1,"swap setup failed");
 @(negedge clk);ram[0]='hfeedbeef;dirty_sector=0;dirty=1;@(negedge clk);ram[128]='hfeed1234;dirty_sector=1;@(negedge clk);dirty=0;
 inject_swap=1;@(negedge clk);flush=1;@(negedge clk);flush=0;wait(error);
 if(saved || mounted || ram[0]!==32'hfeedbeef || ram[128]!==32'hfeed1234)$fatal(1,"media replacement lost unsaved DDR");
 // A stuck HPS transaction must not report Saved or discard DDR contents.
 @(negedge clk);reset=1;repeat(3)@(negedge clk);reset=0;repeat(12)@(negedge clk);
 mount_image(1,0,2560);wait(mounted || error);if(error)$fatal(1,"timeout setup failed");
 @(negedge clk);ram[0]='hcafef00d;dirty_sector=0;dirty=1;@(negedge clk);dirty=0;hold_requests=1;flush=1;@(negedge clk);flush=0;
 wait(error);if(saved || mounted || ram[0]!==32'hcafef00d)$fatal(1,"HPS timeout lost unsaved DDR");
 $display("PASS actual hps_io C/PMM restore, flush, remount and concurrent S1 (%0d reads, %0d writes)",reads,writes);$finish;
end
initial begin #5000000;$fatal(1,"test timeout mounted=%b error=%b state=%d",mounted,error,save.state);end
endmodule
