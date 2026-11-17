// SPDX-License-Identifier: GPL-3.0-or-later
// Isolated area experiment: all 64 architectural entries, eight comparisons.
// Eight 24-bit tags share a BRAM row. First-row hits retain the two-edge bank
// pipeline; later rows cost one edge each. Mutations serialize with busy.
module arm920_tlb_bank (
    input wire clk, reset, lookup,
    input wire [31:0] lookup_mva,
    output wire result_valid, result_hit,
    output wire [37:0] result_payload,
    input wire cancel_fill,
    input wire fill,
    input wire [31:0] fill_mva,
    input wire [37:0] fill_payload,
    input wire invalidate, invalidate_mva,
    input wire [31:0] invalidate_address,
    input wire lock_write,
    input wire [31:0] lock_data,
    output wire [31:0] lock_read,
    output wire busy
);
    localparam IDLE=0, SEARCH=1, FILL_SCAN=2, INVALIDATE_SCAN=3;
    reg [1:0] state;
    reg [2:0] row;
    reg [63:0] valid, preserved;
    reg [5:0] base, victim;
    reg preserve;
    reg [31:0] key;
    reg [37:0] saved_payload;
    reg [5:0] saved_victim;
    reg saved_preserve;
    // CP15 waits for busy to drain, so at most its one mutation can arrive
    // during an older fill/scan. Never drop that command or abort a prior fill.
    reg queued;
    reg queued_inv, queued_mva;
    reg [31:0] queued_data;
    reg response_valid, response_hit;
    reg [63:0] overlap_mask;
    wire compare_valid = state==SEARCH; // passive row-observer seam
    wire mutate = fill || invalidate || lock_write;
    wire scanning_mutation = state==FILL_SCAN || state==INVALIDATE_SCAN;
    wire command = !scanning_mutation && (queued || mutate);
    wire command_inv = queued ? queued_inv : invalidate;
    wire command_mva = queued ? queued_mva : invalidate_mva;
    wire command_lock = queued ? !queued_inv : (!invalidate && lock_write);
    wire [31:0] command_data = queued ? queued_data : command_inv ? invalidate_address : lock_data;
    wire start_fill = command && !queued && !invalidate && !lock_write && fill;
    wire finish_fill = state==FILL_SCAN && row==7 && !reset && !cancel_fill;
    wire [2:0] read_row = state==IDLE || command ? 3'd0 : row==7 ? row : row+3'd1;
    wire [191:0] tags;
    wire [7:0] lane_valid = valid >> {row,3'b0};
    wire [7:0] lane_hits, overlaps;
    wire [63:0] accumulated_overlap = overlap_mask | ({56'b0,overlaps} << {row,3'b0});
    wire [2:0] lane;
    wire [5:0] selected_entry = {row,lane};
    wire [191:0] tag_write = {{168{1'b0}},saved_payload[37:36],key[31:10]} << (saved_victim[2:0]*24);
    wire [23:0] tag_enable = finish_fill ? (24'h7 << (saved_victim[2:0]*3)) : 24'd0;
    function covers;
        input [21:0] tag;
        input [1:0] kind;
        input [31:0] address;
        begin
            case(kind)
                0: covers=tag[21:10]==address[31:20];
                1: covers=tag[21:6]==address[31:16];
                2: covers=tag[21:2]==address[31:12];
                default: covers=tag==address[31:10];
            endcase
        end
    endfunction
    function [2:0] pick8;
        input [7:0] bits;
        begin
            casez(bits)
                8'b???????1:pick8=0; 8'b??????10:pick8=1;
                8'b?????100:pick8=2; 8'b????1000:pick8=3;
                8'b???10000:pick8=4; 8'b??100000:pick8=5;
                8'b?1000000:pick8=6; default:pick8=7;
            endcase
        end
    endfunction
    genvar n;
    generate for(n=0;n<8;n=n+1)begin:lanes
        wire [23:0] entry_tag=tags[n*24+:24];
        assign lane_hits[n]=lane_valid[n] && covers(entry_tag[21:0],entry_tag[23:22],key);
        assign overlaps[n]=covers(entry_tag[21:0],entry_tag[23:22],key) ||
            covers(key[31:10],saved_payload[37:36],{entry_tag[21:0],10'b0});
    end endgenerate
    assign lane=pick8(lane_hits);
    assign busy=state!=IDLE || queued;
    assign result_valid=response_valid && !mutate && !queued;
    assign result_hit=response_hit;
    assign lock_read={base,victim,19'b0,preserve};
    // Byte enables update one 24-bit tag without a wide read-modify-write mux.
    // Read B is independent. A same-row write poisons that read only after
    // the last comparison; no result is consumed from that collided output.
    ngage_bram #(.AW(3),.DW(192),.BYTE_WIDTH(8),.READ_ONLY_B(1)) tag_rows (
        .clk(clk),.addr_a(saved_victim[5:3]),.addr_b(read_row),
        .data_a(tag_write),.data_b(192'b0),.we_a(tag_enable),.we_b(24'b0),.q_a(),.q_b(tags)
    );
    ngage_bram #(.AW(6),.DW(38),.READ_ONLY_B(1)) entries (
        .clk(clk),.addr_a(saved_victim),.addr_b(selected_entry),
        .data_a(saved_payload),.data_b(38'b0),.we_a(finish_fill),.we_b(1'b0),.q_a(),.q_b(result_payload)
    );
    integer i;
    always @(posedge clk)begin
        if(reset)begin
            state<=IDLE;row<=0;valid<=0;preserved<=0;
            base<=0;victim<=0;preserve<=0;queued<=0;
            queued_inv<=0;queued_mva<=0;queued_data<=0;
            response_valid<=0;response_hit<=0;overlap_mask<=0;
            key<=0;saved_payload<=0;saved_victim<=0;saved_preserve<=0;
        end else begin
            response_valid<=0;
            if(scanning_mutation && (invalidate || lock_write))begin
                queued<=1;queued_inv<=invalidate;queued_mva<=invalidate_mva;
                queued_data<=invalidate ? invalidate_address : lock_data;
            end
            if(state==FILL_SCAN && cancel_fill)begin
                state<=IDLE;
            end else if(command)begin
                queued<=0;row<=0;
                if(command_inv)begin
                    if(command_mva)begin state<=INVALIDATE_SCAN;key<=command_data;end
                    else begin valid<=valid & preserved;state<=IDLE;end
                end else if(command_lock)begin
                    base<=command_data[31:26];victim<=command_data[25:20];preserve<=command_data[0];state<=IDLE;
                end else if(start_fill)begin
                    key<=fill_mva;saved_payload<=fill_payload;saved_victim<=victim;saved_preserve<=preserve;
                    overlap_mask<=0;state<=FILL_SCAN;
                end
            end else case(state)
                IDLE:if(lookup)begin key<=lookup_mva;row<=0;state<=SEARCH;end
                SEARCH:begin
                    if(|lane_hits || row==7)begin response_valid<=1;response_hit<=|lane_hits;state<=IDLE;end
                    else row<=row+3'd1;
                end
                FILL_SCAN:begin
                    overlap_mask<=accumulated_overlap;
                    if(row==7)begin
                        valid<=(valid & ~accumulated_overlap) | (64'b1 << saved_victim);
                        preserved[saved_victim]<=saved_preserve;
                        victim<=saved_victim==63 ? base : saved_victim+6'd1;
                        state<=IDLE;
                    end
                    else row<=row+3'd1;
                end
                INVALIDATE_SCAN:begin
                    for(i=0;i<8;i=i+1)if(lane_hits[i])valid[{row,3'b0}+i]<=0;
                    if(row==7)state<=IDLE;else row<=row+3'd1;
                end
                default:state<=IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk)if(!reset)begin
        if(mutate && queued)$fatal(1,"TLB mutation queue overflow: CP15 must wait for busy");
        if(scanning_mutation && fill)$fatal(1,"TLB fill before previous mutation drained");
        if(result_valid && busy)$fatal(1,"TLB result escaped an active mutation");
    end
`endif
endmodule
