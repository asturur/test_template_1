`timescale 1ns / 1ps
module tb;
    reg clk = 0, reset = 1, enabled = 0, locked = 1, fv = 1;
    reg [15:0] marker = 16'hfffc;
    reg hv = 0, ready = 0, allow = 1, inject = 0;
    reg [7:0] hd = 0;
    wire hr, rv, link, cv, cr, response, error;
    wire [11:0] debug_status;
    wire [ 7:0] rd;
    wire [ 6:0] ca;
    wire [15:0] cw;
    reg  [ 7:0] output_bytes [0:4095];
    reg  [ 7:0] input_bytes  [ 0:255];
    integer count = 0, codecs = 0, cycles = 0, i, n, base, before_codecs, file;
    reg  [15:0] check;
    real        half_period = 6.410256;
    initial
        if ($value$plusargs("half_period=%f", half_period)) begin
        end
    always #(half_period) clk = ~clk;
    ngage_adsp dut (
        .clk                 (clk),
        .reset               (reset),
        .enabled             (enabled),
        .clock_ready         (locked),
        .flash_valid         (fv),
        .flash_marker        (marker),
        .host_tx_valid       (hv),
        .host_tx_ready       (hr),
        .host_tx_data        (hd),
        .host_rx_valid       (rv),
        .host_rx_ready       (ready),
        .host_rx_data        (rd),
        .codec_valid         (cv),
        .codec_ready         (cr && allow),
        .codec_address       (ca),
        .codec_word          (cw),
        .codec_response_valid(response),
        .codec_response_error(error || inject),
        .link_ready          (link),
        .debug_status        (debug_status)
    );
    ngage_aic23 codec (
        .clk            (clk),
        .reset          (reset),
        .control_valid  (cv && allow),
        .control_ready  (cr),
        .control_address(ca),
        .control_word   (cw),
        .response_valid (response),
        .response_error (error),
        .reset_seen     ()
    );
    always @(posedge clk)
        if (!reset) begin
            cycles <= cycles + 1;
            if (rv && ready) begin
                output_bytes[count] <= rd;
                count               <= count + 1;
            end
            if (cv && cr && allow) codecs <= codecs + 1;
            if (!hr) $fatal(1, "serial TX blocked");
            if (cycles > 100000) $fatal(1, "peer timeout state%0d count%0d", dut.state, count);
        end
    task tick;
        begin
            @(negedge clk);
            #1;
        end
    endtask
    task quiet;
        input integer old_count;
        begin
            repeat (25) tick();
            if (count != old_count) $fatal(1, "unexpected response");
        end
    endtask
    task emit;
        input integer bytes;
        begin
            for (n = 0; n < bytes; n = n + 1) begin
                hv = 1;
                hd = input_bytes[n];
                tick();
                hv = 0;
                tick();
            end
        end
    endtask
    task checksum;
        input integer bytes;
        begin
            check = 0;
            for (i = 2; i < bytes - 2; i = i + 2)
            check = check ^ {input_bytes[i], input_bytes[i+1]};
            input_bytes[bytes-2] = check[15:8];
            input_bytes[bytes-1] = check[7:0];
        end
    endtask
    task header;
        input [7:0] resource, length;
        begin
            for (i = 0; i < 256; i = i + 1) input_bytes[i] = 0;
            input_bytes[0] = 8'h55;
            input_bytes[1] = 8'h55;
            input_bytes[2] = 8'h20;
            input_bytes[3] = 8'h78;
            input_bytes[5] = resource;
            input_bytes[7] = length;
        end
    endtask
    task acknowledge;
        input [7:0] flags;
        begin
            header(8'h7f, 2);
            input_bytes[8] = 8'h82;
            input_bytes[9] = flags;
            checksum(12);
            emit(12);
        end
    endtask
    task request;
        input [2:0] seq;
        input [15:0] id;
        input [7:0] message;
        input corrupt;
        begin
            header(8'h82, 12);
            input_bytes[8]  = 8'h12;
            input_bytes[9]  = 8'h34;
            input_bytes[10] = 8'h0e;
            input_bytes[11] = message;
            input_bytes[13] = 7;
            input_bytes[14] = id[15:8];
            input_bytes[15] = id[7:0];
            input_bytes[18] = 1;
            input_bytes[19] = 8'h40 | seq;
            checksum(22);
            if (corrupt) input_bytes[21] = input_bytes[21] ^ 1;
            emit(22);
        end
    endtask
    task packet_check;
        input integer start, bytes;
        begin
            check = 0;
            for (i = start + 2; i < start + bytes; i = i + 2)
            check = check ^ {output_bytes[i], output_bytes[i+1]};
            if (check != 0) $fatal(1, "bad device checksum %h", check);
        end
    endtask
    task await_bytes;
        input integer wanted;
        begin
            while (count < wanted) begin
                ready = (cycles % 4) != 0;
                tick();
            end
            ready = 1;
            tick();
            if (count != wanted) $fatal(1, "extra bytes %0d expected%0d", count, wanted);
        end
    endtask
    task validate_reply;
        input integer start;
        input [2:0] expected_seq;
        input [15:0] id, result;
        begin
            packet_check(start, 22);
            if(output_bytes[start+5]!=8'h82 || output_bytes[start+7]!=12 ||
                output_bytes[start+8]!=8'h34 || output_bytes[start+9]!=8'h12 ||
                output_bytes[start+10]!=8'h0e || output_bytes[start+11]!=8'h8b ||
                {output_bytes[start+14],output_bytes[start+15]}!=id ||
                {output_bytes[start+16],output_bytes[start+17]}!=result ||
                output_bytes[start+18]!=1 || output_bytes[start+19]!=(8'h60|expected_seq))
                $fatal(1, "native reply layout/ownership");
            $fwrite(file, "reply ");
            for (i = start; i < start + 22; i = i + 1) $fwrite(file, "%02x", output_bytes[i]);
            $fwrite(file, "\n");
        end
    endtask
    task start_link;
        begin
            enabled = 1;
            ready   = 0;
            repeat (2) tick();
            repeat (8) begin
                tick();
                if (!rv || rd != 8'h55 || link) $fatal(1, "stalled startup");
            end
            base = count;
            await_bytes(base + 28);
            packet_check(base, 14);
            packet_check(base + 14, 14);
            if (link) $fatal(1, "link ready without ACK");
            header(8'hd0, 3);
            input_bytes[8]  = 5;
            input_bytes[9]  = 1;
            input_bytes[10] = 8'h40;
            checksum(14);
            emit(14);
            repeat (3) tick();
            if (!link) $fatal(1, "native D0/05 did not ready link");
        end
    endtask
    initial begin
        file = $fopen("build/sim/unit-adsp-boot-peer/replies.txt", "w");
        repeat (3) tick();
        reset = 0;
        quiet(0);
        start_link();
        base = count;
        request(1, 16'h42, 8'h2b, 1);
        quiet(base);
        // Codec backpressure must hold its control transaction, not pass early.
        allow = 0;
        request(1, 16'h42, 8'h2b, 0);
        await_bytes(base + 12);
        repeat (8) tick();
        if (count != base + 12 || !cv || cw != 16'h1e00 || ca != 7'h1a)
            $fatal(1, "codec ownership");
        allow = 1;
        await_bytes(base + 34);
        packet_check(base, 12);
        validate_reply(base + 12, 0, 16'h42, 0);
        if (codecs != 1) $fatal(1, "diagnostic codec count");
        if (debug_status[11:8] !== 4'b0111) $fatal(1, "diagnostic completion observation");
        // Duplicate input and NACK replay the owned result; neither reruns42.
        base = count;
        request(1, 16'h42, 8'h2b, 0);
        await_bytes(base + 34);
        validate_reply(base + 12, 0, 16'h42, 0);
        base = count;
        acknowledge(8'h80);
        await_bytes(base + 22);
        validate_reply(base, 0, 16'h42, 0);
        if (codecs != 1) $fatal(1, "replay reran codec");
        acknowledge(0);
        repeat (3) tick();
        if (debug_status[11:8] !== 4'b1111) $fatal(1, "native ACK observation");
        base = count;
        request(1, 16'h42, 8'h2b, 0);
        await_bytes(base + 12);
        quiet(base + 12);
        // Unsupported operation gets a transport ACK, no invented application response.
        base = count;
        request(2, 16'h42, 8'h2c, 0);
        await_bytes(base + 12);
        quiet(base + 12);
        // Known diagnostic envelope with unsupported test reports native failure.
        base = count;
        request(3, 16'h43, 8'h2b, 0);
        await_bytes(base + 34);
        validate_reply(base + 12, 1, 16'h43, 12);
        if (codecs != 1) $fatal(1, "unknown test touched codec");
        acknowledge(1);
        // Separate prerequisite failures remain observable rather than generic pass.
        locked = 0;
        base   = count;
        request(4, 16'h42, 8'h2b, 0);
        await_bytes(base + 34);
        validate_reply(base + 12, 2, 16'h42, 12);
        if (debug_status[11:8] !== 4'b0011) $fatal(1, "failed prerequisite observation");
        acknowledge(2);
        locked = 1;
        fv     = 0;
        base   = count;
        request(5, 16'h42, 8'h2b, 0);
        await_bytes(base + 34);
        validate_reply(base + 12, 3, 16'h42, 12);
        acknowledge(3);
        fv     = 1;
        marker = 16'hffff;
        base   = count;
        request(6, 16'h42, 8'h2b, 0);
        await_bytes(base + 34);
        validate_reply(base + 12, 4, 16'h42, 12);
        acknowledge(4);
        marker = 16'hfffc;
        inject = 1;
        base   = count;
        request(7, 16'h42, 8'h2b, 0);
        await_bytes(base + 34);
        validate_reply(base + 12, 5, 16'h42, 12);
        acknowledge(5);
        inject = 0;
        // Link disable cancels a held response and parser, preserving TX drain.
        ready  = 0;
        request(0, 16'h42, 8'h2b, 0);
        repeat (5) tick();
        enabled = 0;
        tick();
        if (rv || link || !hr) $fatal(1, "disable ownership");
        start_link();
        if (debug_status[11:8] !== 4'b1011) $fatal(1, "clock gating discarded observation");
        reset = 1;
        repeat (3) tick();
        if (debug_status[11:8] !== 0) $fatal(1, "phone reset did not clear observations");
        $fclose(file);
        $display(
            "PASS D550 boot peer: startup ACK, native 2B/8B, CRC, routing, stalls, codec prerequisite failures, unsupporteds, duplicate/NACK replay, sequence and disable/reset");
        $finish;
    end
endmodule
