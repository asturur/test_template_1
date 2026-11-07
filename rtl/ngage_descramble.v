/*  N-Gage flash read-side descrambler — combinational, one halfword.
    Auto-generated from build/firmware/thc/scrambler-model.json.
    Each formula verified 100% on 1.09M known pairs; the stock digest
    2c09c86f reproduces exactly (scratch/flash-cipher-r4/).
    Active for PA in [0xa000, 0x2b3000) only; caller gates the range.
    Made with Claude, 2026-11-01. */

module ngage_descramble (
    input  wire [21:1] addr,    // halfword address (byte PA >> 1)
    input  wire [15:0] cipher,  // ciphertext from flash
    output wire [15:0] plain    // descrambled plaintext
);

    wire [21:0] A = {addr, 1'b0};  // reconstruct byte address
    wire [15:0] C = cipher;

    assign plain[0] = (^(C & 16'h0101)) ^ (^(A & 22'h020102)) ^ (A[4] & A[10]) ^ (A[8] & A[17]);
    assign plain[1] = (^(C & 16'h0202)) ^ (A[3] & A[13]) ^ (A[9] & A[17]);
    assign plain[2] = (^(C & 16'h0044)) ^ (^(A & 22'h102628)) ^ (A[9] & A[10]) ^ (A[5] & A[13]);
    assign plain[3] = 1'b1 ^ (^(C & 16'h0108)) ^ (^(A & 22'h040008)) ^ (A[11] & A[12]) ^
        (A[5] & A[14]);
    assign plain[4] = (^(C & 16'h0012)) ^ (^(A & 22'h004c84)) ^ (A[7] & A[11]) ^ (A[10] & A[14]);
    assign
        plain[5] = 1'b1 ^ (^(C & 16'h8020)) ^ (^(A & 22'h240188)) ^ (A[3] & A[8]) ^ (A[7] & A[18]);
    assign
        plain[6] = 1'b1 ^ (^(C & 16'h0840)) ^ (^(A & 22'h041042)) ^ (A[6] & A[12]) ^ (A[4] & A[15]);
    assign
        plain[7] = 1'b1 ^ (^(C & 16'h00a0)) ^ (^(A & 22'h010802)) ^ (A[2] & A[5]) ^ (A[11] & A[16]);
    assign
        plain[8] = 1'b1 ^ (^(C & 16'h0140)) ^ (^(A & 22'h202204)) ^ (A[9] & A[13]) ^ (A[7] & A[16]);
    assign plain[9] = (^(C & 16'h2200)) ^ (^(A & 22'h088012)) ^ (A[4] & A[15]) ^ (A[8] & A[16]);
    assign plain[10] = (^(C & 16'h0401)) ^ (^(A & 22'h002280)) ^ (A[5] & A[11]) ^ (A[7] & A[13]);
    assign plain[11] = 1'b1 ^ (^(C & 16'h0800)) ^ (^(A & 22'h084980));
    assign
        plain[12] = 1'b1 ^ (^(C & 16'h5000)) ^ (^(A & 22'h008122)) ^ (A[3] & A[6]) ^ (A[8] & A[15]);
    assign plain[13] = 1'b1 ^ (^(C & 16'h2004)) ^ (^(A & 22'h001004)) ^ (A[6] & A[11]);
    assign plain[14] = (^(C & 16'h4400)) ^ (^(A & 22'h000006)) ^ (A[4] & A[15]) ^ (A[6] & A[16]);
    assign plain[15] = (^(C & 16'h8008)) ^ (^(A & 22'h100444)) ^ (A[6] & A[10]) ^ (A[12] & A[17]);

endmodule
