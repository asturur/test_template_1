// Actual hps_io transport and overlay/DDR adapter; CPU and DDR device are modeled.
module overlay_transport (
    input wire clk, reset, host_strobe, host_enable,
    input wire [15:0] host_data,
    input wire firmware_valid, enabled,
    output wire wait_req, ready, loaded, applied,
    output wire [3:0] error,
    input wire ddr_busy, ddr_ready,
    input wire [63:0] ddr_q,
    output wire [28:0] ddr_addr,
    output wire [63:0] ddr_data,
    output wire [7:0] ddr_be,
    output wire ddr_we, ddr_rd
);
    tri [45:0] bus;
    tri [35:0] ext;
    tri [21:0] gamma;
    assign bus[31:16]=host_data;
    assign bus[33]=host_strobe;
    assign bus[34]=0;
    assign bus[35]=host_enable;
    assign bus[45:38]=0;
    assign ext[32]=0;
    wire download, wr;
    wire [15:0] index, data;
    wire [26:0] addr;
    wire [31:0] sd_lba[2];
    wire [5:0] sd_count[2];
    wire [15:0] sd_in[2];
    assign sd_lba[0]=0;assign sd_lba[1]=0;
    assign sd_count[0]=0;assign sd_count[1]=0;
    assign sd_in[0]=0;assign sd_in[1]=0;
    hps_io #(.CONF_STR("test"),.WIDE(1),.VDNUM(2),.PS2DIV(1)) hps (
        .clk_sys(clk),.HPS_BUS(bus),.EXT_BUS(ext),.gamma_bus(gamma),
        .ioctl_download(download),.ioctl_wr(wr),.ioctl_addr(addr),
        .ioctl_dout(data),.ioctl_index(index),.ioctl_wait(wait_req),
        .sd_lba(sd_lba),.sd_blk_cnt(sd_count),.sd_rd(2'b0),
        .sd_wr(2'b0),.sd_buff_din(sd_in),
        .ioctl_upload_req(1'b0),.ioctl_upload_index(8'b0),.ioctl_din(16'b0),
        .status_in(128'b0),.status_set(1'b0),.status_menumask(16'b0),
        .info_req(1'b0),.info(8'b0),.video_rotated(1'b0),.new_vmode(1'b0),
        .joystick_0_rumble(16'b0),.joystick_1_rumble(16'b0),
        .joystick_2_rumble(16'b0),.joystick_3_rumble(16'b0),
        .joystick_4_rumble(16'b0),.joystick_5_rumble(16'b0)
    );
    wire req, accept, write, done;
    wire [31:0] target, value, response;
    ngage_nos_overlay overlay (
        .clk(clk),.reset(reset),.firmware_valid(firmware_valid),.firmware_loading(1'b0),
        .enabled(enabled),.blocked(1'b0),
        .download(download && (index==16'h80 || index==3)),
        .wr(wr),.addr(addr),.data(data),.wait_req(wait_req),
        .ready(ready),.loaded(loaded),.applied(applied),.busy(),.error(error),
        .mem_valid(req),.mem_ready(accept),.mem_write(write),.mem_addr(target),
        .mem_data(value),.mem_done(done),.mem_rdata(response)
    );
    ngage_ddr_adapter adapter (
        .clk(clk),.reset(reset),.req_valid(req),.req_ready(accept),.req_write(write),
        .req_addr(target),.req_wdata(value),.req_be(4'hf),.rsp_valid(done),.rsp_data(response),
        .ddr_addr(ddr_addr),.ddr_din(ddr_data),.ddr_be(ddr_be),.ddr_we(ddr_we),
        .ddr_rd(ddr_rd),.ddr_busy(ddr_busy),.ddr_dout(ddr_q),.ddr_dout_ready(ddr_ready)
    );
endmodule
