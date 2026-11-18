`timescale 1ns/1ps
module recorder_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg sample_valid = 0, ready = 1, rsp = 0;
    reg [31:0] sample = 0;
    wire valid;
    wire [31:0] addr, data;
    reg [31:0] ring [0:7];
    reg [31:0] head = -1, metadata = -1;

    ngage_diag_pcm_ddr #(.RING_BITS(3), .HEAD_BITS(2)) dut (
        .clk(clk), .reset(reset), .sample_valid(sample_valid),
        .sample(sample), .activity(2'b11), .req_valid(valid),
        .req_ready(ready), .req_addr(addr), .req_data(data), .rsp_valid(rsp)
    );
    always @(posedge clk) begin
        rsp <= valid && ready;
        if (valid && ready)
            case (addr)
                32'h31900000: head <= data;
                32'h31900004: metadata <= data;
                default: begin
                    if (addr < 32'h31940000 || addr > 32'h3194001c)
                        $fatal(1, "unexpected address %h", addr);
                    ring[addr[4:2]] <= data;
                end
            endcase
    end

    task submit(input [31:0] value);
        begin
            @(negedge clk);
            sample = value;
            sample_valid = 1;
            @(negedge clk);
            sample_valid = 0;
        end
    endtask

    integer i;
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        repeat (10) @(negedge clk);
        if (head !== 0 || metadata !== 0)
            $fatal(1, "initial header %h %h", head, metadata);
        for (i = 0; i < 12; i = i + 1) begin
            submit(32'hfedc8000 + i);
            repeat (10) @(negedge clk);
        end
        if (head !== 12 || metadata !== 32'hc0000000)
            $fatal(1, "capture header %h %h", head, metadata);
        for (i = 4; i < 12; i = i + 1)
            if (ring[i % 8] !== 32'hfedc8000 + i)
                $fatal(1, "ring reorder %0d %h", i, ring[i % 8]);

        ready = 0;
        submit(32'hfedc800c);
        submit(32'hbad0bad0);
        if (!valid || addr !== 32'h31940010 || data !== 32'hfedc800c)
            $fatal(1, "DDR hold changed the pending sample");
        ready = 1;
        repeat (10) @(negedge clk);
        for (i = 13; i < 16; i = i + 1) begin
            submit(32'hfedc8000 + i);
            repeat (10) @(negedge clk);
        end
        if (head !== 16 || metadata !== 32'hc0000001)
            $fatal(1, "lost sample was not published %h %h", head, metadata);
        $display("PASS PCM DDR recorder wrap, signed L/R, overlap and stalled write");
        $finish;
    end
endmodule
