//
// (C)2016-2024 Revanth Kamaraj (krevanth) <revanth91kamaraj@gmail.com>
//
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
// 02110-1301, USA.
//
// Flip flop based register files. Good for FPGA where flip-flops are
// plentiful.
//

module zap_register_file
(
        // Clock and reset.
        input logic              i_clk,
        input logic              i_reset,

        // Write enable.
        input logic              i_wen,

        // Write address. Note that _c does not need write enable.
        input logic  [5:0]       i_wr_addr_a,   // Binary address.
        input logic  [5:0]       i_wr_addr_b,   // Binary address.
        input logic  [39:0]      i_wr_addr_c,   // 1-Hot address.

        // Write data.
        input logic  [31:0]      i_wr_data_a,
        input logic  [31:0]      i_wr_data_b,
        input logic  [31:0]      i_wr_data_c,

        // Read addresses (All binary).
        input logic  [5:0]       i_rd_addr_a,
        input logic  [5:0]       i_rd_addr_b,
        input logic  [5:0]       i_rd_addr_c,
        input logic  [5:0]       i_rd_addr_d,

        // Read data corresponding. Combinationally read via MUX.
        output logic  [31:0]      o_rd_data_a,
        output logic  [31:0]      o_rd_data_b,
        output logic  [31:0]      o_rd_data_c,
        output logic  [31:0]      o_rd_data_d
);

logic [39:0][31:0] mem; // Flip-flop array.

// 3 write ports. Synchronous reset for the register file.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                mem <= {32'd40{32'd0}};
        end
        else
        begin
                // Standard 2-port write.
                if ( i_wen )
                begin
                        mem [ i_wr_addr_a ] <= i_wr_data_a;
                        mem [ i_wr_addr_b ] <= i_wr_data_b;
                end

                // Background load.
                if ( |i_wr_addr_c )
                begin
                        for(int i=0;i<40;i++)
                        begin
                                if(i_wr_addr_c[i])
                                begin
                                        mem [i] <= i_wr_data_c;
                                end
                        end
                end
        end
end

// Decode each asynchronous read locally, then reduce masked words through a
// balanced tree. Keep the read combinational: write timing, port priorities and
// the decode/issue pipeline boundary are unchanged.
wire [3:0][5:0] rd_addr = {i_rd_addr_d, i_rd_addr_c,
                           i_rd_addr_b, i_rd_addr_a};
wire [3:0][31:0] rd_data;
generate
        for (genvar port_no = 0; port_no < 4; port_no = port_no + 1)
        begin : g_read_port
                wire [31:0] tree [1:127];
                for (genvar reg_no = 0; reg_no < 64; reg_no = reg_no + 1)
                begin : g_word
                        if (reg_no < 40)
                        begin : g_present
                                assign tree[64 + reg_no] = mem[reg_no] &
                                        {32{rd_addr[port_no] == reg_no}};
                        end
                        else
                        begin : g_padding
                                assign tree[64 + reg_no] = 32'd0;
                        end
                end
                for (genvar node_no = 1; node_no < 64; node_no = node_no + 1)
                begin : g_reduce
                        assign tree[node_no] = tree[2*node_no] | tree[2*node_no+1];
                end
                // Unimplemented physical addresses retain the original X value.
                assign rd_data[port_no] = rd_addr[port_no] < 6'd40 ? tree[1] : 'x;
        end
endgenerate
assign {o_rd_data_d, o_rd_data_c, o_rd_data_b, o_rd_data_a} = rd_data;

`ifndef SYNTHESIS

wire [31:0] r0   =  mem[0];
wire [31:0] r1   =  mem[1];
wire [31:0] r2   =  mem[2];
wire [31:0] r3   =  mem[3];
wire [31:0] r4   =  mem[4];
wire [31:0] r5   =  mem[5];
wire [31:0] r6   =  mem[6];
wire [31:0] r7   =  mem[7];
wire [31:0] r8   =  mem[8];
wire [31:0] r9   =  mem[9];
wire [31:0] r10  =  mem[10];
wire [31:0] r11  =  mem[11];
wire [31:0] r12  =  mem[12];
wire [31:0] r13  =  mem[13];
wire [31:0] r14  =  mem[14];
wire [31:0] r15  =  mem[15];
wire [31:0] r16  =  mem[16];
wire [31:0] r17  =  mem[17];
wire [31:0] r18  =  mem[18];
wire [31:0] r19  =  mem[19];
wire [31:0] r20  =  mem[20];
wire [31:0] r21  =  mem[21];
wire [31:0] r22  =  mem[22];
wire [31:0] r23  =  mem[23];
wire [31:0] r24  =  mem[24];
wire [31:0] r25  =  mem[25];
wire [31:0] r26  =  mem[26];
wire [31:0] r27  =  mem[27];
wire [31:0] r28  =  mem[28];
wire [31:0] r29  =  mem[29];
wire [31:0] r30  =  mem[30];
wire [31:0] r31  =  mem[31];
wire [31:0] r32  =  mem[32];
wire [31:0] r33  =  mem[33];
wire [31:0] r34  =  mem[34];
wire [31:0] r35  =  mem[35];
wire [31:0] r36  =  mem[36];
wire [31:0] r37  =  mem[37];
wire [31:0] r38  =  mem[38];
wire [31:0] r39  =  mem[39];

`endif

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
