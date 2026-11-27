// SPDX-License-Identifier: GPL-3.0-or-later
// Held UPP requests and cold zeroing share the phone's DDR client.
module ngage_upp_ddr_port #(
    parameter [31:0] BASE = 32'h31820000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        upp_req,
    input  wire        upp_we,
    input  wire [16:2] upp_addr,
    input  wire [31:0] upp_wdata,
    input  wire [ 3:0] upp_be,
    output wire        upp_ack,
    output wire [31:0] upp_rdata,
    input  wire        clear,
    output reg         clear_done = 0,

    output wire        req_valid,
    input  wire        req_ready,
    output wire        req_bulk,
    output wire        req_write,
    output wire [31:0] req_addr,
    output wire [31:0] req_data,
    output wire [ 3:0] req_be,
    input  wire        rsp_valid,
    input  wire [31:0] rsp_data
);
    reg waiting = 0, owner_clear = 0, wait_request_drop = 0;
    reg [7:0] clear_block = 0;

    assign req_valid = !reset && !waiting && (clear ? !clear_done : upp_req && !wait_request_drop);
    assign req_bulk  = clear;
    assign req_write = clear || upp_we;
    assign req_addr  = {BASE[31:17], clear ? {clear_block, 9'b0} : {upp_addr, 2'b0}};
    assign req_data  = upp_wdata;
    assign req_be    = upp_be;
    assign upp_ack   = !reset && waiting && !owner_clear && rsp_valid;
    assign upp_rdata = rsp_data;

    always @(posedge clk) begin
        if (reset) begin
            waiting           <= 0;
            wait_request_drop <= 0;
            clear_block       <= 0;
            clear_done        <= 0;
        end else begin
            if (!upp_req) wait_request_drop <= 0;
            if (!clear) begin
                clear_block <= 0;
                clear_done  <= 0;
            end
            if (req_valid && req_ready) begin
                waiting     <= 1;
                owner_clear <= clear;
            end
            if (waiting && rsp_valid) begin
                waiting <= 0;
                if (owner_clear) begin
                    if (&clear_block) clear_done <= 1;
                    else clear_block <= clear_block + 1'b1;
                end else wait_request_drop <= 1;
            end
        end
    end
endmodule
