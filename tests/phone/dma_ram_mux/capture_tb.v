`timescale 1ns/1ps
// The outer arbiter must retain the accepted packet when mux sources change.
module capture_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, lcd_req=0, dma_req=0, dma_write=1, complete=0;
    reg [24:0] lcd_addr=25'h100, dma_addr=25'h200;
    reg [31:0] dma_data=32'h12345678;
    reg [3:0] dma_be=4'h5;
    wire lcd_accept, lcd_ack, dma_ack, req, we, accept, ack;
    wire [24:0] addr, physical_addr;
    wire [31:0] data, rdata, physical_data;
    wire [3:0] be, physical_be;
    wire physical_req, physical_we;
    integer n;
    reg [24:0] expected_addr;
    reg [31:0] expected_data;
    ngage_dma_ram_mux mux (
        .clk(clk),.reset(reset),.lcd_req(lcd_req),.lcd_addr(lcd_addr),
        .lcd_accept(lcd_accept),.lcd_ack(lcd_ack),.lcd_rdata(),
        .dma_req(dma_req),.dma_write(dma_write),.dma_addr(dma_addr),
        .dma_data(dma_data),.dma_be(dma_be),.dma_ack(dma_ack),.dma_rdata(),
        .mem_req(req),.mem_write(we),.mem_addr(addr),.mem_data(data),.mem_be(be),
        .mem_accept(accept),.mem_ack(ack),.mem_rdata(rdata)
    );
    ngage_sdram_arbiter arb (
        .clk(clk),.reset(reset),.cpu_lock(1'b0),.cpu_req(1'b0),.cpu_we(1'b0),
        .cpu_addr(25'b0),.cpu_data(32'b0),.cpu_be(4'b0),.cpu_ack(),.cpu_rdata(),
        .dma_req(req),.dma_we(we),.dma_addr(addr),.dma_data(data),.dma_be(be),
        .dma_ack(ack),.dma_rdata(rdata),.dma_accept(accept),.cpu_accept(),
        .mem_req(physical_req),.mem_we(physical_we),.mem_addr(physical_addr),
        .mem_data(physical_data),.mem_be(physical_be),
        .mem_ack(complete),.mem_rdata(32'hcafef00d)
    );
    initial begin
        repeat(3) @(negedge clk);
        reset=0;
        // Keep both sources requesting to exercise alternating ownership.
        lcd_req=1;dma_req=1;
        for(n=0;n<32;n=n+1) begin
            lcd_addr=25'h100+n;dma_addr=25'h200+n;dma_data=32'h12345678+n;
            expected_addr=n[0]?dma_addr:lcd_addr;
            expected_data=n[0]?dma_data:0;
            #1;
            if(!accept || lcd_accept===n[0]) $fatal(1,"admission %0d",n);
            @(negedge clk);
            // Deliberately break the producer hold contract after acceptance.
            lcd_addr=25'h777;dma_addr=25'h888;dma_data=32'hdeadbeef;
            dma_be=4'ha;dma_write=0;
            repeat(3) begin
                #1;
                if(!physical_req || physical_addr!==expected_addr ||
                   physical_data!==expected_data || physical_we!==n[0] ||
                   physical_be!==(n[0]?4'h5:4'hf) || accept || lcd_accept)
                    $fatal(1,"outer packet changed after acceptance %0d",n);
                @(negedge clk);
            end
            complete=1;
            #1;
            if(lcd_ack!==!n[0] || dma_ack!==n[0]) $fatal(1,"response tag %0d",n);
            @(negedge clk);
            complete=0;dma_be=4'h5;dma_write=1;
        end
        lcd_req=0;dma_req=0;
        #1;
        if(physical_req || lcd_ack || dma_ack) $fatal(1,"ghost owner");
        $display("PASS DMA RAM mux outer packet retention, 32 alternating requests and response ownership");
        $finish;
    end
    initial begin
        #20000;$fatal(1,"packet retention timeout");
    end
endmodule
