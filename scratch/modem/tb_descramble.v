/*  Cross-check testbench: drives ngage_descramble.v with vectors from the
    Python model (gen_descramble_vectors.py -> descr_vectors.hex) and compares.
    Run:  python3 -I gen_descramble_vectors.py > descr_vectors.hex
          iverilog -g2001 -o tb_descr tb_descramble.v ../../rtl/ngage_descramble.v
          vvp tb_descr
    Made with Claude, 2026-11-01.
*/
`timescale 1ns/1ns

module tb_descramble;

reg  [21:1] addr;
reg  [15:0] cipher;
wire [15:0] plain;

ngage_descramble dut(.addr(addr), .cipher(cipher), .plain(plain));

reg [15:0] vec [0:131071];
integer vp, nvec, fails;

initial begin
    $readmemh("descr_vectors.hex", vec);
    vp = 0; nvec = 0; fails = 0;

    while (vec[vp] !== 16'hffff && vec[vp] !== 16'hxxxx) begin
        addr   = {vec[vp][5:0], vec[vp+1][15:1]};  // 21-bit halfword addr
        cipher = vec[vp+2];
        #1;
        if (plain !== vec[vp+3]) begin
            $display("FAIL vec %0d: addr=%05x cipher=%04x got=%04x want=%04x",
                     nvec, {addr,1'b0}, cipher, plain, vec[vp+3]);
            fails = fails + 1;
        end
        vp = vp + 4;
        nvec = nvec + 1;
    end

    if (fails == 0)
        $display("ALL %0d VECTORS PASS (HDL descrambler == Python model)", nvec);
    else
        $display("%0d FAILURES over %0d vectors", fails, nvec);
    $finish;
end

endmodule
