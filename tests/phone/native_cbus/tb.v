`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [3:0] lanes;
    reg [31:0] program_words[0:2047];
    reg [31:0] original_words[0:262143];
    reg [31:0] ram[0:32767];
    integer i, cycles = 0, delay = 0, wait_cycles = 0;
    integer status_reads = 0, writes = 0;
    wire access = cyc && stb;
    wire ack = access && delay >= wait_cycles;
    wire in_program = address < 8192;
    wire in_original = address >= 32'h50300000 && address < 32'h50400000;
    wire in_ram = address >= 32'h80000000 && address < 32'h80020000;
    // Match the phone's observed HAL mapping at this unit-test boundary.
    // Native 503245FC/50324608 execute unchanged; MMU is outside this fixture.
    wire in_cbus = address >= 32'h58150420 && address < 32'h58150428;
    wire claim, bad, irq;
    wire [31:0] cbus_data;
    wire [15:0] route3b;
    wire [31:0] physical = 32'h0c000000 | {8'b0, address[23:0]};
    ngage_cbus_uem cbus (
        .clk(clk), .reset(reset), .req(access && in_cbus),
        .commit(ack && in_cbus), .we(write_op), .addr(physical),
        .din(value), .sel(lanes), .kernel_periodic(1'b0), .clear_irq(1'b0),
        .claim(claim), .bad(bad), .dout(cbus_data), .irq_pending(irq),
        .route2a(), .route2c(), .route3b(route3b), .cbus8d_written(),
        .power_pressed(1'b0)
    );
    assign data = in_program ? program_words[address[12:2]] :
        in_original ? original_words[address[19:2]] :
        in_ram ? ram[address[16:2]] : in_cbus ? cbus_data : 0;
    ngage_cpu cpu (
        .clk(clk), .reset(reset), .irq(1'b0), .fiq(1'b0),
        .wb_cyc(cyc), .wb_stb(stb), .wb_write(write_op), .wb_address(address),
        .wb_write_data(value), .wb_byte_enable(lanes), .wb_ack(ack),
        .wb_read_data(data), .wb_error(1'b0), .debug_pc(pc),
        .line_ready(1'b0), .line_reject(1'b0), .line_valid(1'b0),
        .line_data(64'b0), .line_wide(1'b0), .line_last(1'b0), .line_error(1'b0)
    );
    always @(posedge clk) if (!reset) begin
        cycles <= cycles + 1;
        if (cycles > 200000) $fatal(1, "native CBUS timeout PC=%h", pc);
        if (!access || ack) delay <= 0;
        else delay <= delay + 1;
        if (ack && in_cbus) begin
            if (!claim || bad) $fatal(1, "native CBUS rejected %h we=%b lanes=%h PC=%h", address, write_op, lanes, pc);
            if (write_op) writes <= writes + 1;
            else begin
                status_reads <= status_reads + 1;
                if (!cbus_data[26]) $fatal(1, "native idle/completion poll not ready");
            end
        end
        if (ack && write_op) begin
            if (address == 32'hf0000000) begin
                if (value != 32'h50415353 || status_reads != 2 || writes != 3 || route3b != 16'h1234)
                    $fatal(1, "native CBUS result=%h reads=%0d writes=%0d route=%h", value, status_reads, writes, route3b);
                $display("PASS original NEM-4 CPU/CBUS transfer, unchanged HAL, reset-idle/completion and payload wait=%0d cycles=%0d", wait_cycles, cycles);
                $finish;
            end else if (in_ram) begin
                for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) ram[address[16:2]][i*8+:8] <= value[i*8+:8];
            end else if (!in_cbus) $fatal(1, "native CBUS write outside map %h", address);
        end
        if (ack && !write_op && !in_program && !in_original && !in_ram && !in_cbus)
            $fatal(1, "native CBUS read outside map %h PC=%h", address, pc);
    end
    initial begin
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) ram[i] = 0;
        $readmemh("build/sim/unit-native-cbus/program.hex", program_words);
        $readmemh("build/sim/unit-native-cbus/original.hex", original_words);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
