// Mainline frontend boundaries. Sample the same pre-update edge as FILL_EDGE.
`define C dut.u_zap.u_zap_core
`define W `C.u_zap_writeback
`define I dut.u_zap.l_generate_with_cache_mmu.u_code_cache
`define A `I.cache_adapter
task fill_frontend_sample;
    begin
        if (fill_trace && windows == 2 && start_cycle >= 0) begin
            $display("FRONT t=%0d launch=%08h p1=%08h p2=%08h treq=%08h req=%0d ack=%0d held=%0d btb=%0d pred=%0d target=%08h dec_clear=%0d alu_clear=%0d wb_clear=%0d i_state=%0d i_fast=%0d i_accept=%0d i_tlb_busy=%0d i_retry=%0d fetched=%08h fetch_valid=%0d fifo=%08h fifo_valid=%0d fifo_full=%0d inflate=%08h inflate_valid=%0d predecode=%08h predecode_valid=%0d decode=%08h decode_valid=%0d",
                cycles-start_cycle, `W.pc_ff[31:0], `W.pc_del_ff[31:0], `W.pc_del2_ff[31:0],
                `C.o_instr_wb_adr, `C.o_instr_wb_stb && `C.o_instr_wb_cyc,
                `C.i_instr_wb_ack, `C.code_stall, `W.clear_from_btb, `C.wb_pred[32],
                `W.pc_from_btb, `C.clear_from_decode, `C.clear_from_alu, `C.clear_from_writeback,
                `A.cache.state, `A.fast_hit, `A.cache.accept_demand, `I.tlb_busy, `C.i_icache_err2,
                `C.fetch_pc_plus_8_ff-8, `C.fetch_valid, `C.fifo_pc_plus_8-8, `C.fifo_valid, `C.fifo_full,
                `C.mode16_pc_plus_8_ff-8, `C.mode16_valid, `C.predecode_pc, `C.predecode_val,
                `C.decode_pc_ff, `C.decode_condition_code != 15);
            $display("FRONT_STREAM t=%0d va=%08h fast=%0d valid=%b tag0=%08h tag1=%08h result=%0d result_va=%08h read=%0d read_va=%08h",
                cycles-start_cycle, `A.cache.req_mva, `A.fast_hit, `A.cache.stream_valid,
                {`A.cache.stream_tag[0], 5'b0}, {`A.cache.stream_tag[1], 5'b0},
                `A.cache.fast_result_valid, `A.cache.fast_result_address,
                `A.cache.fast_read, `A.cache.fast_lookup_address);
        end
    end
endtask
`undef A
`undef I
`undef W
`undef C
