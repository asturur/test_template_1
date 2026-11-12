`timescale 1ns/1ps
// Same backing-store contract for every source revision. This deliberately
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
    reg [31:0] rom[0:16383], ram[0:32767];
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
        if(addr<32'h10000) load_word=rom[addr[15:2]];
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

            if(retire) retired_proxy=retired_proxy+1;
            if(retire && retire_pc==begin_pc) begin
                if(start_cycle>=0)$fatal(1,"overlapping benchmark window");
                start_cycle=cycles;start_retired=retired_proxy;
                start_reads=scalar_reads;start_writes=scalar_writes;
                start_lines=line_requests;start_beats=line_beats;
            end
            if(retire && retire_pc==end_pc) begin
                if(start_cycle<0)$fatal(1,"window end without start");
                $display("WINDOW index=%0d cycles=%0d retire_proxy=%0d reads=%0d writes=%0d lines=%0d halfwords=%0d",
                    windows,cycles-start_cycle,retired_proxy-start_retired,
                    scalar_reads-start_reads,scalar_writes-start_writes,
                    line_requests-start_lines,line_beats-start_beats);
                windows=windows+1;start_cycle=-1;
            end
            if(line_req&&line_ready) begin
                if(line_addr[4:0]!=0)$fatal(1,"unaligned line request");
                saved_line<=line_addr;line_active<=1;line_index<=0;
                line_wait<=(line_addr < 32'h10000 ? i_wait : d_wait)+extra_wait(line_addr);
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
                        for(integer lane=0;lane<4;lane=lane+1)
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
                    if(!(address<32'h10000 || (address>=32'h0a000000 && address<32'h0a020000)))
                        $fatal(1,"unexpected read %h",address);
                end
            end
        end
    end

    initial begin
        if(!$value$plusargs("program=%s",program_file))$fatal(1,"program required");
        if(!$value$plusargs("begin_pc=%h",begin_pc) || !$value$plusargs("end_pc=%h",end_pc) ||
            begin_pc==end_pc)$fatal(1,"distinct window markers required");
        if(!$value$plusargs("i_wait=%d",i_wait))i_wait=0;
        if(!$value$plusargs("d_wait=%d",d_wait))d_wait=0;
        if(!$value$plusargs("jitter=%d",jitter))jitter=0;
        if(!$value$plusargs("seed=%d",seed))seed=1;
        if(!$value$plusargs("max_cycles=%d",max_cycles))max_cycles=3000000;
        for(integer n=0;n<16384;n=n+1)rom[n]=0;
        for(integer n=0;n<32768;n=n+1)ram[n]=0;
        for(integer n=0;n<256;n=n+1)begin ram['h400+n]='h100+n;ram['h800+n]='h1000+n;end
        ram['h408]=32'h80ff7f01;
        for(integer n=0;n<65;n=n+1)ram['h4000+n*64]='h200+n;
        $readmemh(program_file,rom);
        repeat(5)@(negedge clk);
        reset=0;
    end
endmodule
