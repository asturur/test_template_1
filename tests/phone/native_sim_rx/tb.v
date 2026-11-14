`timescale 1ns / 1ps
// Original SIM RX callback on actual ZAP, with either an authored byte FIFO
// or production SIMIF/card. Scheduler import is a no-op fixture leaf.
module tb;
    reg clk = 0, reset = 1;
    real half_period = 6.410256;
    always #(half_period) clk = ~clk;
    wire cyc, stb, we;
    wire [31:0] adr, din, pc;
    wire [3:0] sel;
    reg [31:0] code[0:1023], native[0:1023], ram[0:262143];
    reg [31:0] data;
    integer cycles = 0, delay = 0, wait_cycles = 0, cached = 0, reads = 0, real_card = 0, i;
    wire access = cyc && stb;
    wire peripheral = adr[31:16] == 16'h5815;
    wire board_ready, board_claim, board_bad, board_init;
    wire [31:0] board_data;
    wire        ack = access && delay >= wait_cycles && (!real_card || !peripheral || board_ready);
    ngage_board #(
        .SIMIF_ENABLE   (1),
        .TEST_SIM_ENABLE(1),
        .SYS_CLK_HZ     (78000000)
    ) board (
        .clk            (clk),
        .rst            (reset),
        .init_rst       (reset),
        .cyc            (access && peripheral && real_card != 0),
        .stb            (access && peripheral && real_card != 0),
        .commit         (ack && peripheral && real_card != 0),
        .we             (we),
        .adr            ({8'h0c, adr[23:0]}),
        .din            (din),
        .sel            (sel),
        .cfg_lcd        (1'b0),
        .cfg_keypad     (1'b1),
        .cfg_clocks     (1'b1),
        .dma_irq_pending(1'b0),
        .sim_fiq_pending(1'b0),
        .keys           (27'b0),
        .sim_present    (1'b1),
        .adsp_tx_ready  (1'b0),
        .adsp_rx_valid  (1'b0),
        .adsp_rx_data   (8'b0),
        .claim          (board_claim),
        .ready          (board_ready),
        .unmodeled      (board_bad),
        .dout           (board_data),
        .init_done      (board_init)
    );
    wire mem = (adr[31:20] == 12'h800) || (adr[31:20] == 12'h0a0);
    ngage_cpu cpu (
        .clk           (clk),
        .reset         (reset),
        .irq           (1'b0),
        .fiq           (1'b0),
        .wb_cyc        (cyc),
        .wb_stb        (stb),
        .wb_write      (we),
        .wb_address    (adr),
        .wb_write_data (din),
        .wb_byte_enable(sel),
        .wb_ack        (ack),
        .wb_read_data  (data),
        .wb_error      (1'b0),
        .debug_pc      (pc),
        .line_ready    (1'b0),
        .line_reject   (1'b0),
        .line_valid    (1'b0),
        .line_data     (64'b0),
        .line_wide     (1'b0),
        .line_last     (1'b0),
        .line_error    (1'b0)
    );
    always @* begin
        data = 0;
        if (adr < 4096) data = code[adr[11:2]];
        else if (adr[31:12] == 20'h51635) data = native[adr[11:2]];
        else if (adr[31:12] == 20'h516c7) data = 32'h47704770;
        else if (mem) data = ram[adr[19:2]];
        else if (peripheral && real_card != 0) data = board_data;
        else if (adr == 32'h5815080c) data = reads == 0 ? 32'h9f : 32'h16;
        else if (adr == 32'hf0000004) data = cached;
        else if (adr == 32'hf000000c) data = real_card;
    end
    always @(posedge clk)
        if (!reset) begin
            cycles <= cycles + 1;
            if (cycles > 300000) $fatal(1, "native SIM RX timeout pc=%h adr=%h", pc, adr);
            if (!access || ack) delay <= 0;
            else delay <= delay + 1;
            if (ack) begin
                if (real_card != 0 && peripheral && (!board_claim || board_bad))
                    $fatal(1, "production SIMIF rejected %h", adr);
                if (!we && adr == 32'h5815080c) begin
                    if (reads >= (real_card != 0 ? 5 : 2) || sel != 3)
                        $fatal(1, "SIM FIFO read count/lanes");
                    reads <= reads + 1;
                end
                if (we) begin
                    if (mem) begin
                        for (i = 0; i < 4; i = i + 1)
                        if (sel[i]) ram[adr[19:2]][8*i+:8] <= din[8*i+:8];
                    end else if (adr == 32'hf0000008) $display("NATIVE_SIM_RX_BUFFER %h", din);
                    else if (adr == 32'hf0000000) begin
                        if (din != 32'h50415353 || reads != (real_card != 0 ? 5 : 2))
                            $fatal(1, "native SIM RX result%h reads%0d", din, reads);
                        $display(
                            "PASS original SIM RX on ZAP card=%0d cache=%0d wait=%0d cycles=%0d",
                            real_card, cached, wait_cycles, cycles);
                        $finish;
                    end else if (!(real_card != 0 && peripheral) && adr != 32'h58150008)
                        $fatal(1, "unmapped SIM write adr%h pc%h", adr, pc);
                end else if(!mem&&adr>=4096&&adr[31:12]!=20'h51635&&adr[31:12]!=20'h516c7&&adr!=32'h5815080c&&adr!=32'hf0000004&&adr!=32'hf000000c&&!(real_card!=0&&peripheral))
                    $fatal(1, "unmapped SIM read adr%h pc%h", adr, pc);
            end
        end
    initial begin
        if ($value$plusargs("half_period=%f", half_period)) begin
        end
        if ($value$plusargs("wait=%d", wait_cycles)) begin
        end
        if ($value$plusargs("card=%d", real_card)) begin
        end
        if ($value$plusargs("cached=%d", cached)) begin
        end
        for (i = 0; i < 262144; i = i + 1) ram[i] = 0;
        $readmemh("build/sim/unit-native-sim-rx/program.hex", code);
        $readmemh("build/sim/unit-native-sim-rx/native.hex", native);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
