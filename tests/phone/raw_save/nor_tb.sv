`timescale 1ns/1ps
module tb;
parameter STREAM_TRANSPORT=0, FLASH_CACHE_BYTES=0, BULK=0;
reg clk=0;always #5 clk=~clk;reg inject_short=0,inject_swap=0,hold_requests=0,inject_mutation=0,saw_old_snapshot=0,first_snapshot_checked=0;
reg reset=1,flush=0,dirty=0;reg [13:0] dirty_sector=0;
tri [45:0] bus;tri [35:0] ext;tri [21:0] gamma;
reg [15:0] host_data=0;reg strobe=0,enable=0;
assign bus[31:16]=host_data;assign bus[33]=strobe;assign bus[34]=enable;assign bus[35]=0;assign bus[45:38]=0;assign ext[32]=0;
wire [2:0] mounts,rd,wr,ack;wire readonly_image;wire [63:0] size;wire [31:0] lba[3];wire [5:0] count[3];wire [12:0] ha;wire [15:0] hd,hi[3];wire hwe;
wire mounted,saving,saved,error,busy,mv,mw,mdone;wire [31:0] ma,mdata,mr;wire [3:0] mbe;
reg [31:0] ram[0:511], erase_tail[256:16383];reg [7:0] firmware[0:20905983],firmware_before[0:20905983];integer image_fd,image_got;reg [15:0] disk[0:1279],header[0:255],original_disk[0:1279];reg [255:0] core,extension;
reg fv=0,fw=0,pv=0,pw=0;reg [21:0] fo=0;reg [31:0] fd=0,pa=0,pd=0;reg [3:0] fb=0,pb=0;
wire fr,frsp,ferr,fmv,fmw,fdirty,fready,fdone,fpending;wire [31:0] fq,fma,fmd,fmr;wire [3:0] fmb;wire [12:0] fsector;
wire pr,prsp,perr,pmv,pmw,pdirty,pready,pdone,ppending;wire [31:0] pq,pma,pmd,pmr;wire [3:0] pmb;wire [13:0] psector;
wire aux_bulk, req_bulk, bulk_cancel, bulk_error;
wire bulk_read_valid, bulk_read_ready, bulk_read_last;
wire bulk_write_valid, bulk_write_ready, bulk_write_last;
wire [63:0] bulk_read_data, bulk_write_data;
wire mem_ready;integer idx,part,n,requests=0,reads=0,writes=0;reg [15:0] status_word,snapshot_word0;reg [31:0] current_lba;reg [31:0] stable_lba0,stable_lba1;reg stable_req0,stable_req1;
assign count[0]=0;assign count[1]=0;assign count[2]=0;
assign rd[2]=0;assign wr[2]=0;assign lba[2]=0;assign hi[2]=16'hffff;assign hi[1]=hi[0];
hps_io #(.CONF_STR("test"),.WIDE(1),.VDNUM(3),.PS2DIV(1)) hps(.clk_sys(clk),.HPS_BUS(bus),.EXT_BUS(ext),.gamma_bus(gamma),
 .img_mounted(mounts),.img_readonly(readonly_image),.img_size(size),.sd_lba(lba),.sd_blk_cnt(count),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),
 .sd_buff_addr(ha),.sd_buff_dout(hd),.sd_buff_din(hi),.sd_buff_wr(hwe),.ioctl_wait(1'b0),.ioctl_upload_req(1'b0),.ioctl_upload_index(8'b0),.ioctl_din(16'b0),
 .status_in(128'b0),.status_set(1'b0),.status_menumask(16'b0),.info_req(1'b0),.info(8'b0),.video_rotated(1'b0),.new_vmode(1'b0),
 .joystick_0_rumble(16'b0),.joystick_1_rumble(16'b0),.joystick_2_rumble(16'b0),.joystick_3_rumble(16'b0),.joystick_4_rumble(16'b0),.joystick_5_rumble(16'b0));
ngage_raw_save_manager #(.C_SECTORS(2),.PMM_SECTORS(2),.SD_TIMEOUT(100000),.BULK(BULK)) save(.clk(clk),.reset(reset),.mount(mounts[1:0]),.readonly_image(readonly_image),.image_size(size),.bundle_verified(1'b1),
 .bulk_cancel(bulk_cancel),.bulk_error(bulk_error),
 .bulk_read_valid(bulk_read_valid),.bulk_read_ready(bulk_read_ready),
 .bulk_read_data(bulk_read_data),.bulk_read_last(bulk_read_last),
 .bulk_write_valid(bulk_write_valid),.bulk_write_ready(bulk_write_ready),
 .bulk_write_data(bulk_write_data),.bulk_write_last(bulk_write_last),
 .dirty_valid(dirty || fdirty || pdirty),.dirty_sector(dirty ? dirty_sector : pdirty ? psector-14'd8190 : {1'b0,fsector}),.flush_start(flush),.autosave_enable(1'b0),.pause_autosave(1'b0),.mounted(mounted),.saving(saving),.saved(saved),.error(error),.busy(busy),
 .mem_valid(mv),.mem_ready(mem_ready),.mem_write(mw),.mem_addr(ma),.mem_data(mdata),.mem_be(mbe),.mem_done(mdone),.mem_rdata(mr),
 .sd_lba0(lba[0]),.sd_lba1(lba[1]),.sd_rd(rd[1:0]),.sd_wr(wr[1:0]),.sd_ack(ack[1:0]),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hi[0]),.flash_quiescent(!fpending && !ppending));
wire av,ar,aw,adone,xv,xr,xw,xdone,bv,br,bw,bdone;wire [31:0] aa,ad,ard,xa,xd,xrd,ba,bd,brd;wire [3:0] ab,xb,bb;
wire [28:0] phyaddr;wire [63:0] phydata;wire [7:0] phybe;wire phyrd,phywr;reg [63:0] phyrdata=0;reg phyready=0;integer delay=0,base_index,j,cycle=0;
wire phybusy=(cycle%7)<3;
ngage_ddr_arbiter aux(.l_bulk(1'b0),.c_bulk(BULK!=0),.req_bulk(aux_bulk),.clk(clk),.reset(reset),.cpu_lock(1'b0),.l_valid(1'b0),.l_ready(),.l_addr(32'b0),.l_data(32'b0),.l_be(4'b0),.l_done(),.c_valid(mv),.c_ready(mem_ready),.c_write(mw),.c_addr(ma),.c_data(mdata),.c_be(mbe),.c_done(mdone),.c_rdata(mr),.req_valid(av),.req_ready(ar),.req_write(aw),.req_addr(aa),.req_data(ad),.req_be(ab),.rsp_valid(adone),.rsp_data(ard),.l_write(1'b1),.l_rdata());
ngage_ddr_arbiter flash_arb(.clk(clk),.reset(reset),.cpu_lock(1'b0),.l_valid(fmv),.l_ready(fready),.l_addr(fma),.l_data(fmd),.l_be(fmb),.l_done(fdone),.c_valid(pmv),.c_ready(pready),.c_write(pmw),.c_addr(pma),.c_data(pmd),.c_be(pmb),.c_done(pdone),.c_rdata(pmr),.req_valid(xv),.req_ready(xr),.req_write(xw),.req_addr(xa),.req_data(xd),.req_be(xb),.rsp_valid(xdone),.rsp_data(xrd),.l_write(fmw),.l_rdata(fmr));
ngage_ddr_arbiter outer(.l_bulk(aux_bulk),.c_bulk(1'b0),.req_bulk(req_bulk),.clk(clk),.reset(reset),.cpu_lock(1'b0),.l_valid(av),.l_ready(ar),.l_addr(aa),.l_data(ad),.l_be(ab),.l_done(adone),.c_valid(xv),.c_ready(xr),.c_write(xw),.c_addr(xa),.c_data(xd),.c_be(xb),.c_done(xdone),.c_rdata(xrd),.req_valid(bv),.req_ready(br),.req_write(bw),.req_addr(ba),.req_data(bd),.req_be(bb),.rsp_valid(bdone),.rsp_data(brd),.l_write(aw),.l_rdata(ard));
ngage_cflash flash(clk,reset,1'b0,fv,fr,fw,fo,fd,fb,frsp,ferr,fq,fmv,fready,fmw,fma,fmd,fmb,fdone,fmr,fdirty,fsector,fpending,);
ngage_codeflash pflash(,clk,reset,1'b0,pv,pr,pw,pa,pd,pb,prsp,perr,pq,pmv,pready,pmw,pma,pmd,pmb,pdone,pmr,pdirty,psector,ppending,);
wire [7:0] phyburst;
reg [28:0] next_read;
integer beats_left=0, physical_reads=0, physical_writes=0, snapshots=0;
ngage_ddr_flash_adapter #(
 .STREAM_TRANSPORT(STREAM_TRANSPORT), .FLASH_CACHE_BYTES(FLASH_CACHE_BYTES), .BULK_PERSISTENCE(BULK)
) adapter(
 .req_bulk(req_bulk),
 .bulk_cancel(bulk_cancel),.bulk_error(bulk_error),
 .bulk_read_valid(bulk_read_valid),.bulk_read_ready(bulk_read_ready),
 .bulk_read_data(bulk_read_data),.bulk_read_last(bulk_read_last),
 .bulk_write_valid(bulk_write_valid),.bulk_write_ready(bulk_write_ready),
 .bulk_write_data(bulk_write_data),.bulk_write_last(bulk_write_last),
 .clk(clk), .reset(reset), .req_valid(bv), .req_ready(br), .req_write(bw),
 .req_addr(ba), .req_wdata(bd), .req_be(bb), .rsp_valid(bdone), .rsp_data(brd),
 .ddr_addr(phyaddr), .ddr_din(phydata), .ddr_be(phybe), .ddr_rd(phyrd), .ddr_we(phywr),
 .ddr_busy(phybusy), .ddr_dout(phyrdata), .ddr_dout_ready(phyready),
 .req_fetch(1'b0), .req_line(1'b0), .ddr_burstcount(phyburst));
function automatic [63:0] read_ddr(input [28:0] address);
 integer base;
 begin
  base = (address - (32'h30000000 >> 3)) * 8;
  if (base >= 0 && base < 20905984) begin
   for (integer lane=0; lane<8; lane++) read_ddr[lane*8+:8] = firmware[base+lane];
  end else if (address >= (32'h31400000 >> 3) && address < (32'h31410000 >> 3)) begin
   base = (address - (32'h31400000 >> 3)) * 2;
   read_ddr = base < 256 ? {ram[base+1],ram[base]} : {erase_tail[base+1],erase_tail[base]};
  end else if (address >= (32'h31800000 >> 3) && address < (32'h31800400 >> 3)) begin
   base = 256 + (address - (32'h31800000 >> 3)) * 2;
   read_ddr = {ram[base+1],ram[base]};
  end else $fatal(1,"unexpected DDR read %h",address);
 end
endfunction
always @(posedge clk) begin
 cycle <= cycle + 1;
 phyready <= 0;
 if (delay > 0) delay <= delay - 1;
 else if (beats_left > 0) begin
  phyready <= 1;
  phyrdata <= read_ddr(next_read);
  next_read <= next_read + 1'b1;
  beats_left <= beats_left - 1;
 end
 if (phyrd && !phybusy) begin
  if (beats_left || (phyburst != 1 && phyburst != 4 && phyburst != 64)) $fatal(1,"overlapping/invalid DDR read");
  next_read <= phyaddr;
  beats_left <= int'(phyburst);
  physical_reads <= physical_reads + 1;
  if (phyburst == 64) begin
   if (!BULK || phyaddr[5:0] != 0) $fatal(1,"unexpected sector snapshot");
   snapshots <= snapshots + 1;
  end
  delay <= 2;
 end
 if (phywr && !phybusy) begin
  if (beats_left || phyburst != 1) $fatal(1,"overlapping/invalid DDR write");
  physical_writes <= physical_writes + 1;
  if (phyaddr >= (32'h31400000 >> 3) && phyaddr < (32'h31410000 >> 3)) begin
   base_index = (phyaddr - (32'h31400000 >> 3)) * 2;
   for (j=0; j<8; j++) if (phybe[j]) begin
    if (base_index < 256) ram[base_index+j/4][(j%4)*8+:8] <= phydata[j*8+:8];
    else erase_tail[base_index+j/4][(j%4)*8+:8] <= phydata[j*8+:8];
   end
  end else if (phyaddr >= (32'h31800000 >> 3) && phyaddr < (32'h31800400 >> 3)) begin
   base_index = 256 + (phyaddr - (32'h31800000 >> 3)) * 2;
   for (j=0; j<8; j++) if (phybe[j]) ram[base_index+j/4][(j%4)*8+:8] <= phydata[j*8+:8];
  end else $fatal(1,"unexpected DDR write %h",phyaddr);
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
reg [31:0] decode_address=0, decode_raw=0;
wire [31:0] decode_expected;
ngage_flash_read_decode expected_decode(decode_address,decode_raw,1'b1,1'b1,decode_expected);
task code_read(input [31:0] address,input [3:0] mask,input [31:0] value);
 integer t;
 begin
  while (!pr) @(negedge clk);
  @(negedge clk); pv=1; pw=0; pa=address; pb=mask; pd=0;
  @(negedge clk); pv=0;
  t=0; while (!prsp && t<5000) begin @(negedge clk); t++; end
  if (!prsp || perr || pq!==value) $fatal(1,"code read %h got %h expected %h",address,pq,value);
 end
endtask
task firmware_at(input [31:0] address);
 begin
  decode_address=address;
  decode_raw={firmware_before[address+3],firmware_before[address+2],
              firmware_before[address+1],firmware_before[address]};
  #1;
  code_read(address,15,decode_expected);
 end
endtask
task firmware_read;
 begin firmware_at(0); end
endtask
task c_read(input [21:0] address,input [3:0] mask,input [31:0] value);
 integer t;
 begin
  while (!fr) @(negedge clk);
  @(negedge clk); fv=1; fw=0; fo=address; fb=mask;
  @(negedge clk); fv=0;
  t=0; while (!frsp && t<400000) begin @(negedge clk); t++; end
  if (!frsp || ferr || fq!==value) $fatal(1,"C read %h got %h expected %h",address,fq,value);
 end
endtask
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
  if((current_lba>1))$fatal(1,"bad LBA");
  if(part<2)current_lba=current_lba+1+(part==1?2:0);
  requests=requests+1;
  if(status_word[0])begin
   reads=reads+1;begin_io();word_out((part<<8)|'h17);
   if(inject_short && part<2)begin
    for(n=0;n<128;n=n+1)word_out(disk[current_lba*256+n]);inject_short=0;
   end else for(n=0;n<256;n=n+1)word_out(disk[current_lba*256+n]);
   repeat(4)@(negedge clk);end_io();
  end else begin
   writes=writes+1;if(part==0)snapshot_word0=save.bridge.sector.buffer.memory[0];begin_io();word_out((part<<8)|'h18);
   if(inject_swap && part==0)begin
    for(n=0;n<8;n=n+1)word_out(0);end_io();inject_swap=0;mount_image(1,0,2560);
   end else begin
    for(n=0;n<256;n=n+1)begin
     word_out(0);#1;disk[current_lba*256+n]=bus[15:0];
     if(inject_mutation && part==0 && current_lba==1 && n==100)begin
      if (BULK && FLASH_CACHE_BYTES != 0) begin
       integer before_hit;
       firmware_read();
       before_hit=physical_reads;
       firmware_read();
       if (physical_reads != before_hit) $fatal(1,"cached read during HPS save missed");
      end
      flash_program(0,16'hccdd);inject_mutation=0;saw_old_snapshot=1;
     end
    end
    if(saw_old_snapshot && !first_snapshot_checked && part==0 && current_lba==1)begin
     if(disk[256]!==16'h1234)$fatal(1,"first snapshot did not retain old data");first_snapshot_checked=1;
    end
    if(part==0)repeat(4)begin @(negedge clk);if(save.bridge.sector.buffer.memory[0]!==snapshot_word0)$fatal(1,"sector buffer changed before HPS ack release");end
    end_io();
   end
  end
 end
end

initial begin: test
 hold_requests=1;
 for(integer k=256;k<16384;k++)erase_tail[k]=32'hffffffff;
 for(integer k=0;k<1280;k=k+1)disk[k]=16'h1000+k;
 for(integer k=0;k<512;k=k+1)begin ram[k]=32'hdeadbeef;end
 image_fd=$fopen("build/firmware/nem4-factory/core.bin","rb");if(!image_fd)$fatal(1,"missing stock core");
 image_got=$fread(firmware,image_fd,0,18612224);$fclose(image_fd);if(image_got!=18612224)$fatal(1,"stock core length");
 image_fd=$fopen("build/firmware/nem4-factory/extension.bin","rb");if(!image_fd)$fatal(1,"missing stock extension");
 image_got=$fread(firmware,image_fd,18612224,2293760);$fclose(image_fd);if(image_got!=2293760)$fatal(1,"stock extension length");
 for(integer k=0;k<20905984;k=k+1)firmware_before[k]=firmware[k];
 for(integer k=0;k<4;k=k+1)begin disk[256+k*256]=16'hffff;disk[257+k*256]=16'hffff;end
 disk[511]=16'hffff;
 for(integer k=0;k<1280;k=k+1)original_disk[k]=disk[k];
 repeat(4)@(negedge clk);reset=0;repeat(12)@(negedge clk);
 mount_image(1,0,1024);mount_image(2,0,1024);hold_requests=0;
 wait(mounted||error);if(error)$fatal(1,"raw NOR mount failed");
 if (physical_writes != (BULK ? 256 : 512)) $fatal(1,"restore physical command count");
 $display("METRIC bulk=%0d initial_restore_writes=%0d restore_complete_cycle=%0d",BULK,physical_writes,cycle);
 for(integer k=0;k<256;k=k+1)begin
  if(ram[k]!=={disk[257+k*2],disk[256+k*2]})$fatal(1,"C restore mismatch %d",k);
  if(ram[256+k]!=={disk[769+k*2],disk[768+k*2]})$fatal(1,"PMM restore mismatch %d",k);
 end
 firmware_read();
 flash_program(0,16'h1234);
 flash_program(22'h1fe,16'h55aa);flash_program(22'h200,16'h5678);
 pmm_cmd(32'h007f0000,16'h40);pmm_cmd(32'h007f0000,16'h1236);pmm_cmd(0,16'hf0);
 pmm_cmd(32'h007f0200,16'h40);pmm_cmd(32'h007f0200,16'h1237);pmm_cmd(0,16'hf0);
 @(negedge clk);flush=1;@(negedge clk);flush=0;
 wait((saved&&!saving)||error);
 if(error||!saved)$fatal(1,"raw NOR flush failed");
 for(integer k=0;k<4;k=k+1)if({disk[257+k*256],disk[256+k*256]}!==expected(k))$fatal(1,"saved raw sector %d",k);
 if(disk[511]!==16'h55aa||disk[512]!==16'h5678)$fatal(1,"cross-sector NOR persistence");
 for(integer k=0;k<1280;k=k+1)if(k!=256&&k!=511&&k!=512&&k!=768&&k!=1024&&disk[k]!==original_disk[k])$fatal(1,"unchanged disk word%d",k);
 // NOR program commits during transfer must be marked and persisted again.
 @(negedge clk);dirty_sector=0;dirty=1;@(negedge clk);dirty=0;inject_mutation=1;flush=1;@(negedge clk);flush=0;
 wait((saved&&!saving)||error);if(error||!saw_old_snapshot||!first_snapshot_checked||{disk[257],disk[256]}!==32'hffffccdd)$fatal(1,"NOR mutation lost");
 if (snapshots != (BULK ? 6 : 0)) $fatal(1,"snapshot count %0d",snapshots);
 $display("METRIC bulk=%0d snapshots=%0d DDR_reads_through_save=%0d save_complete_cycle=%0d",
          BULK,snapshots,physical_reads,cycle);
 // Remount each image independently, C first, without altering firmware.
 hold_requests=1;for(integer k=0;k<512;k=k+1)ram[k]=0;
 mount_image(1,0,1024);mount_image(2,0,1024);hold_requests=0;wait(mounted||error);if(error)$fatal(1,"raw NOR reload failed");
 for(integer k=0;k<4;k=k+1)if(ram[k*128]!==(k==0?32'hffffccdd:expected(k)))$fatal(1,"reload sector%d",k);
 if(ram[127][31:16]!==16'h55aa)$fatal(1,"cross-sector halfword reload");
 firmware_read();for(integer k=0;k<20905984;k=k+1)if(firmware[k]!==firmware_before[k])$fatal(1,"immutable firmware byte%d changed",k);
 if (FLASH_CACHE_BYTES != 0) begin
  integer before_status;
  firmware_at(32'h9ffc); firmware_at(32'ha000);
  firmware_at(32'h2b2ffc); firmware_at(32'h2b3000);
  firmware_at(32'h9ffc); firmware_at(32'ha000);
  firmware_at(32'h2b2ffc); firmware_at(32'h2b3000);
  c_read(0,15,32'hffffccdd);
  code_read(32'h007f0200,15,32'hffff1237);
  // The manager conservatively requires a flush after NOR activity
  // before media replacement. The scan has no dirty sectors here.
  @(negedge clk); flush=1; @(negedge clk); flush=0;
  wait((saved && !saving) || error);
  if (error) $fatal(1,"flush before changed image restore");
  // Replace both host images while the old flash lines are warm.
  hold_requests=1;
  disk[256]=16'hc9c8;
  disk[1024]=16'h1357;
  mount_image(1,0,1024); mount_image(2,0,1024);
  hold_requests=0;
  wait(mounted || error);
  if (error) $fatal(1,"changed raw image restore");
  c_read(0,15,32'hffffc9c8);
  code_read(32'h007f0200,15,32'hffff1357);
  flash_cmd('haaa,'haa); flash_cmd('h554,'h55); flash_cmd('haaa,'h90);
  before_status=physical_reads;
  c_read(0,3,1); c_read(2,12,32'h257e0000);
  if (physical_reads!=before_status) $fatal(1,"NOR ID reached backing");
  flash_cmd(0,'hf0);
  c_read(0,15,32'hffffc9c8);
  code_read(32'h007f0000,15,32'hffff1236);
  pmm_cmd(32'h007f0000,16'h40); pmm_cmd(32'h007f0000,16'h1034);
  before_status=physical_reads;
  code_read(32'h007f0000,3,32'h80);
  if (physical_reads!=before_status) $fatal(1,"PMM status reached backing");
  pmm_cmd(0,'hf0); code_read(32'h007f0000,15,32'hffff1034);
  flash_cmd('haaa,'haa); flash_cmd('h554,'h55); flash_cmd('haaa,'h80);
  flash_cmd('haaa,'haa); flash_cmd('h554,'h55); flash_cmd(0,'h30);
  c_read(0,3,8); c_read(0,3,32'hffff);
  c_read(0,15,32'hffffffff);
  c_read('h1fc,15,32'hffffffff);
  $display("PASS D2 raw NOR cached array, changed C/PMM restore, descramble boundaries, C ID/erase and PMM status");
 end
 $display("PASS raw NOR program, scalar DDR adapter/arbiters and actual three-slot hps_io, independent C/PMM flush/reload, concurrent mutation, immutable firmware (%0d reads, %0d writes)",reads,writes);$finish;
end
initial begin #10000000;$fatal(1,"raw NOR timeout state=%d",save.state);end
endmodule
