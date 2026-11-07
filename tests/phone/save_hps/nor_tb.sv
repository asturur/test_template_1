`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg inject_short=0,inject_swap=0,hold_requests=0,inject_mutation=0,saw_old_snapshot=0,first_snapshot_checked=0;
reg reset=1,start=0,flush=0,dirty=0;reg [13:0] dirty_sector=0;
tri [45:0] bus;tri [35:0] ext;tri [21:0] gamma;
reg [15:0] host_data=0;reg strobe=0,enable=0;
assign bus[31:16]=host_data;assign bus[33]=strobe;assign bus[34]=enable;assign bus[35]=0;assign bus[45:38]=0;assign ext[32]=0;
wire [1:0] mounts,rd,wr,ack;wire readonly_image;wire [63:0] size;wire [31:0] lba[2];wire [5:0] count[2];wire [12:0] ha;wire [15:0] hd,hi[2];wire hwe;
wire mounted,saving,saved,error,busy,mv,mw,mdone;wire [31:0] ma,mdata,mr;wire [3:0] mbe;
reg [31:0] ram[0:511];reg [7:0] firmware[0:20905983],firmware_before[0:20905983];integer image_fd,image_got;reg [15:0] disk[0:1279],diag_disk[0:511],header[0:255],original_disk[0:1279];reg [255:0] core,extension;
reg fv=0,fw=0,pv=0,pw=0;reg [21:0] fo=0;reg [31:0] fd=0,pa=0,pd=0;reg [3:0] fb=0,pb=0;
wire fr,frsp,ferr,fmv,fmw,fdirty,fready,fdone,fpending;wire [31:0] fq,fma,fmd,fmr;wire [3:0] fmb;wire [12:0] fsector;
wire pr,prsp,perr,pmv,pmw,pdirty,pready,pdone,ppending;wire [31:0] pq,pma,pmd,pmr;wire [3:0] pmb;wire [13:0] psector;
wire mem_ready;integer idx,part,n,requests=0,reads=0,writes=0;reg [15:0] status_word,snapshot_word0;reg [31:0] current_lba;reg [31:0] stable_lba0,stable_lba1;reg stable_req0,stable_req1;
wire [10:0] debug_word;wire [15:0] debug_data=16'h5000|debug_word;wire debug_mounted,debug_busy,debug_error,debug_done,freeze;
assign count[0]=0;assign count[1]=0;
hps_io #(.CONF_STR("test"),.WIDE(1),.VDNUM(2),.PS2DIV(1)) hps(.clk_sys(clk),.HPS_BUS(bus),.EXT_BUS(ext),.gamma_bus(gamma),
 .img_mounted(mounts),.img_readonly(readonly_image),.img_size(size),.sd_lba(lba),.sd_blk_cnt(count),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),
 .sd_buff_addr(ha),.sd_buff_dout(hd),.sd_buff_din(hi),.sd_buff_wr(hwe),.ioctl_wait(1'b0),.ioctl_upload_req(1'b0),.ioctl_upload_index(8'b0),.ioctl_din(16'b0),
 .status_in(128'b0),.status_set(1'b0),.status_menumask(16'b0),.info_req(1'b0),.info(8'b0),.video_rotated(1'b0),.new_vmode(1'b0),
 .joystick_0_rumble(16'b0),.joystick_1_rumble(16'b0),.joystick_2_rumble(16'b0),.joystick_3_rumble(16'b0),.joystick_4_rumble(16'b0),.joystick_5_rumble(16'b0));
ngage_save_manager #(.C_SECTORS(2),.PMM_SECTORS(2),.SD_TIMEOUT(100000)) save(.clk(clk),.reset(reset),.mount(mounts[0]),.readonly_image(readonly_image),.image_size(size),.bundle_verified(1'b1),.profile(2'd1),.core_sha_le(core),.extension_sha_le(extension),
 .dirty_valid(dirty || fdirty || pdirty),.dirty_sector(dirty ? dirty_sector : pdirty ? psector-14'd8190 : {1'b0,fsector}),.flush_start(flush),.mounted(mounted),.saving(saving),.saved(saved),.error(error),.busy(busy),
 .mem_valid(mv),.mem_ready(mem_ready),.mem_write(mw),.mem_addr(ma),.mem_data(mdata),.mem_be(mbe),.mem_done(mdone),.mem_rdata(mr),
 .sd_lba(lba[0]),.sd_rd(rd[0]),.sd_wr(wr[0]),.sd_ack(ack[0]),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hi[0]),.flash_quiescent(!fpending && !ppending));
ngage_diag_export #(.TIMEOUT(100000)) diag(.clk(clk),.reset(reset),.mount(mounts[1]),.readonly_image(readonly_image),.image_size(size),.start(start),.mounted(debug_mounted),.busy(debug_busy),.error(debug_error),.done(debug_done),.freeze_trace(freeze),.debug_word(debug_word),.debug_data(debug_data),.sd_lba(lba[1]),.sd_rd(rd[1]),.sd_wr(wr[1]),.sd_ack(ack[1]),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hi[1]));
wire av,ar,aw,adone,xv,xr,xw,xdone,bv,br,bw,bdone;wire [31:0] aa,ad,ard,xa,xd,xrd,ba,bd,brd;wire [3:0] ab,xb,bb;
wire [28:0] phyaddr;wire [63:0] phydata;wire [7:0] phybe;wire phyrd,phywr;reg [63:0] phyrdata=0;reg phyready=0;integer delay=0,base_index,j,cycle=0;
wire phybusy=(cycle%7)<3;
ngage_ddr_arbiter aux(clk,reset,1'b0,1'b0,,32'b0,32'b0,4'b0,,mv,mem_ready,mw,ma,mdata,mbe,mdone,mr,av,ar,aw,aa,ad,ab,adone,ard,1'b1,);
ngage_ddr_arbiter flash_arb(clk,reset,1'b0,fmv,fready,fma,fmd,fmb,fdone,pmv,pready,pmw,pma,pmd,pmb,pdone,pmr,xv,xr,xw,xa,xd,xb,xdone,xrd,fmw,fmr);
ngage_ddr_arbiter outer(clk,reset,1'b0,av,ar,aa,ad,ab,adone,xv,xr,xw,xa,xd,xb,xdone,xrd,bv,br,bw,ba,bd,bb,bdone,brd,aw,ard);
ngage_cflash flash(clk,reset,1'b0,fv,fr,fw,fo,fd,fb,frsp,ferr,fq,fmv,fready,fmw,fma,fmd,fmb,fdone,fmr,fdirty,fsector,fpending,);
ngage_codeflash pflash(clk,reset,1'b0,pv,pr,pw,pa,pd,pb,prsp,perr,pq,pmv,pready,pmw,pma,pmd,pmb,pdone,pmr,pdirty,psector,ppending,);
ngage_ddr_adapter adapter(clk,reset,bv,br,bw,ba,bd,bb,bdone,brd,phyaddr,phydata,phybe,phyrd,phywr,phybusy,phyrdata,phyready);
always @(posedge clk)begin
 cycle<=cycle+1;phyready<=0;
 if(delay>0)begin delay<=delay-1;if(delay==1)phyready<=1;end
 if((phyrd||phywr) && !phybusy)begin
  if(phyaddr>=(32'h30000000>>3) && phyaddr<(32'h313f0000>>3))begin
   base_index=(phyaddr-(32'h30000000>>3))*8;
   if(phywr)begin for(j=0;j<8;j=j+1)if(phybe[j])firmware[base_index+j]<=phydata[j*8+:8];end
   else begin for(j=0;j<8;j=j+1)phyrdata[j*8+:8]<=firmware[base_index+j];delay<=3;end
  end else begin
   if(phyaddr>=(32'h31400000>>3) && phyaddr<(32'h31400400>>3))base_index=(phyaddr-(32'h31400000>>3))*2;
   else if(phyaddr>=(32'h31800000>>3) && phyaddr<(32'h31800400>>3))base_index=256+(phyaddr-(32'h31800000>>3))*2;
   else $fatal(1,"unexpected DDR address %h",phyaddr);
   if(phywr)begin for(j=0;j<8;j=j+1)if(phybe[j])ram[base_index+(j/4)][(j%4)*8+:8]<=phydata[j*8+:8];end
   else begin phyrdata<={ram[base_index+1],ram[base_index]};delay<=3;end
  end
 end
end
function automatic [31:0] expected(input integer k);begin case(k)
 0:expected=32'hffff1234;1:expected=32'hffff5678;2:expected=32'hffff1236;default:expected=32'hffff1237;endcase end endfunction
task flash_cmd(input [21:0] off,input [15:0] val);integer t;begin
 while(!fr)@(negedge clk);@(negedge clk);fv=1;fw=1;fo=off;fb=off[1]?12:3;fd=off[1]?{val,16'b0}:{16'b0,val};@(negedge clk);fv=0;
 t=0;while(!frsp && t<5000)begin @(negedge clk);t=t+1;end if(!frsp||ferr)$fatal(1,"NOR command off=%h val=%h rsp=%b err=%b unlock=%d t=%0d",off,val,frsp,ferr,flash.unlock,t);
end endtask
task flash_program(input [21:0] off,input [15:0] val);begin flash_cmd('haaa,'haa);flash_cmd('h554,'h55);flash_cmd('haaa,'ha0);flash_cmd(off,val);end endtask
task pmm_cmd(input [31:0] address,input [15:0] val);integer t;begin
 while(!pr)@(negedge clk);@(negedge clk);pv=1;pw=1;pa=address;pb=address[1]?12:3;pd=address[1]?{val,16'b0}:{16'b0,val};@(negedge clk);pv=0;
 t=0;while(!prsp && t<5000)begin @(negedge clk);t=t+1;end if(!prsp||perr)$fatal(1,"PMM command %h",address);
end endtask
task firmware_read;integer t;begin
 while(!pr)@(negedge clk);@(negedge clk);pv=1;pw=0;pa=0;pb=15;pd=0;@(negedge clk);pv=0;
 t=0;while(!prsp && t<5000)begin @(negedge clk);t=t+1;end
 if(!prsp || perr || pq!=={firmware_before[3],firmware_before[2],firmware_before[1],firmware_before[0]})$fatal(1,"firmware DDR read changed %h",pq);
end endtask
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
   writes=writes+1;if(part==0)snapshot_word0=save.bridge.sector.bufmem[0];begin_io();word_out((part<<8)|'h18);
   if(inject_swap && part==0)begin
    for(n=0;n<8;n=n+1)word_out(0);end_io();inject_swap=0;mount_image(1,0,2560);
   end else begin
    for(n=0;n<256;n=n+1)begin
     word_out(0);#1;if(part==0)disk[current_lba*256+n]=bus[15:0];else diag_disk[current_lba*256+n]=bus[15:0];
     if(inject_mutation && part==0 && current_lba==1 && n==100)begin
      flash_program(0,16'hccdd);inject_mutation=0;saw_old_snapshot=1;
     end
    end
    if(saw_old_snapshot && !first_snapshot_checked && part==0 && current_lba==1)begin
     if(disk[256]!==16'h1234)$fatal(1,"first snapshot did not retain old data");first_snapshot_checked=1;
    end
    if(part==0)repeat(4)begin @(negedge clk);if(save.bridge.sector.bufmem[0]!==snapshot_word0)$fatal(1,"sector buffer changed before HPS ack release");end
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
 image_fd=$fopen("build/firmware/nem4-factory/core.bin","rb");if(!image_fd)$fatal(1,"missing stock core");
 image_got=$fread(firmware,image_fd,0,18612224);$fclose(image_fd);if(image_got!=18612224)$fatal(1,"stock core length");
 image_fd=$fopen("build/firmware/nem4-factory/extension.bin","rb");if(!image_fd)$fatal(1,"missing stock extension");
 image_got=$fread(firmware,image_fd,18612224,2293760);$fclose(image_fd);if(image_got!=2293760)$fatal(1,"stock extension length");
 for(integer k=0;k<20905984;k=k+1)firmware_before[k]=firmware[k];
 for(integer k=0;k<4;k=k+1)begin disk[256+k*256]=16'hffff;disk[257+k*256]=16'hffff;end
 disk[511]=16'hffff;
 for(integer k=0;k<1280;k=k+1)original_disk[k]=disk[k];
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
 firmware_read();
 // Change first/last C and PMM sectors and request S1 concurrently.
 flash_program(0,16'h1234);
 flash_program(22'h1fe,16'h55aa);flash_program(22'h200,16'h5678);
 pmm_cmd(32'h007f0000,16'h40);pmm_cmd(32'h007f0000,16'h1236);pmm_cmd(0,16'hf0);
 pmm_cmd(32'h007f0200,16'h40);pmm_cmd(32'h007f0200,16'h1237);pmm_cmd(0,16'hf0);
 mount_image(2,0,1024);if(!debug_mounted)$fatal(1,"S1 mount failed");
 @(negedge clk);start=1;flush=1;@(negedge clk);start=0;flush=0;
 wait((saved && !saving && !debug_busy) || error || debug_error);
 if(error || debug_error || !saved)$fatal(1,"concurrent flush/export failed");
 for(integer k=0;k<4;k=k+1)if({disk[257+k*256],disk[256+k*256]}!==expected(k))$fatal(1,"saved sector %d",k);
 if(disk[511]!==16'h55aa || disk[512]!==16'h5678)$fatal(1,"cross-sector NOR persistence");
 for(integer k=0;k<1280;k=k+1)
  if(k!=256 && k!=511 && k!=512 && k!=768 && k!=1024 && disk[k]!==original_disk[k])$fatal(1,"unchanged disk word %0d",k);
 for(integer k=0;k<512;k=k+1)if(diag_disk[k]!==(16'h5000|k))$fatal(1,"diagnostic isolation %d",k);
 // A guest write during the HPS sector transfer must force a second pass.
 @(negedge clk);dirty_sector=0;dirty=1;@(negedge clk);dirty=0;inject_mutation=1;flush=1;@(negedge clk);flush=0;
 wait((saved && !saving) || error);if(error || !saw_old_snapshot || !first_snapshot_checked || {disk[257],disk[256]}!==32'hffffccdd)$fatal(1,"concurrent mutation was not saved");
 for(integer k=0;k<512;k=k+1)ram[k]=0;
 mount_image(1,0,2560);wait(mounted || error);if(error)$fatal(1,"remount failed");
 for(integer k=0;k<4;k=k+1)if(ram[k*128]!==(k==0?32'hffffccdd:expected(k)))$fatal(1,"remount sector %d",k);
 if(ram[127][31:16]!==16'h55aa)$fatal(1,"boundary halfword not restored");
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
 firmware_read();for(integer k=0;k<20905984;k=k+1)if(firmware[k]!==firmware_before[k])$fatal(1,"immutable firmware byte %0d changed",k);
 $display("PASS actual NOR, DDR and hps_io C/PMM restore, flush, remount and concurrent S1 (%0d reads, %0d writes)",reads,writes);$finish;
end
initial begin #5000000;$fatal(1,"test timeout mounted=%b error=%b state=%d",mounted,error,save.state);end
endmodule
