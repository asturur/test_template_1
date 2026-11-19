 // One observation at each guest milestone and one bounded hot-loop window.
 `define D2 adapter.shared_cache.cache
 `define REFILL dut.board.upp.cpu_inside.cpu.refill
 reg [63:0] d2_hits=0, d2_misses=0, d2_reads=0, d2_beats=0;
 reg [63:0] scalar_wait=0, line_wait=0;
 reg [31:0] clear_clocks=0, delay_returns=0;
 reg saw_logo=0, saw_clear=0;
 always @(posedge clk) begin
    if (!cold && `D2.state == `D2.CLEAR)
        clear_clocks <= clear_clocks + 1;
    if (!reset) begin
        if (`D2.state == `D2.LOOKUP && `D2.cacheable && !`D2.writing) begin
            if (`D2.tag_hit)
                d2_hits <= d2_hits + 1;
            else
                d2_misses <= d2_misses + 1;
        end
        if (pr && ddelay == 0)
            d2_reads <= d2_reads + 1;
        if (phyready)
            d2_beats <= d2_beats + 1;
        if (dut.wb_cyc && dut.wb_stb && dut.flash_hit && !dut.wb_ack && !dut.wb_err)
            scalar_wait <= scalar_wait + 1;
        if ((dut.line_state == dut.LINE_ROM_ISSUE || dut.line_state == dut.LINE_ROM_WAIT) &&
             `REFILL.cpu_cyc && !`REFILL.cpu_ack && !`REFILL.cpu_error)
            line_wait <= line_wait + 1;
        if (retire && retire_pc == 32'h00006150 && delay_returns <= 4096) begin
            if (delay_returns == 32 || delay_returns == 4096)
                $display("D2_HOT cycle=%0d entry=%0d retired=%0d reads=%0d beats=%0d hits=%0d misses=%0d scalar_wait=%0d line_wait=%0d",
                         cycles,delay_returns,boot_retired,d2_reads,d2_beats,d2_hits,d2_misses,scalar_wait,line_wait);
            delay_returns <= delay_returns + 1;
        end
        if (lcd_writes == 18353 && !saw_clear) begin
            saw_clear <= 1;
            $display("D2_FRAME cycle=%0d words=%0d reads=%0d beats=%0d hits=%0d misses=%0d scalar_wait=%0d line_wait=%0d sweep=%0d",
                     cycles,lcd_writes,d2_reads,d2_beats,d2_hits,d2_misses,scalar_wait,line_wait,clear_clocks);
        end
        if (lcd_writes == 36689 && !saw_logo) begin
            saw_logo <= 1;
            $display("D2_FRAME cycle=%0d words=%0d reads=%0d beats=%0d hits=%0d misses=%0d scalar_wait=%0d line_wait=%0d sweep=%0d",
                     cycles,lcd_writes,d2_reads,d2_beats,d2_hits,d2_misses,scalar_wait,line_wait,clear_clocks);
        end
    end
 end
 `undef REFILL
 `undef D2
