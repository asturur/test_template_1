`timescale 1ns/1ps
// Both clients use the same actual arbiter and the same physical memory model.
// No register-programming clocks or CPU contention enter the timed interval.
module measured_path #(parameter FAST = 0, parameter LATENCY = 0)(
    input wire clk,
    input wire reset,
    output reg finished = 0
);
    wire client_req, client_ack, client_accept;
    wire [24:0] client_addr;
    wire [31:0] client_data;
    wire pixel_valid;
    wire [31:0] pixel_data;
    wire [14:0] pixel_index;
    wire terminal;
    reg transfer_valid = 0;
    reg reg_req = 0, reg_we = 0, reg_commit = 0;
    reg [31:0] reg_addr = 0, reg_data = 0;
    wire physical_req, physical_write;
    wire [24:0] physical_addr;
    wire [31:0] physical_wdata;
    wire [3:0] physical_be;
    wire unused_cpu_ack, unused_cpu_accept;
    wire [31:0] unused_cpu_rdata;
    reg pending = 0;
    reg [24:0] owned_addr;
    integer delay_left = 0;
    wire physical_ack = LATENCY == 0 ? physical_req : pending && delay_left == 0;
    wire [24:0] response_addr = LATENCY == 0 ? physical_addr : owned_addr;
    function [31:0] oracle;
        input [24:0] addr;
        begin oracle = (32'h9d4b03a7 ^ {7'b0,addr}) + ((addr >> 2)*32'h1234567); end
    endfunction
    wire [31:0] physical_data = oracle(response_addr);
    reg [31:0] observed[0:18303];
    integer cycle = 0, first_request = -1, last_pixel = -1;
    integer completion = -1, read_words = 0, pixel_words = 0;
    reg [31:0] checksum = 0;
    ngage_sdram_arbiter arbiter (
        .clk(clk), .reset(reset), .cpu_lock(1'b0), .cpu_req(1'b0),
        .cpu_we(1'b0), .cpu_addr(25'b0), .cpu_data(32'b0), .cpu_be(4'b0),
        .cpu_ack(unused_cpu_ack), .cpu_rdata(unused_cpu_rdata),
        .cpu_accept(unused_cpu_accept), .dma_req(client_req), .dma_we(1'b0),
        .dma_addr(client_addr), .dma_data(32'b0), .dma_be(4'hf),
        .dma_ack(client_ack), .dma_rdata(client_data), .dma_accept(client_accept),
        .mem_req(physical_req), .mem_we(physical_write), .mem_addr(physical_addr),
        .mem_data(physical_wdata), .mem_be(physical_be),
        .mem_ack(physical_ack), .mem_rdata(physical_data)
    );
    generate if (FAST) begin: fast_path
        wire unused_ready, unused_busy, failed, aborted;
        ngage_lcd_stream stream (
            .clk(clk), .reset(reset), .transfer_valid(transfer_valid),
            .transfer_ready(unused_ready), .source_addr(32'h0a000020),
            .transfer_words(33'd18304), .stop(1'b0), .busy(unused_busy),
            .done(terminal), .error(failed), .aborted(aborted),
            .mem_req(client_req), .mem_addr(client_addr), .mem_accept(client_accept),
            .mem_ack(client_ack), .mem_data(client_data), .pixel_valid(pixel_valid),
            .pixel_data(pixel_data), .pixel_ready(1'b1), .pixel_error(1'b0)
        );
        always @(posedge clk) if (!reset && (failed || aborted)) begin
            $display("FAIL fast unexpected error latency=%0d", LATENCY); $finish(1);
        end
    end else begin: legacy_path
        wire claim, bad, frame_full;
        wire [31:0] dout;

        ngage_lcd_dma legacy (
            .clk(clk), .reset(reset), .req(reg_req), .commit(reg_commit),
            .we(reg_we), .addr(reg_addr), .din(reg_data), .sel(4'hf),
            .claim(claim), .bad(bad), .dout(dout),
            .mem_req(client_req), .mem_addr(client_addr),
            .mem_ack(client_ack), .mem_data(client_data), .lcd_valid(pixel_valid),
            .lcd_frame_full(frame_full), .lcd_word_addr(pixel_index),
            .lcd_data(pixel_data), .irq_pending(terminal), .irq_clear(1'b0)
        );
        always @(posedge clk) if (!reset && bad) begin
            $display("FAIL legacy address/register latency=%0d", LATENCY); $finish(1);
        end
    end endgenerate
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (reset) pending <= 0;
        else begin
            if (LATENCY != 0) begin
                if (pending) begin
                    if (!physical_req || physical_addr !== owned_addr) begin
                        $display("FAIL physical ownership fast=%0d latency=%0d", FAST,LATENCY); $finish(1);
                    end
                    if (physical_ack) pending <= 0;
                    else delay_left <= delay_left - 1;
                end else if (physical_req) begin
                    pending <= 1;
                    owned_addr <= physical_addr;
                    delay_left <= LATENCY - 1;
                end
            end
            if (client_req && first_request < 0) first_request = cycle;
            if (client_accept) begin
                if (client_addr !== 25'h20 + read_words*4 || read_words >= 18304) begin
                    $display("FAIL source order fast=%0d latency=%0d read=%0d addr=%h", FAST,LATENCY,read_words,client_addr); $finish(1);
                end
                read_words = read_words + 1;
            end
            if (pixel_valid) begin
                if (pixel_words >= 18304 || (!FAST && pixel_index !== pixel_words) ||
                    pixel_data !== oracle(25'h20 + pixel_words*4)) begin
                    $display("FAIL fullword oracle fast=%0d latency=%0d word=%0d data=%h", FAST,LATENCY,pixel_words,pixel_data); $finish(1);
                end
                observed[pixel_words] = pixel_data;
                checksum = checksum + pixel_data;
                pixel_words = pixel_words + 1;
                last_pixel = cycle;
            end
            // Terminal is sampled after this edge's sequential updates, making
            // the timing origin/final pixel/terminal convention equal for both.
            #1;
            if (terminal && !finished) begin
                completion = cycle;
                if (read_words != 18304 || pixel_words != 18304 || pending || client_req) begin
                    $display("FAIL incomplete terminal fast=%0d latency=%0d reads=%0d pixels=%0d",FAST,LATENCY,read_words,pixel_words); $finish(1);
                end
                finished = 1;
                $display("MATCHED fast=%0d physical_delay=%0d words=18304 first_request=%0d last_pixel=%0d completion=%0d pixel_elapsed=%0d completion_elapsed=%0d checksum=%h",FAST,LATENCY,first_request,last_pixel,completion,last_pixel-first_request,completion-first_request,checksum);
            end
        end
    end
    task wr;
        input [31:0] addr, data;
        begin
            @(negedge clk); reg_req = 1; reg_we = 1; reg_commit = 1;
            reg_addr = addr; reg_data = data;
            @(negedge clk); reg_req = 0; reg_commit = 0;
        end
    endtask
    initial begin
        wait (!reset);
        if (FAST) begin
            @(negedge clk); transfer_valid = 1;
            @(negedge clk); transfer_valid = 0;
        end else begin
            wr(32'h0c120354,32'h0a000020);
            wr(32'h0c120360,32'h10121208);
            wr(32'h0c12036c,32'd18303);
            wr(32'h0c120348,32'd2);
        end
    end
endmodule
module comparison_tb;
    reg clk = 0, reset = 1;
    always #5 clk = !clk;
    wire l0, f0, l1, f1, l3, f3;
    measured_path #(.FAST(0),.LATENCY(0)) legacy0(clk,reset,l0);
    measured_path #(.FAST(1),.LATENCY(0)) fast0(clk,reset,f0);
    measured_path #(.FAST(0),.LATENCY(1)) legacy1(clk,reset,l1);
    measured_path #(.FAST(1),.LATENCY(1)) fast1(clk,reset,f1);
    measured_path #(.FAST(0),.LATENCY(3)) legacy3(clk,reset,l3);
    measured_path #(.FAST(1),.LATENCY(3)) fast3(clk,reset,f3);
    integer i;
    initial begin
        repeat (2) @(negedge clk); reset = 0;
        wait (l0 && f0 && l1 && f1 && l3 && f3);
        for (i = 0; i < 18304; i = i + 1) begin
            if (legacy0.observed[i] !== fast0.observed[i] ||
                legacy1.observed[i] !== fast1.observed[i] ||
                legacy3.observed[i] !== fast3.observed[i]) begin
                $display("FAIL legacy/fast bitexact stream word=%0d",i); $finish(1);
            end
        end
        if (legacy0.completion-legacy0.first_request != fast0.completion-fast0.first_request ||
            legacy1.completion-legacy1.first_request != fast1.completion-fast1.first_request ||
            legacy3.completion-legacy3.first_request != fast3.completion-fast3.first_request) begin
            $display("FAIL legacy/fast matched elapsed mismatch"); $finish(1);
        end
        $display("PASS LCD legacy/fast matched physical delays=0,1,3 words=18304 bitexact");
        $finish;
    end
    initial begin #2000000; $display("FAIL comparison timeout"); $finish(1); end
endmodule
