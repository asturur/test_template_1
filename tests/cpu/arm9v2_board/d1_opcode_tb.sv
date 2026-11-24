`timescale 1ns / 1ps

module d1_opcode_case #(
    parameter THUMB_HALF = 0,
    parameter PAYLOAD_FREE = 0
) (output bit pass);
    integer clocks = 0;
    integer seed = 32'hd150c1a5;
    integer pushes, pops, fast, simultaneous, full_hold, killed, faults, prefixes, suffixes;
    integer thumb_checks, list_checks;
    reg [15:0] seen_kind = 0;
`include "interface.vh"

    task automatic compare_packet;
        compare_interface();
        if ({reference.count, reference.tail, reference.head_select, reference.d2_valid,
             reference.out_valid, reference.redirect_in_d2, reference.prefix_valid,
             reference.push, reference.pop, reference.shortcut, reference.d2} !==
            {candidate.count, candidate.tail, candidate.head_select, candidate.d2_valid,
             candidate.out_valid, candidate.redirect_in_d2, candidate.prefix_valid,
             candidate.push, candidate.pop, candidate.shortcut, candidate.d2})
            $fatal(1, "D1/D2 control or packet differs at %0d", clocks);
        if (candidate.count != 0 &&
            {candidate.front, candidate.decoded, candidate.head_kind} !==
            {reference.front, reference.decoded, reference.decoded[131-:4]})
            $fatal(1, "Queued class differs from its original packet at %0d", clocks);
    endtask

    task automatic check_input;
        reg [3:0] kind;
        kind = reference.classify(reference.incoming[208-:32], reference.incoming[80:76],
            reference.incoming[18], reference.incoming[16], reference.incoming[32-:5] == 5'h10,
            reference.incoming[27-:5] == 0);
        if (candidate.incoming !== reference.incoming || candidate.incoming_kind !== kind)
            $fatal(1, "Input class mismatch word=%h PC=%h mode=%h", i_word, i_pc, i_mode);
    endtask

    task automatic tick;
        #1;
        if (clocks != 0) begin
            compare_packet();
            check_input();
            if (candidate.push) begin
                pushes++;
                seen_kind[candidate.incoming_kind] = 1;
                if (i_fault) faults++;
                if (candidate.incoming_kind == 10) prefixes++;
                if (candidate.incoming_kind == 11) suffixes++;
            end
            if (candidate.pop) pops++;
            if (candidate.shortcut) fast++;
            if (candidate.push && candidate.pop) simultaneous++;
            if (candidate.count == 2 && !candidate.pop && !candidate.kill_younger) full_hold++;
            if (candidate.kill_younger && candidate.count != 0) killed++;
        end
        i_clk = 1;
        #1;
        i_clk = 0;
        #1;
        clocks++;
        compare_packet();
    endtask

    task automatic thumb_word(input [15:0] value, input bit upper);
        i_thumb = 1;
        i_pc[1] = upper;
        // The production interface supplies one selected halfword in the
        // low half. The alternate interface presents the whole word.
        i_word = !THUMB_HALF && upper ? {value, 16'h5981} : {16'h5981, value};
    endtask

    function automatic [31:0] directed_arm(input int n);
        case (n)
            0: directed_arm = 32'he3a01023; // DP
            1: directed_arm = 32'he10f2000; // MRS
            2: directed_arm = 32'he129f000; // MSR
            3: directed_arm = 32'hea000040; // direct branch
            4: directed_arm = 32'he12fff12; // BX
            5: directed_arm = 32'he5932100; // LDR
            6: directed_arm = 32'he893000c; // LDM
            7: directed_arm = 32'hee010f10; // CP15
            8: directed_arm = 32'hffffffff; // undefined
            9: directed_arm = 32'hef000016; // SWI
            10: directed_arm = 32'he1032091; // SWP
            11: directed_arm = 32'he0020391; // MUL
            12: directed_arm = 32'he0832491; // MULL
            13: directed_arm = 32'he8930000; // empty LDM
            14: directed_arm = 32'he1c120d0; // unsupported halfword store
            default: directed_arm = 32'hf0000000;
        endcase
    endfunction

    initial begin
        i_reset = 1;
        tick();
        i_reset = 0;
        // Prove that testing empty directly agrees with the old popcount
        // for every list. Compare every Thumb encoding in both halves and
        // exercise an ARM block with that exact same list.
        i_mode = 5'h13;
        for (int bits = 0; bits < 65536; bits++) begin
            if ((reference.popcount16(bits[15:0]) == 0) !== (bits == 0))
                $fatal(1, "zero test differs for register list %h", bits[15:0]);
            i_thumb = 0;
            i_word = {16'he893, bits[15:0]};
            #1;
            check_input();
            list_checks++;
            for (int upper = 0; upper < 2; upper++) begin
                thumb_word(bits[15:0], upper[0]);
                #1;
                check_input();
                thumb_checks++;
            end
        end
        // Fill both slots on real enqueue edges before enabling issue.
        i_thumb = 0;
        i_pc = 0;
        i_valid = 1;
        i_word = 32'he3a00001;
        repeat (5) tick();
        i_ready = 1;
        i_ready_payload = 1;
        i_serial_continue = 1;
        repeat (8) tick();
        // Directed classes, wrap and backpressure, ARM/Thumb switches,
        // fetch faults, permission modes, flushes and direct shortcuts.
        for (int n = 0; n < 30000; n++) begin
            i_valid = n % 23 != 0;
            i_pc = i_pc + 4;
            i_ready = n % 7 < 4;
            i_ready_payload = i_ready || n % 47 == 0;
            i_fault = n % 59 == 0;
            i_flush = n % 37 == 0;
            i_reset = n % 1283 == 0;
            i_serial_continue = n % 5 == 0;
            i_mode = n % 13 == 0 ? 5'h10 : (n % 17 == 0 ? 5'h12 : 5'h13);
            i_lock_valid = n % 19 == 0;
            i_lock_tag = 6'($random(seed));
            i_predicted = n % 11 == 0;
            i_pred_target = i_pc + 20;
            i_predicate_stable = n % 31 == 0;
            i_predicate_flags = 4'($random(seed));
            i_thumb = 0;
            if (n % 23 < 16) begin
                i_word = directed_arm(n % 23);
            end else if (n % 23 == 16) begin
                thumb_word(16'hf000, 0);
            end else if (n % 23 == 17) begin
                i_pc = i_pc - 2;
                thumb_word(16'hf801, 1);
            end else if (n % 23 == 18) begin
                thumb_word(16'he012, n[0]);
            end else if (n[0]) begin
                thumb_word(16'($random(seed)), n[1]);
            end else begin
                i_word = 32'($random(seed));
            end
            tick();
        end
        if (!(pushes && pops && fast && simultaneous && full_hold && killed && faults && prefixes && suffixes) ||
            seen_kind != 16'h7fff)
            $fatal(1, "Incomplete coverage class=%h fast=%0d simultaneous=%0d prefixes=%0d suffixes=%0d",
                   seen_kind, fast, simultaneous, prefixes, suffixes);
        $display("PASS D1 opcode half=%0d free=%0d lists=%0d thumb=%0d clocks=%0d pushes=%0d pops=%0d fast=%0d simultaneous=%0d full=%0d kills=%0d faults=%0d class=%h",
                 THUMB_HALF, PAYLOAD_FREE, list_checks, thumb_checks, clocks, pushes, pops, fast,
                 simultaneous, full_hold, killed, faults, seen_kind);
        pass = 1;
    end
endmodule

module d1_opcode_tb;
    wire [3:0] pass;
    for (genvar n = 0; n < 4; n++)
        d1_opcode_case #(.THUMB_HALF(n % 2), .PAYLOAD_FREE(n / 2)) sim(pass[n]);
    initial begin
        wait (&pass);
        $finish;
    end
    initial begin
        #500000;
        $fatal(1, "D1 opcode differential timed out");
    end
endmodule
