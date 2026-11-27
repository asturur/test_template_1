`timescale 1ns / 1ps
// Original CPU instructions and candidate DMA model, with bounded test memories.
// The exact MMC-style address is intercepted ONLY here: the production router
// intentionally rejects it until the real endpoint contract is implemented.
module tb;
    parameter PRODUCTION_PROFILE = 0;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [ 3:0] lanes;
    reg  [31:0] program_words[  0:2047];
    reg  [31:0] app_words    [0:180223];
    reg  [31:0] kernel_ram   [ 0:32767];
    reg  [ 7:0] ram          [  0:4095];
    reg  [ 7:0] chip         [  0:4095];
    reg  [ 7:0] sent         [    0:15];
    integer i, j, cycles = 0, delay = 0, wait_cycles = 0;
    integer checked = 0, starts = 0, selectors = 0, sent_count = 0, received_count = 0;
    integer dma_delay = 0, local_delay = 0, fifo_delay = 0;
    reg local_busy = 0, fifo_busy = 0, fifo_write = 0;
    reg  [7:0] fifo_byte;
    wire       access = cyc && stb;
    wire       ack = access && delay >= wait_cycles && (!(in_dma || selector) || dma_ready);
    wire       in_program = address < 8192;
    wire       in_app = address >= 32'h50320000 && address < 32'h503d0000;
    wire       in_kernel_ram = address >= 32'h80000000 && address < 32'h80020000;
    wire       in_dma = address >= 32'h58120300 && address < 32'h58120500;
    wire       selector = address == 32'h58120064 || address == 32'h58120068;
    wire claim, bad, dma_ready;
    wire [31:0] dma_data;
    wire [7:0] irq, errors, active;
    wire cmd_valid, cmd_ready, cmd_write, rsp_valid, rsp_error;
    wire [31:0] cmd_addr, cmd_data, rsp_data;
    wire [3:0] cmd_be;
    wire route_ready, route_rsp, route_error;
    wire [31:0] route_data;
    wire        fifo_hit = cmd_addr == 32'h10120624;
    wire        fifo_take = cmd_valid && cmd_ready && fifo_hit;
    wire        fifo_done = fifo_busy && fifo_delay >= wait_cycles + 2;
    assign cmd_ready = fifo_hit ? !fifo_busy && route_ready : route_ready && !fifo_busy;
    assign rsp_valid = fifo_done || route_rsp;
    assign rsp_error = route_error;
    assign rsp_data  = fifo_done ? {24'd0, (8'hc0 + received_count[7:0])} : route_data;
    wire ram_req, ram_write, ram_ack;
    wire [24:0] ram_addr;
    wire [31:0] ram_data;
    wire [ 3:0] ram_be;
    wire [11:0] rbase = ram_addr[11:0];
    wire [31:0] ram_rdata = {ram[rbase+3], ram[rbase+2], ram[rbase+1], ram[rbase]};
    assign ram_ack = ram_req && dma_delay >= wait_cycles + 1;
    wire local_valid, local_write;
    wire [31:0] local_addr, local_data;
    wire [ 3:0] local_be;
    wire        local_done = local_busy && local_delay >= wait_cycles + 1;
    wire [11:0] lbase = local_addr[11:0];
    wire [31:0] local_rdata = {chip[lbase+3], chip[lbase+2], chip[lbase+1], chip[lbase]};

    assign data = in_program ? program_words[address[12:2]] :
        in_app ? app_words[(address - 32'h50320000) >> 2] :
        in_kernel_ram ? kernel_ram[address[16:2]] : (in_dma || selector) ? dma_data : 0;
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
        .debug_pc      (pc)
    );
    ngage_dma_channels #(
        .PRODUCTION(PRODUCTION_PROFILE),
        .ENGINES   (PRODUCTION_PROFILE ? 2 : 3)
    ) dut (
        .clk              (clk),
        .reset            (reset),
        .req              (access && (in_dma || selector)),
        .commit           (ack && (in_dma || selector)),
        .we               (write_op),
        .addr             (address - 32'h4c000000),
        .din              (value),
        .sel              (lanes),
        .claim            (claim),
        .bad              (bad),
        .dout             (dma_data),
        .ready            (dma_ready),
        .irq_pending      (irq),
        .error_pending    (errors),
        .active_channels  (active),
        .lcd_ready        (1'b1),
        .lcd_drained      (1'b1),
        .mmc_ready        (!fifo_busy),
        .mmc_rx_ready     (!fifo_busy),
        .mmc_tx_ready     (!fifo_busy),
        .source_ready     (8'hff),
        .destination_ready(8'hff),
        .cmd_valid        (cmd_valid),
        .cmd_ready        (cmd_ready),
        .cmd_write        (cmd_write),
        .cmd_addr         (cmd_addr),
        .cmd_data         (cmd_data),
        .cmd_be           (cmd_be),
        .rsp_valid        (rsp_valid),
        .rsp_error        (rsp_error),
        .rsp_data         (rsp_data)
    );
    ngage_dma_route route (
        .clk        (clk),
        .reset      (reset),
        .cpu_lock   (1'b0),
        .cmd_valid  (cmd_valid && !fifo_hit && !fifo_busy),
        .cmd_ready  (route_ready),
        .cmd_write  (cmd_write),
        .cmd_addr   (cmd_addr),
        .cmd_data   (cmd_data),
        .cmd_be     (cmd_be),
        .rsp_valid  (route_rsp),
        .rsp_error  (route_error),
        .rsp_data   (route_data),
        .ram_req    (ram_req),
        .ram_write  (ram_write),
        .ram_addr   (ram_addr),
        .ram_data   (ram_data),
        .ram_be     (ram_be),
        .ram_ack    (ram_ack),
        .ram_rdata  (ram_rdata),
        .local_valid(local_valid),
        .local_ready(!local_busy),
        .local_write(local_write),
        .local_addr (local_addr),
        .local_data (local_data),
        .local_be   (local_be),
        .local_done (local_done),
        .local_error(1'b0),
        .local_rdata(local_rdata)
    );

    // Compare all SDRAM bytes, including every unwritten trail and source byte.
    task verify_memory;
        input integer stage;
        reg     [7:0] expected;
        integer       k;
        begin
            for (k = 0; k < 4096; k = k + 1) begin
                expected = 8'ha5;
                if (k >= 256 && k < 272) expected = (k - 256) * 13 + 7;
                if (stage >= 1 && k >= 1024 && k < 1040) expected = (k - 1024) * 13 + 7;
                if (stage >= 3 && k >= 1088 && k < 1104) expected = 8'hc0 + k - 1088;
                if (stage >= 4 && k >= 1152 && k < 1168) expected = 8'h80 + k - 1152;
                if (ram[k] !== expected)
                    $fatal(
                        1, "SDRAM stage=%0d byte=%h got=%h expected=%h", stage, k, ram[k], expected
                    );
                expected = k >= 256 && k < 272 ? 8'h80 + k - 256 : 8'h5a;
                if (chip[k] !== expected) $fatal(1, "on-chip memory overwritten byte=%h", k);
            end
        end
    endtask

    always @(posedge clk)
        if (!reset) begin
            cycles <= cycles + 1;
            if (cycles > 100000) $fatal(1, "original DMA timeout pc=%h active=%h", pc, active);
            if (!access || ack) delay <= 0;
            else delay <= delay + 1;
            if (!ram_req || ram_ack) dma_delay <= 0;
            else dma_delay <= dma_delay + 1;
            if (ram_req && ram_addr >= 4096)
                $fatal(1, "SDRAM outside bounded fixture %h", ram_addr);
            if (ram_ack && ram_write)
                for (j = 0; j < 4; j = j + 1) if (ram_be[j]) ram[rbase+j] <= ram_data[j*8+:8];
            if (local_valid && !local_busy) begin
                if (local_write || local_addr < 32'h0c004100 || local_addr >= 32'h0c004110)
                    $fatal(1, "unexpected on-chip transaction %h", local_addr);
                local_busy  <= 1;
                local_delay <= 0;
            end else if (local_done) local_busy <= 0;
            else if (local_busy) local_delay <= local_delay + 1;
            // Acceptance reserves exactly one byte; delayed completion cannot
            // accept a second command or consume/append another FIFO byte.
            if (fifo_take) begin
                if (cmd_be !== 1 || (cmd_write ? sent_count : received_count) >= 16)
                    $fatal(1, "FIFO width/capacity violation");
                fifo_busy  <= 1;
                fifo_delay <= 0;
                fifo_write <= cmd_write;
                fifo_byte  <= cmd_data[7:0];
            end else if (fifo_done) begin
                fifo_busy <= 0;
                if (fifo_write) begin
                    sent[sent_count] <= fifo_byte;
                    sent_count       <= sent_count + 1;
                end else received_count <= received_count + 1;
            end else if (fifo_busy) fifo_delay <= fifo_delay + 1;
            if (errors != 0) $fatal(1, "DMA error %h pc=%h", errors, pc);
            if (ack && in_dma && (!claim || bad)) $fatal(1, "DMA register rejected %h", address);
            if (ack && write_op) begin
                if (in_kernel_ram) begin
                    for (i = 0; i < 4; i = i + 1)
                    if (lanes[i]) kernel_ram[address[16:2]][i*8+:8] <= value[i*8+:8];
                end else if (selector) begin
                    if ((selectors == 0 && (address != 32'h58120068 || value != 32'hf0)) ||
                    (selectors == 1 && (address != 32'h58120064 || value != 32'h20)) ||
                    (selectors == 2 && (address != 32'h58120068 || value != 32'hf00)) ||
                    (selectors == 3 && (address != 32'h58120064 || value != 32'h200)) || selectors >= 4)
                        $fatal(
                            1,
                            "original request selector write %h=%h index=%0d",
                            address,
                            value,
                            selectors
                        );
                    selectors <= selectors + 1;
                end else if (in_dma) begin
                    if (address[5:0] == 8 && value != 0) begin
                        if (starts >= 4 || irq != 0 || dut.ch !== starts[2:0] ||
                        dut.count_value !== ((starts == 0 || starts == 3) ? 7 : 15) ||
                        dut.source_bytes[dut.ch] !== (starts == 2 ? 1 : starts == 3 ? 2 : 4) ||
                        dut.destination_bytes[dut.ch] !== (starts == 1 ? 1 : 4) ||
                        value !== ((starts == 0 || starts == 3) ? 1 : 2))
                            $fatal(1, "original descriptor mismatch case=%0d", starts);
                        $display(
                            "original descriptor ch=%0d source=%h destination=%h widths=%0d/%0d raw_count=%0d control=%0d",
                            dut.ch, dut.src_value, dut.dst_value, dut.source_bytes[dut.ch] * 8,
                            dut.destination_bytes[dut.ch] * 8, dut.count_value, value);
                        starts <= starts + 1;
                    end
                end else if (address == 32'he0000000) begin
                    if (value != checked + 1 || active != 0 || irq != (1 << (value - 1)))
                        $fatal(
                            1, "original completion stage=%0d irq=%h active=%h", value, irq, active
                        );
                    verify_memory(value);
                    if (value >= 2) begin
                        if (sent_count != 16) $fatal(1, "transmit count %0d", sent_count);
                        for (i = 0; i < 16; i = i + 1)
                        if (sent[i] !== ram[256+i]) $fatal(1, "transmit byte %0d", i);
                    end
                    if (value >= 3 && received_count != 16)
                        $fatal(1, "receive count %0d", received_count);
                    checked <= checked + 1;
                end else if (address == 32'hf0000000) begin
                    if (value != 32'h50415353 || checked != 4 || starts != 4 || selectors != 4 || irq != 0)
                        $fatal(1, "original program assertion %h pc=%h", value, pc);
                    for (i = 0; i < 4; i = i + 1)
                    if (kernel_ram[(32'he4c>>2)+i] !== ((i == 0 || i == 3) ? 1 : 2))
                        $fatal(1, "original start bookkeeping ch=%0d", i);
                    $display(
                        "PASS original NEM-4 DMA setup/start wait=%0d cycles=%0d cases=4 exact_bytes=16 unwritten_trails=preserved substitutions=0",
                        wait_cycles, cycles);
                    $finish;
                end else $fatal(1, "CPU write outside fixture %h pc=%h", address, pc);
            end
            if (ack && !write_op && !in_program && !in_app && !in_kernel_ram && !in_dma)
                $fatal(1, "CPU read outside fixture %h pc=%h", address, pc);
        end

    reg [4095:0] program_path, app_path;
    initial begin
        program_path = "scratch/ngage2-integration/p2/original/program.hex";
        app_path     = "scratch/ngage2-integration/p2/original/app.hex";
        if ($value$plusargs("program=%s", program_path)) begin
        end
        if ($value$plusargs("app=%s", app_path)) begin
        end
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) kernel_ram[i] = 0;
        for (i = 0; i < 4096; i = i + 1) begin
            ram[i]  = 8'ha5;
            chip[i] = 8'h5a;
        end
        for (i = 0; i < 16; i = i + 1) begin
            ram[256+i]  = i * 13 + 7;
            chip[256+i] = 8'h80 + i;
        end
        $readmemh(program_path, program_words);
        $readmemh(app_path, app_words);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
