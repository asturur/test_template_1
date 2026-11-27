`timescale 1ps / 1ps

module board_isolation_smoke;
    reg clk = 0, reset = 1;
    always #4808 clk = ~clk;
    wire cyc, stb, write, code, lock, block_write, ack, error;
    wire [31:0] address, wdata, rdata;
    wire [127:0] block_data;
    wire [3:0] mask;
    wire line_req;
    wire [31:0] line_address;
    reg line_ready = 0, line_reject = 0, line_valid = 0, line_last = 0, line_wide = 0;
    reg [63:0] line_data = 0;
    ngage_timing_board_cpu #(
        .LINE_REFILL(1), .EXPLICIT_LINE_GUARANTEE(1), .REGISTERED_SCALAR_PEER(1)
    ) master (
        .clk(clk), .reset(reset), .irq(1'b0), .fiq(1'b0),
        .line_req(line_req), .line_addr(line_address), .line_ready(line_ready),
        .line_reject(line_reject), .line_valid(line_valid), .line_data(line_data),
        .line_wide(line_wide), .line_last(line_last), .line_error(1'b0),
        .line_no_late_error(1'b1), .wb_cyc(cyc), .wb_stb(stb), .wb_lock(lock),
        .wb_write(write), .wb_code(code), .wb_address(address), .wb_write_data(wdata),
        .wb_write_block(block_write), .wb_block_data(block_data), .wb_byte_enable(mask),
        .wb_cycle_type(), .wb_burst_type(), .wb_ack(ack), .wb_error(error),
        .wb_read_data(rdata), .debug_pc(), .debug_cpsr(), .debug_instruction(), .debug_fetch()
    );

    wire ram_req, ram_we, ram_pending, slow_stb;
    wire [31:0] ram_address, ram_write_data;
    wire [3:0] ram_mask;
    reg [2:0] ram_wait = 0, slow_wait = 0;
    reg ram_ack = 0, slow_ack = 0, slow_active = 0;
    reg [31:0] ram_read_data = 0, slow_read_data = 0;
    reg [5:0] tick = 0;
    wire ram_accept = ram_req && tick[1:0] == 0;
    ngage_cpu_memory_route #(.DIRECT_SDRAM(1), .CPU_OWNS_SCALAR_REPLY(1)) route (
        .clk(clk), .reset(reset),
        .master_cyc(cyc), .master_stb(stb), .master_we(write), .master_code(code),
        .master_address(address), .master_data(wdata), .master_sel(mask),
        .master_ack(ack), .master_error(error), .master_rdata(rdata), .slow_cyc(),
        .slow_stb(slow_stb), .slow_idle(!slow_active && !slow_ack), .slow_ack(slow_ack),
        .slow_error(1'b0), .slow_rdata(slow_read_data), .ram_req(ram_req),
        .ram_we(ram_we), .ram_code(), .ram_address(ram_address), .ram_wdata(ram_write_data),
        .ram_be(ram_mask), .ram_accept(ram_accept), .ram_ack(ram_ack),
        .ram_rdata(ram_read_data), .ram_pending(ram_pending), .ram_response()
    );

    reg [31:0] offered_line = 0, rejected_address = 0, locked_address = 0;
    reg [4:0] pieces = 0, remaining = 0;
    reg locked_read_seen = 0;
    integer narrow_complete = 0, wide_complete = 0, rejected = 0, fallbacks = 0;
    integer ram_reads = 0, ram_writes = 0, masks = 0, blocks = 0, locks = 0, local_replies = 0;
    reg [127:0] block_bits = 0;
    reg [39:0] scalar_bits = 0;

    always @(posedge clk) begin
        tick <= tick + 1'b1;
        ram_ack <= 0;
        slow_ack <= 0;
        line_valid <= 0;
        line_last <= 0;
        line_reject <= 0;
        if (reset) begin
            ram_wait <= 0;
            slow_active <= 0;
            line_ready <= 0;
            pieces <= 0;
            remaining <= 0;
            locked_read_seen <= 0;
        end else begin
            if (ram_accept) begin
                ram_wait <= 4;
                ram_read_data <= ram_address ^ 32'h9eed37a5;
                if (ram_we) begin
                    ram_writes <= ram_writes + 1;
                    if (ram_mask != 4'hf) masks <= masks + 1;
                    if (block_write) begin
                        if (ram_mask != 4'hf || ram_address[3:0] != 0)
                            $fatal(1, "Malformed block offer");
                        block_bits <= block_bits | block_data;
                        blocks <= blocks + 1;
                    end
                end else ram_reads <= ram_reads + 1;
            end else if (ram_pending && ram_wait != 0) begin
                ram_ack <= ram_wait == 1;
                ram_wait <= ram_wait - 1'b1;
            end
            if (slow_stb && !slow_active && !slow_ack) begin
                slow_active <= 1;
                slow_wait <= 3;
                slow_read_data <= address ^ 32'h05da9587;
                if (remaining != 0) begin
                    if (write || address != rejected_address + ((8 - remaining) * 4))
                        $fatal(1, "Rejected line did not fall back in order");
                    remaining <= remaining - 1'b1;
                    fallbacks <= fallbacks + 1;
                end
            end else if (slow_active) begin
                slow_wait <= slow_wait - 1'b1;
                if (slow_wait == 1) begin
                    slow_active <= 0;
                    slow_ack <= 1;
                    local_replies <= local_replies + 1;
                end
            end
            if (cyc && ack) begin
                scalar_bits <= scalar_bits | {address[15:8], rdata};
                if (lock && !write) begin
                    locked_address <= address;
                    locked_read_seen <= 1;
                end
                if (lock && write) begin
                    if (!locked_read_seen || locked_address != address)
                        $fatal(1, "Unpaired locked write");
                    locked_read_seen <= 0;
                    locks <= locks + 1;
                end
            end
            if (locked_read_seen && !lock) $fatal(1, "Lost lock between scalar halves");

            if (line_req && line_ready) begin
                if (cyc || line_address[4:0] != 0) $fatal(1, "Invalid line offer");
                line_ready <= 0;
                offered_line <= line_address;
                line_wide <= line_address[31:24] != 8'h0a;
                if (line_address[31:22] == 10'h009) begin
                    line_reject <= 1;
                    rejected_address <= line_address;
                    rejected <= rejected + 1;
                    remaining <= 8;
                end else pieces <= line_address[31:24] == 8'h0a ? 16 : 4;
            end else if (pieces != 0) begin
                pieces <= pieces - 1'b1;
                line_valid <= 1;
                line_data <= {offered_line, offered_line[26:0], pieces};
                if (pieces == 1) begin
                    line_last <= 1;
                    if (line_wide) wide_complete <= wide_complete + 1;
                    else narrow_complete <= narrow_complete + 1;
                end
            end else line_ready <= tick[1];
        end
    end

    reg blocked = 0, line_blocked = 0;
    reg [200:0] saved_scalar;
    reg [31:0] saved_line;
    wire [200:0] scalar_offer = {address, write, code, lock, mask, wdata, block_write, block_data, cyc};
    always @(posedge clk) begin
        if (!reset && blocked && scalar_offer !== saved_scalar) $fatal(1, "Unstable scalar offer");
        if (!reset && line_blocked && (!line_req || line_address != saved_line))
            $fatal(1, "Unstable line offer");
        blocked <= !reset && cyc && !(ack || error);
        line_blocked <= !reset && line_req && !line_ready;
        saved_scalar <= scalar_offer;
        saved_line <= line_address;
    end

    initial begin
        repeat (12) @(negedge clk);
        reset = 0;
        repeat (10000) @(negedge clk);
        if (locks < 20 || blocks < 20 || masks < 20 || ram_reads < 50 || ram_writes < 60 ||
            local_replies < 100 || wide_complete < 20 || narrow_complete < 20 || rejected < 20 ||
            fallbacks < 8 * (rejected - 1) || block_bits !== {128{1'b1}} || scalar_bits == 0)
            $fatal(1, "Insufficient activity in board diagnostic fixture");
        $display("PASS board fixture RAM R/W=%0d/%0d locks=%0d masked=%0d blocks=%0d local=%0d lines=%0d/%0d reject=%0d fallback=%0d",
                 ram_reads, ram_writes, locks, masks, blocks, local_replies, narrow_complete, wide_complete, rejected, fallbacks);
        $finish;
    end
endmodule
