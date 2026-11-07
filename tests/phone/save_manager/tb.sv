module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,mount=0,readonly_image=0,bundle_ok=1,dv=0,flush=0,quiet=1,stall_sd=0;reg [63:0] image_size=1536;reg [13:0] di=0;
reg [255:0] core,ext;
reg fv=0,fw=0;reg [21:0] fo=0;reg [31:0] fd=0;reg [3:0] fb=0;
wire fr,frsp,ferr,fmv,fmw,fdirty,fready,fdone;wire [31:0] fq,fma,fmd,fmr;wire [3:0] fmb;wire [12:0] fsector;
reg pv=0,pw=0;reg [31:0] pa=0,pd=0;reg [3:0] pb=0;
wire pr,prsp,perr,pmv,pmw,pdirty,pready,pdone;wire [31:0] pq,pma,pmd,pmr;wire [3:0] pmb;wire [13:0] psector;wire mounted,saving,saved,error,mv,mw;wire [31:0] ma,md,sd_lba;wire [3:0] mb;wire mem_done,mem_ready;wire [31:0] mr;
wire sd_rd,sd_wr,sd_ack;wire [12:0] haddr;wire [15:0] hdata;wire hwe;wire [15:0] hout;
reg [31:0] ram[0:255];reg [15:0] disk[0:767];reg [15:0] header[0:255];
reg [1:0] hs=0;reg hop_read=0;reg [8:0] idx=0;reg [31:0] held_lba=0;integer i;
ngage_save_manager #(.C_SECTORS(1),.PMM_SECTORS(1),.SD_TIMEOUT(5000)) dut(clk,reset,mount,readonly_image,image_size,bundle_ok,2'd1,core,ext,(dv||fdirty||pdirty),(dv?di:(pdirty?(psector-14'd8191):{1'b0,fsector})),flush,mounted,saving,saved,error,,
 mv,mem_ready,mw,ma,md,mb,mem_done,mr,sd_lba,sd_rd,sd_wr,sd_ack,haddr,hdata,hwe,hout,quiet);
assign sd_ack=hs==1;
assign haddr=idx;
assign hwe=hs==1 && hop_read;
assign hdata=disk[held_lba*256+idx];
wire av,ar,aw,adone;wire [31:0] aa,ad,ard;wire [3:0] ab;
wire bv,br,bw,bdone;wire [31:0] ba,bd,brd;wire [3:0] bb;
wire xv,xr,xw,xdone;wire [31:0] xa,xd,xrd;wire [3:0] xb;
wire [28:0] da;wire [63:0] din;wire [7:0] dbe;wire dr,dw;reg [63:0] dout=0;reg dready=0;integer delay=0,base_index,j,cycle=0;
wire dbusy=(cycle%7)<3;
ngage_ddr_arbiter aux(clk,reset,1'b0,1'b0,,32'b0,32'b0,4'b0,,mv,mem_ready,mw,ma,md,mb,mem_done,mr,av,ar,aw,aa,ad,ab,adone,ard,1'b1,);
ngage_ddr_arbiter flash_arb(clk,reset,1'b0,fmv,fready,fma,fmd,fmb,fdone,pmv,pready,pmw,pma,pmd,pmb,pdone,pmr,xv,xr,xw,xa,xd,xb,xdone,xrd,fmw,fmr);
ngage_ddr_arbiter outer(clk,reset,1'b0,av,ar,aa,ad,ab,adone,xv,xr,xw,xa,xd,xb,xdone,xrd,bv,br,bw,ba,bd,bb,bdone,brd,aw,ard);
ngage_cflash flash(clk,reset,1'b0,fv,fr,fw,fo,fd,fb,frsp,ferr,fq,fmv,fready,fmw,fma,fmd,fmb,fdone,fmr,fdirty,fsector,,);
ngage_codeflash pflash(clk,reset,1'b0,pv,pr,pw,pa,pd,pb,prsp,perr,pq,pmv,pready,pmw,pma,pmd,pmb,pdone,pmr,pdirty,psector,,);
ngage_ddr_adapter adapter(clk,reset,bv,br,bw,ba,bd,bb,bdone,brd,da,din,dbe,dr,dw,dbusy,dout,dready);
always @(posedge clk)begin
 cycle<=cycle+1;dready<=0;
 if(delay>0)begin delay<=delay-1;if(delay==1)dready<=1;end
 if((dr||dw) && !dbusy)begin
  if(da==(32'h31400000>>3) || (da>(32'h31400000>>3) && da<(32'h31400200>>3)))base_index=(da-(32'h31400000>>3))*2;
  else if(da>=(32'h31800000>>3) && da<(32'h31800200>>3))base_index=128+(da-(32'h31800000>>3))*2;
  else $fatal(1,"unexpected DDR %h",da);
  if(dw)begin for(j=0;j<8;j=j+1)if(dbe[j])ram[base_index+(j/4)][(j%4)*8+:8]<=din[j*8+:8];end
  else begin dout<={ram[base_index+1],ram[base_index]};delay<=3;end
 end
 if(!stall_sd) case(hs)
 0:if(sd_rd||sd_wr)begin if(sd_lba>2)$fatal(1,"invalid disk LBA");held_lba<=sd_lba;hop_read<=sd_rd;idx<=0;hs<=1;end
 1:begin
  if(!hop_read)disk[held_lba*256+idx]<=hout;
  if(idx==255)hs<=2;else idx<=idx+1'b1;
 end
 2:if(!sd_rd && !sd_wr)hs<=0;
 endcase
end
task tick;begin @(posedge clk);#1;end endtask
task flash_cmd(input [21:0] offset,input [15:0] val);
 integer n;begin
 while(!fr) tick();@(negedge clk);fv=1;fw=1;fo=offset;fb=offset[1]?12:3;fd=offset[1]?{val,16'b0}:{16'b0,val};tick();@(negedge clk);fv=0;
 n=0;while(!frsp && n<3000)begin tick();n=n+1;end
 if(!frsp || ferr)$fatal(1,"flash command failed %h",offset);
 end
endtask
task flash_program(input [21:0] offset,input [15:0] val);begin flash_cmd('haaa,'haa);flash_cmd('h554,'h55);flash_cmd('haaa,'ha0);flash_cmd(offset,val);end endtask
task pmm_cmd(input [31:0] address,input [15:0] val);
 integer n;begin while(!pr)tick();@(negedge clk);pv=1;pw=1;pa=address;pb=address[1]?12:3;pd=address[1]?{val,16'b0}:{16'b0,val};tick();@(negedge clk);pv=0;n=0;while(!prsp && n<3000)begin tick();n=n+1;end if(!prsp||perr)$fatal(1,"PMM command");end
endtask
task pulse_mount;begin @(negedge clk);mount=1;tick();@(negedge clk);mount=0;end endtask
initial begin
 for(i=0;i<32;i=i+1)begin core[i*8+:8]=i;ext[i*8+:8]=i+32;end
 $readmemh("build/sim/unit-save-manager/header.hex",header);
 for(i=0;i<256;i=i+1)begin disk[i]=header[i];disk[256+i]=16'h1000+i;disk[512+i]=16'h2000+i;ram[i]=0;end
 tick();reset=0;repeat(5)tick();
 bundle_ok=0;pulse_mount();if(!error||mounted)$fatal(1,"unverified bundle accepted");
 bundle_ok=1;readonly_image=1;pulse_mount();if(!error||mounted)$fatal(1,"readonly save accepted");
 readonly_image=0;image_size=1537;pulse_mount();if(!error||mounted)$fatal(1,"wrong size accepted");
 image_size=1536;pulse_mount();wait(mounted||error);if(error)$fatal(1,"mount failed");
 for(i=0;i<128;i=i+1)begin
  if(ram[i]!=={disk[257+i*2],disk[256+i*2]})$fatal(1,"C restore %d",i);
  if(ram[128+i]!=={disk[513+i*2],disk[512+i*2]})$fatal(1,"PMM restore %d",i);
 end
 flash_program(12,16'hbeef);flash_program(14,16'hcafe);pmm_cmd(32'h007f0002,16'h40);pmm_cmd(32'h007f0002,16'h60);pmm_cmd(0,16'hf0);repeat(3)tick();if(saved || ram[3]!==32'hcafebeef || ram[128]!==32'h00002000)$fatal(1,"flash mutation/dirty not reported");
 @(negedge clk);quiet=0;flush=1;tick();@(negedge clk);flush=0;wait(saving);repeat(20)tick();if(sd_wr)$fatal(1,"flush ignored pending flash operation");
 @(negedge clk);quiet=1;wait(sd_wr && sd_lba==1);quiet=0;flash_program(12,16'h1234);quiet=1;
 while(!saved && !error)tick();
 if(error||!saved||disk[262]!==16'h1234||disk[263]!==16'hcafe || disk[512]!==16'h2000 || disk[513]!==0)$fatal(1,"flush failed e=%b saved=%b c=%h/%h p=%h/%h",error,saved,disk[262],disk[263],disk[512],disk[513]);
 for(i=0;i<256;i=i+1)ram[i]=0;
 pulse_mount();wait(mounted||error);if(error||ram[3]!==32'hcafe1234 || ram[128]!==32'h00002000)$fatal(1,"reload failed");
 image_size=0;pulse_mount();if(mounted || error || saved)$fatal(1,"clean zero-size unmount");
 image_size=1536;pulse_mount();wait(mounted||error);if(error)$fatal(1,"remount after unmount");
 disk[0]=disk[0]^1;ram[3]=32'hfeedface;pulse_mount();wait(error);if(mounted || ram[3]!==32'hfeedface)$fatal(1,"invalid header changed memory");
 // A media swap during an active SD write must never report a saved image.
 disk[0]=disk[0]^1;@(negedge clk);reset=1;tick();@(negedge clk);reset=0;repeat(5)tick();pulse_mount();wait(mounted||error);if(error)$fatal(1,"remount setup");
 @(negedge clk);ram[7]=32'habcdef01;dv=1;di=0;tick();@(negedge clk);dv=0;flush=1;tick();@(negedge clk);flush=0;
 wait(sd_wr);@(negedge clk);mount=1;#1;if(sd_wr)$fatal(1,"request not gated during media swap");tick();@(negedge clk);mount=0;
 if(!error || mounted || saved)$fatal(1,"media swap not reported as uncertain failure");
 // Withhold HPS ack during a flush: report failure and retain RAM, never saved.
 @(negedge clk);reset=1;tick();@(negedge clk);reset=0;stall_sd=0;repeat(5)tick();pulse_mount();wait(mounted||error);if(error)$fatal(1,"timeout setup mount");
 @(negedge clk);ram[9]=32'hbadc0ffe;dv=1;di=0;tick();@(negedge clk);dv=0;stall_sd=1;flush=1;tick();@(negedge clk);flush=0;
 wait(error);if(saved||mounted||ram[9]!==32'hbadc0ffe)$fatal(1,"failed flush lost RAM or reported saved");
 // Mounting a different image while dirty is an actual media change, not a
 // request that can be declined: stop and preserve unsaved DDR bytes.
 @(negedge clk);reset=1;tick();@(negedge clk);reset=0;stall_sd=0;repeat(5)tick();pulse_mount();wait(mounted||error);if(error)$fatal(1,"dirty mount setup");
 @(negedge clk);ram[7]=32'hdec0ded1;di=0;dv=1;tick();@(negedge clk);dv=0;repeat(2)tick();pulse_mount();
 if(mounted || !error || saved || ram[7]!==32'hdec0ded1)$fatal(1,"dirty media swap corrupted RAM");
 $display("PASS save mount, CRC/hash validation, restore, flush, reload and failure handling");$finish;
end
initial begin #3000000;$fatal(1,"timeout state=%d mounted=%b error=%b",dut.state,mounted,error);end
endmodule
