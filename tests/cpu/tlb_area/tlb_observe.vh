`define AT_I dut.u_zap.l_generate_with_cache_mmu.u_code_cache.u_zap_tlb
`define AT_D dut.u_zap.l_generate_with_cache_mmu.u_data_cache.u_zap_tlb
`define AT_C dut.u_zap.u_zap_core
integer at_search[0:1],at_fill[0:1],at_inv[0:1],at_lock[0:1],at_wait[0:1],at_requests[0:1];
integer at_group[0:15];
integer at_total_search[0:1],at_total_fill[0:1],at_total_inv[0:1],at_total_lock[0:1];
reg [2:0] at_irow,at_drow;
// The grouped selector returns its default after hit_vector clears. Capture
// on compare_valid; bank_valid consumes the payload on the following edge.
always @(posedge clk)begin
    if(`AT_I.bank.compare_valid)at_irow<=`AT_I.bank.selected_entry[5:3];
    if(`AT_D.bank.compare_valid)at_drow<=`AT_D.bank.selected_entry[5:3];
end
integer at_union=0,at_slot,at_tmp,at_initialized=0;
initial begin
    for(at_slot=0;at_slot<2;at_slot=at_slot+1)begin
        at_total_search[at_slot]=0;at_total_fill[at_slot]=0;at_total_inv[at_slot]=0;at_total_lock[at_slot]=0;
    end
end
task area_begin;
    integer i;
    begin
        for(i=0;i<2;i=i+1)begin at_search[i]=0;at_fill[i]=0;at_inv[i]=0;at_lock[i]=0;at_wait[i]=0;at_requests[i]=0;end
        for(i=0;i<16;i=i+1)at_group[i]=0;
        at_union=0;at_initialized=1;
    end
endtask
task area_sample;
    reg iw,dw;
    begin
        if(`AT_I.bank_lookup)at_total_search[0]=at_total_search[0]+1;
        if(`AT_D.bank_lookup)at_total_search[1]=at_total_search[1]+1;
        if(`AT_I.bank_fill)at_total_fill[0]=at_total_fill[0]+1;
        if(`AT_D.bank_fill)at_total_fill[1]=at_total_fill[1]+1;
        if(`AT_I.i_inv)at_total_inv[0]=at_total_inv[0]+1;
        if(`AT_D.i_inv)at_total_inv[1]=at_total_inv[1]+1;
        if(`AT_I.i_lock_write)at_total_lock[0]=at_total_lock[0]+1;
        if(`AT_D.i_lock_write)at_total_lock[1]=at_total_lock[1]+1;
        if(start_cycle>=0 && at_initialized)begin
            if(`AT_I.bank_lookup)at_search[0]=at_search[0]+1;
            if(`AT_D.bank_lookup)at_search[1]=at_search[1]+1;
            if(`AT_I.bank_fill)at_fill[0]=at_fill[0]+1;
            if(`AT_D.bank_fill)at_fill[1]=at_fill[1]+1;
            if(`AT_I.i_inv)at_inv[0]=at_inv[0]+1;
            if(`AT_D.i_inv)at_inv[1]=at_inv[1]+1;
            if(`AT_I.i_lock_write)at_lock[0]=at_lock[0]+1;
            if(`AT_D.i_lock_write)at_lock[1]=at_lock[1]+1;
            if(`AT_I.bank_valid && `AT_I.bank_hit)at_group[at_irow]=at_group[at_irow]+1;
            if(`AT_D.bank_valid && `AT_D.bank_hit)at_group[8+at_drow]=at_group[8+at_drow]+1;
            // Exposure is an observed blocking condition, not an additive speedup.
            iw=`AT_I.state==1 && `AT_C.o_instr_wb_cyc && `AT_C.o_instr_wb_stb && !`AT_C.i_instr_wb_ack;
            dw=`AT_D.state==1 && `AT_C.data_stall;
            if(iw)at_wait[0]=at_wait[0]+1;
            if(dw)at_wait[1]=at_wait[1]+1;
            if(iw || dw)at_union=at_union+1;
            if(`AT_I.i_request_rd && `AT_I.i_complete)at_requests[0]=at_requests[0]+1;
            if((`AT_D.i_request_rd || `AT_D.i_request_wr) && `AT_D.i_complete)at_requests[1]=at_requests[1]+1;
        end
    end
endtask
task area_end;
    integer i;
    begin
        $display("TLB_AREA_WINDOW index=%0d isearch=%0d dsearch=%0d ifill=%0d dfill=%0d iinv=%0d dinv=%0d ilock=%0d dlock=%0d iwait=%0d dwait=%0d union_wait=%0d irequests=%0d drequests=%0d",windows,at_search[0],at_search[1],at_fill[0],at_fill[1],at_inv[0],at_inv[1],at_lock[0],at_lock[1],at_wait[0],at_wait[1],at_union,at_requests[0],at_requests[1]);
        for(i=0;i<16;i=i+1)$display("TLB_AREA_GROUP index=%0d side=%0d row=%0d hits=%0d",windows,i/8,i%8,at_group[i]);
    end
endtask
task area_dump;
    begin
        $display("TLB_AREA_TOTAL isearch=%0d dsearch=%0d ifill=%0d dfill=%0d iinv=%0d dinv=%0d ilock=%0d dlock=%0d",at_total_search[0],at_total_search[1],at_total_fill[0],at_total_fill[1],at_total_inv[0],at_total_inv[1],at_total_lock[0],at_total_lock[1]);
    end
endtask
`undef AT_I
`undef AT_D
`undef AT_C
