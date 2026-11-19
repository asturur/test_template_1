// Used by the generated payload replay of the production phone and D2.
reg [31:0] payload_begin, payload_end, payload_base, helper_base;
integer window = 0, first_clock = -1, payload_ops = 0, helper_ops = 0;
integer nos_ticks = 0, nos_matches = 0, mmc_bits = 0, irq_clocks = 0;
integer window_nos, window_mmc, window_irq, window_ddr;
reg previous_mmc_bit = 0;
`ifdef NGAGE_REAL_SDRAM
`define FRAME_CPU dut.board.upp.cpu_inside.cpu.u_arm925t
`ifdef NGAGE_FRAME_GAP_POSTED
`define FRAME_RAM_REQ p_req
`define FRAME_RAM_ADDR p_addr
`define FRAME_RAM_WE p_we
`define FRAME_RAM_ACK p_ack
`define FRAME_RAM_DATA p_data
`else
`define FRAME_RAM_REQ sreq
`define FRAME_RAM_ADDR sa
`define FRAME_RAM_WE swe
`define FRAME_RAM_ACK sack
`define FRAME_RAM_DATA sd
`endif
`ifdef NGAGE_FRAME_GAP_PIN_WAIT
wire payload_sdram_request = profile_scalar_req;
`else
wire payload_sdram_request = `FRAME_RAM_REQ;
`endif
integer window_read, window_write, window_read_line, window_scalar_wait;
integer window_blocks;
integer window_itlb, window_dtlb, window_ifill, window_dfill;
integer act_count=0, pre_count=0, ref_count=0;
integer window_act, window_pre, window_ref;
integer sdram_trace=0;
string sdram_trace_path;
initial begin
    if ($value$plusargs("sdram-trace=%s", sdram_trace_path)) sdram_trace=$fopen(sdram_trace_path,"w");
end
always @(posedge memclk) begin
    case ({ncs,nras,ncas,nwe})
        4'b0011: act_count=act_count+1;
        4'b0010: pre_count=pre_count+1;
        4'b0001: ref_count=ref_count+1;
        default: ;
    endcase
end
`endif
`ifdef NGAGE_FRAME_GAP_DONOR_SDRAM
reg donor_mailbox = 0;
always @(posedge clk)
    if (sack && swe && sa == 25'h100000) begin
        if (sd != 32'h50415353) $fatal(1, "Guest output check rejected payload");
        donor_mailbox <= 1;
    end
`endif
initial begin
    if (!$value$plusargs("begin_pc=%h", payload_begin) ||
        !$value$plusargs("end_pc=%h", payload_end) ||
        !$value$plusargs("payload_base=%h", payload_base) ||
        !$value$plusargs("helper_base=%h", helper_base) ||
        payload_begin == payload_end) $fatal(1, "Payload marker arguments required");
end

always @(posedge clk) if (!reset) begin
    previous_mmc_bit <= dut.board.mmc_clk;
    if (dut.board.mmc_clk && (MMC_CLK_DIV == 1 || !previous_mmc_bit)) mmc_bits = mmc_bits + 1;
    if (dut.board.upp.peripherals.nos_tick) nos_ticks = nos_ticks + 1;
    if (dut.board.upp.peripherals.nos_timer.timer_match) nos_matches = nos_matches + 1;
    if (dut.cpu_cpsr[4:0] == 5'h12 || dut.cpu_cpsr[4:0] == 5'h11) irq_clocks = irq_clocks + 1;
    if (retire && retire_pc == payload_begin) begin
        if (first_clock >= 0) $fatal(1, "Overlapping payload windows");
        if (!dut.board.upp.cpu_inside.cpu.u_arm925t.u_zap.cpu_mmu_en ||
            !dut.board.upp.cpu_inside.cpu.u_arm925t.u_zap.cpu_ic_en ||
            !dut.board.upp.cpu_inside.cpu.u_arm925t.u_zap.cpu_dc_en)
            $fatal(1, "Payload ran with MMU or cache disabled");
        first_clock = cycles;
        payload_ops = 0;
        helper_ops = 0;
        window_nos = nos_ticks;
        window_mmc = mmc_bits;
        window_irq = irq_clocks;
        window_ddr = d2_reads;
`ifdef NGAGE_REAL_SDRAM
        window_read = 0; window_write = 0; window_read_line = 0; window_scalar_wait = 0; window_blocks = 0;
        window_itlb = 0; window_dtlb = 0; window_ifill = 0; window_dfill = 0;
        window_act = act_count; window_pre = pre_count; window_ref = ref_count;
`endif
    end
`ifdef NGAGE_REAL_SDRAM
    if (first_clock >= 0) begin
        if (sreq && !sack) window_scalar_wait = window_scalar_wait + 1;
        if (`FRAME_CPU.dbg_icache[6]) window_itlb = window_itlb + 1;
        if (`FRAME_CPU.dbg_icache[7]) window_dtlb = window_dtlb + 1;
        if (`FRAME_CPU.dbg_icache[2]) window_ifill = window_ifill + 1;
        if (|`FRAME_CPU.dbg_dcache[1:0]) window_dfill = window_dfill + 1;
        if (ram_line_req && ram_line_ready && !lock) begin
            window_read_line = window_read_line + 1;
            if (window == 2 && sdram_trace)
                $fdisplay(sdram_trace, "%0d %08x 0 32", cycles-first_clock, ram_line_addr);
        end else if (
`ifdef NGAGE_FRAME_GAP_DONOR_SDRAM
                     sadapter.scalar_accept
`else
                     sadapter.state == 0 && payload_sdram_request && scrub_done && !dma_reset && !cold
`endif
                    ) begin
            if (mem_write_block) window_blocks = window_blocks + 1;
            else if (`FRAME_RAM_WE) window_write = window_write + 1;
            else window_read = window_read + 1;
            if (window == 2 && sdram_trace)
                $fdisplay(sdram_trace, "%0d %08x %b %0d", cycles-first_clock, `FRAME_RAM_ADDR, `FRAME_RAM_WE, mem_write_block ? 16 : 4);
        end
    end
`endif
    if (retire && first_clock >= 0) begin
        if (retire_pc[31:20] == payload_base[31:20]) payload_ops = payload_ops + 1;
        if (retire_pc[31:20] == helper_base[31:20]) helper_ops = helper_ops + 1;
        if (retire_pc == payload_end) begin
`ifdef NGAGE_REAL_SDRAM
            $display("V5_MEMORY_WINDOW window=%0d reads=%0d writes=%0d blocks=%0d lines=%0d wait=%0d itlb=%0d dtlb=%0d ifills=%0d dfills=%0d act=%0d pre=%0d refresh=%0d",
                     window, window_read, window_write, window_blocks, window_read_line, window_scalar_wait,
                     window_itlb, window_dtlb, window_ifill, window_dfill,
                     act_count-window_act,pre_count-window_pre,ref_count-window_ref);
`endif
            $display("PAYLOAD_RESULT window=%0d cycles=%0d payload_ops=%0d helper_ops=%0d ddr_reads=%0d nos_ticks=%0d mmc_bits=%0d irq_clocks=%0d",
                     window, cycles - first_clock, payload_ops, helper_ops, d2_reads - window_ddr,
                     nos_ticks - window_nos, mmc_bits - window_mmc, irq_clocks - window_irq);
            first_clock = -1;
            window = window + 1;
        end
    end
`ifdef NGAGE_REAL_SDRAM
`ifdef NGAGE_FRAME_GAP_DONOR_SDRAM
    if (donor_mailbox && sadapter.drained) begin
        if ({memory.Bank0[131073],memory.Bank0[131072]} !== 32'h50415353)
            $fatal(1, "Guest mailbox did not physically drain");
`else
    if (`FRAME_RAM_ACK && `FRAME_RAM_WE && `FRAME_RAM_ADDR == 25'h100000) begin
        if (`FRAME_RAM_DATA != 32'h50415353) $fatal(1, "Guest output check rejected payload");
`endif
        if (sdram_trace) $fclose(sdram_trace);
`else
    if (spending && sdelay == 0 && swrite && saddr == 25'h100000) begin
        if (swdata != 32'h50415353) $fatal(1, "Guest output check rejected payload");
`endif
        if (first_clock >= 0 || window != 7 || errors || data_errors || clear_clocks != FLASH_CACHE_BYTES / 32)
            $fatal(1, "Invalid payload completion windows=%0d bus_errors=%0d D2_lines=%0d", window, errors, clear_clocks);
        $display("PAYLOAD_PASS cycles=%0d nos_ticks=%0d nos_matches=%0d mmc_bits=%0d irq_clocks=%0d ddr_reads=%0d d2_lines=%0d",
                 cycles, nos_ticks, nos_matches, mmc_bits, irq_clocks, d2_reads, clear_clocks);
        $finish;
    end
end
`ifdef NGAGE_REAL_SDRAM
`undef FRAME_CPU
`undef FRAME_RAM_REQ
`undef FRAME_RAM_ADDR
`undef FRAME_RAM_WE
`undef FRAME_RAM_ACK
`undef FRAME_RAM_DATA
`endif
