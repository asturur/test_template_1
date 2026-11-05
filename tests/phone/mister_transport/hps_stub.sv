// Elaboration-only HPS substitute; the real hps_io is not simulated here.
module hps_io #(parameter CONF_STR="", parameter WIDE=0)(
 input clk_sys, inout [48:0] HPS_BUS, inout [35:0] EXT_BUS, inout [21:0] gamma_bus,
 output forced_scandoubler, output [1:0] buttons, output [127:0] status, input [15:0] status_menumask,
 output [10:0] ps2_key, output [31:0] joystick_0, output ioctl_download, output ioctl_wr,
 output [26:0] ioctl_addr, output [15:0] ioctl_dout, output [15:0] ioctl_index,
 input ioctl_wait, output ioctl_upload, input ioctl_upload_req, input [7:0] ioctl_upload_index,
 input [15:0] ioctl_din, output ioctl_rd);
assign {forced_scandoubler,buttons,status,ps2_key,joystick_0,ioctl_download,ioctl_wr,ioctl_addr,ioctl_dout,ioctl_index,ioctl_upload,ioctl_rd}=0;
endmodule
