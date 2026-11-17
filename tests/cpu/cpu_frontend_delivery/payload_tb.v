`timescale 1ns/1ps
// Adapted from tests/cpu/donor_import/tb.sv; same scalar/line contract. This deliberately
// models scalar/line transport, NOT SDRAM command timing or board performance.
module bench;
    parameter LINE_ENABLE=0;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    wire cyc,stb,we,code,ack,lock;
    wire [31:0] address,wdata,rdata;
    wire [3:0] be;
    wire [2:0] cti;
    wire [1:0] bte;
    wire line_req,line_ready;
    wire [31:0] line_addr;
    reg line_valid=0,line_last=0;
    reg [63:0] line_data=0;
    reg [31:0] rom[0:65535], ram[0:32767];
    reg [31:0] payload[0:262143], firmware[0:262143];
    reg [4095:0] payload_file, firmware_file;
    integer payload_ops=0,helper_ops=0,start_payload_ops=0,start_helper_ops=0;
    integer lane,n;
    integer i_wait=0,d_wait=0,jitter=0,seed=1,waited=0;
    integer cycles=0,max_cycles=3000000;
    integer scalar_reads=0,scalar_writes=0,line_requests=0,line_beats=0;
    integer retired_proxy=0,start_cycle=-1,start_retired=0;
    integer start_reads=0,start_writes=0,start_lines=0,start_beats=0,windows=0;
    reg [31:0] begin_pc=0,end_pc=0;
    reg line_active=0;
    reg [31:0] saved_line=0;
    integer line_wait=0,line_index=0;
    reg [4095:0] program_file;

`ifdef BENCH_HAS_LINE
    ngage_cpu #(.LINE_REFILL(LINE_ENABLE)) dut (
        .line_req(line_req),.line_addr(line_addr),.line_ready(line_ready),
        .line_reject(1'b0),.line_valid(line_valid),.line_data(line_data),
        .line_wide(1'b0),.line_last(line_last),.line_error(1'b0),
`else
    assign line_req=0;
    assign line_addr=0;
    ngage_cpu dut (
`endif
        .clk(clk),.reset(reset),.irq(1'b0),.fiq(1'b0),
        .wb_cyc(cyc),.wb_stb(stb),.wb_lock(lock),.wb_code(code),
        .wb_address(address),.wb_write(we),.wb_write_data(wdata),
        .wb_byte_enable(be),.wb_cycle_type(cti),.wb_burst_type(bte),
        .wb_ack(ack),.wb_error(1'b0),.wb_read_data(rdata),
        .debug_pc(),.debug_cpsr(),.debug_instruction(),.debug_fetch()
    );

    function [31:0] load_word(input [31:0] addr);
        if(addr<32'h40000) load_word=rom[addr[17:2]];
        else if(addr>=32'h10000000 && addr<32'h10100000) load_word=payload[addr[19:2]];
        else if(addr>=32'h50300000 && addr<32'h50400000) load_word=firmware[addr[19:2]];
        else if(addr>=32'h0a000000 && addr<32'h0a020000)
            load_word=ram[addr[16:2]];
        else load_word=0;
    endfunction

    function [15:0] load_half(input [31:0] addr);
        reg [31:0] word_value;
        begin
            word_value=load_word(addr);
            load_half=addr[1] ? word_value[31:16] : word_value[15:0];
        end
    endfunction

    function integer extra_wait(input [31:0] addr);
        reg [31:0] mixed;
        begin
            mixed=(addr>>2)^seed;
            mixed=mixed^(mixed<<13);
            mixed=mixed^(mixed>>17);
            mixed=mixed^(mixed<<5);
            extra_wait=jitter>0 ? mixed%(jitter+1) : 0;
        end
    endfunction

    wire [31:0] retire_pc=dut.u_zap.u_zap_core.u_zap_writeback.i_pc_plus_8_buf_ff-8;
    // Existing ZAP fixture's ordinary-retirement predicate. CP15/exception
    // events are excluded: report as a proxy, never architectural CPI.
    wire retire=dut.u_zap.u_zap_core.u_zap_writeback.i_uop_last &&
        (dut.u_zap.u_zap_core.u_zap_writeback.i_valid ||
         dut.u_zap.u_zap_core.u_zap_writeback.i_decompile_valid) &&
        !(|dut.u_zap.u_zap_core.u_zap_writeback.i_data_abt) &&
        !dut.u_zap.u_zap_core.u_zap_writeback.i_fiq &&
        !dut.u_zap.u_zap_core.u_zap_writeback.i_irq &&
        !dut.u_zap.u_zap_core.u_zap_writeback.i_instr_abt &&
        !dut.u_zap.u_zap_core.u_zap_writeback.i_swi &&
        !dut.u_zap.u_zap_core.u_zap_writeback.i_und &&
        !dut.u_zap.u_zap_core.u_zap_writeback.i_copro_reg_en;
    assign ack=cyc && stb && !line_active && !line_valid &&
        waited>=(code?i_wait:d_wait)+extra_wait(address);
    assign rdata=load_word(address);
    assign line_ready=LINE_ENABLE && !reset && !line_active && !line_valid && !(cyc&&stb);

    reg waiting=0;
    reg [69:0] held_packet;
    always @(posedge clk) begin
        line_valid<=0;
        line_last<=0;
        if(reset) begin
            waited<=0;waiting<=0;
        end else begin
            cycles=cycles+1;
            if(cycles>max_cycles)$fatal(1,"benchmark timeout pc=%h",retire_pc);
            if(waiting && (!cyc || !stb || {we,code,address,wdata,be}!==held_packet))
                $fatal(1,"scalar request changed while waiting");
            waiting<=cyc&&stb&&!ack;
            held_packet<={we,code,address,wdata,be};
            if(!cyc || !stb || ack) waited<=0;
            else if(!line_active && !line_valid) waited<=waited+1;

            if(retire) begin
                retired_proxy=retired_proxy+1;
                if(retire_pc>=32'h10000000 && retire_pc<32'h10100000)payload_ops=payload_ops+1;
                if(retire_pc>=32'h50300000 && retire_pc<32'h50400000)helper_ops=helper_ops+1;
            end
            if(start_cycle>=0)metrics_sample();
            if(retire && retire_pc==begin_pc) begin
                if(start_cycle>=0)$fatal(1,"overlapping benchmark window");
                start_cycle=cycles;start_retired=retired_proxy;
                start_reads=scalar_reads;start_writes=scalar_writes;
                start_lines=line_requests;start_beats=line_beats;
                start_payload_ops=payload_ops;start_helper_ops=helper_ops;metrics_begin();
            end
            if(retire && retire_pc==end_pc) begin
                if(start_cycle<0)$fatal(1,"window end without start");
                $display("WINDOW index=%0d cycles=%0d retire_proxy=%0d reads=%0d writes=%0d lines=%0d halfwords=%0d",
                    windows,cycles-start_cycle,retired_proxy-start_retired,
                    scalar_reads-start_reads,scalar_writes-start_writes,
                    line_requests-start_lines,line_beats-start_beats);
                $display("PAYLOAD_WINDOW index=%0d payload_retire_proxy=%0d helper_retire_proxy=%0d",
                    windows,payload_ops-start_payload_ops,helper_ops-start_helper_ops);
                if(payload_ops==start_payload_ops)$fatal(1,"window executed no payload");
                metrics_end();
                windows=windows+1;start_cycle=-1;
            end
            if(line_req&&line_ready) begin
                if(line_addr[4:0]!=0)$fatal(1,"unaligned line request");
                saved_line<=line_addr;line_active<=1;line_index<=0;
                line_wait<=((line_addr < 32'h40000 || (line_addr>=32'h10000000 && line_addr<32'h10100000) || (line_addr>=32'h50300000 && line_addr<32'h50400000)) ? i_wait : d_wait)+extra_wait(line_addr);
                line_requests=line_requests+1;
            end
            if(line_active) begin
                if(line_wait>0)line_wait<=line_wait-1;
                else begin
                    line_data<={48'b0,load_half(saved_line+line_index*2)};
                    line_valid<=1;line_last<=line_index==15;
                    line_beats=line_beats+1;
                    if(line_index==15)line_active<=0;
                    else line_index<=line_index+1;
                end
            end
            if(ack) begin
                if(we)begin
                    scalar_writes=scalar_writes+1;
                    if(address>=32'h0a000000 && address<32'h0a020000)begin
                        for(lane=0;lane<4;lane=lane+1)
                            if(be[lane])ram[address[16:2]][lane*8+:8]<=wdata[lane*8+:8];
                    end else if(address==32'hf0000000)begin
                        if(wdata!==32'h50415353)$fatal(1,"guest result check failed pc=%h",retire_pc);
                        if(start_cycle>=0)$fatal(1,"unfinished benchmark window");
                        $display("RESULT windows=%0d cycles=%0d reads=%0d writes=%0d lines=%0d halfwords=%0d",
                            windows,cycles,scalar_reads,scalar_writes,line_requests,line_beats);
                        $finish;
                    end else $fatal(1,"unexpected write %h",address);
                end else begin
                    scalar_reads=scalar_reads+1;
                    if(!(address<32'h40000 || (address>=32'h10000000 && address<32'h10100000) || (address>=32'h50300000 && address<32'h50400000) || (address>=32'h0a000000 && address<32'h0a020000)))
                        $fatal(1,"unexpected read %h",address);
                end
            end
        end
    end


    `define MDC dut.u_zap.l_generate_with_cache_mmu.u_data_cache.cache_adapter
    integer cp_read=0,cp_write=0,cp_loadlock=0,cp_otherlock=0,cp_empty=0,cp_rest=0,cp_trace=0;
    integer mt_stores=0,mt_store_pipe=0,mt_store_credit=0,mt_store_overlap=0;
    integer mt_cycles=0,mt_fast=0,mt_admit=0,mt_fallback=0,mt_reads=0,mt_wait=0,mt_probe=0;
    task metrics_begin;
      begin load_begin(); late_begin();cp_read=0;cp_write=0;cp_loadlock=0;cp_otherlock=0;cp_empty=0;cp_rest=0;cp_trace=0;mt_stores=0;mt_store_pipe=0;mt_store_credit=0;mt_store_overlap=0;mt_cycles=0;mt_fast=0;mt_admit=0;mt_fallback=0;mt_reads=0;mt_wait=0;mt_probe=0;end
    endtask
    task metrics_sample;
      begin
        load_sample(); pair_sample(); issue_sample(); late_sample(); front_sample();
        mt_cycles=mt_cycles+1;
        if(dut.u_zap.u_zap_core.data_stall)begin
          if(dut.u_zap.u_zap_core.postalu_data_wb_we)cp_write=cp_write+1;
          else cp_read=cp_read+1;
        end else if(dut.u_zap.u_zap_core.u_zap_issue_main.operand_valid && dut.u_zap.u_zap_core.u_zap_issue_main.lock)begin
          if(dut.u_zap.u_zap_core.u_zap_issue_main.load_lock)cp_loadlock=cp_loadlock+1;
          else cp_otherlock=cp_otherlock+1;
        end else if(!dut.u_zap.u_zap_core.u_zap_issue_main.operand_valid)cp_empty=cp_empty+1;
        else cp_rest=cp_rest+1;
        if(windows==2 && ((cp_trace>0 && cp_trace<33) || (cp_trace==0 && dut.u_zap.u_zap_core.data_stall && dut.u_zap.u_zap_core.postalu_pc_plus_8_ff>=32'h10000008 && dut.u_zap.u_zap_core.postalu_pc_plus_8_ff<32'h10100000)))begin
          $display("CREDIT_WORK_TRACE t=%0d edge=%0d p2=%h p1=%h addr=%h write=%0d pending=%0d alloc=%0d ret=%0d ack=%0d completion=%0d stall=%0d state=%0d probe=%0d fast=%0d issue_pc=%h issue_pop=%0d lock=%0d loadlock=%0d retire=%0d retire_pc=%h",cp_trace,cycles,dut.u_zap.u_zap_core.postalu_pc_plus_8_ff-8,dut.u_zap.u_zap_core.postalu1_pc_plus_8_ff-8,`MDC.address,`MDC.wr,`MDC.store_pending,`MDC.store_credit_accept,`MDC.store_response,`MDC.request_ack,dut.u_zap.u_zap_core.completion_valid,dut.u_zap.u_zap_core.data_stall,`MDC.cache.state,`MDC.cache.probe_result_valid,`MDC.fast_hit,dut.u_zap.u_zap_core.u_zap_issue_main.operand_pc_plus_8_ff-8,dut.u_zap.u_zap_core.u_zap_issue_main.operand_pop,dut.u_zap.u_zap_core.u_zap_issue_main.lock,dut.u_zap.u_zap_core.u_zap_issue_main.load_lock,retire,retire_pc);
          cp_trace=cp_trace+1;
        end
        if(`MDC.cache.accept_demand && `MDC.cache.req_write)begin
          mt_stores=mt_stores+1;
          if(`MDC.cache.pipe_accept)mt_store_pipe=mt_store_pipe+1;
          if(`MDC.request_ack)mt_store_credit=mt_store_credit+1;
          if(`MDC.cache.pipe_busy)mt_store_overlap=mt_store_overlap+1;
        end
        if(`MDC.fast_hit)mt_fast=mt_fast+1;
        if(`MDC.cache.admitted_probe_owner)mt_admit=mt_admit+1;
        if(`MDC.cache.probe_read)mt_probe=mt_probe+1;
        if(dut.u_zap.u_zap_core.data_stall)mt_wait=mt_wait+1;
        if(`MDC.cache.accept_demand && !`MDC.cache.req_write)begin
          mt_reads=mt_reads+1;
          if(!(`MDC.cache.use_indexed_read && `MDC.cache.probe_read &&
            `MDC.cache.probe_owner_tag==`MDC.cache.req_mva[31:5] &&
            `MDC.cache.probe_owner_way==`MDC.cache.result_way))mt_fallback=mt_fallback+1;
        end
      end
    endtask
    task metrics_end;
      begin
        if(mt_cycles!=cycles-start_cycle)$fatal(1,"probe metric window mismatch");
        load_end(); late_end();
        if(cp_read+cp_write+cp_loadlock+cp_otherlock+cp_empty+cp_rest!=mt_cycles)$fatal(1,"credit profile accounting");
        $display("CREDIT_WORK_PROFILE index=%0d read_stall=%0d write_stall=%0d load_lock=%0d other_lock=%0d empty=%0d other=%0d",windows,cp_read,cp_write,cp_loadlock,cp_otherlock,cp_empty,cp_rest);
        $display("STORE_METRIC index=%0d accepted=%0d resident_pipe=%0d admission_credit=%0d overlap=%0d",windows,mt_stores,mt_store_pipe,mt_store_credit,mt_store_overlap);
        $display("PROBE_METRIC index=%0d cycles=%0d fast=%0d admitted=%0d fallback=%0d read_accept=%0d waits=%0d probe_reads=%0d",windows,mt_cycles,mt_fast,mt_admit,mt_fallback,mt_reads,mt_wait,mt_probe);
      end
    endtask

    initial begin
        if(!$value$plusargs("program=%s",program_file))$fatal(1,"program required");
        if(!$value$plusargs("begin_pc=%h",begin_pc) || !$value$plusargs("end_pc=%h",end_pc) ||
            begin_pc==end_pc)$fatal(1,"distinct window markers required");
        if(!$value$plusargs("i_wait=%d",i_wait))i_wait=0;
        if(!$value$plusargs("d_wait=%d",d_wait))d_wait=0;
        if(!$value$plusargs("jitter=%d",jitter))jitter=0;
        if(!$value$plusargs("seed=%d",seed))seed=1;
        if(!$value$plusargs("max_cycles=%d",max_cycles))max_cycles=3000000;
        for(n=0;n<65536;n=n+1)rom[n]=0;
        for(n=0;n<32768;n=n+1)ram[n]=0;
        for(n=0;n<256;n=n+1)begin ram['h400+n]='h100+n;ram['h800+n]='h1000+n;end
        ram['h408]=32'h80ff7f01;
        for(n=0;n<65;n=n+1)ram['h4000+n*64]='h200+n;
        if(!$value$plusargs("payload=%s",payload_file) || !$value$plusargs("firmware=%s",firmware_file))
            $fatal(1,"payload/firmware files required");
        for(n=0;n<262144;n=n+1)begin payload[n]=0;firmware[n]=0;end
        $readmemh(program_file,rom);
        $readmemh(payload_file,payload);
        $readmemh(firmware_file,firmware);
        repeat(5)@(negedge clk);
        reset=0;
    end
`include "tests/cpu/cpu_frontend_delivery/profile.vh"
`include "tests/cpu/cpu_frontend_delivery/pair.vh"
`include "tests/cpu/cpu_frontend_delivery/issue.vh"
`include "tests/cpu/cpu_frontend_delivery/late.vh"
`include "tests/cpu/cpu_frontend_delivery/front.vh"
endmodule
