`timescale 1ns/1ps
// Actual outer arbiter + adapter; delayed native-word controller contract.
// Physical command/timing/line coverage remains in the Micron-model fixtures.
module ownership_tb;
    parameter TAKE_WAIT = 7;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1, phone_reset = 1;
    reg req = 0, we = 0;
    reg [24:0] addr = 0;
    reg [31:0] data = 0;
    reg [3:0] be = 0;
    wire accept, ack, owner_ready, mem_req, mem_we, mem_ack, scrub_done;
    wire [24:0] mem_addr;
    wire [31:0] mem_data, mem_rdata, rdata;
    wire [3:0] mem_be, rd, wr;
    wire [21:0] ba_addr;
    wire [15:0] ba_data;
    wire [1:0] ba_mask, ba_line;
    reg [3:0] ba_ack = 0, ba_ready = 0, ba_dst = 0;
    reg [15:0] ba_rdata = 0;
    reg [15:0] memory [0:127];
    integer phase = 0, delay_left = 0, recover_left = 0;
    integer saved_addr = 0, cycles = 0, completed = 0, accepted = 0;
    reg writing = 0;
    wire allow_owner;
`ifdef SDRAM_SHARED_PAYLOAD
`ifdef OMIT_OWNER_GUARD
    assign allow_owner = 1;
`else
    assign allow_owner = owner_ready;
`endif
`else
    assign owner_ready = 1;
    assign allow_owner = 1;
`endif
    ngage_sdram_arbiter arb (
        .clk(clk), .reset(phone_reset), .cpu_lock(1'b0),
        .cpu_req(req && allow_owner), .cpu_we(we), .cpu_addr(addr),
        .cpu_data(data), .cpu_be(be), .cpu_ack(ack), .cpu_rdata(rdata), .cpu_accept(accept),
        .dma_req(1'b0), .dma_we(1'b0), .dma_addr(25'b0), .dma_data(32'b0),
        .dma_be(4'b0), .dma_ack(), .dma_rdata(), .dma_accept(),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_data(mem_data), .mem_be(mem_be), .mem_ack(mem_ack), .mem_rdata(mem_rdata)
    );
    ngage_sdram_adapter #(.RAM_BYTES(4), .REFRESH_PERIOD(250)) adapter (
`ifdef SDRAM_SHARED_PAYLOAD
        .owner_ready(owner_ready),
`endif
        .clk(clk), .rst(reset), .phone_reset(phone_reset), .init(1'b0),
        .req(mem_req), .we(mem_we), .addr(mem_addr), .din(mem_data), .be(mem_be),
        .ack(mem_ack), .dout(mem_rdata), .scrub_done(scrub_done),
        .line_req(1'b0), .line_addr(25'b0), .line_ready(), .line_valid(),
        .line_data(), .line_last(), .ba_line(ba_line),
        .ba_addr(ba_addr), .ba_din(ba_data), .ba_dsn(ba_mask), .rd(rd), .wr(wr),
        .ba_ack(ba_ack), .ba_dst(ba_dst), .ba_rdy(ba_ready), .ba_dout(ba_rdata), .rfsh()
    );
    // ACK selects the upper write halfword for the consecutive second edge.
    // Keep request acceptance delayed to expose a canceled owner overwritten
    // before a previously offered physical command has actually started.
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (accept) accepted = accepted + 1;
        if (ack) completed = completed + 1;
        ba_ack <= 0;
        ba_ready <= 0;
        ba_dst <= 0;
        case (phase)
            0: if (!reset && |(rd | wr)) begin
                saved_addr = ba_addr;
                writing = |wr;
                delay_left = TAKE_WAIT;
                phase = 1;
            end
            1: if (delay_left > 0) delay_left = delay_left - 1;
               else begin
                   ba_ack <= 1;
                   if (writing) begin
                       if (!ba_mask[0]) memory[saved_addr][7:0] <= ba_data[7:0];
                       if (!ba_mask[1]) memory[saved_addr][15:8] <= ba_data[15:8];
                   end
                   phase = 2;
               end
            2: begin
                if (writing) begin
                    if (!ba_mask[0]) memory[saved_addr+1][7:0] <= ba_data[7:0];
                    if (!ba_mask[1]) memory[saved_addr+1][15:8] <= ba_data[15:8];
                end else begin
                    ba_dst <= 1;
                    ba_rdata <= memory[saved_addr];
                end
                phase = 3;
            end
            3: begin
                ba_rdata <= memory[saved_addr+1];
                recover_left = 3;
                phase = 4;
            end
            4: if (recover_left > 0) recover_left = recover_left - 1;
               else begin ba_ready <= 1; phase = 5; end
            5: phase = 0;
        endcase
    end
    task transaction(input bit write_value, input [24:0] address_value,
                     input [31:0] payload, input [3:0] lanes, input [31:0] expected);
        integer start_cycle, before_done, before_accept;
        begin
            @(negedge clk);
            req = 1; we = write_value; addr = address_value; data = payload; be = lanes;
            start_cycle = cycles; before_done = completed; before_accept = accepted;
            wait(accept); @(negedge clk);
            // Producers may change every payload field after admission.
            we = !write_value; addr = 25'h1fc; data = ~payload; be = ~lanes;
            while (!ack && cycles - start_cycle < 300) @(negedge clk);
            if (!ack || (!write_value && rdata !== expected))
                $fatal(1, "owned request data/timeout address=%h got=%h expected=%h", address_value, rdata, expected);
            $display("OWNER_LATENCY write=%0d mask=%0d clocks=%0d", write_value, lanes, cycles-start_cycle);
            req = 0;
            repeat(5) @(negedge clk);
            if (completed != before_done+1 || accepted != before_accept+1)
                $fatal(1, "duplicate/missing owner or response");
        end
    endtask
    task canceled_write(input bit after_launch);
        integer before_done, start_cycle;
        begin
            @(negedge clk); req=1; we=1; addr=25'h80; data=32'ha1b2c3d4; be=4'h5;
            wait(accept); @(negedge clk);
            if (after_launch) wait(adapter.state==2);
            else wait(phase==1 && adapter.state==1);
            @(negedge clk); phone_reset=1; req=0; before_done=completed;
            @(negedge clk); phone_reset=0; req=1; we=1; addr=25'h84; data=32'h11223344; be=15;
            start_cycle=cycles;
            while (!ack && cycles-start_cycle<300) @(negedge clk);
            if (!ack) $fatal(1,"canceled write/new owner timeout");
            req=0; repeat(5) @(negedge clk);
            if (completed!=before_done+1 || {memory[65],memory[64]}!==32'h00b200d4 ||
                {memory[67],memory[66]}!==32'h11223344)
                $fatal(1,"canceled write payload or response escaped drain old=%h new=%h",{memory[65],memory[64]},{memory[67],memory[66]});
            $display("OWNER_RESET after_launch=%0d new_response_clocks=%0d",after_launch,cycles-start_cycle-5);
        end
    endtask
    integer i;
    reg [31:0] expected;
    initial begin
        for(i=0;i<128;i=i+1) memory[i]=0;
        repeat(4) @(negedge clk); reset=0;
        wait(scrub_done); @(negedge clk); phone_reset=0;
        for(i=0;i<16;i=i+1) begin
            expected=((i&1)?32'h000000ef:0)|((i&2)?32'h0000cd00:0)|
                     ((i&4)?32'h00ab0000:0)|((i&8)?32'h89000000:0);
            transaction(1,4+i*4,32'h89abcdef,i[3:0],0);
            transaction(0,4+i*4,0,15,expected);
        end
        canceled_write(0);
        // Restore the first write's untouched lanes for the second reset probe.
        memory[64]=0;memory[65]=0;
        canceled_write(1);
        $display("PASS shared SDRAM ownership: all16 masks, post-admission mutation, delayed grant and reset drain wait=%0d",TAKE_WAIT);
        $finish;
    end
    initial begin #100000; $fatal(1,"ownership timeout"); end
endmodule
