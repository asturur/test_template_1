`timescale 1ns/1ps
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, lcd_req = 0, dma_req = 0, dma_write = 1;
    reg [24:0] lcd_addr = 25'h100, dma_addr = 25'h200;
    reg [31:0] dma_data = 32'h12345678;
    reg [3:0] dma_be = 4'h5;
    wire lcd_accept, lcd_ack, dma_ack, mem_req, mem_write;
    wire [24:0] mem_addr;
    wire [31:0] mem_data, lcd_rdata, dma_rdata;
    wire [3:0] mem_be;
    reg mem_accept = 0, mem_ack = 0;
    reg [31:0] mem_rdata = 32'hcafef00d;
    integer n;
    ngage_dma_ram_mux dut (
        .clk(clk), .reset(reset), .lcd_req(lcd_req), .lcd_addr(lcd_addr),
        .lcd_accept(lcd_accept), .lcd_ack(lcd_ack), .lcd_rdata(lcd_rdata),
        .dma_req(dma_req), .dma_write(dma_write), .dma_addr(dma_addr),
        .dma_data(dma_data), .dma_be(dma_be), .dma_ack(dma_ack), .dma_rdata(dma_rdata),
        .mem_req(mem_req), .mem_write(mem_write), .mem_addr(mem_addr),
        .mem_data(mem_data), .mem_be(mem_be), .mem_accept(mem_accept),
        .mem_ack(mem_ack), .mem_rdata(mem_rdata)
    );
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        lcd_req = 1;
        dma_req = 1;
        #1;
        if (!mem_req || mem_addr != 25'h100 || mem_write || mem_be != 15)
            $fatal(1, "free request gained a pipeline delay or wrong payload");
        repeat (4) @(negedge clk);
        if (lcd_accept || lcd_ack || dma_ack) $fatal(1, "upstream accepted without outer grant");
        mem_accept = 1;
        #1;
        if (!lcd_accept) $fatal(1, "LCD acceptance missing");
        @(negedge clk);
        mem_accept = 0;
        lcd_addr = 25'h777;
        dma_addr = 25'h888;
        repeat (3) @(negedge clk);
        if (mem_addr != 25'h100 || mem_write || mem_be != 15 || lcd_accept)
            $fatal(1, "owned word changed or accepted twice");
        mem_ack = 1;
        #1;
        if (!lcd_ack || dma_ack || lcd_rdata != 32'hcafef00d) $fatal(1, "LCD response ownership");
        @(negedge clk);
        mem_ack = 0;
        // Both held sources alternate at each terminal response.
        for (n = 0; n < 32; n = n + 1) begin
            lcd_addr = 25'h100 + n;
            dma_addr = 25'h200 + n;
            dma_data = 32'h12345678 + n;
            #1;
            if (mem_addr !== (n[0] ? lcd_addr : dma_addr)) $fatal(1, "round-robin choice %0d", n);
            if (!n[0] && (!mem_write || mem_data !== dma_data || mem_be != 5))
                $fatal(1, "captured write fields");
            mem_accept = 1;
            @(negedge clk);
            mem_accept = 0;
            repeat (2) @(negedge clk);
            mem_ack = 1;
            #1;
            if (lcd_ack !== n[0] || dma_ack !== !n[0] || dma_rdata != mem_rdata)
                $fatal(1, "round-robin response %0d", n);
            @(negedge clk);
            mem_ack = 0;
        end
        // Same-edge acceptance and completion do not leave a ghost owner.
        dma_req = 0;
        mem_accept = 1;
        mem_ack = 1;
        #1;
        if (!lcd_accept || !lcd_ack || dma_ack) $fatal(1, "same-edge terminal response");
        @(negedge clk);
        mem_accept = 0;
        mem_ack = 0;
        lcd_req = 0;
        #1;
        if (mem_req) $fatal(1, "same-edge response retained ownership");
        // Reset kills both acceptance and response, including a stale ACK.
        lcd_req = 1;
        mem_accept = 1;
        @(negedge clk);
        mem_accept = 0;
        reset = 1;
        mem_ack = 1;
        #1;
        if (mem_req || lcd_accept || lcd_ack || dma_ack) $fatal(1, "reset leaked ownership");
        @(negedge clk);
        lcd_req = 0;
        reset = 0;
        #1;
        if (lcd_ack || dma_ack) $fatal(1, "stale ACK acquired a new owner");
        mem_ack = 0;
        $display("PASS DMA RAM mux zero request latency, 32 alternating grants, capture, masks, response ownership and reset");
        $finish;
    end
    initial begin
        #20000;
        $fatal(1, "DMA RAM mux timeout");
    end
endmodule
