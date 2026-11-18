`define CORE dut.u_zap.g_arm9.u_arm9_core
`define CACHE dut.u_zap.l_generate_with_cache_mmu.u_data_cache
task fill_sample;
    begin
        if (trace_mode != 0 && windows == 2 && start_cycle >= 0) begin
            $display("FILL_DONOR_EDGE t=%0d execute=%0d pc=%08h result=%08h va=%08h mask=%h data=%08h retire=%0d rpc=%08h",
                cycles-start_cycle, `CORE.a_a_valid && `CORE.a_a_can_finish, `CORE.a_pc,
                `CORE.a_result[31:0], `CORE.a_data_address,
                `CORE.input_record[19-:4], `CORE.a_store_data, retire, retire_pc);
            if (dut.dbg_d_done && dut.dbg_d_we)
                $display("FILL_DONOR_ACK t=%0d va=%08h mask=%h data=%08h fast=%0d",
                    cycles-start_cycle, dut.dbg_d_va, dut.dbg_d_sel, dut.dbg_d_wdata,
                    `CORE.i_data_ack_fast);
            if (`CACHE.ram_write && `CACHE.cf_cache_tag_wr_en && |`CACHE.cf_cache_line_ben)
                $display("FILL_DONOR_RAM t=%0d va=%08h mask=%04h data=%032h",
                    cycles-start_cycle, `CACHE.cache_address, `CACHE.cf_cache_line_ben, `CACHE.cf_cache_line);
        end
    end
endtask
`undef CORE
`undef CACHE
