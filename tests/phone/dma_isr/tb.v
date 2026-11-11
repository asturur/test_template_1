`timescale 1ns / 1ps
// Original NEM-4 ISR and callees execute on ZAP. Bounded synthetic objects,
// section descriptor and captured ICU-disable writes supply the kernel context.
module tb;
    reg clk = 0, reset = 1;
    always #5 clk = ~clk;
    wire cyc, stb, write_op;
    wire [31:0] address, value, data, pc;
    wire [3:0] lanes;
    reg [31:0] program_words[0:2047];
    reg [31:0] app_words[0:180223];
    reg [31:0] kernel_ram[0:32767];
    reg [7:0] ram[0:4095];
    integer i, j, cycles = 0, delay = 0, wait_cycles = 0;
    integer checked = 0, starts = 0, callbacks = 0, disables = 0;
    integer stops = 0, idle_stops = 0, acknowledgments = 0, dma_delay = 0;
    integer isr_entries = 0, status_hits = 0, remaining_hits = 0;
    integer chunk_hits = 0, physical_hits = 0;
    // Observe retirement, not speculative instruction-bus fetches. A multi-
    // micro-op instruction counts once at its last committed operation.
    wire retired = cpu.u_zap.u_zap_core.u_zap_writeback.i_valid &&
        cpu.u_zap.u_zap_core.u_zap_writeback.i_uop_last;
    wire [31:0] retired_pc = cpu.u_zap.u_zap_core.u_zap_writeback.i_pc_plus_8_buf_ff - 8;
    wire access = cyc && stb;
    wire ack = access && delay >= wait_cycles && (!in_dma || dma_ready);
    wire in_program = address < 8192;
    wire in_app = address >= 32'h50320000 && address < 32'h503d0000;
    wire in_kernel_ram = address >= 32'h80000000 && address < 32'h80020000;
    wire in_dma = address >= 32'h58120300 && address < 32'h58120500;
    wire page_table = address == 32'h41000280;
    wire claim, bad, dma_ready;
    wire [31:0] dma_data;
    wire [7:0] irq, errors, active;
    wire cmd_valid, cmd_ready, cmd_write, rsp_valid, rsp_error;
    wire [31:0] cmd_addr, cmd_data, rsp_data;
    wire [3:0] cmd_be;
    wire ram_req, ram_write, ram_ack;
    wire [24:0] ram_addr;
    wire [31:0] ram_data;
    wire [3:0] ram_be;
    wire [11:0] rbase = ram_addr[11:0];
    wire [31:0] ram_rdata = {ram[rbase+3], ram[rbase+2], ram[rbase+1], ram[rbase]};
    assign ram_ack = ram_req && dma_delay >= wait_cycles + 1;
    wire local_valid;

    assign data = in_program ? program_words[address[12:2]] :
        in_app ? app_words[(address - 32'h50320000) >> 2] :
        in_kernel_ram ? kernel_ram[address[16:2]] :
        in_dma ? dma_data : page_table ? 32'h0a000002 : 0;
    ngage_cpu cpu (
        .clk(clk), .reset(reset), .irq(1'b0), .fiq(1'b0),
        .wb_cyc(cyc), .wb_stb(stb), .wb_write(write_op),
        .wb_address(address), .wb_write_data(value), .wb_byte_enable(lanes),
        .wb_ack(ack), .wb_read_data(data), .wb_error(1'b0), .debug_pc(pc)
    );
    ngage_dma_channels dut (
        .clk(clk), .reset(reset), .req(access && in_dma), .commit(ack && in_dma),
        .we(write_op), .addr(address - 32'h4c000000), .din(value), .sel(lanes),
        .claim(claim), .bad(bad), .dout(dma_data), .ready(dma_ready), .irq_pending(irq),
        .error_pending(errors), .active_channels(active),
        .source_ready(8'hff), .destination_ready(8'hff),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_data(cmd_data), .cmd_be(cmd_be),
        .rsp_valid(rsp_valid), .rsp_error(rsp_error), .rsp_data(rsp_data)
    );
    ngage_dma_route route (
        .clk(clk), .reset(reset), .cpu_lock(1'b0),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_data(cmd_data), .cmd_be(cmd_be),
        .rsp_valid(rsp_valid), .rsp_error(rsp_error), .rsp_data(rsp_data),
        .ram_req(ram_req), .ram_write(ram_write), .ram_addr(ram_addr),
        .ram_data(ram_data), .ram_be(ram_be), .ram_ack(ram_ack), .ram_rdata(ram_rdata),
        .local_valid(local_valid), .local_ready(1'b0), .local_write(),
        .local_addr(), .local_data(), .local_be(), .local_done(1'b0),
        .local_error(1'b0), .local_rdata(32'd0)
    );

    task verify_memory;
        input integer final_chunk;
        reg [7:0] expected;
        integer k;
        begin
            for (k = 0; k < 4096; k = k + 1) begin
                expected = 8'ha5;
                if (k >= 256 && k < 288) expected = (k - 256) * 13 + 7;
                if (k >= 1024 && k < 1040) expected = (k - 1024) * 13 + 7;
                if (final_chunk && k >= 1088 && k < 1104) expected = (k - 1088 + 16) * 13 + 7;
                if (ram[k] !== expected)
                    $fatal(1, "ISR SDRAM byte=%h got=%h expected=%h final=%0d", k, ram[k], expected, final_chunk);
            end
        end
    endtask

    always @(posedge clk)
        if (!reset) begin
            cycles <= cycles + 1;
            if (cycles > 100000) $fatal(1, "ISR timeout pc=%h address=%h", pc, address);
            if (!access || ack) delay <= 0;
            else delay <= delay + 1;
            if (!ram_req || ram_ack) dma_delay <= 0;
            else dma_delay <= dma_delay + 1;
            if (ram_req && ram_addr >= 4096) $fatal(1, "SDRAM outside fixture %h", ram_addr);
            if (local_valid) $fatal(1, "unexpected local route");
            if (ram_ack && ram_write)
                for (j = 0; j < 4; j = j + 1)
                    if (ram_be[j]) ram[rbase+j] <= ram_data[j*8+:8];
            if (errors != 0) $fatal(1, "DMA error %h pc=%h", errors, pc);
            if (ack && in_dma && (!claim || bad)) $fatal(1, "DMA rejected %h", address);
            // Count original committed entry-point instructions once each.
            if (retired) begin
                case (retired_pc)
                    32'h5032ca14: isr_entries <= isr_entries + 1;
                    32'h50321860: status_hits <= status_hits + 1;
                    32'h50330c7c: remaining_hits <= remaining_hits + 1;
                    32'h50330d10: chunk_hits <= chunk_hits + 1;
                    32'h50328460: physical_hits <= physical_hits + 1;
                    default: begin end
                endcase
            end
            if (ack && write_op) begin
                if (in_kernel_ram) begin
                    for (i = 0; i < 4; i = i + 1)
                        if (lanes[i]) kernel_ram[address[16:2]][i*8+:8] <= value[i*8+:8];
                end else if (address == 32'h5812010c) begin
                    if (irq != 0 || value != 32'h80 || callbacks != disables ||
                        kernel_ram[32'h1004 >> 2] != 1)
                        $fatal(1, "original interrupt disable before callback irq=%h mask=%h", irq, value);
                    disables <= disables + 1;
                end else if (in_dma) begin
                    if (address[5:0] == 8 && value != 0) begin
                        if (irq != 0 || starts >= 3 || dut.ch != 1 ||
                            dut.count_reg[1] != 7 || dut.source_bytes[1] != 4 ||
                            dut.destination_bytes[1] != 4 || value != 1 ||
                            (starts == 2 && (acknowledgments != 2 || callbacks != 1)))
                            $fatal(1, "ISR start order count=%0d irq=%h ack=%0d", starts, irq, acknowledgments);
                        if (dut.src_reg[1] != (starts == 2 ? 32'h0a000110 : 32'h0a000100) ||
                            dut.dst_reg[1] != (starts == 2 ? 32'h0a000440 : 32'h0a000400))
                            $fatal(1, "ISR source/destination mismatch");
                        starts <= starts + 1;
                    end
                    if (address == 32'h58120348 && value == 0) begin
                        if (irq == 0) begin
                            // Both setup and start issue an idle stop. The
                            // next-chunk start does this only after ISR ACK.
                            if (active != 0 || (checked != 0 && checked != 2 && checked != 3) ||
                                (checked == 3 && (acknowledgments != 2 || stops != 2)))
                                $fatal(1, "idle stop outside original setup/start sequence");
                            idle_stops <= idle_stops + 1;
                        end else begin
                            if (irq != 2 || stops != acknowledgments)
                                $fatal(1, "ISR stop must be first channel acknowledgment irq=%h", irq);
                            stops <= stops + 1;
                        end
                    end
                    if (address == 32'h58120344 && value == 0) begin
                        if (irq != 0 || stops != acknowledgments + 1)
                            $fatal(1, "ISR channel disable preceded stop acknowledgment");
                        acknowledgments <= acknowledgments + 1;
                    end
                end else if (address == 32'he0000004) begin
                    if (value != 32'h80001100 || irq != 0 || active != 0 ||
                        disables != callbacks + 1 || kernel_ram[32'h1004 >> 2] != 0 ||
                        kernel_ram[32'h112c >> 2] != 0 || callbacks >= 2 ||
                        (callbacks == 0 ? checked != 1 : checked != 5))
                        $fatal(1, "ISR duplicate/early callback count=%0d checked=%0d", callbacks, checked);
                    callbacks <= callbacks + 1;
                end else if (address == 32'he0000000) begin
                    if (value != checked + 1) $fatal(1, "marker order");
                    case (value)
                        1, 3, 5: begin
                            if (irq != 2 || active != 0) $fatal(1, "completion IRQ missing");
                            verify_memory(value == 5);
                        end
                        2: if (callbacks != 1 || irq != 0 || acknowledgments != 1)
                            $fatal(1, "zero remaining ISR result");
                        4: begin
                            if (callbacks != 1 || starts != 3 || acknowledgments != 2 ||
                                disables != 1 || kernel_ram[32'h112c >> 2] != 0 ||
                                kernel_ram[32'h1124 >> 2] != 32'h0a000120 ||
                                kernel_ram[32'h1128 >> 2] != 32'h0a000450)
                                $fatal(1, "positive remaining ISR chunk result");
                        end
                        6: if (callbacks != 2 || irq != 0 || acknowledgments != 3)
                            $fatal(1, "next chunk final ISR result");
                        default: $fatal(1, "unexpected marker");
                    endcase
                    checked <= checked + 1;
                end else if (address == 32'hf0000000) begin
                    if (value != 32'h50415353 || checked != 6 || starts != 3 ||
                        callbacks != 2 || disables != 2 || idle_stops != 5 || irq != 0 || active != 0 ||
                        isr_entries != 3 || status_hits != 3 || remaining_hits != 3 ||
                        chunk_hits != 1 || physical_hits != 2)
                        $fatal(1, "ISR final assertion %h isr=%0d status=%0d remaining=%0d chunk=%0d phys=%0d", value, isr_entries, status_hits, remaining_hits, chunk_hits, physical_hits);
                    verify_memory(1);
                    $display("PASS original NEM-4 DMA ISR wait=%0d cycles=%0d isr=3 callbacks=2 next_chunks=1 ack_before_restart=1 guards=preserved substitutions=0", wait_cycles, cycles);
                    $finish;
                end else $fatal(1, "CPU write outside ISR fixture %h pc=%h", address, pc);
            end
            if (ack && !write_op && !in_program && !in_app && !in_kernel_ram && !in_dma && !page_table)
                $fatal(1, "CPU read outside ISR fixture %h pc=%h", address, pc);
        end

    reg [4095:0] program_path, app_path;
    initial begin
        program_path = "scratch/ngage2-integration/lcd-handover/isr/program.hex";
        app_path = "scratch/ngage2-integration/lcd-handover/isr/app.hex";
        if ($value$plusargs("program=%s", program_path)) begin end
        if ($value$plusargs("app=%s", app_path)) begin end
        if (!$value$plusargs("wait=%d", wait_cycles)) wait_cycles = 0;
        for (i = 0; i < 32768; i = i + 1) kernel_ram[i] = 0;
        // Original wrapper validates handler ID against limit, then examines
        // the handler table. A null table slot means no remaining chain owner.
        kernel_ram[32'h66e4 >> 2] = 32'hba;
        kernel_ram[32'h66e0 >> 2] = 32'h80002000;
        kernel_ram[32'h673c >> 2] = 4096;
        for (i = 0; i < 4096; i = i + 1) ram[i] = 8'ha5;
        for (i = 0; i < 32; i = i + 1) ram[256+i] = i * 13 + 7;
        $readmemh(program_path, program_words);
        $readmemh(app_path, app_words);
        repeat (5) @(negedge clk);
        reset = 0;
    end
endmodule
