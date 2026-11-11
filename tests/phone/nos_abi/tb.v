`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [3:0] lanes;
    reg [31:0] program_words[0:2047];
    reg [31:0] app_words[0:180223];
    reg [31:0] ldd_words[0:1023];
    reg [31:0] nos_words[0:1048575];
    reg [31:0] ram[0:32767];
    integer i, cycles = 0, delay = 0, wait_cycles = 0;
    integer charger_reads = 0, allocations = 0;
    wire access = cyc && stb;
    wire ack = access && delay >= wait_cycles;
    wire in_program = address < 8192;
    wire in_app = address >= 32'h50320000 && address < 32'h503d0000;
    wire in_ldd = address >= 32'h511b4000 && address < 32'h511b5000;
    wire in_nos = address >= 32'h51400000 && address < 32'h51800000;
    wire in_ram = address >= 32'h80000000 && address < 32'h80020000;
    assign data = in_program ? program_words[address[12:2]] :
        in_app ? app_words[(address - 32'h50320000) >> 2] :
        in_ldd ? ldd_words[address[11:2]] :
        in_nos ? nos_words[address[21:2]] :
        in_ram ? ram[address[16:2]] : 0;
    ngage_cpu cpu (
        .clk(clk), .reset(reset), .irq(1'b0), .fiq(1'b0),
        .wb_cyc(cyc), .wb_stb(stb), .wb_write(write_op), .wb_address(address),
        .wb_write_data(value), .wb_byte_enable(lanes), .wb_ack(ack),
        .wb_read_data(data), .wb_error(1'b0), .debug_pc(pc)
    );
    always @(posedge clk) if (!reset) begin
        cycles <= cycles + 1;
        if (cycles > 1000000) $fatal(1, "NOS ABI timeout at %h", pc);
        if (!access || ack) delay <= 0;
        else delay <= delay + 1;
        if (ack && write_op) begin
            if (address == 32'hf0000000) begin
                if (value != 32'h50415353) $fatal(1, "NOS ABI assertion %h at %h", value, pc);
                if (charger_reads != 4 || allocations != 5)
                    $fatal(1, "charger ownership reads=%0d allocations=%0d", charger_reads, allocations);
                $display("PASS original NEM-4 NOS cancel, receive/retry and charger ABI wait=%0d cycles=%0d", wait_cycles, cycles);
                $finish;
            end else if (in_ram) begin
                if (address == 32'h80000710 && value != 0) allocations <= allocations + 1;
                for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) ram[address[16:2]][i*8+:8] <= value[i*8+:8];
            end else $fatal(1, "NOS write outside fixture RAM %h", address);
        end
        if (ack && !write_op && address == 32'h58004048) charger_reads <= charger_reads + 1;
        if (ack && !write_op && !in_program && !in_app && !in_ldd && !in_nos && !in_ram && address != 32'h58004048)
            $fatal(1, "NOS read outside fixture map %h at %h", address, pc);
    end
    initial begin
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) ram[i] = 0;
        $readmemh("build/sim/unit-nos-abi/program.hex", program_words);
        $readmemh("build/sim/unit-nos-abi/app.hex", app_words);
        $readmemh("build/sim/unit-nos-abi/ldd.hex", ldd_words);
        $readmemh("build/sim/unit-nos-abi/nos.hex", nos_words);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
