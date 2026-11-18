// Passive pre-edge samples. Flags distinguish accepted predecode and actual
// operand dequeue from held or killed packets. Window 2 is the first scored work.
`define EC dut.u_zap.u_zap_core
`define EI `EC.u_zap_issue_main
`define EW `EC.u_zap_writeback
`define EP `EC.u_zap_predecode
`define EA dut.u_zap.l_generate_with_cache_mmu.u_code_cache.cache_adapter
task target_sample;
begin
    if (windows == 2) begin
        $display("TARGET5E e=%0d ret=%0d rpc=%h data=%0d wr=%0d code=%0d busy=%0d oval=%0d opc=%h pop=%0d ll=%0d sl=%0d req=%0d ack=%0d addr=%h fv=%0d fpc=%h qv=%0d qpc=%h mv=%0d mpc=%h pv=%0d ppc=%h ins=%h pred=%h taken=%0d pa=%0d wc=%0d wt=%h ras=%0d rn=%0d dv=%0d dpc=%h dc=%0d dt=%h ac=%0d at=%h wbc=%0d btbc=%0d btbt=%h pc0=%h pc1=%h pc2=%h pc3=%h saved=%0d old=%h tlb=%0d trans=%0d launched=%0d fast=%0d owner=%0d state=%0d line=%0d scalar=%0d extcode=%0d thumb=%0d qempty=%0d qread=%0d qwrite=%0d qclear=%0d qhead=%h mstall=%0d pstall=%0d pmem=%0d dstall=%0d istall=%0d opush=%0d rawvalid=%0d rawword=%h ferr=%0d qerr=%0d merr=%0d phys=%h cfault=%0d calign=%0d creqready=%0d cresp=%0d cinv=%0d cclean=%0d",
            cycles, retire, `EW.i_pc_plus_8_buf_ff-(`EW.cpsr_ff[5] ? 4 : 8), `EC.data_stall, `EC.postalu_data_wb_we,
            `EC.code_stall, `EC.stall_from_shifter, `EI.operand_valid,
            `EI.operand_pc_ff, `EI.operand_pop, `EI.load_lock,
            `EI.shift_lock, `EC.o_instr_wb_stb, `EC.i_instr_wb_ack,
            `EC.o_instr_wb_adr, `EC.fetch_valid, `EC.u_zap_fetch_main.o_pc_ff,
            `EC.fifo_valid, `EC.fifo_pc_plus_8-(`EC.alu_flags_ff[5] ? 4 : 8), `EC.mode16_valid,
            `EC.u_zap_mode16_decoder.o_pc_ff, `EP.mode32_instruction_valid,
            `EP.skid_pc_ff, `EP.mode32_instruction, `EP.skid_pred,
            `EP.skid_taken,
            !`EP.i_reset && !`EC.clear_from_writeback &&
                !(`EC.clear_from_alu && !`EC.data_stall) &&
                !`EP.o_clear_from_decode && !`EP.stall &&
                !`EP.mem_fetch_stall && `EP.mode32_instruction_valid,
            `EP.w_clear_from_decode, `EP.w_pc_from_decode,
            `EP.ras_ptr_ff, `EP.ras_ptr_nxt,
            `EC.decode_condition_code!=15, `EC.decode_pc_ff,
            `EC.clear_from_decode, `EC.pc_from_decode,
            `EC.clear_from_alu, `EC.pc_from_alu, `EC.clear_from_writeback,
            `EW.clear_from_btb, `EW.pc_from_btb,
            `EW.pc_ff, `EW.pc_del_ff, `EW.pc_del2_ff, `EW.pc_del3_ff,
            `EW.shelve_ff, `EW.pc_shelve_ff,
            `EA.tlb_busy, `EA.translation_wait, `EA.launched,
            `EA.fast_hit, `EA.req_valid, `EA.cache.state,
            line_req, cyc && stb, code, `EC.alu_flags_ff[5],
            `EC.U_ZAP_FIFO.u_zap_sync_fifo.empty_ff, `EC.U_ZAP_FIFO.u_zap_sync_fifo.read_ok,
            `EC.U_ZAP_FIFO.u_zap_sync_fifo.write_ok, `EC.U_ZAP_FIFO.clear,
            `EC.U_ZAP_FIFO.instr[99:68], `EC.u_zap_mode16_decoder.stall,
            `EP.stall, `EP.mem_fetch_stall, `EC.stall_from_decode, `EC.stall_from_issue,
            `EI.operand_push, `EC.instr_valid, `EC.i_instr_wb_dat,
            `EC.fetch_instr_abort, `EC.fifo_instr_abort, `EC.mode16_iabort,
            `EA.physical, `EA.fault, `EA.alignment_fault, `EA.req_ready,
            `EA.response_valid, `EA.cache_invalidate, `EA.cache_clean);
    end
end
endtask
`undef EC
`undef EI
`undef EW
`undef EP
`undef EA
