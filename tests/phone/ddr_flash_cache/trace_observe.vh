 `define FLASH_D2 adapter.shared_cache.cache
 `define FLASH_CPU dut.board.upp.cpu_inside.cpu
 `define FLASH_IC `FLASH_CPU.u_arm925t.u_zap.l_generate_with_cache_mmu.u_code_cache
 `define FLASH_EXEC `FLASH_CPU.u_arm925t.u_zap.g_arm9.u_arm9_core

 function directed_address;
    input [31:0] address;
    begin
        directed_address = (address >= 32'h5000 && address < 32'h5200) ||
                           (address >= 32'h6000 && address < 32'h6200);
    end
 endfunction
 function directed_target;
    input [31:0] address;
    begin
        directed_target = address == 32'h6000 || address == 32'h6044 ||
                          address == 32'h6088 || address == 32'h60cc ||
                          address == 32'h6110 || address == 32'h6154 ||
                          address == 32'h6198 || address == 32'h61dc;
    end
 endfunction

 reg [31:0] trace_physical = 0;
 reg [5:0] trace_hold = 0;
 assign d2_hold_tail = ddelay == 1 && ddr_remaining == 1 &&
                       directed_address(read_addr) && trace_hold < 48;
 always @(posedge clk) begin
    if (pr && ddelay == 0) begin
        trace_hold <= 0;
        trace_physical <= {pa,3'b000} - 32'h30000000;
        if (directed_address({pa,3'b000} - 32'h30000000))
            $display("D2_TRACE REQUEST %0d %08h %0d",cycles,{pa,3'b000} - 32'h30000000,ddr_burst);
    end
    if (d2_hold_tail) trace_hold <= trace_hold + 1;
    if (av && ar && !aw && directed_address(aa - 32'h30000000))
        $display("D2_TRACE ADMIT %0d %08h %0d",cycles,aa - 32'h30000000,arb_line);
    if (phyready) begin
        if (directed_address(trace_physical))
            $display("D2_TRACE RETURN %0d %08h %016h",cycles,trace_physical,phydata);
        trace_physical <= trace_physical + 8;
    end
    if (`FLASH_D2.state == `FLASH_D2.LOOKUP && !`FLASH_D2.writing &&
        directed_address(`FLASH_D2.address - 32'h30000000))
        $display("D2_TRACE LOOKUP %0d %08h %0d %0d",cycles,`FLASH_D2.address - 32'h30000000,`FLASH_D2.line_request,`FLASH_D2.tag_hit);
    if (`FLASH_D2.fill_done && directed_address(`FLASH_D2.address - 32'h30000000))
        $display("D2_TRACE TAG %0d %08h",cycles,`FLASH_D2.address - 32'h30000000);
    if (adone && !`FLASH_D2.line_request && directed_address(`FLASH_D2.address - 32'h30000000))
        $display("D2_TRACE WORD %0d %08h %08h",cycles,`FLASH_D2.address - 32'h30000000,arsp);
    if (dut.line_valid && directed_address(dut.line_decode_address))
        $display("D2_TRACE LINE %0d %08h %016h %0d",cycles,dut.line_decode_address,dut.line_data,dut.line_last);
    if (`FLASH_CPU.refill.cpu_ack && directed_address(`FLASH_CPU.refill.cpu_address))
        $display("D2_TRACE ACK %0d %08h %08h %0d",cycles,`FLASH_CPU.refill.cpu_address,`FLASH_CPU.refill.cpu_data,`FLASH_CPU.refill.state);
    if (`FLASH_IC.cf_cache_tag_wr_en && (&`FLASH_IC.cf_cache_line_ben) &&
        directed_address(`FLASH_IC.u_zap_cache_fsm.address))
        $display("D2_TRACE IVALID %0d %08h",cycles,`FLASH_IC.u_zap_cache_fsm.address);
    if (accepted_fetch && directed_target(fetch_pc))
        $display("D2_TRACE FETCH %0d %08h %08h",cycles,fetch_pc,dut.cpu_instruction);
    if (`FLASH_EXEC.a_valid && `FLASH_EXEC.backend_ready && `FLASH_EXEC.a_condition_pass &&
        !`FLASH_EXEC.a_fault && directed_target(`FLASH_EXEC.a_pc))
        $display("D2_TRACE EXEC %0d %08h %08h",cycles,`FLASH_EXEC.a_pc,`FLASH_EXEC.a_result);
    if (retire && directed_target(retire_pc))
        $display("D2_TRACE RETIRE %0d %08h",cycles,retire_pc);
    if (sack && swrite && saddr == 25'h100) begin
        if (swdata !== 32'h50415353 || errors != 0)
            $fatal(1,"D2 guest failed: %h bus errors=%0d",swdata,errors);
        $display("PASS D2 directed guest capacity=%0d mmc_div=%0d clocks=%0d",FLASH_CACHE_BYTES,MMC_CLK_DIV,cycles);
        $finish;
    end
 end
 `undef FLASH_EXEC
 `undef FLASH_IC
 `undef FLASH_CPU
 `undef FLASH_D2
