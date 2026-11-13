`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [3:0] lanes;
    reg [31:0] program_words[0:2047];
    reg [31:0] original_words[0:1023];
    reg [31:0] ram[0:32767];
    integer i, cycles = 0, delay = 0, wait_cycles = 0;
    integer input_writes = 0, replies = 0;
    reg [3:0] tick_count = 0;
    wire access = cyc && stb;
    wire ack = access && delay >= wait_cycles && (!in_mdi || mdi_ready);
    wire in_program = address < 8192;
    wire in_original = address >= 32'h515bf000 && address < 32'h515c0000;
    wire in_ram = address >= 32'h80000000 && address < 32'h80020000;
    wire in_mdi = (address >= 32'h0c100000 && address < 32'h0c1003f0) || address == 32'h0c14b004;
    wire claim, bad, mdi_ready;
    wire [31:0] mdi_data;
    wire [15:0] mdi_events;
    ngage_upp_mdi #(.ANNOUNCE_TICKS(2)) mdi (
        .clk(clk),.reset(reset),.tick(tick_count==15),.periodic_active(1'b1),
        .req(access && in_mdi),.commit(ack && in_mdi),.we(write_op),
        .addr(address),.din(value),.sel(lanes),.claim(claim),.bad(bad),
        .ready(mdi_ready),.dout(mdi_data),.irq_events(mdi_events)
    );
    assign data = in_program ? program_words[address[12:2]] :
        in_original ? original_words[address[11:2]] :
        in_ram ? ram[address[16:2]] : in_mdi ? mdi_data : 0;
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
        if (cycles > 200000) $fatal(1, "native MDI timeout PC=%h", pc);
        if (!access || ack) delay <= 0;
        else delay <= delay + 1;
        tick_count <= tick_count + 1'b1;
        if (mdi_events[10]) replies <= replies + 1;
        if (ack && in_mdi) begin
            if (!claim || bad) $fatal(1,"native MDI rejected %h PC=%h",address,pc);
            if (write_op && address>=32'h0c100000 && address<32'h0c1001f4) input_writes<=input_writes+1;
        end
        if (ack && write_op) begin
            if (address == 32'hf0000000) begin
                if (value != 32'h50415353 || input_writes != 6 || replies != 2)
                    $fatal(1,"native MDI result%h input stores%0d replies%0d PC%h",value,input_writes,replies,pc);
                $display("PASS original MDI TX/RX/availability on HDL CPU, native byte order, BRAM ownership and DSP-version reply wait=%0d cycles=%0d",wait_cycles,cycles);
                $finish;
            end else if (in_ram) begin
                for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) ram[address[16:2]][i*8+:8] <= value[i*8+:8];
            end else if (!in_mdi) $fatal(1, "native MDI write outside map %h", address);
        end
        if (ack && !write_op && !in_program && !in_original && !in_ram && !in_mdi)
            $fatal(1, "native MDI read outside map %h PC=%h", address, pc);
    end
    initial begin
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) ram[i] = 0;
        $readmemh("build/sim/unit-native-mdi/program.hex", program_words);
        $readmemh("build/sim/unit-native-mdi/original.hex", original_words);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
