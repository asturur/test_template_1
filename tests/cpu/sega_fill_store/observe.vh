// Sega fill timing, outside the RTL under test.
`define CORE dut.u_zap.u_zap_core
`define ISSUE `CORE.u_zap_issue_main
`define CACHE dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
`define BANK `CACHE.cache.bank
localparam [31:0] FILL_MOV = 32'h1001c9f4;
localparam [31:0] FILL_STORE = FILL_MOV + 4;
localparam [31:0] FILL_ADD = FILL_MOV + 8;
integer fill_trace;
initial if (!$value$plusargs("fill_trace=%d", fill_trace)) fill_trace = 0;
wire [31:0] fill_selected_pc = (`CORE.data_select_p1 ?
    `CORE.postalu1_pc_plus_8_ff : `CORE.postalu_pc_plus_8_ff) - 8;
wire [31:0] fill_selected_va = `CORE.data_select_p1 ?
    `CORE.postalu1_address_ff : `CORE.postalu_address_ff;

task fill_sample;
    begin
        if (fill_trace && windows == 2 && start_cycle >= 0) begin
            $display("FILL_EDGE t=%0d pop=%0d pc=%08h valid=%0d lock=%0d datastall=%0d selected=%08h issue=%08h issuevalid=%0d shift=%08h shiftvalid=%0d alu=%08h aluvalid=%0d alu_result=%08h alu_va=%08h alu_mask=%h retire=%0d rpc=%08h",
                cycles-start_cycle, `ISSUE.operand_pop, `ISSUE.operand_pc_ff,
                `ISSUE.operand_valid, `ISSUE.lock, `CORE.data_stall,
                fill_selected_pc, `CORE.issue_pc_ff, `CORE.issue_condition_code_ff != 15,
                `CORE.shifter_pc_ff, `CORE.shifter_condition_code_ff != 15,
                `CORE.alu_pc_plus_8_ff-8, `CORE.alu_dav_ff, `CORE.alu_alu_result_ff,
                `CORE.alu_address_ff, `CORE.alu_data_wb_sel, retire, retire_pc);
            if (fill_selected_pc == FILL_STORE && `CORE.completion_offer)
                $display("FILL_OFFER t=%0d va=%08h mask=%h data=%08h ack=%0d accept=%0d pipe=%0d credit=%0d",
                    cycles-start_cycle, fill_selected_va, `CORE.o_data_wb_sel, `CORE.o_data_wb_dat,
                    `CORE.i_data_wb_ack, `CACHE.cache.accept_demand, `CACHE.cache.pipe_accept,
                    `CACHE.store_credit_accept);
            if (|`BANK.lines.write_enable)
                $display("FILL_RAM t=%0d mask=%08h segment=%0d way=%0d data=%064h",
                    cycles-start_cycle, `BANK.lines.write_enable, `BANK.lines.write_segment,
                    `BANK.lines.write_way, `BANK.lines.write_line);
        end
    end
endtask
`undef CORE
`undef ISSUE
`undef CACHE
`undef BANK
