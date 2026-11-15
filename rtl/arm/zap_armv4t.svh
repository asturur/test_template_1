// ARM920T guest classification before any coprocessor or CISC expansion.
// ARM DDI0151C2.2.2: extension spaces are undefined. Cond1111 is
// architecturally UNPREDICTABLE on v4; this core chooses deterministic UND.
// Internal ZAP/Thumb-expanded micro-operations bypass this guest classifier.
function automatic armv4t_unsupported(input [31:0] ins, input [4:0] mode);
    reg supported;
    begin
        supported = 1'b0;
        if (ins[27:24] == 4'hf || ins[27:25] == 3'b101 || ins[27:25] == 3'b100)
            supported = 1'b1; // SWI, B/BL, LDM/STM.
        else if (ins[27:26] == 2'b01 && !(ins[25] && ins[4]))
            supported = 1'b1; // ARMv4 single transfer, no register-shift extension.
        else if ((ins & 32'h0fc000f0) == 32'h00000090 ||
                 (ins & 32'h0f8000f0) == 32'h00800090 ||
                 (ins & 32'h0fb00ff0) == 32'h01000090)
            supported = 1'b1; // MUL/MLA, long multiply and SWP/B.
        else if ((ins & 32'h0ffffff0) == 32'h012fff10 ||
                 (ins & 32'h0fbf0fff) == 32'h010f0000 ||
                 (ins & 32'h0fb0fff0) == 32'h0120f000 ||
                 (ins & 32'h0fb0f000) == 32'h0320f000)
            supported = 1'b1; // BX, MRS and register/immediate MSR.
        else if (ins[27:24] == 4'he && ins[4] && ins[11:8] == 4'hf)
            supported = mode != 5'h10; // Privileged CP15 MRC/MCR only.
        else if (ins[27:25] == 3'b000 && ins[7] && ins[4] && ins[6:5] != 2'b00)
            supported = ins[20] || !ins[6]; // STRH/LDRH/LDRSB/LDRSH; no LDRD/STRD.
        else if (ins[27:26] == 2'b00 && !(ins[7] && ins[4] && !ins[25]) &&
                 !(!ins[20] && ins[24:23] == 2'b10))
            supported = 1'b1; // Ordinary data processing, excluding misc extension space.
        armv4t_unsupported = !supported || ins[31:28] == 4'hf;
    end
endfunction
