`timescale 1ns/1ps
module tb;
    reg clk = 0, reset = 1, cyc = 0, drive_stb = 0, we = 0, code = 0;
    reg [31:0] address = 0, data = 0, rdata = 0;
    reg [3:0] sel = 0;
    reg ack = 0, error = 0;
    wire cpu_ack, cpu_error, bus_cyc, bus_stb, bus_we, bus_code;
    wire [31:0] cpu_data, bus_address, bus_data;
    wire [3:0] bus_sel;
    integer completed = 0, returned = 0, writes = 0, n, before_count;
    always #5 clk = ~clk;
    ngage_upp_bus_bridge dut (
        .clk(clk), .reset(reset), .master_cyc(cyc), .master_stb(drive_stb && !cpu_error),
        .master_we(we), .master_code(code), .master_address(address),
        .master_data(data), .master_sel(sel), .master_ack(cpu_ack),
        .master_error(cpu_error), .master_read_data(cpu_data),
        .bus_cyc(bus_cyc), .bus_stb(bus_stb), .bus_we(bus_we), .bus_code(bus_code),
        .bus_address(bus_address), .bus_data(bus_data), .bus_sel(bus_sel),
        .bus_ack(ack), .bus_error(error), .bus_read_data(rdata)
    );
    always @(posedge clk) if (!reset) begin
        if (bus_cyc && bus_stb && (ack || error)) completed = completed + 1;
        if (bus_cyc && bus_stb && ack && !error && bus_we) writes = writes + 1;
        if (cpu_ack || cpu_error) returned = returned + 1;
        if ((cpu_ack && cpu_error) || ((cpu_ack || cpu_error) && bus_stb))
            $fatal(1, "response overlapped downstream request or error/ACK");
    end
    task tick;
        begin @(posedge clk); #1; @(negedge clk); end
    endtask
    task beat;
        input integer id, wait_cycles;
        input fail;
        reg [31:0] expected;
        integer j, old_writes;
        begin
            cyc = 1; drive_stb = 1; we = id & 1; code = (id >> 1) & 1;
            address = 32'h08000000 + id * 4;
            data = 32'h12340000 + id; sel = id;
            expected = address ^ 32'h87654321;
            old_writes = writes;
            #1; if (bus_stb || cpu_ack || cpu_error) $fatal(1, "request bypassed capture");
            tick;
            for (j = 0; j <= wait_cycles; j = j + 1) begin
                if (!bus_cyc || !bus_stb || bus_address !== address || bus_data !== data ||
                    bus_sel !== sel || bus_code !== code || bus_we !== we)
                    $fatal(1, "request fields changed during wait");
                if (cpu_ack || cpu_error) $fatal(1, "early response");
                if (j != wait_cycles) tick;
            end
            ack = 1; error = fail; rdata = expected; // ERR wins over simultaneous ACK.
            #1; if (cpu_ack || cpu_error) $fatal(1, "response bypassed capture");
            tick;
            if (bus_stb || cpu_ack !== !fail || cpu_error !== fail || cpu_data !== expected)
                $fatal(1, "bad registered response id=%0d", id);
            ack = 0; error = 0; rdata = ~expected;
            #1; if (cpu_data !== expected) $fatal(1, "response data was not held");
            tick; // CPU consumes response; CYC/STB deliberately stay high.
            if (bus_stb || cpu_ack || cpu_error) $fatal(1, "duplicate response/request");
            if (writes != old_writes + ((id & 1) && !fail)) $fatal(1, "side effect duplicated");
            // Next call presents the next beat while CYC remains asserted.
        end
    endtask
    initial begin
        tick; reset = 0;
        for (n = 0; n < 200; n = n + 1) beat(n, n % 9, n % 11 == 0);
        cyc = 0; drive_stb = 0; tick;
        if (completed != 200 || returned != 200) $fatal(1, "lost/duplicated beat");
        // Reset cancels a waiting request and masks immediate downstream ACK.
        cyc = 1; drive_stb = 1; tick;
        reset = 1; ack = 1; #1;
        if (bus_stb || cpu_ack || cpu_error) $fatal(1, "reset did not cancel waiting beat");
        tick; cyc = 0; drive_stb = 0; reset = 0; ack = 0; tick;
        // CYC withdrawal before completion must neither commit nor return.
        cyc = 1; drive_stb = 1; tick;
        before_count = completed; cyc = 0; ack = 1; tick;
        ack = 0; drive_stb = 0; tick;
        if (completed != before_count || cpu_ack || cpu_error) $fatal(1, "cancelled beat completed");
        // Reset after capture of a response must not replay it after release.
        cyc = 1; drive_stb = 1; tick; ack = 1; tick;
        reset = 1; ack = 0; #1;
        if (cpu_ack || cpu_error || bus_stb) $fatal(1, "reset did not suppress response");
        tick; reset = 0; cyc = 0; drive_stb = 0; tick; tick;
        if (cpu_ack || cpu_error || bus_stb) $fatal(1, "response replayed after reset");
        $display("PASS UPP bridge: 200 beats, waits, exact-once writes, registered data/errors, cancellation and reset");
        $finish;
    end
endmodule
