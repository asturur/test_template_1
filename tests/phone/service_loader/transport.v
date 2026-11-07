// Actual hps_io byte stream and production DDR adapter; host DDR is modeled.
module service_transport (
    input wire clk, reset, use_hps,
    input wire host_strobe, host_enable,
    input wire [15:0] host_data,
    input wire direct_download, direct_wr,
    input wire [15:0] direct_index, direct_data,
    input wire [26:0] direct_addr,
    input wire mounted, save_busy, save_error,
    input wire ddr_busy,
    output wire wait_req, valid, failed, blocked,
    output wire [3:0] reason,
    output wire [28:0] ddr_addr,
    output wire [63:0] ddr_data,
    output wire [7:0] ddr_be,
    output wire ddr_we,
    output wire [31:0] decoded
);
    tri [45:0] bus;
    tri [35:0] ext;
    tri [21:0] gamma;
    assign bus[31:16] = host_data;
    assign bus[33] = host_strobe;
    assign bus[34] = 1'b0;
    assign bus[35] = host_enable;
    assign bus[45:38] = 0;
    assign ext[32] = 0;
    wire hd, hw;
    wire [15:0] hi, hdata;
    wire [26:0] ha;
    wire [31:0] sd_lba[2];
    wire [5:0] sd_count[2];
    wire [15:0] sd_in[2];
    assign sd_lba[0] = 0;
    assign sd_lba[1] = 0;
    assign sd_count[0] = 0;
    assign sd_count[1] = 0;
    assign sd_in[0] = 0;
    assign sd_in[1] = 0;
    hps_io #(.CONF_STR("test"), .WIDE(1), .VDNUM(2), .PS2DIV(1)) hps (
        .clk_sys(clk), .HPS_BUS(bus), .EXT_BUS(ext), .gamma_bus(gamma),
        .ioctl_download(hd), .ioctl_wr(hw), .ioctl_addr(ha),
        .ioctl_dout(hdata), .ioctl_index(hi), .ioctl_wait(wait_req),
        .sd_lba(sd_lba), .sd_blk_cnt(sd_count), .sd_rd(2'b0),
        .sd_wr(2'b0), .sd_buff_din(sd_in),
        .ioctl_upload_req(1'b0), .ioctl_upload_index(8'b0), .ioctl_din(16'b0),
        .status_in(128'b0), .status_set(1'b0), .status_menumask(16'b0),
        .info_req(1'b0), .info(8'b0), .video_rotated(1'b0), .new_vmode(1'b0),
        .joystick_0_rumble(16'b0), .joystick_1_rumble(16'b0),
        .joystick_2_rumble(16'b0), .joystick_3_rumble(16'b0), .joystick_4_rumble(16'b0),
        .joystick_5_rumble(16'b0)
    );
    wire download = use_hps ? hd : direct_download;
    wire wr = use_hps ? hw : direct_wr;
    wire [15:0] index = use_hps ? hi : direct_index;
    wire [15:0] data = use_hps ? hdata : direct_data;
    wire [26:0] addr = use_hps ? ha : direct_addr;
    wire accepted_download;
    ngage_bundle_gate gate (
        .clk(clk), .reset(reset),
        .request(download && (index == 0 || index == 16'h40 || index == 1 || index == 2)),
        .save_mounted(mounted), .save_busy(save_busy), .save_error(save_error),
        .download(accepted_download), .blocked(blocked)
    );
    wire mv, mr, md;
    wire [31:0] ma, mw;
    wire [3:0] mb;
    ngage_service_loader loader (
        .clk(clk), .reset(reset), .download(accepted_download),
        .ppm(index == 16'h40 || index == 2), .wr(wr), .addr(addr), .data(data),
        .wait_req(wait_req), .valid(valid), .failed(failed), .failure_reason(reason),
        .mem_valid(mv), .mem_ready(mr), .mem_addr(ma), .mem_data(mw), .mem_be(mb), .mem_done(md)
    );
    ngage_ddr_adapter adapter (
        .clk(clk), .reset(reset), .req_valid(mv), .req_ready(mr), .req_write(1'b1),
        .req_addr(ma), .req_wdata(mw), .req_be(mb), .rsp_valid(md), .rsp_data(),
        .ddr_addr(ddr_addr), .ddr_din(ddr_data), .ddr_be(ddr_be), .ddr_we(ddr_we),
        .ddr_rd(), .ddr_busy(ddr_busy), .ddr_dout(64'b0), .ddr_dout_ready(1'b0)
    );
    // Probe actual production flash-array decoding of supplied raw DDR data.
    // Address/data are driven by the host after loading to compare decoded
    // guest reads independently of the raw backing comparison.
    ngage_flash_read_decode decode (
        .physical_address({5'b0, direct_addr}), .raw_data({host_data, direct_data}),
        .array_read(1'b1), .code_flash(1'b1), .result(decoded)
    );
endmodule
