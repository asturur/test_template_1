module tb;
    reg [31:0] address;
    wire rom_hit, ram_hit, cdrive_hit, pmm_hit;
    wire [24:0] rom_offset;
    ngage_rom_map dut(address, rom_hit, rom_offset, ram_hit, cdrive_hit, pmm_hit);

    task check(input [31:0] a, input [3:0] hits, input [24:0] offset);
        begin
            address = a; #1;
            if ({rom_hit,ram_hit,cdrive_hit,pmm_hit} !== hits ||
                (rom_hit && rom_offset !== offset)) begin
                $display("FAIL %08x hits=%b offset=%08x", a,
                         {rom_hit,ram_hit,cdrive_hit,pmm_hit}, rom_offset);
                $fatal(1);
            end
        end
    endtask
    initial begin
        check(32'h00000000, 4'b1000, 25'h0000000);
        check(32'h006fffff, 4'b1000, 25'h06fffff);
        check(32'h00700000, 4'b1000, 25'h1300000);
        check(32'h007effff, 4'b1000, 25'h13effff);
        check(32'h007f0000, 4'b0001, 0);
        check(32'h007fffff, 4'b0001, 0);
        check(32'h00800000, 4'b0000, 0);
        check(32'h02000000, 4'b1000, 25'h0700000);
        check(32'h023fffff, 4'b1000, 25'h0afffff);
        check(32'h02400000, 4'b0010, 0);
        check(32'h027fffff, 4'b0010, 0);
        check(32'h02800000, 4'b0000, 0);
        check(32'h04000000, 4'b1000, 25'h0b00000);
        check(32'h047fffff, 4'b1000, 25'h12fffff);
        check(32'h04800000, 4'b0000, 0);
        check(32'h0a000000, 4'b0100, 0);
        check(32'h0affffff, 4'b0100, 0);
        check(32'h0b000000, 4'b0000, 0);
        $display("PASS firmware address map");
        $finish;
    end
endmodule
