// Address map used by the current firmware simulation. ROM offsets address the
// concatenation of core.bin and extension.bin; this is not a flash controller.
module ngage_rom_map (
    input  wire [31:0] address,
    output reg         rom_hit,
    output reg  [24:0] rom_offset,
    output wire        ram_hit,
    output wire        cdrive_hit,
    output wire        pmm_hit
);
    assign ram_hit    = address >= 32'h0a000000 && address < 32'h0b000000;
    assign cdrive_hit = address >= 32'h02400000 && address < 32'h02800000;
    assign pmm_hit    = address >= 32'h007f0000 && address < 32'h00800000;

    always @* begin
        rom_hit    = 1'b1;
        rom_offset = 25'd0;
        if (address < 32'h00700000) rom_offset = address[24:0];
        else if (address < 32'h007f0000) rom_offset = 25'h1300000 + (address[24:0] - 25'h0700000);
        else if (address >= 32'h02000000 && address < 32'h02400000)
            rom_offset = 25'h0700000 + address[24:0];
        else if (address >= 32'h04000000 && address < 32'h04800000)
            rom_offset = 25'h0b00000 + address[24:0];
        else rom_hit = 1'b0;
    end
endmodule
