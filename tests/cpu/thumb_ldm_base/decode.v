// Thumb format15: loaded Rn wins over implicit LDM writeback.
`timescale 1ns / 1ps
module test;
    reg  [31:0] instruction;
    wire [34:0] decoded;
    wire valid, undefined_instruction, align32, irq, fiq;
    reg [34:0] expected;
    integer load, base, mask;
    integer cases  /* verilator public_flat_rw */;

    zap_mode16_decoder dut (
        .i_instruction      (instruction),
        .i_instruction_valid(1'b1),
        .i_offset           (11'b0),
        .i_irq              (1'b0),
        .i_fiq              (1'b0),
        .i_cpsr_ff_t        (1'b1),
        .o_instruction      (decoded),
        .o_instruction_valid(valid),
        .o_und              (undefined_instruction),
        .o_force32_align    (align32),
        .o_irq              (irq),
        .o_fiq              (fiq)
    );

    initial begin
        cases = 0;
        for (load = 0; load < 2; load = load + 1)
        for (base = 0; base < 8; base = base + 1)
        for (mask = 0; mask < 256; mask = mask + 1) begin
            instruction = 32'hc000 | (load << 11) | (base << 8) | mask;
            expected = {
                3'b000,
                4'he,
                3'b100,
                1'b0,
                1'b1,
                1'b0,
                (load == 0 || (mask & (1 << base)) == 0),
                load[0],
                base[3:0],
                8'b0,
                mask[7:0]
            };
            #1;
            if (decoded !== expected || !valid || undefined_instruction || irq || fiq)
                $fatal(
                    1,
                    "Thumb multiple decode %h: got %h expected %h",
                    instruction,
                    decoded,
                    expected
                );
            cases = cases + 1;
        end
        if (cases != 4096) $fatal(1, "Incomplete decoder sweep: %0d", cases);
        $display("PASS: %0d Thumb LDM/STM decoder cases, all bases and lists", cases);
        $finish;
    end
endmodule
