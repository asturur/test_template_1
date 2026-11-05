// Apply the authentic-path flash transformation to each halfword independently.
// Only normal code-flash array reads in the configured physical window use it.
module ngage_flash_read_decode(
 input wire [31:0] physical_address, input wire [31:0] raw_data,
 input wire array_read, input wire code_flash, output wire [31:0] result
);
 wire [15:0] low_plain, high_plain;
 wire [31:0] aligned={physical_address[31:2],2'b00};
 wire active=array_read && code_flash && aligned>=32'h0000a000 && aligned<32'h002b3000;
 ngage_descramble low(.addr(aligned[21:1]),.cipher(raw_data[15:0]),.plain(low_plain));
 ngage_descramble high(.addr(aligned[21:1]+21'd1),.cipher(raw_data[31:16]),.plain(high_plain));
 assign result=active ? {high_plain,low_plain} : raw_data;
endmodule
