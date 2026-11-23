// Included by the pin peer and directed FIFO schedule.
wire [31:0] reference_mask, reference_data;
wire reference_busy, reference_rx_ready, reference_tx_ready;
wire [3:0] reference_irq;
wire reference_clk, reference_cmd, reference_cmd_oe, reference_dat, reference_dat_oe;
mmc_host_fifo_reference #(.DIV(DIV), .RESP_WAIT(12), .TIMEOUT_LOG2(10), .FIFO_DEPTH(FIFO_DEPTH)) reference (
    .clk(clk), .reset(reset), .acc(acc), .we(we), .wr(wr), .rd(rd), .off(off), .be(be), .wdata(wdata),
    .rmask(reference_mask), .rdata(reference_data), .busy(reference_busy),
    .rx_ready(reference_rx_ready), .tx_ready(reference_tx_ready), .irq(reference_irq),
    .mmc_clk(reference_clk), .cmd_o(reference_cmd), .cmd_oe(reference_cmd_oe), .cmd_i(cmd_i),
    .dat_o(reference_dat), .dat_oe(reference_dat_oe), .dat_i(dat_i)
);

always @(posedge clk) begin
    if (!reset && ({rmask, rdata, busy, rx_ready, tx_ready, irq, mmc_clk, cmd_oe, dat_oe} !==
            {reference_mask, reference_data, reference_busy, reference_rx_ready, reference_tx_ready,
             reference_irq, reference_clk, reference_cmd_oe, reference_dat_oe} ||
            (cmd_oe && cmd_o !== reference_cmd) || (dat_oe && dat_o !== reference_dat)))
        $fatal(1, "MMC FIFO diverged at %t data=%08x/%08x busy=%b/%b IRQ=%b/%b",
            $time, rdata, reference_data, busy, reference_busy, irq, reference_irq);
end
