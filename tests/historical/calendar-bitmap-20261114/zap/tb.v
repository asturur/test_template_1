`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, we;
    wire [31:0] adr, din, pc;
    wire [3:0] sel;
    reg [31:0] code[0:1023], native[0:1023], payload[0:1023], ram[0:16383];
    reg [31:0] data;
    integer cycles = 0, delay = 0, waits = 0, i, j, chars = 0;
    wire access = cyc && stb;
    wire ack = access && delay >= waits;
    ngage_cpu cpu (
        .clk           (clk),
        .reset         (reset),
        .irq           (1'b0),
        .fiq           (1'b0),
        .wb_cyc        (cyc),
        .wb_stb        (stb),
        .wb_write      (we),
        .wb_address    (adr),
        .wb_write_data (din),
        .wb_byte_enable(sel),
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
    always @* begin
        data = 0;
        if (adr < 4096) data = code[adr[11:2]];
        else if (adr[31:12] == 20'h50559) data = native[adr[11:2]];
        else if (adr[31:12] == 20'h511b8) data = payload[adr[11:2]];
        else if (adr[31:16] == 16'h8000) data = ram[adr[15:2]];
    end
    always @(posedge clk)
        if (!reset) begin
            cycles <= cycles + 1;
            if (!access || ack) delay <= 0;
            else delay <= delay + 1;
            if (cycles > 300000) $fatal(1, "timeout pc=%h adr=%h", pc, adr);
            if (ack && we) begin
                if (adr[31:16] == 16'h8000) begin
                    for (j = 0; j < 4; j = j + 1) if (sel[j]) ram[adr[15:2]][j*8+:8] <= din[j*8+:8];
                end else if (adr == 32'h59000000) begin
                    chars <= chars + 1;
                    $write("%c", din[7:0]);
                end else if (adr == 32'hf0000000) begin
                    if (din != 32'h600d0001) $fatal(1, "exception pc=%h marker=%h", pc, din);
                    if (chars == 0) $fatal(1, "continuation without trace");
                    $display("PASS ZAP Thumb observer continuation cycles=%0d chars=%0d wait=%0d",
                             cycles, chars, waits);
                    $finish;
                end
            end
        end
    initial begin
        if ($value$plusargs("wait=%d", waits)) begin
        end
        for (i = 0; i < 1024; i = i + 1) begin
            code[i]    = 0;
            native[i]  = 0;
            payload[i] = 0;
        end
        for (i = 0; i < 16384; i = i + 1) ram[i] = 0;
        $readmemh("scratch/calendar-bitmap-20261114/zap/program.hex", code);
        $readmemh("scratch/calendar-bitmap-20261114/zap/native.hex", native);
        $readmemh("scratch/calendar-bitmap-20261114/zap/payload.hex", payload);
        // Replace only the continuation with a fixture success exit, reached by execution.
        native['h8b0/4] = 32'h47184b00;  // ldr r3,[pc]; bx r3 (Thumb)
        native['h8b4/4] = 32'h00000200;
        code['h200/4]   = 32'he59f1008;  // ldr r1,[pc,#8]
        code['h204/4]   = 32'he59f0008;  // ldr r0,[pc,#8]
        code['h208/4]   = 32'he5810000;  // str r0,[r1]
        code['h20c/4]   = 32'heafffffe;
        code['h210/4]   = 32'hf0000000;
        code['h214/4]   = 32'h600d0001;
        repeat (8) @(posedge clk);
        reset <= 0;
    end
endmodule
