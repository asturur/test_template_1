`timescale 1ns/1ps
module tb;
    localparam MEMORY_BYTES = 1024;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg transfer_valid = 0;
    wire transfer_ready;
    reg [31:0] source_addr = 0;
    reg [31:0] destination_addr = 0;
    reg [2:0] source_bytes = 1;
    reg [2:0] destination_bytes = 1;
    reg source_increment = 1;
    reg destination_increment = 1;
    reg [34:0] transfer_bytes = 0;
    reg source_ready = 1;
    reg destination_ready = 1;
    reg stop = 0;
    wire busy, done, error, aborted;
    wire cmd_valid, cmd_write, cmd_ready;
    wire [31:0] cmd_addr, cmd_data;
    wire [3:0] cmd_be;
    wire rsp_valid, rsp_error;
    wire [31:0] rsp_data;

    ngage_dma_engine dut (
        .clk(clk),
        .reset(reset),
        .transfer_valid(transfer_valid),
        .transfer_ready(transfer_ready),
        .source_addr(source_addr),
        .destination_addr(destination_addr),
        .source_bytes(source_bytes),
        .destination_bytes(destination_bytes),
        .source_increment(source_increment),
        .destination_increment(destination_increment),
        .transfer_bytes(transfer_bytes),
        .source_ready(source_ready),
        .destination_ready(destination_ready),
        .stop(stop),
        .busy(busy),
        .done(done),
        .error(error),
        .aborted(aborted),
        .cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),
        .cmd_write(cmd_write),
        .cmd_addr(cmd_addr),
        .cmd_data(cmd_data),
        .cmd_be(cmd_be),
        .rsp_valid(rsp_valid),
        .rsp_error(rsp_error),
        .rsp_data(rsp_data)
    );

    reg [7:0] memory [0:MEMORY_BYTES-1];
    reg [7:0] initial_memory [0:MEMORY_BYTES-1];
    reg [7:0] expected_memory [0:MEMORY_BYTES-1];
    reg [7:0] stream [0:255];
    integer cycle = 0;
    integer cases = 0;
    integer total_requests = 0;
    integer reads = 0;
    integer read_total = 0;
    integer written = 0;
    integer requests = 0;
    integer terminals = 0;
    integer units, sw, dw, sa, da, total;
    reg si, di;
    reg check_commands = 1;
    reg zero_latency = 0;
    reg hold_bus = 0;
    reg paced = 0;
    integer fail_request = -1;
    integer latency = 0;
    reg pending = 0;
    integer delay_left = 0;
    reg saved_write;
    reg [31:0] saved_addr, saved_data;
    reg [3:0] saved_be;
    reg saved_error;
    reg rsp_valid_reg = 0;
    reg rsp_error_reg = 0;
    reg [31:0] rsp_data_reg = 0;
    reg [31:0] immediate_data;
    assign cmd_ready = !hold_bus && !pending && !rsp_valid_reg && (cycle % 5 != 1);
    wire accepted = cmd_valid && cmd_ready;
    assign rsp_valid = zero_latency ? accepted : rsp_valid_reg;
    assign rsp_error = zero_latency ? requests == fail_request : rsp_error_reg;
    assign rsp_data = zero_latency ? immediate_data : rsp_data_reg;
    integer lane, j;
    always @* begin
        immediate_data = 0;
        if (cmd_addr < MEMORY_BYTES - 3)
            for (j = 0; j < 4; j = j + 1)
                immediate_data[j*8 +: 8] = memory[cmd_addr + j];
    end

    // Independent byte oracle: command addresses follow source/destination
    // unit sequences, and write payloads come from the original byte stream.
    // It does not reproduce the engine's buffer or read/write scheduling.
    integer logical_addr, nbytes, b, expected_be;
    reg [31:0] expected_data;
    reg stalled = 0;
    reg [68:0] stalled_packet;
    reg previous_terminal = 0;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (!reset) begin
            if ((done && error) || (done && aborted) || (error && aborted))
                $fatal(1, "multiple terminal outcomes");
            if (done || error || aborted) begin
                terminals = terminals + 1;
                if (previous_terminal) $fatal(1, "terminal pulse held");
            end
            previous_terminal = done || error || aborted;
            if (busy && transfer_ready) $fatal(1, "active descriptor may be overwritten");
            if (stalled && !stop && !reset) begin
                if (!cmd_valid || {cmd_write, cmd_addr, cmd_data, cmd_be} !== stalled_packet)
                    $fatal(1, "offered packet changed under backpressure");
            end
            stalled = cmd_valid && !cmd_ready;
            stalled_packet = {cmd_write, cmd_addr, cmd_data, cmd_be};
            if (pending && cmd_valid) $fatal(1, "second request while a word is owned");
            if (accepted) begin
                if (!check_commands) $fatal(1, "invalid descriptor issued a request");
                if (cmd_addr[1:0] != 0 || cmd_be == 0 || cmd_addr > MEMORY_BYTES - 4)
                    $fatal(1, "malformed memory word");
                if (cmd_write) begin
                    nbytes = total - written;
                    if (nbytes > dw) nbytes = dw;
                    if (nbytes <= 0) $fatal(1, "extra destination unit");
                    logical_addr = da + (di ? written : 0);
                    expected_data = 0;
                    expected_be = 0;
                    for (b = 0; b < nbytes; b = b + 1) begin
                        expected_be = expected_be | (1 << ((logical_addr % 4) + b));
                        expected_data[((logical_addr % 4) + b)*8 +: 8] = stream[written+b];
                    end
                    if (written + nbytes > read_total)
                        $fatal(1, "write consumed unread bytes");
                    if (cmd_addr !== (logical_addr & 32'hfffffffc) ||
                        cmd_be !== expected_be[3:0] || cmd_data !== expected_data)
                        $fatal(1, "write oracle case=%0d byte=%0d got=%h/%h/%h expected=%h/%h/%h",
                               cases, written, cmd_addr, cmd_be, cmd_data,
                               logical_addr & 32'hfffffffc, expected_be[3:0], expected_data);
                    written = written + nbytes;
                end else begin
                    if (reads >= units) $fatal(1, "extra source unit");
                    logical_addr = sa + (si ? reads * sw : 0);
                    nbytes = total - read_total;
                    if (nbytes > sw) nbytes = sw;
                    expected_be = ((1 << nbytes) - 1) << (logical_addr % 4);
                    if (cmd_addr !== (logical_addr & 32'hfffffffc) ||
                        cmd_be !== expected_be[3:0] || cmd_data !== 0)
                        $fatal(1, "read oracle case=%0d unit=%0d", cases, reads);
                    reads = reads + 1;
                    read_total = read_total + nbytes;
                end
                if (zero_latency) begin
                    if (cmd_write && requests != fail_request)
                        for (lane = 0; lane < 4; lane = lane + 1)
                            if (cmd_be[lane]) memory[cmd_addr+lane] = cmd_data[lane*8 +: 8];
                end else begin
                    pending <= 1;
                    saved_write <= cmd_write;
                    saved_addr <= cmd_addr;
                    saved_data <= cmd_data;
                    saved_be <= cmd_be;
                    saved_error <= requests == fail_request;
                    delay_left <= latency + requests % 4;
                end
                requests = requests + 1;
                total_requests = total_requests + 1;
            end
            rsp_valid_reg <= 0;
            if (pending) begin
                if (delay_left != 0) delay_left <= delay_left - 1;
                else begin
                    pending <= 0;
                    rsp_valid_reg <= 1;
                    rsp_error_reg <= saved_error;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        rsp_data_reg[lane*8 +: 8] <= memory[saved_addr+lane];
                        if (saved_write && saved_be[lane] && !saved_error)
                            memory[saved_addr+lane] = saved_data[lane*8 +: 8];
                    end
                end
            end
        end else begin
            pending <= 0;
            rsp_valid_reg <= 0;
            stalled = 0;
            previous_terminal = 0;
        end
    end

    // Enable deterministic endpoint waits without occupying the memory port.
    always @(negedge clk) begin
        if (paced) begin
            source_ready = cycle % 11 >= 7;
            destination_ready = cycle % 13 >= 8;
        end
    end

    task prepare_bytes;
        input integer source_width, destination_width, byte_budget, source_lane, destination_lane;
        input source_inc, destination_inc;
        integer i, j, target;
        begin
            @(negedge clk);
            if (!transfer_ready || pending || rsp_valid_reg) $fatal(1, "test began before drain");
            cases = cases + 1;
            if (cases % 256 == 0) begin
                $display("DMA engine matrix progress: %0d cases", cases);
                $fflush();
            end
            sw = source_width;
            dw = destination_width;
            total = byte_budget;
            units = (total + sw - 1) / sw;
            sa = 64 + source_lane;
            da = 512 + destination_lane;
            si = source_inc;
            di = destination_inc;
            reads = 0;
            read_total = 0;
            written = 0;
            requests = 0;
            fail_request = -1;
            check_commands = 1;
            for (i = 0; i < MEMORY_BYTES; i = i + 1) begin
                memory[i] = (i * 29 + cases * 13 + (i / 7)) % 256;
                initial_memory[i] = memory[i];
                expected_memory[i] = memory[i];
            end
            for (i = 0; i < total; i = i + 1)
                stream[i] = memory[sa + (si ? i : i % sw)];
            for (i = 0; i < total; i = i + dw)
                for (j = 0; j < dw && i+j < total; j = j + 1) begin
                    target = da + (di ? i : 0) + j;
                    expected_memory[target] = stream[i+j];
                end
            source_addr = sa;
            destination_addr = da;
            source_bytes = sw;
            destination_bytes = dw;
            source_increment = si;
            destination_increment = di;
            transfer_bytes = total;
        end
    endtask

    // Retain the original complete-source-unit matrix as a regression of
    // the byte-budget engine: count source units imply count * width bytes.
    task prepare;
        input integer source_width, destination_width, count, source_lane, destination_lane;
        input source_inc, destination_inc;
        begin
            prepare_bytes(source_width, destination_width, count * source_width,
                          source_lane, destination_lane, source_inc, destination_inc);
        end
    endtask

    task launch;
        begin
            transfer_valid = 1;
            @(posedge clk);
            @(negedge clk);
            transfer_valid = 0;
            // Active work must use captured fields, including its byte budget/modes.
            source_addr = 32'hffffffff;
            destination_addr = 32'hdeadbeef;
            source_bytes = 3;
            destination_bytes = 0;
            source_increment = !si;
            destination_increment = !di;
            transfer_bytes = 35'h7ffffffff;
        end
    endtask

    task result;
        input integer outcome; // 0 done, 1 error, 2 aborted
        integer timeout_count, terminal_before, i;
        begin
            timeout_count = 0;
            terminal_before = terminals;
            while (!(done || error || aborted)) begin
                @(negedge clk);
                timeout_count = timeout_count + 1;
                if (timeout_count > 4000) $fatal(1, "timeout case=%0d", cases);
            end
            if ((outcome == 0 && !done) || (outcome == 1 && !error) ||
                (outcome == 2 && !aborted))
                $fatal(1, "wrong terminal outcome case=%0d expected=%0d got=%b%b%b",
                       cases, outcome, done, error, aborted);
            if (pending || busy) $fatal(1, "terminal before owned word drained");
            if (outcome == 0) begin
                if (reads != units || read_total != total || written != total)
                    $fatal(1, "incomplete success");
                for (i = 0; i < MEMORY_BYTES; i = i + 1)
                    if (memory[i] !== expected_memory[i])
                        $fatal(1, "memory byte mismatch case=%0d addr=%0d", cases, i);
            end
            @(negedge clk);
            if (done || error || aborted) $fatal(1, "outcome was not a pulse");
            if (terminals != terminal_before + 1) $fatal(1, "duplicate/missing outcome");
        end
    endtask

    integer s, d, count, mode, sl, dl, z, before_requests, budget;
    initial begin
        repeat (3) @(negedge clk);
        reset = 0;
        for (z = 0; z < 2; z = z + 1) begin
            zero_latency = z;
            paced = !z;
            source_ready = 1;
            destination_ready = 1;
            for (s = 1; s <= 4; s = s * 2)
                for (d = 1; d <= 4; d = d * 2)
                    for (mode = 0; mode < 4; mode = mode + 1)
                        for (count = 1; count <= 9; count = count + 1)
                            for (sl = 0; sl < 4; sl = sl + s)
                                for (dl = 0; dl < 4; dl = dl + d) begin
                                    prepare(s, d, count, sl, dl, mode[0], mode[1]);
                                    launch;
                                    result(0);
                                end
            // Byte budgets that end inside a native source unit. Every
            // legal lane/mode and destination width also sees these tails.
            for (s = 2; s <= 4; s = s * 2)
                for (d = 1; d <= 4; d = d * 2)
                    for (mode = 0; mode < 4; mode = mode + 1)
                        for (budget = 1; budget <= 13; budget = budget + 1)
                            if (budget % s != 0)
                                for (sl = 0; sl < 4; sl = sl + s)
                                    for (dl = 0; dl < 4; dl = dl + d) begin
                                        prepare_bytes(s, d, budget, sl, dl, mode[0], mode[1]);
                                        launch;
                                        result(0);
                                    end
        end
        paced = 0;
        source_ready = 1;
        destination_ready = 1;
        zero_latency = 0;

        // Fixed endpoints must wait before offering; incrementing memory
        // continues despite these inputs, as covered by the matrix above.
        prepare(2, 4, 5, 2, 0, 0, 0);
        source_ready = 0;
        destination_ready = 0;
        launch;
        repeat (10) begin
            @(negedge clk);
            if (cmd_valid || requests != 0) $fatal(1, "unready fixed source took bus");
        end
        source_ready = 1;
        while (reads < 2) @(negedge clk);
        repeat (15) @(negedge clk);
        if (written != 0 || cmd_valid) $fatal(1, "unready fixed destination took bus");
        destination_ready = 1;
        result(0);

        // Withdraw an unaccepted offer. A restart cannot overwrite that offer.
        prepare(4, 4, 8, 0, 0, 1, 1);
        hold_bus = 1;
        launch;
        while (!cmd_valid) @(negedge clk);
        transfer_valid = 1;
        repeat (6) begin
            @(negedge clk);
            if (transfer_ready) $fatal(1, "restart admitted while offered");
        end
        transfer_valid = 0;
        stop = 1;
        if (requests != 0) $fatal(1, "test offer accidentally accepted");
        result(2);
        stop = 0;
        hold_bus = 0;
        prepare(1, 4, 7, 3, 0, 1, 1);
        launch;
        result(0);

        // Stop each kind of accepted word; a one-cycle stop pulse is sticky
        // through the delayed response, including accepted-write side effects.
        for (mode = 0; mode < 2; mode = mode + 1) begin
            prepare(4, 4, 8, 0, 0, 1, 1);
            latency = 12;
            launch;
            while (!(pending && saved_write == mode[0])) @(negedge clk);
            before_requests = requests;
            stop = 1;
            @(negedge clk);
            stop = 0;
            if (transfer_ready || !busy) $fatal(1, "stop did not drain");
            result(2);
            if (requests != before_requests) $fatal(1, "stop issued more words");
            if (mode == 1)
                for (b = 0; b < 4; b = b + 1)
                    if (memory[da+b] !== stream[b]) $fatal(1, "accepted write was lost");
            prepare(2, 1, 3, 2, 3, 1, 1);
            launch;
            result(0);
        end
        latency = 0;

        // Fail both initial and later reads/writes, delayed and same-edge.
        for (z = 0; z < 2; z = z + 1)
            for (mode = 0; mode < 6; mode = mode + 1) begin
                zero_latency = z;
                prepare(4, 4, 8, 0, 0, 1, 1);
                fail_request = mode;
                launch;
                result(1);
                if (requests != mode + 1) $fatal(1, "error did not halt immediately");
                for (b = 0; b < MEMORY_BYTES; b = b + 1)
                    if (b >= da && b < da + mode / 2 * 4) begin
                        if (memory[b] !== stream[b-da]) $fatal(1, "successful prefix was lost");
                    end else if (memory[b] !== initial_memory[b])
                        $fatal(1, "failed word or unissued suffix committed");
            end
        zero_latency = 0;

        // A failed partial source read must not flush the earlier buffered
        // bytes as a fabricated complete destination word. A failed final
        // destination tail preserves only the successful write prefix.
        for (z = 0; z < 2; z = z + 1) begin
            zero_latency = z;
            prepare_bytes(2, 4, 3, 2, 0, 1, 1);
            fail_request = 1;
            launch;
            result(1);
            if (requests != 2 || written != 0) $fatal(1, "failed source tail was flushed");
            for (b = 0; b < MEMORY_BYTES; b = b + 1)
                if (memory[b] !== initial_memory[b]) $fatal(1, "failed read changed memory");
            prepare_bytes(4, 2, 3, 0, 2, 1, 1);
            fail_request = 2;
            launch;
            result(1);
            if (requests != 3) $fatal(1, "failed write tail did not halt");
            for (b = 0; b < MEMORY_BYTES; b = b + 1)
                if (b >= da && b < da + 2) begin
                    if (memory[b] !== stream[b-da]) $fatal(1, "write prefix was lost");
                end else if (memory[b] !== initial_memory[b])
                    $fatal(1, "failed write tail changed memory");
        end
        zero_latency = 0;

        // Stop on the response edge, both successfully and with an error.
        // An error must never be converted into a benign cancellation.
        for (mode = 0; mode < 2; mode = mode + 1) begin
            prepare(4, 4, 1, 0, 0, 1, 1);
            fail_request = mode == 1 ? 0 : -1;
            launch;
            while (!rsp_valid) @(negedge clk);
            stop = 1;
            result(mode == 1 ? 1 : 2);
            stop = 0;
            if (requests != 1 || written != 0) $fatal(1, "response-edge stop launched write");
        end

        // Large budgets fit the byte counter when both endpoints are fixed.
        // The physical last byte may be 0xffffffff.
        for (mode = 0; mode < 3; mode = mode + 1) begin
            prepare(4, 4, 1, 0, 0, 0, 0);
            hold_bus = 1;
            if (mode == 0) transfer_bytes = 35'h7ffffffff;
            else if (mode == 1) begin
                source_addr = 32'hffffffff;
                destination_addr = 32'hffffffff;
                source_bytes = 1;
                destination_bytes = 1;
                source_increment = 1;
                destination_increment = 1;
                transfer_bytes = 1;
            end else begin
                source_addr = 0;
                destination_addr = 0;
                source_bytes = 1;
                destination_bytes = 1;
                source_increment = 1;
                destination_increment = 1;
                transfer_bytes = 35'h100000000;
            end
            launch;
            while (!cmd_valid) begin
                @(negedge clk);
                if (error || !busy) $fatal(1, "valid range/count boundary rejected");
            end
            if (mode == 1 && (cmd_addr !== 32'hfffffffc || cmd_be !== 4'b1000))
                $fatal(1, "last physical byte packet malformed");
            stop = 1;
            result(2);
            stop = 0;
            hold_bus = 0;
        end

        // Reset is a coordinated cancellation with the downstream adapter;
        // it produces no terminal result and a fresh transfer can follow.
        prepare(4, 4, 8, 0, 0, 1, 1);
        latency = 12;
        launch;
        while (!pending) @(negedge clk);
        reset = 1;
        repeat (2) @(negedge clk);
        if (busy || cmd_valid || done || error || aborted || pending)
            $fatal(1, "reset did not cancel engine/adapter ownership");
        reset = 0;
        latency = 0;
        prepare(4, 1, 5, 0, 2, 1, 1);
        launch;
        result(0);

        // Unsupported widths, natural alignment and 32-bit address overflow.
        for (mode = 0; mode < 12; mode = mode + 1) begin
            prepare(4, 4, 2, 0, 0, 1, 1);
            check_commands = 0;
            case (mode)
                0: source_bytes = 0;
                1: source_bytes = 3;
                2: destination_bytes = 7;
                3: source_addr = sa + 1;
                4: destination_addr = da + 2;
                5: source_addr = 32'hfffffffc;
                6: destination_addr = 32'hfffffffc;
                7: transfer_bytes = 35'h400000000;
                8: begin
                    source_bytes = 1;
                    transfer_bytes = 35'h100000000;
                end
                9: transfer_bytes = 0;
                10: transfer_bytes = 35'h7ffffffff;
                11: begin
                    source_increment = 0;
                    transfer_bytes = 35'h7ffffffff;
                end
            endcase
            launch;
            result(1);
            if (requests != 0) $fatal(1, "rejected descriptor used bus");
        end
        $display("PASS DMA engine: %0d cases, %0d owned words, byte oracle/stalls/stop/errors", cases, total_requests);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "global timeout");
    end
endmodule
