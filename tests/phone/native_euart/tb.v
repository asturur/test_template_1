`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [3:0] lanes;
    reg [31:0] program_words[0:2047];
    reg [31:0] hal_words[0:1023], poll_words[0:1023], iat_words[0:1023], driver_words[0:2047];
    reg [31:0] ram[0:32767];
    integer i, cycles = 0, delay = 0, wait_cycles = 0;
    wire access = cyc && stb;
    wire in_program = address < 8192;
    wire in_hal = address >= 32'h50324000 && address < 32'h50325000;
    wire in_poll = address >= 32'h5033c000 && address < 32'h5033d000;
    wire in_iat = address >= 32'h50348000 && address < 32'h50349000;
    wire in_driver = address >= 32'h510e8000 && address < 32'h510ea000;
    wire in_ram = address >= 32'h80000000 && address < 32'h80020000;
    wire in_uart = address >= 32'h58150000 && address < 32'h58150600;
    reg [31:0] clock_control=0;
    wire in_clock = {address[31:2],2'b0} == 32'h5814f008;
    wire claim,bad,uart_ready,irq,tv,rr;
    wire [31:0] uart_data;
    wire [7:0] td;
    integer byte_count = 0;
    wire ack = access && delay >= wait_cycles && (!in_uart || uart_ready);
    ngage_upp_euart uart (
        .clk(clk),.reset(reset),.req(access && in_uart),.commit(ack && in_uart),
        .we(write_op),.addr({8'h0c,address[23:0]}),.din(value),.sel(lanes),
        .claim(claim),.bad(bad),.ready(uart_ready),.dout(uart_data),.irq_pending(irq),
        .tx_valid(tv),.tx_ready(rr),.tx_data(td),.rx_valid(tv),.rx_ready(rr),.rx_data(td)
    );
    assign data = in_program ? program_words[address[12:2]] :
        in_hal ? hal_words[address[11:2]] : in_poll ? poll_words[address[11:2]] :
        in_iat ? iat_words[address[11:2]] : in_driver ? driver_words[address[12:2]] :
        in_ram ? ram[address[16:2]] : in_clock ? clock_control : in_uart ? uart_data : 0;
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
        if (cycles > 200000) $fatal(1,"native EUART timeout PC=%h",pc);
        if (!access || ack) delay <= 0;
        else delay <= delay + 1;
        if (tv && rr) byte_count <= byte_count + 1;
        if (ack && in_uart && bad) $fatal(1,"native EUART rejected %h PC%h",address,pc);
        if (ack && write_op) begin
            if (address == 32'hf0000000) begin
                if (value != 32'h50415353 || byte_count != 3)
                    $fatal(1,"native EUART result%h bytes%0d PC%h",value,byte_count,pc);
                $display("PASS original EUART TX/RX IRQ/HAL on HDL CPU, BRAM FIFO, count/lanes/loopback wait=%0d cycles=%0d",wait_cycles,cycles);
                $finish;
            end else if (in_ram) begin
                for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) ram[address[16:2]][i*8+:8] <= value[i*8+:8];
            end else if (in_clock) begin
                for (i=0;i<4;i=i+1) if(lanes[i]) clock_control[i*8+:8]<=value[i*8+:8];
            end else if (!in_uart) $fatal(1, "native EUART write outside map %h", address);
        end
        if (ack && !write_op && !in_program && !in_hal && !in_poll && !in_iat && !in_driver && !in_ram && !in_uart && !in_clock)
            $fatal(1, "native EUART read outside map %h PC=%h", address, pc);
    end
    initial begin
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) ram[i] = 0;
        $readmemh("build/sim/unit-native-euart/program.hex", program_words);
        $readmemh("build/sim/unit-native-euart/hal.hex", hal_words);
        $readmemh("build/sim/unit-native-euart/poll.hex", poll_words);
        $readmemh("build/sim/unit-native-euart/iat.hex", iat_words);
        $readmemh("build/sim/unit-native-euart/driver.hex", driver_words);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
