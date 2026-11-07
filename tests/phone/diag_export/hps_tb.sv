`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
tri [45:0] bus;tri [35:0] ext;tri [21:0] gamma;
reg [15:0] host_data=0;reg strobe=0,enable=0;reg reset=1,start=0;
assign bus[31:16]=host_data;assign bus[33]=strobe;assign bus[34]=enable;assign bus[35]=0;
assign bus[45:38]=0;assign ext[32]=0;
wire [1:0] mounted,rd,wr,ack;wire readonly_image;wire [63:0] size;
wire [31:0] lba[2];wire [5:0] count[2];wire [12:0] haddr;wire [15:0] hout,hin[2];wire hwe;
wire [10:0] word;wire [15:0] data=16'h5000|word;wire busy,error,done,freeze,valid_mount;
assign lba[0]=0;assign count[0]=0;assign count[1]=0;assign rd[0]=0;assign wr[0]=0;assign hin[0]=0;
hps_io #(.CONF_STR("test"),.WIDE(1),.VDNUM(2),.PS2DIV(1)) hps(.clk_sys(clk),.HPS_BUS(bus),.EXT_BUS(ext),.gamma_bus(gamma),
 .img_mounted(mounted),.img_readonly(readonly_image),.img_size(size),.sd_lba(lba),.sd_blk_cnt(count),.sd_rd(rd),.sd_wr(wr),.sd_ack(ack),
 .sd_buff_addr(haddr),.sd_buff_dout(hout),.sd_buff_din(hin),.sd_buff_wr(hwe),.ioctl_wait(1'b0),.ioctl_upload_req(1'b0),.ioctl_upload_index(8'b0),.ioctl_din(16'b0),
 .status_in(128'b0),.status_set(1'b0),.status_menumask(16'b0),.info_req(1'b0),.info(8'b0),.video_rotated(1'b0),.new_vmode(1'b0),
 .joystick_0_rumble(16'b0),.joystick_1_rumble(16'b0),.joystick_2_rumble(16'b0),.joystick_3_rumble(16'b0),.joystick_4_rumble(16'b0),.joystick_5_rumble(16'b0));
ngage_diag_export #(.TIMEOUT(2000)) exp(.clk(clk),.reset(reset),.mount(mounted[1]),.readonly_image(readonly_image),.image_size(size),.start(start),.mounted(valid_mount),.busy(busy),.error(error),.done(done),.freeze_trace(freeze),.debug_word(word),.debug_data(data),.sd_lba(lba[1]),.sd_rd(rd[1]),.sd_wr(wr[1]),.sd_ack(ack[1]),.hps_addr(haddr),.hps_dout(hout),.hps_we(hwe),.hps_din(hin[1]));
task word_out(input [15:0] v);begin @(negedge clk);host_data=v;strobe=1;@(negedge clk);strobe=0;end endtask
task begin_io;begin @(negedge clk);enable=1;end endtask
task end_io;begin @(negedge clk);enable=0;strobe=0;repeat(2)@(negedge clk);end endtask
integer i,part;reg [15:0] value;
initial begin
 repeat(3)@(negedge clk);reset=0;
 begin_io;word_out('h1d);word_out(1024);word_out(0);word_out(0);word_out(0);end_io;
 begin_io;word_out('h1c);word_out(2);end_io;
 if(!valid_mount)begin $display("FAIL HPS mount size=%d",size);$finish;end
 @(negedge clk);start=1;@(negedge clk);start=0;
 for(part=0;part<2;part=part+1)begin
  wait(wr[1]);
  begin_io;word_out('h16);#1;value=bus[15:0];if(!value[1] || value[5:2]!=1)begin $display("FAIL HPS status %h",value);$finish;end
  word_out(0);word_out(0);#1;if(bus[15:0]!==part)begin $display("FAIL HPS LBA %h",bus[15:0]);$finish;end end_io;
  begin_io;word_out('h0118);
  for(i=0;i<256;i=i+1)begin word_out(0);#1;if(bus[15:0]!==(16'h5000|(part*256+i)))begin $display("FAIL HPS data part=%0d word=%0d got=%h",part,i,bus[15:0]);$finish;end end
  end_io;
 end
 wait(done);if(error)begin $display("FAIL HPS export error");$finish;end
 $display("PASS diagnostic export through real hps_io virtual disk protocol");$finish;
end
initial begin #200000;$display("FAIL HPS timeout");$finish;end
endmodule
