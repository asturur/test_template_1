`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1;
    real half_period = 6.410256;
    initial
        if ($value$plusargs("half_period=%f", half_period)) begin
        end
    always #(half_period) clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [ 3:0] lanes;
    reg  [31:0] program_words[0:2047];
    reg [31:0] original_words[0:262143], driver_words[0:2047];
    reg [31:0] ram[0:32767];
    integer i, cycles = 0, delay = 0, wait_cycles = 0;
    wire        access = cyc && stb;
    wire        in_program = address < 8192;
    wire        in_original = address >= 32'h50300000 && address < 32'h50400000;
    wire        in_driver = address >= 32'h510e8000 && address < 32'h510ea000;
    wire        in_ram = address >= 32'h80000000 && address < 32'h80020000;
    wire        in_uart = address >= 32'h58150000 && address < 32'h58150600;
    reg  [31:0] clock_control = 0;
    wire        in_clock = {address[31:2], 2'b0} == 32'h5814f008;
    wire claim, bad, uart_ready, irq, tv, rr;
    wire    [31:0] uart_data;
    wire    [ 7:0] td;
    integer        byte_count = 0;
    wire           ack = access && delay >= wait_cycles && (!peripheral || board_ready);
    wire board_ready, board_claim, board_bad, board_fiq, board_init;
    wire [31:0] board_data;
    wire        peripheral = in_uart || in_clock || address[31:16] == 16'h0c12;
    wire [31:0] physical = address[31:24] == 8'h58 ? {8'h0c, address[23:0]} : address;
    ngage_board board (
        .clk            (clk),
        .rst            (reset),
        .init_rst       (reset),
        .cyc            (access && peripheral),
        .stb            (access && peripheral),
        .commit         (ack && peripheral),
        .we             (write_op),
        .adr            (physical),
        .din            (value),
        .sel            (lanes),
        .cfg_lcd        (1'b0),
        .cfg_keypad     (1'b1),
        .cfg_clocks     (1'b1),
        .dma_irq_pending(1'b0),
        .sim_fiq_pending(1'b0),
        .keys           (27'b0),
        .sim_present    (1'b0),
        .adsp_tx_valid  (tv),
        .adsp_tx_ready  (1'b0),
        .adsp_tx_data   (td),
        .adsp_rx_valid  (1'b0),
        .adsp_rx_ready  (rr),
        .adsp_rx_data   (8'b0),
        .claim          (board_claim),
        .ready          (board_ready),
        .unmodeled      (board_bad),
        .dout           (board_data),
        .fiq            (board_fiq),
        .init_done      (board_init)
    );
    assign data = in_program ? program_words[address[12:2]] :
        in_original ? original_words[address[19:2]] : in_driver ? driver_words[address[12:2]] :
        in_ram ? ram[address[16:2]] : peripheral ? board_data : 0;
    ngage_cpu cpu (
        .clk           (clk),
        .reset         (reset || !board_init),
        .irq           (1'b0),
        .fiq           (board_fiq),
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
            if (cycles > 200000) $fatal(1, "native EUART timeout PC=%h", pc);
            if (!access || ack) delay <= 0;
            else delay <= delay + 1;
            if (tv && board.peer_tx_ready) byte_count <= byte_count + 1;
            if (ack && peripheral && (!board_claim || board_bad))
                $fatal(1, "native EUART rejected %h PC%h", address, pc);
            if (ack && write_op) begin
                if (address == 32'hf0000000) begin
                    if (value != 32'h50415353 || byte_count != 36)
                        $fatal(1, "native EUART result%h bytes%0d PC%h", value, byte_count, pc);
                    $write("NATIVE_RX ");
                    for (i = 0; i < 62; i = i + 1)
                    $write("%02x", (ram[(32'h6000+i)>>2] >> ((i % 4) * 8)) & 255);
                    $write("\n");
                    if (!board.audio_boot.d550.link_ready || !board.audio_boot.n501.reset_seen)
                        $fatal(1, "device startup/codec reset incomplete");
                    if (board.bringup_status[11:8] !== 4'b0111)
                        $fatal(1, "passive ADSP status missing native completion");
                    $display(
                        "PASS production D550 boot peer with original CBUS/UART TX/RX/HAL, CPU FIQ26 and diagnostic8B wait=%0d cycles=%0d",
                        wait_cycles, cycles);
                    $finish;
                end else if (in_ram) begin
                    for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) ram[address[16:2]][i*8+:8] <= value[i*8+:8];
                end else if (in_clock) begin
                    for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) clock_control[i*8+:8] <= value[i*8+:8];
                end else if (!peripheral) $fatal(1, "native EUART write outside map %h", address);
            end
            if (ack && !write_op && !in_program && !in_original && !in_driver && !in_ram && !peripheral)
                $fatal(1, "native EUART read outside map %h PC=%h", address, pc);
        end
    initial begin
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) ram[i] = 0;
        $readmemh("build/sim/unit-native-adsp-boot/program.hex", program_words);
        $readmemh("build/sim/unit-native-adsp-boot/original.hex", original_words);
        $readmemh("build/sim/unit-native-adsp-boot/driver.hex", driver_words);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
