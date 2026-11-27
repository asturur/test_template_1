`timescale 1ns / 1ps

module wb_rs_tb;
    `include "wb_rs_ports.vh"

    integer clocks = 0, accepted = 0, auxiliary = 0, primary = 0, load = 0, fast = 0;
    integer n, k, rail;
    reg [31:0] data, ticket = 32'h10001000;
    localparam [19:0] RF_GRANTS = {4{5'b10000}};
    localparam [31:0] MOVS_REG  = 32'he1b00112;

    task tick;
        begin
            #4 i_clk = 1;
            clocks++;
            #4 i_clk = 0;
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
        input [7:0] count;
        input is_register, carry;
        begin
            ticket             = ticket + 4;
            i_pc               = ticket;
            i_next_pc          = ticket + 4;
            reference_i_valid  = 1;
            candidate_i_valid  = 1;
            i_kind             = 0;
            i_instruction      = is_register ? MOVS_REG : 32'he1b00002;
            i_instruction[6:5] = shift_kind;
            i_used             = is_register ? 4'b0110 : 4'b0010;
            i_early            = i_used;
            i_reg_shift        = is_register;
            i_shift_pre        = {3'b0, shift_kind, 8'd0, 5'd0, is_register};
            i_value            = {32'd0, 24'h01c9bb, count, operand, 32'd0};
            i_forward_grant    = {RF_GRANTS, RF_GRANTS};
            i_mw_value         = 0;
            i_forward_match    = 0;
            i_load_owner       = 0;
            i_load_hit         = 0;
            i_load_trust       = 0;
            i_self_dep         = 0;
            i_cpsr             = {2'b00, carry, 1'b1, 28'h13};
            i_flags_refresh    = 1;
            i_ready            = 1;
            i_admit            = 1;
        end
    endtask

    function automatic [100:0] packet;
        input [31:0] pc, instruction;
        input [31:0] result;
        input [3:0] flags;
        input writes_flags;
        packet = {pc, instruction, result, flags, writes_flags};
    endfunction

    task check_value;
        input use_candidate;
        input [31:0] operand;
        input [1:0] shift_kind;
        input [7:0] count;
        input is_register, carry;
        output [100:0] received;
        reg [31:0] result;
        reg        wc;
        reg [ 3:0] expected_flags;
        begin
            {result, wc} = oracle_shift(operand, shift_kind, count, is_register, carry);
            expected_flags = {result[31], result == 0, wc, 1'b1};
            received = use_candidate ? packet(
                candidate_o_pc,
                candidate_o_instruction,
                candidate_o_result[31:0],
                candidate_o_cpsr_next[31:28],
                candidate_o_write_flags
            ) : packet(
                reference_o_pc,
                reference_o_instruction,
                reference_o_result[31:0],
                reference_o_cpsr_next[31:28],
                reference_o_write_flags
            );
            if (!(use_candidate ? candidate_o_valid : reference_o_valid) || received !== packet(
                    i_pc, i_instruction, result, expected_flags, 1'b1
                ))
                $fatal(
                    1,
                    "different accepted shift at clock %0d lane=%b count=%0d got=%h wanted=%h",
                    clocks,
                    use_candidate,
                    count,
                    received,
                    packet(
                        i_pc, i_instruction, result, expected_flags, 1'b1
                    )
                );
        end
    endtask

    task run_shift;
        input [31:0] operand;
        input [1:0] shift_kind;
        input [7:0] count;
        input carry, is_register;
        input [2:0] source;
        reg use_prepare;
        reg [100:0] old_packet, new_packet;
        begin
            configure(operand, shift_kind, count, is_register, carry);
            case (source)
                1: begin  // W auxiliary count and W load supplying Rm concurrently.
                    i_forward_grant[34:30] = 5'b00100;
                    i_forward_match[11:8]  = 4'b1000;
                    i_mw_value[127:96]     = {24'h801325, count};
                    i_forward_grant[29:25] = 5'b01000;
                    i_forward_match[7:4]   = 4'b0100;
                    i_mw_value[95:64]      = operand;
                    i_w_load_data          = operand;
                    i_load_owner           = 2'b10;
                    i_load_hit             = 1;
                end
                2, 3: begin  // W primary ALU value or trusted short load.
                    i_forward_grant[34:30] = 5'b01000;
                    i_forward_match[11:8]  = 4'b0100;
                    i_mw_value[95:64]      = {24'h751ea2, count};
                    if (source == 3) begin
                        i_self_dep        = 1;
                        i_load_owner      = 2'b10;
                        i_mw_value[95:64] = 32'hcccc00e3;
                        #1;
                        if (reference.accept || candidate.accept)
                            $fatal(1, "unavailable W load issued");
                        tick();
                        i_load_hit = 1;
                        #1;
                        if (reference.accept || candidate.accept)
                            $fatal(1, "untrusted W hit issued");
                        tick();
                        i_mw_value[95:64] = {24'hfe0989, count};
                        i_load_trust      = 1;
                    end
                end
                4: begin  // Younger M count masks simultaneous older W.
                    i_forward_grant[34:30] = 5'b00100;
                    i_forward_match[11:8]  = 4'b1001;
                    i_load_owner           = 2'b01;
                    i_mw_value[127:96]     = 32'hdddd0044;
                    #1;
                    if (reference.accept || candidate.accept || candidate.late_w_aux_rs)
                        $fatal(1, "unavailable M source lost priority");
                    tick();
                    i_load_owner           = 0;
                    i_forward_grant[34:30] = 5'b00010;
                    i_mw_value[31:0]       = {24'h4beab1, count};
                end
                5: begin  // W auxiliary as Rm stays on the original fast data path.
                    i_forward_grant[29:25] = 5'b00100;
                    i_forward_match[7:4]   = 4'b1000;
                    i_mw_value[127:96]     = operand;
                end
                default: begin
                end
            endcase
            use_prepare = source == 1;
            #1;
            if (!reference.accept || candidate.accept == use_prepare)
                $fatal(1, "unexpected issue phase at clock %0d source=%0d", clocks, source);
            tick();
            reference_i_valid = 0;
            i_flags_refresh   = 0;
            check_value(0, operand, shift_kind, count, is_register, carry, old_packet);
            if (use_prepare) begin
                if (!candidate.prepared || candidate.held_amount !== count || candidate_o_valid)
                    $fatal(1, "requested W count was not prepared");
                // The original W packet may retire. Both Rs and any W Rm
                // value have to survive even when the live buses change.
                i_forward_match = 0;
                i_forward_grant = {RF_GRANTS, RF_GRANTS};
                i_mw_value      = 128'hdeaddeaddeaddeaddeaddeaddeaddead;
                i_w_load_data   = 32'hbad0bad0;
                i_load_owner    = 0;
                i_load_hit      = 0;
                #1;
                if (count == 0) begin
                    i_admit = 0;
                    repeat (2) begin
                        tick();
                        if (candidate.accept || !candidate.prepared || candidate.held_amount !== count)
                            $fatal(1, "stalled preparation changed or issued");
                    end
                    i_admit = 1;
                    #1;
                end
                if (!candidate.accept) $fatal(1, "prepared shift missed the following edge");
                tick();
            end
            candidate_i_valid = 0;
            check_value(1, operand, shift_kind, count, is_register, carry, new_packet);
            if (old_packet !== new_packet) $fatal(1, "accepted sequence differs");
            tick();
            if (candidate_o_flags !== reference_o_flags) $fatal(1, "retired flags differ");
            if (candidate_o_a_valid || reference_o_a_valid) $fatal(1, "extra A packet");
            accepted++;
            case (source)
                1:       auxiliary++;
                2:       primary++;
                3:       load++;
                default: fast++;
            endcase
        end
    endtask

    initial begin
        i_reset     = 1;
        i_condition = 14;
        i_writes    = 1;
        i_cpsr      = 32'h13;
        tick();
        i_reset = 0;
        for (rail = 1; rail <= 3; rail++)
        for (k = 0; k < 4; k++)
        for (n = 0; n < 256; n++) begin
            data = n[0] ? 32'h80000001 : 32'h7ffffffe;
            run_shift(data, k[1:0], n[7:0], n[1], 1, rail[2:0]);
        end
        for (k = 0; k < 4; k++) begin
            run_shift(32'h80000001, k[1:0], 8'd32, 0, 1, 4);
            run_shift(32'hffffffff, k[1:0], 8'd0, 1, 1, 0);
            run_shift(32'h80000001, k[1:0], 8'd0, 1, 0, 0);
            run_shift(32'h80000001, k[1:0], 8'd0, 0, 0, 0);
            run_shift(32'h80000001, k[1:0], 8'd31, 1, 1, 5);
        end

        // Kill a newly prepared count and then replay with unrelated input.
        configure(32'h80000001, 0, 1, 1, 0);
        reference_i_valid      = 0;
        i_forward_grant[34:30] = 5'b00100;
        i_forward_match[11:8]  = 4'b1000;
        i_mw_value[127:96]     = 1;
        tick();
        if (!candidate.prepared) $fatal(1, "expected prepared count before flush");
        i_flush = 1;
        #1;
        if (candidate.accept) $fatal(1, "issued during flush");
        tick();
        if (candidate.prepared || candidate.holding || candidate_o_a_valid)
            $fatal(1, "flushed W count leaked");
        i_flush = 0;
        run_shift(32'h80000001, 0, 2, 0, 1, 0);
        if (auxiliary != 1024 || primary != 1024 || load != 1024 || fast != 21)
            $fatal(1, "missing coverage");
        $display(
            "PASS W auxiliary Rs preparation clocks=%0d accepted=%0d aux=%0d primary=%0d load=%0d fast=%0d flush=1",
            clocks, accepted, auxiliary, primary, load, fast);
        $finish;
    end
endmodule
