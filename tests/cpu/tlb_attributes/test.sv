`timescale 1ns/1ps
module test;
    reg clk = 0;
    reg reset = 1;
    reg idle = 0, inv = 0, mmu = 1, rd = 1, wr = 0;
    reg [4:0] mode_bits = 5'h13;
    reg [31:0] dac = 32'hffffffff, baddr = 32'h0a074000;
    reg [31:0] l1_descriptor = 32'h0a200001;
    reg [31:0] last_l2_address = 0;
    reg abort_l1=0, abort_l2=0, bus_error=0, complete=0;
    reg [31:0] descriptor = 32'h0a081ffe;
    wire fault, cacheable, bufferable;
    wire [7:0] external_fsr;
    wire [7:0] fsr;
    wire [31:0] far_address;
    reg [31:0] current_address = 32'h80601868;
    reg [31:0] lookup_address = 32'h80601868;
    reg [31:0] check_address = 32'h80601868;
    wire busy, cyc, stb;
    wire [31:0] bus_address, physical;
    reg request_cyc = 0, request_stb = 0;
    reg [31:0] request_address = 0;
    reg ack = 0;
    reg [31:0] bus_data = 0;
    integer beats = 0;

    always #5 clk = ~clk;
    always @(posedge clk) begin
        request_cyc <= cyc; request_stb <= stb; request_address <= bus_address;
    end
    always @(negedge clk) begin
        ack = request_cyc && request_stb && !ack && !bus_error;
        bus_error = ack && (request_address < 32'h0a200000 ? abort_l1 : abort_l2);
        if(bus_error)ack=0;
        if (ack || bus_error) begin
            beats = beats + 1;
            bus_data = request_address < 32'h0a200000 ? l1_descriptor : descriptor;
            if(request_address>=32'h0a200000)last_l2_address=request_address;
        end
    end

    arm920_tlb dut (
        .i_clk(clk), .i_reset(reset), .i_address(current_address), .i_request_rd(rd), .i_request_wr(wr),
        .i_cpsr(mode_bits), .i_sr(2'b0), .i_dac_reg(dac),
        .i_baddr(baddr), .i_mmu_en(mmu), .i_inv(inv),
        .i_inv_mva(1'b0), .i_inv_address(32'b0), .i_lock_write(1'b0), .i_lock_data(32'b0),
        .i_complete(complete), .i_idle(idle), .o_busy(busy), .o_phy_addr(physical), .o_fault(fault), .o_cacheable(cacheable), .o_bufferable(bufferable), .o_external_fsr(external_fsr), .o_fsr(fsr), .o_far(far_address),
        .o_wb_cyc_nxt(cyc), .o_wb_stb_nxt(stb), .o_wb_adr_nxt(bus_address),
        .i_wb_dat(bus_data), .i_wb_ack(ack), .i_wb_err(bus_error)
    );

    task tick;
        begin @(negedge clk); #1; end
    endtask
    task settle;
        integer n;
        begin
            repeat (8) tick();
            n = 0;
            while (busy && n < 200) begin tick(); n = n + 1; end
            if (busy) $fatal(1, "translation did not settle");
        end
    endtask
    task address(input [31:0] value);
        begin current_address = value; lookup_address = value; check_address = value; end
    endtask
    integer kind,cb,ap,srval,user_mode,write_access,domain_access;
    reg [31:0] expected_pa;
    reg [37:0] entry;
    reg allowed;
    reg [3:0] expected_fault;
    reg [7:0] computed_fault;
    initial begin
        repeat(4)tick();reset=0;idle=1;
        for(kind=0;kind<4;kind=kind+1)for(cb=0;cb<4;cb=cb+1)begin
            l1_descriptor=kind==0 ? 32'h0a000c02 : kind==3 ? 32'h0a200003 : 32'h0a200001;
            case(kind)
                0: begin expected_pa=32'h0a001868;l1_descriptor=l1_descriptor|(cb<<2);end
                1: begin descriptor=32'h0a100ff1;expected_pa=32'h0a101868;end
                2: begin descriptor=32'h0a123ff2;expected_pa=32'h0a123868;end
                3: begin descriptor=32'h0a123c33;expected_pa=32'h0a123c68;end
            endcase
            descriptor=(descriptor&32'hfffffff3)|(cb<<2);
            inv=1;tick();inv=0;settle();
            if(fault || physical!==expected_pa || {cacheable,bufferable}!==cb[1:0])
                $fatal(1,"page kind=%0d CB=%0d physical=%h fault=%b attrs=%b%b",kind,cb,physical,fault,cacheable,bufferable);
            if(kind==3 && last_l2_address!==32'h0a200018)$fatal(1,"fine table did not use VA19:10");
        end
        l1_descriptor=0;inv=1;tick();inv=0;settle();
        if(!fault || fsr!==8'h05)$fatal(1,"L1 translation fault");
        l1_descriptor=32'h0a000c0e;complete=1;tick();complete=0;settle();
        if(fault || physical!==32'h0a001868)$fatal(1,"failed descriptor was cached");
        abort_l1=1;inv=1;tick();inv=0;settle();
        if(!fault || fsr!==8'h0c)$fatal(1,"L1 table external abort fsr=%h",fsr);
        abort_l1=0;abort_l2=1;l1_descriptor=32'h0a2000c1;
        complete=1;tick();complete=0;settle();
        if(!fault || fsr!==8'h6e)$fatal(1,"L2 table external abort fsr=%h",fsr);
        abort_l2=0;idle=0;
        // Independent ARM920 table3-11 permission oracle across all mappings.
        for(kind=0;kind<4;kind=kind+1)
        for(domain_access=0;domain_access<4;domain_access=domain_access+1)
        for(ap=0;ap<4;ap=ap+1)
        for(srval=0;srval<3;srval=srval+1)
        for(user_mode=0;user_mode<2;user_mode=user_mode+1)
        for(write_access=0;write_access<2;write_access=write_access+1)begin
            entry={kind[1:0],2'b11,4'b0,{4{ap[1:0]}},22'b0};
            allowed=0;
            if(domain_access==3)allowed=1;
            else if(domain_access==1)case(ap)
                0: case(srval)
                    1:allowed=!write_access;
                    2:allowed=!user_mode&&!write_access;
                    default:allowed=0;
                endcase
                1:allowed=!user_mode;
                2:allowed=!user_mode||!write_access;
                3:allowed=1;
            endcase
            expected_fault=allowed?0:domain_access==1?(kind==0?4'hd:4'hf):(kind==0?4'h9:4'hb);
            computed_fault=dut.permission_fault(entry,current_address,domain_access,user_mode?5'h10:5'h13,srval[1:0],!write_access,write_access);
            if(computed_fault[3:0]!==expected_fault)$fatal(1,"permission oracle kind=%0d domain=%0d AP=%0d SR=%0d user=%0d write=%0d",kind,domain_access,ap,srval,user_mode,write_access);
        end
        $display("PASS: four page sizes/CB, fine-table index, uncached fault retry, L1/L2 external aborts, permission oracle");
        $finish;
    end
    initial begin #100000; $fatal(1,"timeout");end
endmodule
