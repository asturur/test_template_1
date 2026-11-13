`timescale 1ns/1ps
// Continuous analog samples must match the CE-qualified source for a complete
// pixel period, including both edge columns. No CPU or guest modifications.
module tb;
    parameter integer PIXEL_DIV = 12;
    reg clk = 0, reset = 1, write_valid = 0, dma_valid = 0;
    reg [31:0] write_addr = 0, write_data = 0, dma_data = 0;
    reg [14:0] dma_addr = 0;
    wire raw_ce, raw_hs, raw_vs, raw_hb, raw_vb;
    wire [11:0] raw_rgb, rgb;
    wire [8:0] x, y;
    wire ce, hs, vs, hb, vb;
    wire [23:0] sl_rgb, analog_rgb;
    wire sl_ce, sl_de, sl_hs, sl_vs, analog_de, analog_hs, analog_vs;
    integer i, pattern = 0, samples, pixels, left_samples, right_samples;
    integer source_samples, output_samples, mismatches, ce_mismatches, first_x, first_y;
    integer hdmi_pixels = 0;
    integer first_rgb, first_expected, done = 0;
    reg capture = 0, collecting = 0;
    // One production register, three scanline stages, three analog stages.
    reg [23:0] expected_rgb [0:6];
    reg [8:0] expected_x [0:6], expected_y [0:6];
    reg [6:0] expected_valid = 0, expected_de = 0, expected_ce = 0;
    reg [6:0] expected_hs = 0, expected_vs = 0;
    always #5 clk = ~clk;
    ngage_lcd_display #(.PIXEL_DIV(PIXEL_DIV)) panel (
        .clk(clk), .reset(reset), .diagnostic(1'b0), .status(8'b0),
        .save_state(3'b0), .write_valid(write_valid), .write_addr(write_addr),
        .write_data(write_data), .dma_valid(dma_valid), .dma_frame_full(1'b0),
        .dma_word_addr(dma_addr), .dma_data(dma_data), .ce_pix(raw_ce),
        .hsync(raw_hs), .vsync(raw_vs), .hblank(raw_hb), .vblank(raw_vb),
        .rgb(raw_rgb), .raster_x(x), .raster_y(y)
    );
    // Generated verbatim from ngage_mister.v, not a duplicate implementation.
    production_video_boundary boundary (
        .clk_sys(clk), .raw_ce(raw_ce), .raw_hsync(raw_hs), .raw_vsync(raw_vs),
        .raw_hblank(raw_hb), .raw_vblank(raw_vb), .raw_rgb(raw_rgb),
        .ce_pix(ce), .hsync(hs), .vsync(vs), .hblank(hb), .vblank(vb), .rgb444(rgb)
    );
    // Same continuous-clock blocks as the unscaled RGB CRT route in sys_top.
    // OSD overlay is excluded: its disabled RGB/sync pipeline adds equal delay.
    scanlines #(0) scanline_stage (
        .clk(clk), .scanlines(2'b0),
        .din((!hb && !vb) ? {rgb[11:8],rgb[11:8],rgb[7:4],rgb[7:4],rgb[3:0],rgb[3:0]} : 24'b0),
        .hs_in(hs), .vs_in(vs), .de_in(!hb && !vb), .ce_in(ce),
        .dout(sl_rgb), .hs_out(sl_hs), .vs_out(sl_vs), .de_out(sl_de), .ce_out(sl_ce)
    );
    vga_out analog_stage (
        .clk(clk), .ypbpr_en(1'b0), .hsync(sl_hs), .vsync(sl_vs),
        .csync(1'b0), .de(sl_de), .din(sl_rgb), .dout(analog_rgb),
        .hsync_o(analog_hs), .vsync_o(analog_vs), .csync_o(), .de_o(analog_de)
    );
    function [11:0] pixel;
        input integer xx, yy;
        begin
            if (pattern == 0 && (xx < 2 || xx >= 174)) pixel = 12'hfff;
            else pixel = ((xx + 1) << 4) | (yy & 15);
        end
    endfunction
    function [23:0] expanded;
        input [11:0] value;
        begin expanded = {value[11:8],value[11:8],value[7:4],value[7:4],value[3:0],value[3:0]}; end
    endfunction
    always @(posedge clk) begin
        if (capture && raw_ce && x == 0 && y == 0) begin
            if (collecting) begin capture = 0; collecting = 0; end
            else collecting = 1;
        end
        expected_valid <= {expected_valid[5:0], collecting};
        expected_de <= {expected_de[5:0], !raw_hb && !raw_vb};
        expected_ce <= {expected_ce[5:0], raw_ce};
        expected_hs <= {expected_hs[5:0], raw_hs};
        expected_vs <= {expected_vs[5:0], raw_vs};
        expected_rgb[0] <= (!raw_hb && !raw_vb) ? expanded(pixel(x-72,y-16)) : 24'b0;
        expected_x[0] <= x;
        expected_y[0] <= y;
        for (i = 1; i < 7; i = i + 1) begin
            expected_rgb[i] <= expected_rgb[i-1];
            expected_x[i] <= expected_x[i-1];
            expected_y[i] <= expected_y[i-1];
        end
    end
    // This is the actual shared RGB/CE/DE input consumed by HDMI ascal.
    always @(negedge clk) if (expected_valid[3] && sl_ce && sl_de) begin
        if (sl_rgb !== expected_rgb[3])
            $fatal(1,"HDMI source column order x=%0d y=%0d got=%06x expected=%06x",
                expected_x[3],expected_y[3],sl_rgb,expected_rgb[3]);
        hdmi_pixels = hdmi_pixels + 1;
    end
    always @(negedge clk) if (expected_valid[6]) begin
        output_samples = output_samples + 1;
        if ({analog_de,analog_hs,analog_vs} !== {expected_de[6],expected_hs[6],expected_vs[6]})
            $fatal(1,"analog control/coordinate pipeline mismatch");
        if (analog_rgb !== expected_rgb[6]) begin
            if (!mismatches) begin
                first_x = expected_x[6]; first_y = expected_y[6];
                first_rgb = analog_rgb; first_expected = expected_rgb[6];
            end
            mismatches = mismatches + 1;
            if (expected_ce[6]) ce_mismatches = ce_mismatches + 1;
        end
        if (analog_de) begin
            samples = samples + 1;
            if (expected_ce[6]) pixels = pixels + 1;
            if (expected_x[6] < 74) left_samples = left_samples + 1;
            if (expected_x[6] >= 246) right_samples = right_samples + 1;
        end
    end
    task wr;
        input [31:0] address, data;
        begin @(negedge clk); write_addr = address; write_data = data; write_valid = 1;
              @(negedge clk); write_valid = 0; end
    endtask
    initial begin
        samples = 0; pixels = 0; left_samples = 0; right_samples = 0;
        output_samples = 0; mismatches = 0; ce_mismatches = 0;
        repeat (3) @(negedge clk); reset = 0;
        wr(32'h0c121200,32'h09200000); wr(32'h0c121208,32'haf);
        for (pattern = 0; pattern < 2; pattern = pattern + 1) begin
            for (source_samples = 0; source_samples < 18304; source_samples = source_samples + 1) begin
                @(negedge clk); dma_valid = 1; dma_addr = source_samples;
                // Native little-endian halfword stores: pixel x at the low address.
                dma_data = {4'b0,pixel((source_samples%88)*2+1,source_samples/88),
                            4'b0,pixel((source_samples%88)*2,source_samples/88)};
            end
            @(negedge clk); dma_valid = 0; capture = 1;
            wait (collecting); wait (!collecting); repeat (9) @(negedge clk);
            if (mismatches) $fatal(1,"CRT RGB hold div=%0d pattern=%0d: %0d bad clocks, CE errors=%0d; first raster=%0d,%0d got=%06x expected=%06x",
                PIXEL_DIV,pattern,mismatches,ce_mismatches,first_x,first_y,first_rgb,first_expected);
            if (hdmi_pixels != 176*208 || samples != 176*208*PIXEL_DIV || pixels != 176*208 ||
                left_samples != 2*208*PIXEL_DIV || right_samples != left_samples ||
                output_samples != 400*262*PIXEL_DIV)
                $fatal(1,"missing pixels or edge columns");
            $display("PASS continuous CRT and HDMI source div=%0d pattern=%0d: %0d clocks, %0d pixels, left/right %0d/%0d clocks",
                PIXEL_DIV,pattern,output_samples,pixels,left_samples,right_samples);
            samples = 0; pixels = 0; left_samples = 0; right_samples = 0;
            hdmi_pixels = 0; output_samples = 0;
        end
        $finish;
    end
    initial begin #180000000; $fatal(1,"CRT test timeout"); end
endmodule
