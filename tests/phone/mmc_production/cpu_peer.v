`timescale 1ns / 1ps
// Authored bus master; no instruction execution or original-driver claim.
module ngage_cpu #(
    parameter LINE_REFILL = 0
) (

    output wire        line_req,
    output wire [31:0] line_addr,
    input  wire        line_ready,
    input  wire        line_reject,
    input  wire        line_valid,
    input  wire [63:0] line_data,
    input  wire        line_wide,
    input  wire        line_last,
    input  wire        line_error,

    input  wire        clk,
    input  wire        reset,
    input  wire        irq,
    input  wire        fiq,
    output reg         wb_cyc,
    output reg         wb_lock,
    output wire        wb_code,
    output reg         wb_stb,
    output reg  [31:0] wb_address,
    output reg         wb_write,
    output reg  [31:0] wb_write_data,
    output reg  [ 3:0] wb_byte_enable,
    output reg  [ 2:0] wb_cycle_type,
    output reg  [ 1:0] wb_burst_type,
    input  wire        wb_ack,
    input  wire        wb_error,
    input  wire [31:0] wb_read_data,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_cpsr,
    output wire [31:0] debug_instruction,
    output wire        debug_fetch
);
    assign line_req          = 0;
    assign line_addr         = 0;
    assign wb_code           = 0;
    assign debug_pc          = 0;
    assign debug_cpsr        = 0;
    assign debug_instruction = 0;
    assign debug_fetch       = 0;
    initial begin
        wb_cyc         = 0;
        wb_stb         = 0;
        wb_lock        = 0;
        wb_address     = 0;
        wb_write       = 0;
        wb_write_data  = 0;
        wb_byte_enable = 0;
        wb_cycle_type  = 0;
        wb_burst_type  = 0;
    end
    task transfer;
        input write_access;
        input [31:0] address, data;
        input [3:0] lanes;
        output [31:0] response;
        integer count;
        begin
            @(negedge clk);
            wb_cyc         = 1;
            wb_stb         = 1;
            wb_write       = write_access;
            wb_address     = address;
            wb_write_data  = data;
            wb_byte_enable = lanes;
            count          = 0;
            #1;
            while (!wb_ack && !wb_error) begin
                @(negedge clk);
                #1;
                count = count + 1;
                if (count > 200000) $fatal(1, "Wishbone timeout %h", address);
            end
            if (wb_error) $fatal(1, "Wishbone error %h", address);
            response = wb_read_data;
            @(negedge clk);
            wb_cyc = 0;
            wb_stb = 0;
            repeat (2) @(negedge clk);
        end
    endtask
endmodule
