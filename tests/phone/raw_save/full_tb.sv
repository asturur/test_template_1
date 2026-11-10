`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg reset=1,dv=0,flush=0;reg [13:0] di=0;reg [1:0] mount=0;reg [63:0] image_size=0;
wire mounted,saving,saved,error,mv,mw;wire [31:0] ma,md,lba;wire [3:0] mb;reg m_done=0;reg [31:0] mr=0;
wire [1:0] rd,wr,ack;wire [31:0] lba1;wire active=rd[1]||wr[1];reg held_slot=0;wire [12:0] ha;wire [15:0] hd;wire hwe;wire [15:0] hout;
reg [31:0] ram[0:1064959];reg [15:0] disk[0:2129919];
reg [1:0] hs=0;reg hop_read=0;reg [8:0] idx=0;reg [31:0] held_lba=0;integer i;
ngage_raw_save_manager #(.SD_TIMEOUT(5000)) dut(.clk(clk),.reset(reset),.mount(mount),.readonly_image(1'b0),.image_size(image_size),.bundle_verified(1'b1),
 .dirty_valid(dv),.dirty_sector(di),.flush_start(flush),.mounted(mounted),.saving(saving),.saved(saved),.error(error),.busy(),
 .mem_valid(mv),.mem_ready(1'b1),.mem_write(mw),.mem_addr(ma),.mem_data(md),.mem_be(mb),.mem_done(m_done),.mem_rdata(mr),
 .sd_lba0(lba),.sd_lba1(lba1),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hout),.flash_quiescent(1'b1));
assign ack=hs==1 ? (held_slot ? 2'b10 : 2'b01) : 2'b00;assign ha={4'b0,idx};reg hs_phase=0;
assign hwe=hs==1 && hop_read && hs_phase;assign hd=disk[held_lba*256+idx];
always @(posedge clk)begin
 m_done<=0;
 if(mv)begin
  if(ma>=32'h31400000 && ma<32'h31800000)begin mr<=ram[(ma-32'h31400000)>>2];if(mw)ram[(ma-32'h31400000)>>2]<=md;end
  else if(ma>=32'h31800000 && ma<32'h31810000)begin mr<=ram[1048576+((ma-32'h31800000)>>2)];if(mw)ram[1048576+((ma-32'h31800000)>>2)]<=md;end
  else $fatal(1,"DDR address %h",ma);
  m_done<=1;
 end
 case(hs)
 0:if((|rd)||(|wr))begin
 if((active?lba1:lba)>=(active?128:8192))$fatal(1,"raw LBA bounds");
 held_slot<=active;held_lba<=(active?lba1+8192:lba);hop_read<=|rd;idx<=0;hs_phase<=0;hs<=1;end
 1:begin hs_phase<=!hs_phase;if(hs_phase)begin if(!hop_read)disk[held_lba*256+idx]<=hout;if(idx==255)hs<=2;else idx<=idx+1'b1;end end
 2:if(!(|rd) && !(|wr))hs<=0;
 endcase
end
task tick;begin @(posedge clk);#1;end endtask
task mount_save;begin
 @(negedge clk);image_size=65536;mount=2;tick();@(negedge clk);mount=0;tick();
 @(negedge clk);image_size=4194304;mount=1;tick();@(negedge clk);mount=0;
 wait(mounted||error);if(error)$fatal(1,"mount failed state=%d",dut.state);
end endtask
initial begin
 for(i=0;i<2129920;i=i+1)disk[i]=(i ^ (i>>8) ^ 16'ha5c3);
 for(i=0;i<1064960;i=i+1)ram[i]=0;
 tick();reset=0;repeat(8330)tick();mount_save();
 for(i=0;i<1064960;i=i+1)if(ram[i]!=={disk[1+i*2],disk[i*2]})$fatal(1,"initial restore word %d",i);
 @(negedge clk);ram[1048575]=32'h01234567;di=8191;dv=1;tick();@(negedge clk);ram[1064959]=32'h89abcdef;di=8319;tick();@(negedge clk);dv=0;flush=1;tick();@(negedge clk);flush=0;
 wait(saving);while(!saved && !error)tick();if(error||!saved)$fatal(1,"flush failed");
 if(disk[2*1048575]!==16'h4567 || disk[2*1048575+1]!==16'h0123 || disk[2*1064959]!==16'hcdef || disk[2*1064959+1]!==16'h89ab)$fatal(1,"boundary sector save");
 for(i=0;i<1064960;i=i+1)ram[i]=0;
 mount_save();
 for(i=0;i<1064960;i=i+1)if(ram[i]!=={disk[1+i*2],disk[i*2]})$fatal(1,"reload word %d",i);
 $display("PASS raw full-size 4 MiB C: and 64 KiB PMM scalar restore/readback, last sectors and independent reload");$finish;
end
initial begin #2000000000;$fatal(1,"timeout state=%d cursor=%d",dut.state,dut.cursor);end
endmodule
