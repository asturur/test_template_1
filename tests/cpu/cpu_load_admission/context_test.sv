`timescale 1ns/1ps
module test;
    reg clk=0,reset=1,rd=0,wr=0,revoke=0,kill=0,inv=0,cache_inv=0;
    always #5 clk=~clk;
    reg [31:0] address=32'h80001000, ttbr=32'h00010000,dac=3;
    reg [4:0] mode_bits=5'h13;
    reg [31:0] probe_address=32'h80001000;
    wire ack,request_ack,err,err2,cyc,stb,we,cache_inv_done;
    wire [31:0] data,bus_address,far_address;
    wire [7:0] fsr;
    reg hold_bus=0;
    integer data_reads=0,table_reads=0,checks=0;
    wire bus_ack=cyc && stb && !hold_bus;
    wire [31:0] bus_data=bus_address>=32'h00010000 && bus_address<32'h00020000 ? 32'h0a000c0e :
        bus_address>=32'h00020000 && bus_address<32'h00030000 ? 32'h0b000c0e :
        bus_address[31:24]==8'h0a ? 32'h11112222 : 32'h33334444;
    always @(posedge clk) if(!reset && bus_ack)begin
        if(bus_address[31:24]==8'h0a || bus_address[31:24]==8'h0b)data_reads=data_reads+1;
        else table_reads=table_reads+1;
    end
    zap_dcache dut (
        .i_clk(clk),.i_reset(reset),.i_stall(1'b0),.i_context_change(revoke),.i_admission_clear(kill),
        .i_address(address),.i_address_nxt(address),.i_write_class(wr),
        .i_alignment_fault(1'b0),.i_alignment_far(address),
        .i_address_check(probe_address),.i_wr_check(1'b0),.i_rd_check(1'b1),
        .i_store_overlap(1'b0),.i_load_pair(1'b0),.i_swp_tag(2'b0),
        .i_rd(rd),.i_wr(wr),.i_ben(4'hf),.i_dat(32'b0),
        .o_cache_inv_done(cache_inv_done),.o_dat(data),.o_ack(ack),.o_request_ack(request_ack),.o_err(err),.o_err2(err2),.o_fsr(fsr),.o_far(far_address),
        .i_reg_idx(64'b0),.i_reg_idx_bin(6'b0),.i_load_info(6'b0),
        .i_mmu_en(1'b1),.i_cache_en(1'b1),.i_cache_rr(1'b1),
        .i_cache_lock_write(1'b0),.i_cache_lock_base(6'b0),.i_cache_op_single(1'b0),.i_cache_op_by_mva(1'b0),.i_cache_op_address(32'b0),
        .i_cache_inv_req(cache_inv),.i_cache_clean_req(1'b0),
        .i_cpsr(mode_bits),.i_sr(2'b0),.i_baddr(ttbr),.i_dac_reg(dac),
        .i_tlb_inv(inv),.i_tlb_inv_mva(1'b0),.i_tlb_inv_address(32'b0),.i_tlb_lock_write(1'b0),.i_tlb_lock_data(32'b0),
        .o_wb_cyc(cyc),.o_wb_stb(stb),.o_wb_wen(we),.o_wb_adr(bus_address),.i_wb_dat(bus_data),.i_wb_ack(bus_ack),.i_wb_err(1'b0),
        .line_ready(1'b0),.line_reject(1'b0),.line_valid(1'b0),.line_data(64'b0),.line_wide(1'b0),.line_last(1'b0),.line_error(1'b0)
    );
    task tick;begin @(negedge clk);#1;end endtask
    task settle(input [31:0] expected,input bad);
        integer count;begin
            count=0;
            while(!request_ack && count<500)begin tick();count=count+1;end
            if(!request_ack || err!==bad || err2)$fatal(1,"unexpected admission completion err=%0d fsr=%h count=%0d",err,fsr,count);
            if(!bad && data!==expected)$fatal(1,"wrong/stale admitted data got=%h expected=%h",data,expected);
            if(bad && (far_address!=address || fsr[3:0]!=9))$fatal(1,"wrong permission fault context");
            tick();rd=0;wr=0;repeat(6)tick();checks=checks+1;
        end
    endtask
    task offer;begin rd=1;#1;end endtask
    task await_token;
        integer count;begin
            count=0;
            while(!dut.admission_valid && count<500)begin tick();count=count+1;end
            if(!dut.admission_valid)$fatal(1,"no demand admission token");
        end
    endtask
    task block_check;begin
        #1;
        if(dut.admitted || request_ack || dut.cache_adapter.fast_hit || dut.cache_adapter.req_valid)
            $fatal(1,"revoked token retained authority");
        tick();
        if(dut.admission_valid)$fatal(1,"revocation did not clear token");
        revoke=0;kill=0;inv=0;
    end endtask
    integer old_reads;
    initial begin
        repeat(5)tick();reset=0;repeat(4)tick();
        offer();settle(32'h11112222,0);
        offer();await_token();ttbr=32'h00020000;revoke=1;inv=1;cache_inv=1;block_check();
        // ARM920 cache tags are virtual. A remap needs explicit cache and TLB
        // maintenance before a different physical line is expected at this MVA.
        while(!cache_inv_done)tick();tick();cache_inv=0;
        settle(32'h33334444,0);
        $display("ADMISSION_CONTEXT new_table_new_data PASS");
        offer();await_token();old_reads=data_reads;dac=0;revoke=1;block_check();settle(0,1);
        if(data_reads!=old_reads)$fatal(1,"denied permission generated data access");
        $display("ADMISSION_CONTEXT permission_denied_no_data PASS");
        dac=3;revoke=1;tick();revoke=0;offer();settle(32'h33334444,0);
        offer();await_token();address=32'h80001004;probe_address=address;#1;
        if(dut.admitted || request_ack)$fatal(1,"changed address reused old admission");
        kill=1;block_check();settle(32'h33334444,0);
        $display("ADMISSION_CONTEXT changed_address PASS");
        offer();await_token();kill=1;block_check();rd=0;repeat(4)tick();
        if(dut.admission_valid)$fatal(1,"killed demand retained token");
        $display("ADMISSION_CONTEXT killed_token PASS");
        offer();await_token();inv=1;block_check();settle(32'h33334444,0);
        $display("ADMISSION_CONTEXT TLB_invalidation PASS");
        $display("PASS admission context checks=%0d data_reads=%0d table_reads=%0d",checks,data_reads,table_reads);$finish;
    end
    initial begin #200000;$fatal(1,"context fixture timeout");end
endmodule
