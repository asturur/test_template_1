`timescale 1ns / 1ps

module early_shift_tb;
    `include "shift_ports.vh"

    integer clocks = 0, offered = 0, stale = 0, releases = 0;
    integer prepared = 0, flushed = 0, redirected = 0, rrx_cases = 0;
    integer kind, amount, carry, value_case;
    reg [31:0] pattern;
    localparam [19:0] RF_GRANTS = {4{5'b10000}};
    localparam [31:0] MOVS_REG  = 32'he1b00112;

    task compare;
        begin
            `include "shift_compare.vh"
            if (candidate.accept && candidate.direct_reg_eligible && candidate.s_wait[2])
                $fatal(1, "accepted a stale Rs");
        end
    endtask

    task tick;
        begin
            #2;
            compare();
            if (candidate.prepared) prepared++;
            if (candidate.direct_reg_eligible && candidate.s_wait[2] &&
                candidate.shift_amount != reference.shift_amount)
                stale++;
            #2 i_clk = 1;
            clocks++;
            #2;
            compare();
            #2 i_clk = 0;
        end
    endtask

    // Independent ARM MOVS-with-shift result and carry. Immediate RRX
    // inserts CPSR.C; register ROR by zero preserves the value and carry.
    function automatic [32:0] oracle_shift;
        input [31:0] operand;
        input [1:0] shift_kind;
        input [7:0] count;
        input is_register, old_carry;
        integer n, rotation;
        reg [31:0] result;
        reg        c;
        begin
            n = int'(count);
            if (n == 0 && (is_register || shift_kind == 0)) begin
                result = operand;
                c      = old_carry;
            end else if (n == 0 && shift_kind == 3) begin
                result = {old_carry, operand[31:1]};
                c      = operand[0];
            end else begin
                if (n == 0) n = 32;
                case (shift_kind)
                    0: begin
                        result = n < 32 ? operand << n : 0;
                        c      = n <= 32 ? operand[32-n] : 0;
                    end
                    1: begin
                        result = n < 32 ? operand >> n : 0;
                        c      = n <= 32 ? operand[n-1] : 0;
                    end
                    2: begin
                        if (n < 32) result = $signed(operand) >>> n;
                        else result = {32{operand[31]}};
                        c = n < 32 ? operand[n-1] : operand[31];
                    end
                    3: begin
                        rotation = n % 32;
                        result = rotation == 0 ? operand :
                            (operand >> rotation) | (operand << (32-rotation));
                        c = result[31];
                    end
                endcase
            end
            oracle_shift = {result, c};
        end
    endfunction

    task configure;
        input [31:0] operand;
        input [1:0] shift_kind;
        input is_register, old_carry;
        begin
            i_valid            = 1;
            i_kind             = 0;
            i_instruction      = is_register ? MOVS_REG : 32'he1b00002;
            i_instruction[6:5] = shift_kind;
            i_used             = is_register ? 4'b0110 : 4'b0010;
            i_early            = i_used;
            i_reg_shift        = is_register;
            i_shift_pre        = {3'b0, shift_kind, 8'd0, 5'd0, is_register};
            i_value            = {32'd0, 32'habcd000d, operand, 32'd0};
            i_forward_grant    = {RF_GRANTS, RF_GRANTS};
            i_forward_match    = 0;
            i_load_owner       = 0;
            i_load_hit         = 0;
            i_load_trust       = 0;
            i_self_dep         = 0;
            i_cpsr             = {2'b00, old_carry, 1'b1, 28'h13};
            i_flags_refresh    = 1;
            i_ready            = 1;
            i_admit            = 1;
        end
    endtask

    task expect_result;
        input [31:0] operand;
        input [1:0] shift_kind;
        input [7:0] count;
        input is_register, old_carry;
        reg [31:0] expected;
        reg        carry_out;
        reg [ 3:0] flags;
        begin
            {expected, carry_out} =
                oracle_shift(operand, shift_kind, count, is_register, old_carry);
            flags = {expected[31], expected == 0, carry_out, 1'b1};
            #1;
            if (!candidate_o_valid || !candidate_o_write_flags ||
                candidate_o_result[31:0] !== expected || candidate_o_cpsr_next[31:28] !== flags)
                $fatal(
                    1,
                    "shift/flags mismatch kind=%0d count=%0d got=%h/%h expected=%h/%h",
                    shift_kind,
                    count,
                    candidate_o_result[31:0],
                    candidate_o_cpsr_next[31:28],
                    expected,
                    flags
                );
            tick();
            if (candidate_o_flags !== flags) $fatal(1, "wrong retired NZCV");
        end
    endtask

    task delayed_register_shift;
        input [31:0] operand;
        input [1:0] shift_kind;
        input [7:0] count;
        input old_carry;
        begin
            configure(operand, shift_kind, 1, old_carry);
            // W owns Rs. Deliberately poison the visible forwarding data
            // before either no hit or an untrusted hit becomes usable.
            i_forward_match[11:8]  = 4'b0100;
            i_load_owner           = 2'b10;
            i_self_dep             = 1;
            i_forward_grant[34:30] = 5'b01000;
            i_mw_value[95:64]      = 32'hbadf001b;
            #1;
            if (!candidate_o_shift_wait || candidate.accept) $fatal(1, "missing Rs wait");
            tick();
            offered++;
            if (!candidate.holding || candidate.prepared) $fatal(1, "bad hold/preparation");
            i_load_hit      = 1;
            i_flags_refresh = 0;
            #1;
            if (candidate.accept) $fatal(1, "untrusted load hit issued");
            tick();
            i_load_trust      = 1;
            // Only the low byte of an ARM register shift count is used.
            i_mw_value[95:64] = {24'h821f12, count};
            #1;
            if (!candidate.accept || candidate_o_shift_wait)
                $fatal(1, "forwarded Rs missed accept edge");
            tick();
            releases++;
            i_valid = 0;
            expect_result(operand, shift_kind, count, 1, old_carry);
        end
    endtask

    initial begin
        i_reset     = 1;
        i_condition = 14;
        i_writes    = 1;
        i_cpsr      = 32'h13;
        tick();
        i_reset = 0;
        for (value_case = 0; value_case < 2; value_case++) begin
            pattern = value_case ? 32'h7ffffffe : 32'h80000001;
            for (kind = 0; kind < 4; kind++)
            for (amount = 0; amount < 256; amount++)
            for (carry = 0; carry < 2; carry++)
            delayed_register_shift(pattern, kind[1:0], amount[7:0], carry[0]);

            for (kind = 0; kind < 4; kind++)
            for (carry = 0; carry < 2; carry++) begin
                configure(pattern, kind[1:0], 0, carry[0]);
                tick();
                i_valid         = 0;
                i_flags_refresh = 0;
                expect_result(pattern, kind[1:0], 0, 0, carry[0]);
                if (kind == 3) rrx_cases++;
            end
        end
        // The older W hit cannot release a younger M load for the same Rs.
        configure(32'h80000001, 0, 1, 0);
        i_load_owner           = 2'b11;
        i_load_hit             = 1;
        i_load_trust           = 1;
        i_forward_match[11:8]  = 4'b0101;
        i_forward_grant[34:30] = 5'b00010;
        i_mw_value[31:0]       = 32'h1000001f;
        #1;
        if (candidate.accept) $fatal(1, "younger M load lost priority to W");
        tick();
        i_flags_refresh  = 0;
        i_load_owner[0]  = 0;
        i_mw_value[31:0] = 32'h10000002;
        i_admit          = 0;
        tick();
        if (candidate.prepared) $fatal(1, "blocked backend prepared a shift");
        i_admit = 1;
        #1;
        if (!candidate.accept) $fatal(1, "ready younger M value did not issue");
        tick();
        i_valid          = 0;
        i_ready          = 0;
        i_mw_value[31:0] = 32'hdeaddead;
        tick();
        if (!candidate_o_valid || candidate_o_a_can_finish)
            $fatal(1, "accepted shift did not hold behind A backpressure");
        i_ready = 1;
        expect_result(32'h80000001, 0, 2, 1, 0);

        // A Thumb register shift still prepares the held count.
        configure(32'h80000001, 0, 1, 0);
        i_thumb        = 1;
        i_value[95:64] = 1;
        #1;
        if (!candidate_o_shift_wait || candidate.accept) $fatal(1, "Thumb bypassed preparation");
        tick();
        if (!candidate.prepared) $fatal(1, "Thumb did not prepare");
        tick();
        i_valid         = 0;
        i_thumb         = 0;
        i_flags_refresh = 0;
        expect_result(32'h80000001, 0, 1, 1, 0);

        // Flush a held shift as its unresolved source returns. A separate
        // instruction after the flush has its own register-shift count.
        configure(32'h80000001, 0, 1, 0);
        i_pending = 4'b0100;
        tick();
        i_return_ready   = 1;
        i_return_s_match = 4'b0100;
        i_return_data    = 64'h31;
        i_flush          = 1;
        tick();
        if (candidate.holding || candidate.prepared || candidate_o_valid)
            $fatal(1, "flushed result survived");
        flushed++;
        i_flush        = 0;
        i_pending      = 0;
        i_return_ready = 0;
        delayed_register_shift(32'h80000001, 1, 8'd32, 0);

        // Redirect from the older A-stage branch while the younger shift
        // waits. Even a ready forwarded operand must obey the redirect.
        configure(32'h80000001, 0, 0, 0);
        i_kind          = 3;
        i_branch_target = 32'h10004000;
        tick();
        configure(32'h80000001, 0, 1, 0);
        i_pending = 4'b0100;
        tick();
        if (!candidate_o_redirect) $fatal(1, "expected older branch redirect");
        i_pending             = 0;
        i_forward_match[11:8] = 4'b0100;
        i_load_hit            = 1;
        #1;
        if (candidate.accept) $fatal(1, "accepted across redirect");
        tick();
        if (candidate.holding || candidate.prepared || candidate_o_valid)
            $fatal(1, "redirected result survived");
        redirected++;
        i_valid = 0;
        tick();

        if (releases != 4097 || offered != releases || stale < releases ||
            !prepared || flushed != 1 || redirected != 1 || rrx_cases != 4)
            $fatal(1, "missing coverage");
        $display(
            "PASS early shift clocks=%0d offered=%0d stale=%0d forwarded=%0d prepared=%0d rrx=%0d flush=%0d redirect=%0d",
            clocks, offered, stale, releases, prepared, rrx_cases, flushed, redirected);
        $finish;
    end
endmodule
