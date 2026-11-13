`timescale 1ns/1ps
// Protocol/state comparison, including malformed geometry and headers.
// Historical reference emits high-halfword-first RGB; the intentional scanout
// correction is checked independently against native little-endian pixels.
module equivalence_tb;
    reg clk = 0, reset = 1, diagnostic = 0, write_valid = 0;
    reg [7:0] status = 0;
    reg [2:0] save_state = 0;
    reg [31:0] write_addr = 0, write_data = 0;
    reg dma_valid = 0, dma_frame_full = 0;
    reg [14:0] dma_word_addr = 0;
    reg [31:0] dma_data = 0;
    integer checks = 0, first_row, last_row, count;
    always #5 clk = ~clk;
    wire  c_pixel_commit, r_pixel_commit;
    wire  c_pixel_mode, r_pixel_mode;
    wire  c_ce_pix, r_ce_pix;
    wire  c_hsync, r_hsync;
    wire  c_vsync, r_vsync;
    wire  c_hblank, r_hblank;
    wire  c_vblank, r_vblank;
    wire [11:0] c_rgb, r_rgb;
    wire  c_frame_complete, r_frame_complete;
    wire  c_incomplete, r_incomplete;
    wire  c_unsupported, r_unsupported;
    wire  c_unsupported_valid, r_unsupported_valid;
    wire [31:0] c_unsupported_data, r_unsupported_data;
    wire [31:0] c_unsupported_header, r_unsupported_header;
    wire [ 7:0] c_unsupported_command, r_unsupported_command;
    wire [ 8:0] c_raster_x, r_raster_x;
    wire [ 8:0] c_raster_y, r_raster_y;
    ngage_lcd_display #(.PIXEL_DIV(1)) candidate (
        .clk(clk),
        .reset(reset),
        .diagnostic(diagnostic),
        .status(status),
        .save_state(save_state),
        .write_valid(write_valid),
        .write_addr(write_addr),
        .write_data(write_data),
        .dma_valid(dma_valid),
        .dma_frame_full(dma_frame_full),
        .dma_word_addr(dma_word_addr),
        .dma_data(dma_data),
        .pixel_commit(c_pixel_commit),
        .pixel_mode(c_pixel_mode),
        .ce_pix(c_ce_pix),
        .hsync(c_hsync),
        .vsync(c_vsync),
        .hblank(c_hblank),
        .vblank(c_vblank),
        .rgb(c_rgb),
        .frame_complete(c_frame_complete),
        .incomplete(c_incomplete),
        .unsupported(c_unsupported),
        .unsupported_valid(c_unsupported_valid),
        .unsupported_data(c_unsupported_data),
        .unsupported_header(c_unsupported_header),
        .unsupported_command(c_unsupported_command),
        .raster_x(c_raster_x),
        .raster_y(c_raster_y)
    );
    ngage_lcd_display_reference #(.PIXEL_DIV(1)) reference (
        .clk(clk),
        .reset(reset),
        .diagnostic(diagnostic),
        .status(status),
        .save_state(save_state),
        .write_valid(write_valid),
        .write_addr(write_addr),
        .write_data(write_data),
        .dma_valid(dma_valid),
        .dma_frame_full(dma_frame_full),
        .dma_word_addr(dma_word_addr),
        .dma_data(dma_data),
        .pixel_commit(r_pixel_commit),
        .pixel_mode(r_pixel_mode),
        .ce_pix(r_ce_pix),
        .hsync(r_hsync),
        .vsync(r_vsync),
        .hblank(r_hblank),
        .vblank(r_vblank),
        .rgb(r_rgb),
        .frame_complete(r_frame_complete),
        .incomplete(r_incomplete),
        .unsupported(r_unsupported),
        .unsupported_valid(r_unsupported_valid),
        .unsupported_data(r_unsupported_data),
        .unsupported_header(r_unsupported_header),
        .unsupported_command(r_unsupported_command),
        .raster_x(r_raster_x),
        .raster_y(r_raster_y)
    );
    always @(negedge clk) begin
        checks = checks + 1;
        if ({c_pixel_commit, c_pixel_mode, c_ce_pix, c_hsync, c_vsync, c_hblank, c_vblank, c_frame_complete, c_incomplete, c_unsupported, c_unsupported_valid, c_unsupported_data, c_unsupported_header, c_unsupported_command, c_raster_x, c_raster_y} !==
            {r_pixel_commit, r_pixel_mode, r_ce_pix, r_hsync, r_vsync, r_hblank, r_vblank, r_frame_complete, r_incomplete, r_unsupported, r_unsupported_valid, r_unsupported_data, r_unsupported_header, r_unsupported_command, r_raster_x, r_raster_y})
            $fatal(1, "LCD cycle mismatch check=%0d rows=%0d..%0d addr=%h data=%h", checks, first_row, last_row, write_addr, write_data);
    end
    task write_word;
        input [31:0] address, value;
        begin
            @(negedge clk); write_valid = 1; write_addr = address; write_data = value;
            @(negedge clk); write_valid = 0;
        end
    endtask
    task header;
        input [31:0] value;
        begin write_word(32'h0c121200, value); end
    endtask
    task data;
        input [31:0] value;
        begin write_word(32'h0c121208, value); end
    endtask
    initial begin
        repeat (3) @(negedge clk); reset = 0;
        for (first_row = 0; first_row <= 208; first_row = first_row + 1) begin
            for (last_row = 0; last_row <= 208; last_row = last_row + 1) begin
                header(32'h09200000); data(32'h75);
                header(32'h09240003); data((last_row << 20) | first_row); data(0);
                header(32'h09200000); data(32'h5c);
                count = ((last_row - first_row) * 264 - 1) & 65535;
                header(32'h89240000 | count); data(32'h0abc0123);
                header(32'h89240000 | ((count + 1) & 65535)); data(32'h04560789);
                header(32'h8924d67f); data(32'h0fed0cba);
            end
        end
        @(negedge clk); reset = 1;
        repeat (3) @(negedge clk); reset = 0;
        repeat (10) @(negedge clk);
        $display("PASS LCD cycle equivalence: all 43681 row pairs, correct/wrong/legacy headers, %0d checks", checks);
        $finish;
    end
endmodule
