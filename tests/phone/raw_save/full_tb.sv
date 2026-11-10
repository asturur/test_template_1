`timescale 1ns/1ps
module tb;
parameter BULK=0;
reg clk=0;always #5 clk=~clk;reg reset=1,dv=0,flush=0;reg [13:0] di=0;reg [1:0] mount=0;reg [63:0] image_size=0;
wire mounted,saving,saved,error,mv,mw;wire [31:0] ma,md,lba;wire [3:0] mb;wire m_ready,m_done;wire [31:0] mr;
wire [1:0] rd,wr,ack;wire [31:0] lba1;wire active=rd[1]||wr[1];reg held_slot=0;wire [12:0] ha;wire [15:0] hd;wire hwe;wire [15:0] hout;
reg [31:0] ram[0:1064959];reg [15:0] disk[0:2129919];
reg [1:0] hs=0;reg hop_read=0;reg [8:0] idx=0;reg [31:0] held_lba=0;integer i;
wire bulk_cancel, bulk_error, bulk_read_valid, bulk_read_ready, bulk_read_last;
wire bulk_write_valid, bulk_write_ready, bulk_write_last;
wire [63:0] bulk_read_data, bulk_write_data;
integer writes=0, snapshots=0;
ngage_raw_save_manager #(.SD_TIMEOUT(5000),.BULK(BULK)) dut(.clk(clk),.reset(reset),.mount(mount),.readonly_image(1'b0),.image_size(image_size),.bundle_verified(1'b1),
 .bulk_cancel(bulk_cancel),.bulk_error(bulk_error),
 .bulk_read_valid(bulk_read_valid),.bulk_read_ready(bulk_read_ready),
 .bulk_read_data(bulk_read_data),.bulk_read_last(bulk_read_last),
 .bulk_write_valid(bulk_write_valid),.bulk_write_ready(bulk_write_ready),
 .bulk_write_data(bulk_write_data),.bulk_write_last(bulk_write_last),
 .dirty_valid(dv),.dirty_sector(di),.flush_start(flush),.autosave_enable(1'b0),.pause_autosave(1'b0),.mounted(mounted),.saving(saving),.saved(saved),.error(error),.busy(),
 .mem_valid(mv),.mem_ready(m_ready),.mem_write(mw),.mem_addr(ma),.mem_data(md),.mem_be(mb),.mem_done(m_done),.mem_rdata(mr),
 .sd_lba0(lba),.sd_lba1(lba1),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),.hps_addr(ha),.hps_dout(hd),.hps_we(hwe),.hps_din(hout),.flash_quiescent(1'b1));
assign ack=hs==1 ? (held_slot ? 2'b10 : 2'b01) : 2'b00;assign ha={4'b0,idx};reg hs_phase=0;
assign hwe=hs==1 && hop_read && hs_phase;assign hd=disk[held_lba*256+idx];
function automatic integer ram_index(input [31:0] address);
 if (address >= 32'h31400000 && address < 32'h31800000)
  ram_index = (address-32'h31400000) >> 2;
 else if (address >= 32'h31800000 && address < 32'h31810000)
  ram_index = 1048576 + ((address-32'h31800000) >> 2);
 else $fatal(1,"DDR address %h",address);
endfunction

generate
 if (BULK != 0) begin : bulk_port
  wire [28:0] phyaddr;
  wire [63:0] phydata;
  wire [7:0] phybe, burst;
  wire phy_rd, phy_wr;
  reg phy_valid=0;
  reg [63:0] phy_read=0;
  integer remaining=0, cursor=0, slot;
  ngage_ddr_flash_adapter #(.BULK_PERSISTENCE(1)) adapter(
   .clk(clk),.reset(reset),.req_valid(mv),.req_ready(m_ready),.req_write(mw),
   .req_addr(ma),.req_wdata(md),.req_be(mb),.req_bulk(1'b1),
   .req_fetch(1'b0),.req_line(1'b0),.rsp_valid(m_done),.rsp_data(mr),
   .bulk_cancel(bulk_cancel),.bulk_error(bulk_error),
   .bulk_read_valid(bulk_read_valid),.bulk_read_ready(bulk_read_ready),
   .bulk_read_data(bulk_read_data),.bulk_read_last(bulk_read_last),
   .bulk_write_valid(bulk_write_valid),.bulk_write_ready(bulk_write_ready),
   .bulk_write_data(bulk_write_data),.bulk_write_last(bulk_write_last),
   .ddr_addr(phyaddr),.ddr_din(phydata),.ddr_be(phybe),.ddr_burstcount(burst),
   .ddr_rd(phy_rd),.ddr_we(phy_wr),.ddr_busy(1'b0),
   .ddr_dout(phy_read),.ddr_dout_ready(phy_valid)
  );
  always @(posedge clk) begin
   phy_valid<=0;
   if (phy_rd) begin
    if (remaining || burst!=64 || phyaddr[5:0]!=0) $fatal(1,"incorrect snapshot command");
    snapshots<=snapshots+1;
    cursor<=ram_index({phyaddr,3'b0});
    remaining<=64;
   end
   if (remaining) begin
    phy_valid<=1;
    phy_read<={ram[cursor+1],ram[cursor]};
    cursor<=cursor+2;
    remaining<=remaining-1;
   end
   if (phy_wr) begin
    if (remaining || burst!=1 || phybe!=8'hff) $fatal(1,"incorrect restore command");
    writes<=writes+1;
    slot=ram_index({phyaddr,3'b0});
    ram[slot]<=phydata[31:0];
    ram[slot+1]<=phydata[63:32];
   end
  end
 end else begin : scalar_port
  reg done=0;
  reg [31:0] data=0;
  integer slot;
  assign m_ready=1;
  assign m_done=done;
  assign mr=data;
  always @(posedge clk) begin
   done<=0;
   if (mv) begin
    slot=ram_index(ma);
    data<=ram[slot];
    if (mw) begin
     writes<=writes+1;
     ram[slot]<=md;
    end
    done<=1;
   end
  end
 end
endgenerate
always @(posedge clk) begin
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
 if (writes != (BULK ? 1064960 : 2129920) || snapshots != (BULK ? 2 : 0))
  $fatal(1,"unexpected total DDR writes/snapshots %0d/%0d",writes,snapshots);
 $display("PASS raw full-size 4 MiB C: and 64 KiB PMM restore/readback, bulk=%0d, %0d DDR writes, %0d bulk snapshots",
          BULK,writes,snapshots);$finish;
end
initial begin #2000000000;$fatal(1,"timeout state=%d cursor=%d",dut.state,dut.cursor);end
endmodule
