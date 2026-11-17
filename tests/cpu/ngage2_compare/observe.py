"""Read-only instrumentation added to both benchmark fixtures."""
def observe(tb,donor):
    core='dut.u_zap.g_arm9.u_arm9_core'
    tb=tb.replace('    initial begin\n','''    integer trace_on=0,observer_qualification=0;
    integer cr=0,dr=0,cw=0,dw=0,scr=0,sdr=0,scw=0,sdw=0;
    integer drain_start=-1,drain_writes=0,drain_index=-1;
    initial begin
        if(!$value$plusargs("compare_trace=%d",trace_on))trace_on=0;
        if(!$value$plusargs("observer_qualification=%d",observer_qualification))observer_qualification=0;
''',1)
    tb=tb.replace('            if(retire && retire_pc==begin_pc) begin','''            if(trace_on!=0 && windows==2 && start_cycle>=0) begin
                if(retire)$display("TRACE_RET c=%0d pc=%h",cycles-start_cycle,retire_pc);
                if(ack)$display("TRACE_BUS c=%0d a=%h we=%b be=%h data=%h cti=%b",cycles-start_cycle,address,we,be,we?wdata:rdata,cti);
                if(line_req&&line_ready)$display("TRACE_LINE c=%0d a=%h",cycles-start_cycle,line_addr);
            end
            if(ack)begin
                if(code)begin if(we)cw=cw+1;else cr=cr+1;end
                else begin if(we)dw=dw+1;else dr=dr+1;end
            end
            if(retire && retire_pc==begin_pc) begin
                scr=cr;sdr=dr;scw=cw;sdw=dw;
                if(!dut.u_zap.cpu_mmu_en || !dut.u_zap.cpu_dc_en || !dut.u_zap.cpu_ic_en)
                    $fatal(1,"MMU/cache not enabled");''',1)
    tb=tb.replace('if(payload_ops==start_payload_ops)', 'if(observer_qualification==0 && payload_ops==start_payload_ops)')
    pending='dut.u_zap.dc_writeback_busy' if donor else '(!dut.u_zap.dc_write_buffer_empty || dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter.store_pending!=0)'
    tb=tb.replace('            if(retire && retire_pc==begin_pc) begin',f'''            if(drain_start>=0 && !{pending}) begin
                $display("DRAIN index=%0d extra_cycles=%0d extra_scalar_writes=%0d",drain_index,cycles-drain_start,scalar_writes-drain_writes);
                drain_start=-1;
            end
            if(retire && retire_pc==begin_pc) begin''',1)
    tb=tb.replace('                windows=windows+1;',f'''                drain_start=cycles;drain_writes=scalar_writes;drain_index=windows;
                if(!{pending})begin
                    $display("DRAIN index=%0d extra_cycles=0 extra_scalar_writes=0",windows);
                    drain_start=-1;
                end
                $display("TRAFFIC index=%0d code_read_words=%0d data_read_words=%0d code_write_words=%0d data_write_words=%0d pending_bus=%0d pending_write=%0d",
                    windows,cr-scr,dr-sdr,cw-scw,dw-sdw,cyc,{pending});
                windows=windows+1;''',1)
    if donor:
        tb=tb.replace('    integer trace_on=0', '    integer marker_held=0; reg [31:0] held_pc=0;\n    integer trace_on=0')
        tb=tb.replace('            if(retire) begin', '''            if(trace_on==2)begin
                if(retire)$display("QUAL c=%0d pc=%h held=%0d",cycles,retire_pc,marker_held);
                if(dabt[0]||pabt||und||swi||irq||fiq)$display("EXCEPTION c=%0d pc=%h dabt=%0d pabt=%0d",cycles,retire_pc,dabt[0],pabt);
                if(retire || retire_pc!=held_pc)marker_held=0;
                else marker_held=marker_held+1;
                held_pc=retire_pc;
            end
            if(retire) begin''',1)
        tb=tb.replace('            if(retire) begin',f'''            if(trace_on!=0 && windows==2 && start_cycle>=0) begin
                if({core}.a_a_valid && {core}.a_a_can_finish)
                    $display("TRACE_A c=%0d pc=%h",cycles-start_cycle,{core}.a_pc);
                if(dut.dbg_d_done)$display("TRACE_DATA c=%0d pc=%h va=%h we=%b data=%h",cycles-start_cycle,{core}.data_pc8-8,dut.dbg_d_va,dut.dbg_d_we,dut.dbg_d_we?dut.dbg_d_wdata:dut.dbg_d_rdata);
                if(dv)$display("TRACE_W c=%0d pc=%h tag0=%0d data0=%h pair=%b tag1=%0d data1=%h",cycles-start_cycle,retire_pc,{core}.wb_tag0,{core}.wb_data0,{core}.wb_pair,{core}.wb_tag1,{core}.wb_data1);
            end
            if(retire) begin''',1)
    return tb
