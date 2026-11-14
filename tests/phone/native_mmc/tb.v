`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [ 3:0] lanes;
    reg  [31:0] program_words[0:2047];
    reg [31:0] driver_words[0:2047], boundary[0:1];
    reg [31:0] ram[0:32767];
    integer i, cycles = 0, delay = 0, wait_cycles = 0, native_result = 0;
    wire access = cyc && stb;
    wire in_program = address < 8192;
    wire in_driver = address >= 32'h503f4000 && address < 32'h503f6000;
    wire in_ram = address >= 32'h80000000 && address < 32'h80020000;
    wire in_mmc = address >= 32'h58120600 && address < 32'h58120640;
    wire in_icu = address >= 32'h58120100 && address < 32'h58120140;
    wire in_boundary=address==32'h503fc2ac||address==32'h503fc2b8||address==32'h503f826c||address==32'h503f829c;
    wire in_boundary_literal=address==32'h503fc2b0||address==32'h503fc2bc||address==32'h503f8270||address==32'h503f82a0;
    wire in_boundary_padding = address[31:12] == 20'h503f8 || address[31:12] == 20'h503fc;
    wire [31:0] mmc_data, mmc_mask, icu_data;
    wire busy, rx_ready, tx_ready, mmc_clk, cmd_o, cmd_oe, dat_o, dat_oe;
    wire [3:0] mmc_irq;
    reg        peer_cmd = 1;
    wire       ack = access && delay >= wait_cycles && (!in_mmc || !busy);
    ngage_mmc_host host (
        .clk     (clk),
        .reset   (reset),
        .acc     (access && in_mmc),
        .we      (write_op),
        .wr      (ack && in_mmc && write_op),
        .rd      (ack && in_mmc && !write_op),
        .off     (address[5:0]),
        .be      (lanes),
        .wdata   (value),
        .rmask   (mmc_mask),
        .rdata   (mmc_data),
        .busy    (busy),
        .rx_ready(rx_ready),
        .tx_ready(tx_ready),
        .irq     (mmc_irq),
        .mmc_clk (mmc_clk),
        .cmd_o   (cmd_o),
        .cmd_oe  (cmd_oe),
        .cmd_i   (cmd_oe ? cmd_o : peer_cmd),
        .dat_o   (dat_o),
        .dat_oe  (dat_oe),
        .dat_i   (1'b1)
    );
    ngage_icu #(
        .PASSIVE_STORAGE(0)
    ) icu (
        .clk         (clk),
        .reset       (reset),
        .req         (access && in_icu),
        .commit      (ack && in_icu),
        .we          (write_op),
        .addr        ({8'h0c, address[23:0]}),
        .din         (value),
        .sel         (lanes),
        .irq_pending ({71'd0, mmc_irq[3:2], 23'd0}),
        .fiq_pending (96'd0),
        .dout        (icu_data),
        .timer0_rearm(1'b0)
    );
    assign data=in_program?program_words[address[12:2]]:in_driver?driver_words[address[12:2]]:in_ram?ram[address[16:2]]:in_mmc?mmc_data:in_icu?icu_data:in_boundary?boundary[0]:in_boundary_literal?boundary[1]:0;
    ngage_cpu cpu (
        .clk           (clk),
        .reset         (reset),
        .irq           (1'b0),
        .fiq           (1'b0),
        .wb_cyc        (cyc),
        .wb_stb        (stb),
        .wb_write      (write_op),
        .wb_address    (address),
        .wb_write_data (value),
        .wb_byte_enable(lanes),
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
    always @(posedge clk)
        if (!reset) begin
            cycles <= cycles + 1;
            if (cycles > 200000) $fatal(1, "native MMC timeout PC=%h", pc);
            if (!access || ack) delay <= 0;
            else delay <= delay + 1;
            if (ack && write_op) begin
                if (address == 32'hf0000004) native_result <= value;
                else if (address == 32'hf0000000) begin
                    if (value !== 32'h50415353)
                        $fatal(
                            1,
                            "native MMC failure result=%h native=%h PC=%h",
                            value,
                            native_result,
                            pc
                        );
                    $display(
                        "PASS original EPBUS R2 FSM/event/status functions: delayed IRQ, exact128-bit CID, wait=%0d clocks=%0d",
                        wait_cycles, cycles);
                    $finish;
                end else if (in_ram) begin
                    for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) ram[address[16:2]][i*8+:8] <= value[i*8+:8];
                end else if (!in_mmc && !in_icu)
                    $fatal(1, "unexpected native MMC write %h PC=%h", address, pc);
            end
            if(ack&&!write_op&&!in_program&&!in_driver&&!in_ram&&!in_mmc&&!in_icu&&!in_boundary&&!in_boundary_literal&&!in_boundary_padding)
                $fatal(1, "unexpected native MMC read %h PC=%h", address, pc);
        end
    reg     [ 47:0] command_bits;
    reg     [135:0] response_bits;
    integer         bit_index;
    initial begin
        wait (cmd_oe);
        command_bits = 0;
        for (bit_index = 0; bit_index < 48; bit_index = bit_index + 1) begin
            @(posedge mmc_clk);
            command_bits = {command_bits[46:0], cmd_o};
        end
        if (command_bits[45:40] !== 2 || command_bits[39:8] !== 0)
            $fatal(1, "unexpected wire command %h", command_bits);
        wait (!cmd_oe);
        repeat (5) @(posedge mmc_clk);
        response_bits = {2'b00, 6'h3f, 128'h00112233445566778899aabbccddee91};
        for (bit_index = 135; bit_index >= 0; bit_index = bit_index - 1) begin
            @(negedge mmc_clk);
            peer_cmd = response_bits[bit_index];
        end
        @(negedge mmc_clk);
        peer_cmd = 1;
    end
    initial begin
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) ram[i] = 0;
        $readmemh("build/sim/unit-native-mmc/program.hex", program_words);
        $readmemh("build/sim/unit-native-mmc/driver.hex", driver_words);
        $readmemh("build/sim/unit-native-mmc/boundary.hex", boundary);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
