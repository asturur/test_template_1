`timescale 1ns / 1ps

module cp15_ap0_case #(parameter INSTRUCTION = 0) (output bit pass);
    bit clk, reset, cp_valid, cp_user;
    bit [31:0] cp_word, cp_data;
    wire [1:0] sr [0:1];
    wire [1:0] ap0;
    wire [31:0] cp_dac [0:1];
    wire cp_done [0:1], cp_mmu [0:1];
    bit clock_enable = 1, mmu = 1, rd, wr, user_mode, matrix_dac, use_cp_mmu;
    bit [31:0] va, dac;
    bit [95:0] small_page;
    bit [42:0] large_page;
    bit [37:0] section;
    bit [47:0] fine;
    bit [1:0] small_valid;
    bit large_valid, section_valid, fine_valid;
    bit [1:0] kind, desc_type, access_permissions, attributes;
    bit [3:0] domain;
    integer clocks, checks, held, sr_transitions;
    integer pages_allowed, misses, translations, external_aborts, domain_faults, permission_faults;

    typedef struct packed {
        logic hit, short_hit, walk;
        logic [31:0] walk_va;
        logic [7:0] fsr;
        logic [31:0] far;
        logic cacheable, bufferable, wt;
        logic [31:0] physical;
    } result_t;
    wire result_t result [0:2];

`define CP_PORTS(leg) \
    .i_clk(clk), .i_reset(reset), .i_cp_word(cp_word), .i_cp_dav(cp_valid), \
    .i_cpsr(cp_user ? 32'h10 : 32'h13), .i_reg_rd_data(cp_data), .i_fsr(32'b0), .i_far(32'b0), \
    .i_dcache_inv_done(1'b0), .i_icache_inv_done(1'b0), .i_dcache_clean_done(1'b0), \
    .i_icache_clean_done(1'b0), .i_irq(1'b0), .i_fiq(1'b0), .i_dcache_writeback_busy(1'b0), \
    .i_dcache_line_done(1'b0), .o_cp_done(cp_done[leg]), .o_sr(sr[leg]), \
    .o_dac(cp_dac[leg]), .o_mmu_en(cp_mmu[leg])
    old_cp15 ref_cp (`CP_PORTS(0));
    ngage2_zap_cp15_cb new_cp (`CP_PORTS(1), .o_ap0_mode(ap0));
`undef CP_PORTS

`define GEOMETRY .SPAGE_TLB_ENTRIES(256), .SPAGE_TLB_WAYS(2), \
    .LPAGE_TLB_ENTRIES(32), .SECTION_TLB_ENTRIES(64), .FPAGE_TLB_ENTRIES(64), \
    .MMU_OFF_CACHEABLE(INSTRUCTION)
`define CHECK_PORTS(leg, cp) \
    .i_clk(clk), .i_clkena(clock_enable), .i_mmu_en(use_cp_mmu ? cp_mmu[cp] : mmu), \
    .i_va(va), .i_rd(rd), .i_wr(wr), .i_cpsr(user_mode ? 5'h10 : 5'h13), \
    .i_dac_reg(matrix_dac ? dac : cp_dac[cp]), \
    .i_sptlb_rdata(small_page), .i_sptlb_rdav(small_valid), .i_lptlb_rdata(large_page), \
    .i_lptlb_rdav(large_valid), .i_setlb_rdata(section), .i_setlb_rdav(section_valid), \
    .i_fptlb_rdata(fine), .i_fptlb_rdav(fine_valid), .o_hit_ok(result[leg].hit), \
    .o_hit_ok_short(result[leg].short_hit), .o_walk(result[leg].walk), \
    .o_walk_va(result[leg].walk_va), .o_fsr(result[leg].fsr), .o_far(result[leg].far), \
    .o_cacheable(result[leg].cacheable), .o_bufferable(result[leg].bufferable), \
    .o_wt(result[leg].wt), .o_phy_addr(result[leg].physical)
    old_tlb_check #(`GEOMETRY) reference (`CHECK_PORTS(0,0), .i_sr(sr[0]));
    ngage2_zap_tlb_check #(`GEOMETRY, .AP0_PREDECODED(1'b1)) candidate (
        `CHECK_PORTS(1,1), .i_sr(~sr[1]), .i_ap0_mode(ap0)
    );
    ngage2_zap_tlb_check #(`GEOMETRY) fallback (
        `CHECK_PORTS(2,1), .i_sr(sr[1]), .i_ap0_mode(~ap0)
    );
`undef GEOMETRY
`undef CHECK_PORTS

    function automatic bit permitted(input bit [1:0] sr_value);
        case (access_permissions)
            0: case (sr_value)
                1: permitted = !wr;
                2: permitted = !user_mode && rd;
                default: permitted = 0;
            endcase
            1: permitted = !user_mode;
            2: permitted = !user_mode || rd;
            3: permitted = 1;
        endcase
    endfunction

    task automatic tick;
        result_t old_result;
        bit [1:0] old_sr, domain_mode;
        bit [7:0] expected_fsr;
        bit lookup, walk;
        bit [3:0] reason;
        #1;
        old_result = result[0];
        old_sr = sr[0];
        domain_mode = 2'((matrix_dac ? dac : cp_dac[0]) >> (domain * 2));
        lookup = (use_cp_mmu ? cp_mmu[0] : mmu) && (rd || wr);
        walk = lookup && !(|small_valid || large_valid || section_valid || fine_valid);
        expected_fsr = 0;
        reason = 0;
        if (lookup && !walk) begin
            if ((kind == 0 || kind == 2) && desc_type == 0)
                reason = kind == 2 ? 4'h5 : 4'h7;
            else if ((kind == 0 || kind == 2) && desc_type == 3)
                reason = kind == 2 ? 4'hc : 4'he;
            else if (domain_mode == 0 || domain_mode == 2)
                reason = kind == 2 ? 4'h9 : 4'hb;
            else if (domain_mode == 1 && !permitted(old_sr))
                reason = kind == 2 ? 4'hd : 4'hf;
            expected_fsr = reason == 0 ? 8'b0 : {domain, reason};
        end

        clk = 1;
        #1;
        clocks++;
        if (clocks > 2) begin
            if ({cp_done[1], sr[1], cp_mmu[1], cp_dac[1]} !== {cp_done[0], sr[0], cp_mmu[0], cp_dac[0]} ||
                ap0 !== {sr[0] == 2'b10, sr[0] == 2'b01})
                $fatal(1, "CP15 update edge changed at %0d S/R %b", clocks, sr[0]);
            if (old_sr != sr[0]) sr_transitions++;
            if (result[1] !== result[0] || result[2] !== result[0])
                $fatal(1, "TLB changed at %0d I=%b S/R=%b AP=%b type=%b domain=%b kind=%b rw=%b%b user=%b",
                       clocks, INSTRUCTION, old_sr, access_permissions, desc_type, domain_mode,
                       kind, rd, wr, user_mode);
            if (clock_enable) begin
                checks++;
                if (result[1].fsr !== expected_fsr || result[1].walk !== walk ||
                    result[1].far !== va || result[1].walk_va !== va)
                    $fatal(1, "Bad fault precedence: kind=%b type=%b domain=%b S/R=%b FSR=%h expected=%h",
                           kind, desc_type, domain_mode, old_sr, result[1].fsr, expected_fsr);
                if (walk) misses++;
                else if (lookup)
                    case (reason)
                        0: pages_allowed++;
                        5, 7: translations++;
                        12, 14: external_aborts++;
                        9, 11: domain_faults++;
                        13, 15: permission_faults++;
                        default: $fatal(1, "unexpected fault code");
                    endcase
            end else begin
                held++;
                if (result[1] !== old_result) $fatal(1, "held lookup changed");
            end
        end
        clk = 0;
        #1;
    endtask

    task automatic descriptor(input bit [1:0] form, ap, subpage, dtype, input bit [3:0] dom);
        bit [7:0] ap_fields;
        kind = form;
        domain = dom;
        desc_type = dtype;
        access_permissions = ap;
        attributes = dom[1:0];
        va = 32'h4abc0000 | ({30'b0,subpage} << 14) | ({30'b0,subpage} << 10);
        ap_fields = {4{~ap}};
        ap_fields[2*subpage+:2] = ap;
        small_page = 0;
        small_page[48*dom[0]+:48] = {va[31:20],20'h12345,dom,ap_fields,attributes,dtype};
        large_page = {va[31:21],16'h2345,dom,ap_fields,attributes,dtype};
        section = {va[31:26],12'h345,8'b0,ap,1'b0,dom,1'b0,attributes,dtype};
        fine = {va[31:16],22'h45678,dom,ap,attributes,dtype};
        small_valid = form == 0 ? (2'b01 << dom[0]) : 2'b00;
        large_valid = form == 1;
        section_valid = form == 2;
        fine_valid = form == 3;
    endtask

    task automatic mcr(input bit [31:0] word, value, input bit forbidden);
        integer edges;
        cp_word = word;
        cp_data = value;
        cp_user = forbidden;
        cp_valid = 1;
        edges = 0;
        do begin
            tick();
            edges++;
            if (edges == 12) $fatal(1, "CP15 MCR did not complete");
        end while (!cp_done[0]);
        cp_valid = 0;
        cp_user = 0;
        repeat (2) tick();
    endtask

    initial begin
        reset = 1;
        repeat (3) tick();
        reset = 0;
        rd = 1;
        use_cp_mmu = 1;
        descriptor(2,0,0,2,1);
        mcr(32'hee030f10,32'h55555555,0);
        for (int s = 0; s < 4; s++) begin
            // Keep a read active across the write and its first applicable edge.
            descriptor(2,0,0,2,1);
            mcr(32'hee010f10,32'(s[1])*256 + 32'(s[0])*512 + 1,0);
            if (sr[0] != s[1:0] || !cp_mmu[0]) $fatal(1, "MCR failed to set S/R");
            mcr(32'hee010f10,0,1);
            if (sr[0] != s[1:0] || !cp_mmu[0]) $fatal(1, "user MCR changed S/R");

            for (int form = 0; form < 4; form++)
            for (int typ = 0; typ < 4; typ++)
            for (int ap = 0; ap < 4; ap++)
            for (int sub = 0; sub < 4; sub++)
            for (int dom = 0; dom < 16; dom++) begin
                descriptor(form[1:0],ap[1:0],sub[1:0],typ[1:0],dom[3:0]);
                for (int mode = 0; mode < 4; mode++)
                for (int user_case = 0; user_case < 2; user_case++)
                for (int access = 0; access < (INSTRUCTION ? 2 : 4); access++) begin
                    matrix_dac = 1;
                    dac = 32'(mode) << (dom * 2);
                    user_mode = user_case[0];
                    {wr,rd} = access[1:0];
                    tick();
                end
            end
            // The checker holds the previous result across CP15 changes and
            // then uses the new permissions on its first released edge.
            clock_enable = 0;
            matrix_dac = 0;
            user_mode = 0;
            rd = 1;
            wr = 0;
            descriptor(0,0,3,2,1);
            mcr(32'hee010f10,32'(s[0])*256 + 32'(!s[1])*512 + 1,0);
            clock_enable = 1;
            tick();
            small_valid = 0;
            tick();
            descriptor(0,0,3,3,1);
        end
        reset = 1;
        repeat (3) tick();
        reset = 0;
        repeat (2) tick();
        if (sr[0] != 0 || ap0 != 0 || cp_mmu[0] || !(checks && held && sr_transitions && misses &&
            translations && external_aborts && domain_faults && permission_faults && pages_allowed))
            $fatal(1, "reset or coverage incomplete");
        $display("PASS CP15 AP0 instruction=%0d clocks=%0d checks=%0d held=%0d sr_changes=%0d allow=%0d miss=%0d translation=%0d external=%0d domain=%0d permission=%0d",
                 INSTRUCTION, clocks, checks, held, sr_transitions, pages_allowed, misses, translations,
                 external_aborts, domain_faults, permission_faults);
        pass = 1;
    end
endmodule

module cp15_ap0_tb;
    wire i_pass, d_pass;
    cp15_ap0_case #(.INSTRUCTION(1)) i_case(i_pass);
    cp15_ap0_case d_case(d_pass);
    initial begin
        wait (i_pass && d_pass);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "CP15 AP0 differential timed out");
    end
endmodule
