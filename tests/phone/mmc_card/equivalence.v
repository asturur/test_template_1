// Public-output lockstep peer for the unchanged donor C++ wire/HPS suite.
// Inactive bus data and unowned HPS buffer contents are intentionally ignored.
module mmc_card_equivalence (
    input wire clk,
    input wire reset,
    input wire mmc_clk,
    input wire cmd_i,
    output wire cmd_o,
    output wire cmd_oe,
    input wire dat_i,
    output wire dat_o,
    output wire dat_oe,
    input wire stop_queued,
    output wire present,
    output wire write_protected,
    output wire active,
    input wire img_mounted,
    input wire img_readonly,
    input wire [63:0] img_size,
    output wire [31:0] sd_lba,
    output wire [ 5:0] sd_blk_cnt,
    output wire sd_rd,
    output wire sd_wr,
    input wire sd_ack,
    input wire [12:0] sd_buff_addr,
    input wire [15:0] sd_buff_dout,
    output wire [15:0] sd_buff_din,
    input wire sd_buff_wr
);
    wire reference_cmd_o;
    wire reference_cmd_oe;
    wire reference_dat_o;
    wire reference_dat_oe;
    wire reference_present;
    wire reference_write_protected;
    wire reference_active;
    wire [31:0] reference_sd_lba;
    wire [ 5:0] reference_sd_blk_cnt;
    wire reference_sd_rd;
    wire reference_sd_wr;
    wire [15:0] reference_sd_buff_din;
    ngage_mmc_card ported (
        .clk(clk),
        .reset(reset),
        .mmc_clk(mmc_clk),
        .cmd_i(cmd_i),
        .cmd_o(cmd_o),
        .cmd_oe(cmd_oe),
        .dat_i(dat_i),
        .dat_o(dat_o),
        .dat_oe(dat_oe),
        .stop_queued(stop_queued),
        .present(present),
        .write_protected(write_protected),
        .active(active),
        .img_mounted(img_mounted),
        .img_readonly(img_readonly),
        .img_size(img_size),
        .sd_lba(sd_lba),
        .sd_blk_cnt(sd_blk_cnt),
        .sd_rd(sd_rd),
        .sd_wr(sd_wr),
        .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr),
        .sd_buff_dout(sd_buff_dout),
        .sd_buff_din(sd_buff_din),
        .sd_buff_wr(sd_buff_wr)
    );
    mmc_card reference (
        .clk(clk),
        .reset(reset),
        .mmc_clk(mmc_clk),
        .cmd_i(cmd_i),
        .cmd_o(reference_cmd_o),
        .cmd_oe(reference_cmd_oe),
        .dat_i(dat_i),
        .dat_o(reference_dat_o),
        .dat_oe(reference_dat_oe),
        .stop_queued(stop_queued),
        .present(reference_present),
        .write_protected(reference_write_protected),
        .active(reference_active),
        .img_mounted(img_mounted),
        .img_readonly(img_readonly),
        .img_size(img_size),
        .sd_lba(reference_sd_lba),
        .sd_blk_cnt(reference_sd_blk_cnt),
        .sd_rd(reference_sd_rd),
        .sd_wr(reference_sd_wr),
        .sd_ack(sd_ack),
        .sd_buff_addr(sd_buff_addr),
        .sd_buff_dout(sd_buff_dout),
        .sd_buff_din(reference_sd_buff_din),
        .sd_buff_wr(sd_buff_wr)
    );
    reg hps_write = 0;
    always @(posedge clk) begin
        if (reset) hps_write <= 0;
        else begin
            if (sd_wr) hps_write <= 1;
            if (sd_rd) hps_write <= 0;
            if (present !== reference_present) begin
                $display("FAIL MMC donor/port lockstep: presence");
                $finish(1);
            end
            if (active !== reference_active) begin
                $display("FAIL MMC donor/port lockstep: active");
                $finish(1);
            end
            if (present && write_protected !== reference_write_protected) begin
                $display("FAIL MMC donor/port lockstep: write protection");
                $finish(1);
            end
            if (cmd_oe !== reference_cmd_oe || (cmd_oe && cmd_o !== reference_cmd_o)) begin
                $display("FAIL MMC donor/port lockstep: CMD wire");
                $finish(1);
            end
            if (dat_oe !== reference_dat_oe || (dat_oe && dat_o !== reference_dat_o)) begin
                $display("FAIL MMC donor/port lockstep: DAT wire");
                $finish(1);
            end
            if (sd_rd !== reference_sd_rd || sd_wr !== reference_sd_wr) begin
                $display("FAIL MMC donor/port lockstep: HPS request");
                $finish(1);
            end
            if ((sd_rd || sd_wr) && (sd_lba !== reference_sd_lba || sd_blk_cnt !== reference_sd_blk_cnt)) begin
                $display("FAIL MMC donor/port lockstep: HPS extent");
                $finish(1);
            end
            if (active && sd_ack && hps_write && sd_buff_din !== reference_sd_buff_din) begin
                $display("FAIL MMC donor/port lockstep: HPS write bytes");
                $finish(1);
            end
        end
    end
endmodule
