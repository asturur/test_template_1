`timescale 1ps / 1ps

// The physical PLL HDL is fitted by Quartus. Simulation supplies its output
// period and a delayed lock indication, with no assertion about pin phase.
module pll (
    input  wire refclk,
    input  wire rst,
    output wire outclk_0,
    output wire outclk_1,
    output reg  locked = 0
);
    assign outclk_0 = refclk;
    assign outclk_1 = 0;
    initial #35000 locked = 1;
endmodule

module cpu_isolation_smoke;
    reg clk = 0;
    reg [3:0] switches = 1;
    wire running, progress;
    always #4808 clk = ~clk;
    ngage_cpu_isolation dut (
        .FPGA_CLK2_50(clk),
        .SW          (switches),
        .LED_USER    (progress),
        .LED_POWER   (running)
    );

    integer reads, writes, lock_reads, lock_writes, table_reads;
    integer line_count, rejections, narrow_beats, wide_beats;
    always @(posedge clk) begin
        if (!running) begin
            reads = 0;
            writes = 0;
            lock_reads = 0;
            lock_writes = 0;
            table_reads = 0;
            line_count = 0;
            rejections = 0;
            narrow_beats = 0;
            wide_beats = 0;
        end else begin
            if (dut.emu.wb_ack && dut.emu.wb_cyc) begin
                if (dut.emu.wb_address[31:14] == 18'h02801 && !dut.emu.wb_write)
                    table_reads = table_reads + 1;
                if (dut.emu.wb_address[31:2] == 30'h02800040) begin
                    if (dut.emu.wb_write) writes = writes + 1;
                    else reads = reads + 1;
                    if (dut.emu.wb_lock && dut.emu.wb_write) lock_writes = lock_writes + 1;
                    if (dut.emu.wb_lock && !dut.emu.wb_write) lock_reads = lock_reads + 1;
                end
            end
            if (dut.emu.line_valid && dut.emu.line_last) line_count = line_count + 1;
            if (dut.emu.line_reject) rejections = rejections + 1;
            if (dut.emu.line_valid && dut.emu.line_wide) wide_beats = wide_beats + 1;
            if (dut.emu.line_valid && !dut.emu.line_wide) narrow_beats = narrow_beats + 1;
        end
    end

    task replay;
        input [3:0] mode;
        begin
            switches = mode | 1;
            repeat (12) @(negedge clk);
            if (running) $fatal(1, "CPU peer did not reset");
            switches = mode;
            repeat (3000) @(negedge clk);
            if (!running || reads < 10 || writes < 10 || lock_reads < 5 ||
                lock_writes != lock_reads || table_reads == 0)
                $fatal(1, "CPU peer did not execute the MMU/SWP workload");
            if (mode[2] ? (line_count != 0 || rejections == 0) :
                (line_count == 0 || rejections != 0))
                $fatal(1, "CPU peer did not exercise line accept/reject");
            if (!mode[2] && (mode[3] ? (narrow_beats != 16 * line_count || wide_beats != 0) :
                (wide_beats != 4 * line_count || narrow_beats != 0)))
                $fatal(1, "CPU peer line width/beat count changed");
            $display("PASS CPU fixture mode=%x RAM R/W=%0d/%0d SWP=%0d table_reads=%0d line=%0d reject=%0d",
                     mode, reads, writes, lock_reads, table_reads, line_count, rejections);
        end
    endtask

    initial begin
        replay(0);
        replay(8);
        replay(4);
        $finish;
    end
endmodule
