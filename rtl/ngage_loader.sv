// Sequential v1 bundle loader. DDR requests use 32-bit byte addresses and
// remain pending until acknowledged. CRC-32 is over each unmodified section.
// A new download invalidates the preceding image. CPU reset must include !valid.
module ngage_loader #(
    parameter [31:0] BASE     = 32'h30000000,
    parameter [31:0] CORE_LEN = 32'h11c0000,
                     EXT_LEN  = 32'h230000,
    parameter [31:0] C_LEN    = 32'h400000,
                     PMM_LEN  = 32'h10000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        download,
    input  wire        wr,
    input  wire [26:0] addr,
    input  wire [15:0] data,
    output wire        wait_req,
    output reg         valid = 0,
    output reg         failed = 0,
    output wire        mem_valid,
    input  wire        mem_ready,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_data,
    output wire [ 3:0] mem_be,
    input  wire        mem_done,
    output reg  [ 1:0] image_profile = 0,
    output reg         known_firmware = 0
);
    reg prev = 0, active = 0, pending = 0, issued = 0;
    reg [31:0] position = 0, section_pos = 0, crc = 32'hffffffff;
    reg [ 1:0] section = 0;
    reg [15:0] h           [0:63];
    reg [31:0] target_addr, target_data;
    reg [ 3:0] target_be;
    reg [31:0] expected_crc[0:3];
    reg [31:0] size_now, offset_now;
    reg     [31:0] crc_next;
    integer        j;
    function automatic [31:0] crc_byte(input [31:0] c, input [7:0] b);
        reg     [31:0] x;
        integer        i;
        begin
            x = c ^ {24'b0, b};
            for (i = 0; i < 8; i = i + 1) x = (x >> 1) ^ (32'hedb88320 & {32{x[0]}});
            crc_byte = x;
        end
    endfunction
    always @* begin
        case (section)
            0: begin
                size_now   = CORE_LEN;
                offset_now = 0;
            end
            1: begin
                size_now   = EXT_LEN;
                offset_now = 32'h11c0000;
            end
            2: begin
                size_now   = C_LEN;
                offset_now = 32'h1400000;
            end
            default: begin
                size_now   = PMM_LEN;
                offset_now = 32'h1800000;
            end
        endcase
        crc_next = crc_byte(crc_byte(crc, data[7:0]), data[15:8]);
    end
    assign mem_valid = pending && !issued;
    assign mem_addr  = target_addr;
    assign mem_data  = target_data;
    assign mem_be    = target_be;
    assign wait_req  = pending || (download && !active);
    always @(posedge clk) begin
        prev <= download;
        if (reset) begin
            active         <= 0;
            pending        <= 0;
            issued         <= 0;
            valid          <= 0;
            failed         <= 0;
            position       <= 0;
            prev           <= 0;
            image_profile  <= 0;
            known_firmware <= 0;
        end else begin
            if (download && !prev) begin
                active         <= 1;
                valid          <= 0;
                failed         <= pending;
                position       <= 0;
                section_pos    <= 0;
                section        <= 0;
                crc            <= 32'hffffffff;
                image_profile  <= 0;
                known_firmware <= 0;
            end
            if (mem_valid && mem_ready) issued <= 1;
            if (pending && mem_done) begin
                pending <= 0;
                issued  <= 0;
            end
            if (active && download && wr && !wait_req) begin
                if ({5'b0, addr} != position || addr[0] || failed) failed <= 1;
                else if (position < 128) begin
                    h[position[6:1]] <= data;
                    if (position == 126) begin
                        // Validate all fixed header fields, four section offsets/lengths,
                        // profile, and reserved padding before accepting any payload.
                        if ({h[3], h[2], h[1], h[0]} != 64'h003142454741474e ||
                            {h[5], h[4]} != 1 || h[7] != 0 || (h[6] != 1 && h[6] != 2) ||
                            {h[9], h[8]} != 4 || {h[11], h[10]} != 128 ||
                            {h[13], h[12]} != 0 || {h[15], h[14]} != CORE_LEN ||
                            {h[19], h[18]} != 32'h11c0000 || {h[21], h[20]} != EXT_LEN ||
                            {h[25], h[24]} != 32'h1400000 || {h[27], h[26]} != C_LEN ||
                            {h[31], h[30]} != 32'h1800000 || {h[33], h[32]} != PMM_LEN || data != 0)
                            failed <= 1;
                        for (j = 36; j < 63; j = j + 1) if (h[j] != 0) failed <= 1;
                        image_profile <= h[6][1:0];
                        // Only the audited stock inputs have a corresponding save profile.
                        // CRC verifies transfer integrity but is not a cryptographic hash.
                        known_firmware <= CORE_LEN == 32'h11c0000 && EXT_LEN == 32'h230000 &&
                            {h[17], h[16]} == 32'h9bf61548 && {h[23], h[22]} == 32'h354de3e8;
                        expected_crc[0] <= {h[17], h[16]};
                        expected_crc[1] <= {h[23], h[22]};
                        expected_crc[2] <= {h[29], h[28]};
                        expected_crc[3] <= {h[35], h[34]};
                    end
                    position <= position + 2;
                end else if (section_pos >= size_now || size_now[0]) failed <= 1;
                else begin
                    target_addr <= BASE + offset_now + (section_pos & 32'hfffffffc);
                    target_data <= {data, data};
                    target_be   <= section_pos[1] ? 4'b1100 : 4'b0011;
                    pending     <= 1;
                    issued      <= 0;
                    position    <= position + 2;
                    if (section_pos + 2 == size_now) begin
                        if ((crc_next ^ 32'hffffffff) != expected_crc[section]) failed <= 1;
                        section_pos <= 0;
                        crc         <= 32'hffffffff;
                        if (section != 3) section <= section + 1;
                        else section_pos <= size_now;
                    end else begin
                        section_pos <= section_pos + 2;
                        crc         <= crc_next;
                    end
                end
            end
            if (active && !download && !pending) begin
                active <= 0;
                if(!failed && position == 128+CORE_LEN+EXT_LEN+C_LEN+PMM_LEN && section==3 && section_pos==PMM_LEN)
                    valid <= 1;
                else begin
                    valid  <= 0;
                    failed <= 1;
                end
            end
        end
    end
endmodule
