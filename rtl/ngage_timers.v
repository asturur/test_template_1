// Tick-level port of the staged board's timer hypotheses. UNIT60_DELAY is an
// observed-model constant, not a claim about the physical timer prescaler.
module ngage_timers #(
    parameter integer        CLOCK_DIV    = 1,
    parameter         [31:0] BOOT_DELAY   = 32'd18200000,
                             UNIT60_DELAY = 32'd128
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire        clear_unit1,
    output reg         claim,
    output reg         bad,
    output reg  [31:0] dout,
    output reg         timer0_pending,
    output reg         unit1_pending,
    output reg         unit60_pending,
    output wire        timer0_rearm,
    output wire        periodic_active,
    input  wire        sysc74_seen
);
    wire [31:0] a = {addr[31:2], 2'b00};
    wire timer0=(a==32'h0c120a04 || a==32'h0c120a08 || a==32'h0c120a10 || a==32'h0c120a18);
    wire units = (a >= 32'h0c120a20 && a < 32'h0c120ac0);
    reg [31:0] unit_regs[0:39];
    reg [31:0] control0, compare0, reload0, status0;
    reg [31:0] boot_left, period, period_left, unit1_elapsed, unit1_compare, unit60_left;
    reg unit1_running, boot_started, timer_fired, status_written, compare_written;
    integer index, slot, i;
    // 78/104 MHz CPU clocks use /3 or /4 for the 26 MHz timer domain.
    // Registers and acknowledgements remain accessible on every CPU clock.
    reg  [1:0] divider = 0;
    wire       timer_ce = divider == CLOCK_DIV - 1;
    always @(posedge clk) begin
        if (reset || timer_ce) divider <= 0;
        else divider <= divider + 1'b1;
    end
    wire boot_arm=commit && claim && !bad && we && a==32'h0c120a18 &&
               boot_started && din==32'h0115b5c0;
    wire unit60_write = commit && claim && !bad && we && a >= 32'h0c120a60 && a < 32'h0c120a80;
    wire unit1_control_write = commit && claim && !bad && we && a == 32'h0c120a24;
    wire unit1_compare_write = commit && claim && !bad && we && a == 32'h0c120a30;
    wire unit1_reconfigure = unit1_control_write || unit1_compare_write;
    wire unit1_active_next = unit1_control_write ? (din != 0) : unit1_running;
    wire [31:0] unit1_compare_next = unit1_compare_write ? din : unit1_compare;
    wire unit60_stop = unit60_write && a[4:0] == 4 && din != 2;
    wire unit60_reload=unit60_write && ((a[4:0]==4 && din==2) ||
                      (a[4:0]==8 && unit_regs[(32'h0c120a64-32'h0c120a20)>>2]==2));
    assign periodic_active = (period != 0);
    assign timer0_rearm=commit && claim && !bad && we && a==32'h0c120a18 &&
                      din==32'h000632ea && control0==2;
    always @* begin
        claim = req && (timer0 || units);
        bad   = claim && sel != 15;
        dout  = 0;
        index = 0;
        slot  = 0;
        if (claim && timer0 && !bad) begin
            if (we)
                case (a)
                    32'h0c120a04: if (din != 2 && !(timer_fired && din == 0)) bad = 1;
                    32'h0c120a08: if (din != 0 && !(timer0_pending && din == 1)) bad = 1;
                    32'h0c120a10:
                    if(din!=32'h0115b5c0 && !(timer_fired && din==0) &&
                        !(timer_fired && sysc74_seen && din==32'h000632ea))
                        bad = 1;
                    32'h0c120a18:
                    if(din!=32'h0115b5c0 && !(timer_fired && din==0) &&
                        !(timer_fired && control0==2 && din==32'h000632ea))
                        bad = 1;
                endcase
            else
                case (a)
                    32'h0c120a04: if (!timer_fired || control0 != 2) bad = 1;
                    32'h0c120a08: if (!timer_fired || !status_written) bad = 1;
                    32'h0c120a10: if (!timer_fired || !compare_written) bad = 1;
                    32'h0c120a18: bad = 1;
                endcase
        end
        if (timer0)
            case (a)
                32'h0c120a04: dout = control0;
                32'h0c120a08: dout = status0;
                32'h0c120a10: dout = compare0;
                32'h0c120a18: dout = reload0;
            endcase
        else if (units) begin
            index = (a - 32'h0c120a20) >> 2;
            slot  = a[4:0];
            if (slot == 8 && a[7:5] == 1) dout = unit1_pending ? 1 : 0;
            else if (slot == 8 && a[7:5] == 3) dout = unit60_pending ? 1 : 0;
            else if (slot == 8) dout = 0;
            else dout = unit_regs[index];
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            timer0_pending  <= 0;
            unit1_pending   <= 0;
            unit60_pending  <= 0;
            timer_fired     <= 0;
            status_written  <= 0;
            compare_written <= 0;
            control0        <= 0;
            compare0        <= 0;
            reload0         <= 0;
            status0         <= 0;
            boot_left       <= 0;
            period          <= 0;
            period_left     <= 0;
            unit1_elapsed   <= 0;
            unit1_compare   <= 0;
            unit60_left     <= 0;
            unit1_running   <= 0;
            boot_started    <= 0;
            for (i = 0; i < 40; i = i + 1) unit_regs[i] <= 0;
        end else begin
            if (timer_ce && boot_left != 0) boot_left <= boot_left - 1'b1;
            if (timer_ce && period_left != 0) begin
                period_left <= period_left - 1'b1;
                if (period_left == 1) begin
                    timer0_pending <= 1;
                    status0        <= 1;
                    period_left    <= period;
                end
            end
            if (timer_ce && unit60_left != 0) unit60_left <= unit60_left - 1'b1;
            if (timer_ce && unit1_running) begin
                if (unit1_elapsed + 1 >= unit1_compare) begin
                    unit1_running <= 0;
                    unit1_elapsed <= 0;
                    unit1_pending <= 1;
                end else unit1_elapsed <= unit1_elapsed + 1'b1;
            end
            if (clear_unit1) unit1_pending <= 0;
            if (commit && claim && !bad && we) begin
                if (timer0)
                    case (a)
                        32'h0c120a04: begin
                            control0 <= din;
                            if (din == 2) boot_started <= 1;
                        end
                        32'h0c120a08: begin
                            status0        <= din;
                            timer0_pending <= 0;
                            status_written <= 1;
                        end
                        32'h0c120a10: begin
                            compare0        <= din;
                            compare_written <= 1;
                        end
                        32'h0c120a18: begin
                            reload0 <= din;
                            if (boot_arm) boot_left <= BOOT_DELAY > 0 ? BOOT_DELAY - timer_ce : 0;
                            if (din == 32'h000632ea && control0 == 2) begin
                                period      <= din;
                                period_left <= din - timer_ce;
                            end
                        end
                    endcase
                else if (units) begin
                    unit_regs[index] <= din;
                    if (a >= 32'h0c120a60 && a < 32'h0c120a80) begin
                        unit60_pending <= 0;
                        if (slot == 4)
                            unit60_left<=din==2?(UNIT60_DELAY>0?UNIT60_DELAY-timer_ce:0):0;
                        else if (slot == 8 && unit_regs[(32'h0c120a64-32'h0c120a20)>>2] == 2)
                            unit60_left <= UNIT60_DELAY > 0 ? UNIT60_DELAY - timer_ce : 0;
                    end
                    if (a >= 32'h0c120a20 && a < 32'h0c120a40) begin
                        if (slot == 4) begin
                            unit1_running <= din != 0;
                            unit1_elapsed <= 0;
                        end
                        if (slot == 16) begin
                            unit1_compare <= din;
                            unit1_elapsed <= 0;
                        end
                    end
                end
            end
            // C++ applies a CPU request before ticking the board. A newly armed
            // one-shot consumes its first count on that same edge, and an expiry
            // on an acknowledgement edge reasserts the interrupt.
            if(timer_ce && ((boot_arm && BOOT_DELAY==1) || (!boot_arm && boot_left==1) ||
      (period_left==1 && !timer0_rearm)))
                timer_fired <= 1;
            if (timer_ce && boot_arm && BOOT_DELAY == 1) timer0_pending <= 1;
            else if (timer_ce && !boot_arm && boot_left == 1) timer0_pending <= 1;
            if (timer_ce && period_left == 1 && !timer0_rearm) begin
                timer0_pending <= 1;
                status0        <= 1;
            end
            if (timer_ce && unit60_reload && UNIT60_DELAY == 1) unit60_pending <= 1;
            else if (timer_ce && !unit60_reload && !unit60_stop && unit60_left == 1)
                unit60_pending <= 1;
            if (unit1_reconfigure && unit1_active_next) begin
                if (timer_ce && unit1_compare_next <= 1) begin
                    unit1_running <= 0;
                    unit1_elapsed <= 0;
                    unit1_pending <= 1;
                end else unit1_elapsed <= timer_ce ? 1 : 0;
            end else if (timer_ce && !unit1_reconfigure && unit1_running && unit1_elapsed + 1 >= unit1_compare)
                unit1_pending <= 1;
        end
    end
endmodule
