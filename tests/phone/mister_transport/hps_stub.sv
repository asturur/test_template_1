// Elaboration-only HPS substitute; the real hps_io is not simulated here.
module hps_io #(parameter CONF_STR="", parameter WIDE=0, parameter VDNUM=1)(
 input clk_sys, inout [45:0] HPS_BUS, inout [35:0] EXT_BUS, inout [21:0] gamma_bus,
 output forced_scandoubler, output [1:0] buttons, output [127:0] status, input [15:0] status_menumask,
 output [10:0] ps2_key, output [31:0] joystick_0, output ioctl_download, output ioctl_wr,
 output [26:0] ioctl_addr, output [15:0] ioctl_dout, output [15:0] ioctl_index,
 output [VDNUM-1:0] img_mounted, output img_readonly, output [63:0] img_size,
 input [31:0] sd_lba[VDNUM], input [5:0] sd_blk_cnt[VDNUM], input [VDNUM-1:0] sd_rd,sd_wr, output [VDNUM-1:0] sd_ack,
 output [12:0] sd_buff_addr,output [15:0] sd_buff_dout,input [15:0] sd_buff_din[VDNUM],output sd_buff_wr,
 input ioctl_wait, output ioctl_upload, input ioctl_upload_req, input [7:0] ioctl_upload_index,
 input [15:0] ioctl_din, output ioctl_rd);
assign {forced_scandoubler,buttons,status,ps2_key,joystick_0,ioctl_download,ioctl_wr,ioctl_addr,ioctl_dout,ioctl_index,ioctl_upload,ioctl_rd,img_mounted,img_readonly,img_size,sd_ack,sd_buff_addr,sd_buff_dout,sd_buff_wr}=0;
endmodule
