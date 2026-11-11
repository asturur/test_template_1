`timescale 1ns/1ps
module tb;
    localparam [31:0] CHIP_WORD = 32'h0c004020, LCD_FIFO = 32'h0c121208;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, lock = 0;
    reg cmd_valid = 0, cmd_write = 0;
    reg [31:0] cmd_addr = 0, cmd_data = 0;
    reg [3:0] cmd_be = 0;
    wire cmd_ready, rsp_valid, rsp_error;
    wire [31:0] rsp_data;
    wire ram_req, ram_write;
    wire [24:0] ram_addr;
    wire [31:0] ram_data;
    wire [3:0] ram_be;
    reg ram_ack = 0;
    wire local_valid, local_ready, local_write, local_done;
    wire [31:0] local_addr, local_data, local_rdata;
    wire [3:0] local_be;
    reg inject_error = 0, stale_done = 0;

    ngage_dma_route route (
        .clk(clk), .reset(reset), .cpu_lock(lock),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_data(cmd_data), .cmd_be(cmd_be),
        .rsp_valid(rsp_valid), .rsp_error(rsp_error), .rsp_data(rsp_data),
        .ram_req(ram_req), .ram_write(ram_write), .ram_addr(ram_addr), .ram_data(ram_data),
        .ram_be(ram_be), .ram_ack(ram_ack), .ram_rdata(32'h43505521),
        .local_valid(local_valid), .local_ready(local_ready), .local_write(local_write),
        .local_addr(local_addr), .local_data(local_data), .local_be(local_be),
        .local_done(local_done || stale_done), .local_error(inject_error), .local_rdata(local_rdata)
    );

    reg cpu_req = 0, cpu_we = 0, fifo_space = 0;
    reg [31:0] cpu_data = 0;
    wire cpu_ack, mem_req, mem_we;
    wire [31:0] cpu_rdata, mem_addr, mem_data, mem_rdata;
    wire [3:0] mem_be;
    reg delayed = 0;
    wire mem_ack = mem_req && delayed;
    wire dma_req = local_valid && (local_addr != LCD_FIFO || fifo_space);
    ngage_sdram_arbiter #(.AW(32)) local_bus (
        .clk(clk), .reset(reset), .cpu_lock(lock), .cpu_req(cpu_req),
        .cpu_we(cpu_we), .cpu_addr(CHIP_WORD), .cpu_data(cpu_data), .cpu_be(4'hf),
        .cpu_ack(cpu_ack), .cpu_rdata(cpu_rdata), .cpu_accept(),
        .dma_req(dma_req), .dma_we(local_write), .dma_addr(local_addr),
        .dma_data(local_data), .dma_be(local_be), .dma_ack(local_done),
        .dma_rdata(local_rdata), .dma_accept(local_ready),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_data(mem_data),
        .mem_be(mem_be), .mem_ack(mem_ack), .mem_rdata(mem_rdata)
    );

    wire ram_commit = mem_ack && mem_we && mem_addr != LCD_FIFO && !inject_error;
    ngage_bram_be #(.AW(10)) chip_ram (
        .clk(clk), .raddr(mem_addr[11:2]), .rdata(mem_rdata),
        .waddr(mem_addr[11:2]), .we(ram_commit ? mem_be : 4'b0), .wdata(mem_data)
    );
    integer fifo_writes = 0, responses = 0;
    reg [31:0] fifo_word = 0;
    always @(posedge clk) begin
        delayed <= !reset && mem_req && !mem_ack;
        if (!reset && mem_ack && mem_we && mem_addr == LCD_FIFO && !inject_error) begin
            fifo_writes <= fifo_writes + 1;
            fifo_word   <= mem_data;
        end
        if (rsp_valid) responses <= responses + 1;
    end

    task command;
        input write;
        input [31:0] addr, data;
        input [3:0] be;
        begin
            @(negedge clk);
            if (!cmd_ready) $fatal(1, "command while busy");
            cmd_valid = 1;
            cmd_write = write;
            cmd_addr  = addr;
            cmd_data  = data;
            cmd_be    = be;
            @(negedge clk);
            cmd_valid = 0;
            cmd_addr  = 32'hdeadbeec;
            cmd_data  = 0;
            cmd_be    = 0;
        end
    endtask

    task response;
        input failed, compare_data;
        input [31:0] data;
        begin
            wait (rsp_valid);
            #1;
            if (rsp_error !== failed || (compare_data && rsp_data !== data))
                $fatal(1, "unexpected response error=%b data=%h", rsp_error, rsp_data);
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 0;

        // FIFO waits for capacity without acquiring the local bus.
        command(1, 32'h10121208, 32'h11223344, 4'hf);
        if (!local_valid || local_addr !== LCD_FIFO || local_data !== 32'h11223344)
            $fatal(1, "LCD alias or capture");
        cpu_we = 1;
        cpu_req = 1;
        cpu_data = 32'hdec0ffee;
        wait (cpu_ack);
        @(negedge clk);
        cpu_req = 0;
        if (local_ready || fifo_writes != 0) $fatal(1, "unpaced FIFO grant");
        lock = 1;
        fifo_space = 1;
        repeat (4) @(negedge clk);
        if (local_valid || fifo_writes != 0) $fatal(1, "FIFO crossed SWP gap");
        lock = 0;
        wait (local_ready);
        @(negedge clk);
        fifo_space = 0;
        response(0, 0, 0);
        if (fifo_writes != 1 || fifo_word !== 32'h11223344)
            $fatal(1, "FIFO did not commit one captured word");

        // CPU and DMA share one byte-enabled RAM and see committed updates.
        command(0, CHIP_WORD, 0, 4'hf);
        response(0, 1, 32'hdec0ffee);
        command(1, CHIP_WORD, 32'h11223344, 4'b0101);
        response(0, 0, 0);
        cpu_we = 0;
        cpu_req = 1;
        wait (cpu_ack);
        #1;
        if (cpu_rdata !== 32'hde22ff44) $fatal(1, "CPU missed DMA masked write");
        @(negedge clk);
        cpu_req = 0;

        // An endpoint error is returned once and has no side effect.
        inject_error = 1;
        command(1, CHIP_WORD, 32'hffffffff, 4'hf);
        response(1, 0, 0);
        inject_error = 0;
        command(0, CHIP_WORD, 0, 4'hf);
        response(0, 1, 32'hde22ff44);

        command(1, 32'h0afffffc, 32'hcafef00d, 4'b1010);
        repeat (3) @(negedge clk);
        if (!ram_req || !ram_write || ram_addr !== 25'h0fffffc ||
            ram_data !== 32'hcafef00d || ram_be !== 4'b1010)
            $fatal(1, "SDRAM command lost its captured fields");
        ram_ack = 1;
        response(0, 1, 32'h43505521);
        ram_ack = 0;

        command(0, 32'h0b000000, 0, 4'hf);
        response(1, 0, 0);
        command(0, 32'h0c004748, 0, 4'hf);
        response(1, 0, 0);
        command(1, 32'h10120624, 0, 4'hf);
        response(1, 0, 0);
        command(1, LCD_FIFO, 0, 4'b0011);
        response(1, 0, 0);
        command(1, 32'h0a000002, 0, 4'hf);
        response(1, 0, 0);
        command(1, 32'h0a000004, 0, 4'h0);
        response(1, 0, 0);

        command(1, LCD_FIFO, 32'haabbccdd, 4'hf);
        fifo_space = 1;
        wait (local_ready);
        @(negedge clk);
        reset = 1;
        stale_done = 1;
        #1;
        if (rsp_valid || local_valid || ram_req) $fatal(1, "reset leaked response or offer");
        @(negedge clk);
        reset = 0;
        fifo_space = 0;
        repeat (3) @(negedge clk);
        if (rsp_valid || responses != 12 || fifo_writes != 1)
            $fatal(1, "unexpected completion after reset, replies=%0d FIFO=%0d", responses, fifo_writes);
        $display("PASS DMA route paced FIFO, CPU contention, shared RAM masks, SDRAM, rejects and reset");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "DMA route timeout");
    end
endmodule
