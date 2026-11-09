`timescale 1ns/1ps
module tb;
    parameter REGISTERED_MASTER = 0;
    reg clk = 0, reset = 1, cyc = 0, drive_stb = 0, we = 0, code = 0;
    reg [31:0] address = 0, data = 0, rdata = 0;
    reg [3:0] sel = 0;
    reg ack = 0, error = 0;
    wire cpu_ack, cpu_error, bus_cyc, bus_stb, bus_we, bus_code;
    wire [31:0] cpu_data, bus_address, bus_data;
    wire [3:0] bus_sel;
    integer completed = 0, returned = 0, writes = 0, n, before_count;
    always #5 clk = ~clk;
    ngage_upp_bus_bridge #(.REGISTERED_MASTER(REGISTERED_MASTER)) dut (
        .clk(clk), .reset(reset), .master_cyc(cyc), .master_stb(drive_stb && !cpu_error),
        .master_we(we), .master_code(code), .master_address(address),
        .master_data(data), .master_sel(sel), .master_ack(cpu_ack),
        .master_error(cpu_error), .master_read_data(cpu_data),
        .bus_cyc(bus_cyc), .bus_stb(bus_stb), .bus_we(bus_we), .bus_code(bus_code),
        .bus_address(bus_address), .bus_data(bus_data), .bus_sel(bus_sel),
        .bus_ack(ack), .bus_error(error), .bus_read_data(rdata)
    );
    // Model the merger retiring its registered offer on response consumption.
    always @(posedge clk)
        if (REGISTERED_MASTER && (cpu_ack || cpu_error)) drive_stb <= 0;
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
            #1; if (bus_stb !== (REGISTERED_MASTER!=0) || cpu_ack || cpu_error)
                $fatal(1, "wrong request registration mode");
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
        if (REGISTERED_MASTER) begin
            // A peripheral can complete on the first presented request edge.
            // The upstream response must still be a registered payload/error.
            cyc=1;drive_stb=1;we=0;ack=1;error=0;rdata=32'h12345678;
            #1;if(!bus_stb || cpu_ack)$fatal(1,"bad immediate request");
            tick;
            if(bus_stb || !cpu_ack || cpu_data!==32'h12345678)
                $fatal(1,"first-edge completion lost");
            ack=0;tick;
            if(bus_stb || cpu_ack)$fatal(1,"immediate completion replayed");
            cyc=0;tick;
            if(completed!=201 || returned!=201)$fatal(1,"bad immediate count");
            cyc=1;drive_stb=1;ack=1;error=1;rdata=32'habcdef01;
            #1;if(cpu_error || !bus_stb)$fatal(1,"error bypassed response register");
            tick;
            if(cpu_ack || !cpu_error || bus_stb || cpu_data!==32'habcdef01)
                $fatal(1,"first-edge ACK/ERR priority or payload wrong");
            ack=0;error=0;tick;cyc=0;tick;
            if(completed!=202 || returned!=202)$fatal(1,"bad immediate error count");
            // The merger can also switch owners and offer a new registered
            // packet on the consumption edge, with CYC/STB staying asserted.
            cyc=1;drive_stb=1;address=32'h08000000;ack=1;rdata=32'h11112222;
            tick;ack=0;
            @(posedge clk);#1;
            address=32'h08000004;code=~code;drive_stb=1;
            @(negedge clk);
            if(!bus_stb || bus_address!==32'h08000004 || cpu_ack)
                $fatal(1,"new owner packet delayed or response repeated");
            ack=1;rdata=32'h33334444;tick;ack=0;
            if(!cpu_ack || cpu_data!==32'h33334444)$fatal(1,"handoff response mixed");
            tick;cyc=0;tick;
            if(completed!=204 || returned!=204)$fatal(1,"handoff lost/duplicated beat");
        end
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
        $display("PASS UPP bridge mode=%0d: waits, exact-once writes, registered data/errors, cancellation and reset",REGISTERED_MASTER);
        $finish;
    end
endmodule
