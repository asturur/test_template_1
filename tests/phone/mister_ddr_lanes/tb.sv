module tb;
    reg [31:0] address, data;
    reg [3:0] be;
    reg [63:0] read_data;
    wire [28:0] ddr_address;
    wire [63:0] ddr_data;
    wire [7:0] ddr_be;
    wire [31:0] result;
    ngage_ddr_lanes dut(address, data, be, read_data, ddr_address, ddr_data, ddr_be, result);
    integer lane, mask;
    initial begin
        data = 32'h12345678;
        read_data = 64'hfedcba98_76543210;
        for (lane = 0; lane < 2; lane = lane + 1) begin
            for (mask = 0; mask < 16; mask = mask + 1) begin
                address = 32'h01400000 + 4 * lane;
                be = mask;
                #1;
                if (ddr_address !== 29'h0280000 ||
                    ddr_data !== 64'h12345678_12345678 ||
                    ddr_be !== (lane ? (mask << 4) : mask) ||
                    result !== (lane ? 32'hfedcba98 : 32'h76543210)) begin
                    $display("FAIL lane=%0d mask=%x addr=%x be=%x read=%x", lane, mask, ddr_address, ddr_be, result);
                    $fatal(1);
                end
            end
        end
        address = 32'hffffffff; #1;
        if (ddr_address !== 29'h1fffffff) $fatal(1, "high address truncated");
        $display("PASS MiSTer DDR lanes");
        $finish;
    end
endmodule
