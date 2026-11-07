// Validate one NGSAVE1 sector from an asynchronously readable 16-bit buffer.
// Expected SHA values are supplied by the selected, verified firmware profile;
// the caller must not assert them for an unverified bundle.
module ngage_save_header #(
    parameter [31:0] C_BYTES   = 32'h00400000,
                     PMM_BYTES = 32'h00010000
) (
    input  wire         clk,
    input  wire         reset,
    input  wire         start,
    input  wire [  1:0] profile,
    input  wire [255:0] core_sha_le,
    input  wire [255:0] extension_sha_le,
    output reg  [  7:0] address,
    input  wire [ 15:0] word_data,
    output reg          busy,
    output reg          done,
    output reg          valid
);
    reg [31:0] crc = 32'hffffffff;
    reg [15:0] crc_low = 0;
    reg        mismatch = 0;
    function automatic [31:0] crc_byte(input [31:0] c, input [7:0] b);
        reg     [31:0] x;
        integer        i;
        begin
            x = c ^ {24'b0, b};
            for (i = 0; i < 8; i = i + 1) x = (x >> 1) ^ (32'hedb88320 & {32{x[0]}});
            crc_byte = x;
        end
    endfunction
    reg [15:0] expected;
    always @* begin
        expected = 0;
        case (address)
            0:  expected = 16'h474e;
            1:  expected = 16'h4153;
            2:  expected = 16'h4556;
            3:  expected = 16'h0031;
            4:  expected = 1;
            5:  expected = 0;
            6:  expected = {14'b0, profile};
            7:  expected = 0;
            8:  expected = C_BYTES[15:0];
            9:  expected = C_BYTES[31:16];
            10: expected = PMM_BYTES[15:0];
            11: expected = PMM_BYTES[31:16];
            default: begin
                if (address >= 12 && address < 28) expected = core_sha_le[(address-12)*16+:16];
                else if (address >= 28 && address < 44)
                    expected = extension_sha_le[(address-28)*16+:16];
            end
        endcase
    end
    always @(posedge clk) begin
        done <= 0;
        if (reset) begin
            busy     <= 0;
            valid    <= 0;
            address  <= 0;
            crc      <= 32'hffffffff;
            mismatch <= 0;
        end else if (start && !busy) begin
            busy     <= 1;
            valid    <= 0;
            address  <= 0;
            crc      <= 32'hffffffff;
            mismatch <= 0;
        end else if (busy) begin
            if (address < 254) begin
                if (word_data != expected) mismatch <= 1;
                crc <= crc_byte(crc_byte(crc, word_data[7:0]), word_data[15:8]);
            end else if (address == 254) crc_low <= word_data;
            else begin
                valid<=!mismatch && (profile==1 || profile==2) && ({word_data,crc_low}==(crc^32'hffffffff));
                busy <= 0;
                done <= 1;
            end
            address <= address + 1'b1;
        end
    end
endmodule
