// Staged diagnostic UEM/CBUS model. RTC alarm, ADC and power values below
// are software-model hypotheses, not verified Nokia silicon behavior.
module ngage_cbus_uem #(
    parameter integer SECOND_TICKS     = 104000000,
                      ALARM_TICKS      = 7995392,
                      ALARM_INTERVAL   = 65536,
                      POWER_KEY_ENABLE = 0,
                      POWERUP_STATUS   = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    input  wire        kernel_periodic,
    input  wire        clear_irq,
    output reg         claim,
    output reg         bad,
    output reg  [31:0] dout,
    output reg         irq_pending,
    output wire [15:0] route2a,
    output wire [15:0] route2c,
    output wire [15:0] route3b,
    output wire        cbus8d_written,
    input  wire        power_pressed,
    output wire        adsp_controls_written,
    output wire [ 4:0] adsp_controls,
    input  tri0 [32:0] host_timestamp
);
    wire [31:0] a = {addr[31:2], 2'b00};
    reg [15:0] cfg, command, rtc_status;
    reg [  1:0] stage;
    reg [255:0] written;
    reg [  3:0] adc_channel;
    reg adc_selected, key_released, alarm_started;
    localparam integer SECOND_BITS   = SECOND_TICKS > 1 ? $clog2(SECOND_TICKS) : 1;
    localparam integer ALARM_COUNT   = (ALARM_TICKS + ALARM_INTERVAL - 1) / ALARM_INTERVAL;
    localparam integer ALARM_BITS    = ALARM_COUNT > 0 ? $clog2(ALARM_COUNT + 1) : 1;
    localparam integer INTERVAL_BITS = ALARM_INTERVAL > 1 ? $clog2(ALARM_INTERVAL) : 1;
    reg  [  SECOND_BITS-1:0] sec_count;
    reg  [   ALARM_BITS-1:0] alarm_left;
    reg  [INTERVAL_BITS-1:0] alarm_div;
    wire [             15:0] value = sel == 12 ? din[31:16] : din[15:0];
    wire [              7:0] regno = command[7:0];
    wire [             15:0] stored_value;
    reg [15:0] route_2a, route_2c, route_3b;
    reg [4:0] d550_controls;
    assign adsp_controls_written = written[8'h2f] && written[8'h30];
    assign adsp_controls         = d550_controls;
    reg         payload_forward;
    reg  [15:0] payload_value;
    wire        payload_write = !reset && commit && claim && !bad && we && a == 32'h0c150424;
    wire        command_write = commit && claim && !bad && we && a == 32'h0c150420 && sel == 12;
    // Battery-backed domain: the running clock is independent of phone reset.
    wire        rtc_valid;
    wire [5:0] rtc_second, rtc_minute;
    wire [4:0] rtc_hour;
    wire [7:0] rtc_day;
    wire       rtc_day_write = payload_write && cfg == 7 && regno == 8'h21;
    ngage_uem_clock #(
        .CLK_HZ(SECOND_TICKS)
    ) clock_backend (
        .clk           (clk),
        .host_timestamp(host_timestamp),
        .day_write     (rtc_day_write),
        .day_data      (value[7:0]),
        .valid         (rtc_valid),
        .second        (rtc_second),
        .minute        (rtc_minute),
        .hour          (rtc_hour),
        .day           (rtc_day)
    );
    ngage_bram #(
        .AW         (8),
        .DW         (16),
        .READ_ONLY_B(1)
    ) values_ram (
        .clk   (clk),
        .addr_a(regno),
        .addr_b(command_write ? value[7:0] : regno),
        .data_a(value),
        .data_b(16'b0),
        .we_a  (payload_write),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (stored_value)
    );
    always @(posedge clk) begin
        payload_forward <= payload_write;
        if (payload_write) payload_value <= value;
    end
    assign cbus8d_written = written[8'h8d];
    assign route2a        = written[8'h2a] ? route_2a : 16'b0;
    assign route2c        = written[8'h2c] ? route_2c : 16'b0;
    assign route3b        = written[8'h3b] ? route_3b : 16'b0;
    function automatic is_input(input [7:0] r);
        begin
            is_input = (r >= 8'h20 && r <= 8'h34) || (r >= 8'h3b && r <= 8'h3e) ||
                (r >= 8'h40 && r <= 8'h7f) || r == 8'h81 || (r >= 8'h83 && r <= 8'h8c) ||
                (r >= 8'h8e && r <= 8'h9f);
        end
    endfunction
    function automatic is_known(input [7:0] r);
        begin
            case (r)
                0, 8'h2a, 8'h29, 8'h2b, 8'h2c, 8'h2d, 8'h2e, 8'h2f, 8'h30, 8'h31, 8'h32, 8'h33,
                    8'h37, 8'h38, 8'h39, 8'h3a, 8'h3b, 8'h26, 8'h36, 8'h35:
                is_known = 1;
                default: is_known = 0;
            endcase
        end
    endfunction
    reg recognized, extra;
    reg [15:0] read_value;
    always @* begin
        claim      = req && (a == 32'h0c150420 || a == 32'h0c150424);
        bad        = 0;
        dout       = 0;
        recognized = 0;
        extra      = 0;
        read_value = 0;
        if (claim) begin
            if ((sel != 3 && sel != 12) || (a == 32'h0c150424 && sel != 12)) bad = 1;
            else if (we && a == 32'h0c150420 && sel == 3) begin
                if (value != 16'h10 && value != 8 && value != 7 && value != 15 && value != 16'h8f &&
                    value != 1)
                    bad = 1;
            end else if (we && a == 32'h0c150420) begin
                extra = (value == 16'h27 || value == 16'h82 ||
                         (written[8'h82] && (value == 16'h182 || value == 16'h180 ||
                                             value == 16'h18d || value == 16'h8d)) ||
                         (value[8] && is_input(value[7:0]) && (value & 16'hfe00) == 0));
                recognized = (value == 16'h13f) || is_known(value[7:0]) || extra;
                if (!kernel_periodic && (stage != 1 || (((value & 16'hfec0) != 0) &&
                                                        value != 16'h239 && !extra) || !recognized))
                    bad = 1;
            end else if (we && a == 32'h0c150424) begin
                if (stage != 2 || command[8]) bad = 1;
            end else if (!we && a == 32'h0c150420 && sel == 12) begin
                // The native CBUS client polls before its first transfer and
                // while a command is assembling. Status reads are always
                // legal; reset-idle and completed transfers report done.
                dout = {
                    (command & ~16'h0400) | ((stage == 0 || stage == 3) ? 16'h0400 : 16'b0), 16'b0
                };
            end else if (!we && a == 32'h0c150424 && stage == 3 && command[8]) begin
                if (regno == 8'h3a) begin
                    if (adc_selected && adc_channel > 13) bad = 1;
                    else read_value = 512;
                end  // Staged reset cause: bit 1 denotes power-key startup, cleared after release.
                else if (regno == 8'h3f)
                    read_value = POWERUP_STATUS & (key_released ? 16'hfffd : 16'hffff);
                else if (regno == 8'h35)
                    read_value = ((key_released && !((POWER_KEY_ENABLE != 0) && power_pressed)) ?
                                  16'h0000 : 16'h0010) | rtc_status;
                else if (regno == 8'h36 && !written[regno]) read_value = 0;
                // Read aliases are counters, not the watchdog/vibrator payload
                // stored by writes to these same CBUS addresses.
                else if (cfg == 7 && regno == 8'h31) read_value = {10'b0, rtc_second};
                else if (cfg == 7 && regno == 8'h32) read_value = {10'b0, rtc_minute};
                else if (cfg == 7 && regno == 8'h33) read_value = {11'b0, rtc_hour};
                else if (cfg == 7 && regno == 8'h21 && rtc_valid) read_value = {8'b0, rtc_day};
                // Original ecust treats zero calibration as an unset RTC.
                // Preserve explicit guest calibration writes. One is a neutral
                // nonzero model default; physical calibration is unmeasured.
                else if (regno == 8'h24 && !written[regno]) read_value = {15'b0, rtc_valid};
                else if (is_input(regno) && !written[regno]) read_value = 0;
                else if (regno == 8'h80) read_value = 16'h0400;
                else if (regno == 8'h8d && !written[regno]) read_value = 0;
                else if (written[regno])
                    read_value = payload_forward ? payload_value : stored_value;
                else bad = 1;
                dout = {read_value, 16'b0};
            end else bad = 1;
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            cfg           <= 0;
            d550_controls <= 0;
            command       <= 0;
            stage         <= 0;
            written       <= 0;
            rtc_status    <= 8;
            adc_channel   <= 0;
            adc_selected  <= 0;
            key_released  <= 0;
            alarm_started <= 0;
            sec_count     <= 0;
            alarm_left    <= 0;
            alarm_div     <= 0;
            irq_pending   <= 0;
        end else begin
            if (clear_irq) irq_pending <= 0;
            // The staged model's 1 Hz and alarm checks are aligned to the
            // global board-cycle counter, even before kernel periodic arming.
            if (sec_count == SECOND_TICKS - 1) begin
                sec_count   <= 0;
                irq_pending <= 1;
            end else sec_count <= sec_count + 1;
            if (alarm_div == ALARM_INTERVAL - 1) begin
                alarm_div <= 0;
                if (alarm_left > 0) begin
                    alarm_left <= alarm_left - 1;
                    if (alarm_left == 1) begin
                        rtc_status[3] <= 1;
                        irq_pending   <= 1;
                    end
                end
            end else alarm_div <= alarm_div + 1;
            if (commit && claim && !bad && we) begin
                if (a == 32'h0c150420 && sel == 3) begin
                    cfg   <= value;
                    stage <= 1;
                end else if (a == 32'h0c150420) begin
                    command <= value;
                    stage   <= value[8] ? 3 : 2;
                end else begin
                    if (regno == 8'h2f) d550_controls[4:1] <= value[7:4];
                    if (regno == 8'h30) d550_controls[0] <= value[5];
                    if (regno == 8'h2a) route_2a <= value;
                    if (regno == 8'h2c) route_2c <= value;
                    if (regno == 8'h3b) route_3b <= value;
                    written[regno] <= 1;
                    stage          <= 3;
                    if (regno == 8'h35) rtc_status <= rtc_status & ~value;
                    if (regno == 8'h36 && cfg == 15 && (value & 16'hfff0) == 16'hfff0 &&
                        !value[3]) begin
                        key_released <= 1;
                        if (!alarm_started) begin
                            alarm_left    <= ALARM_COUNT;
                            alarm_started <= 1;
                        end
                    end
                    if (regno == 8'h30 && kernel_periodic) irq_pending <= 1;
                    if (regno == 8'h39) begin
                        adc_selected <= value[11];
                        adc_channel  <= value[15:12];
                    end
                end
            end
        end
    end
endmodule

// MiSTer Unix-time adapter for D190's battery-backed RTC counters. No CPU
// reset input: HPS sends time once at core load, possibly before CPU release.
// Native firmware keeps the calendar base in PMM and resets its 8-bit day
// counter. A new FPGA configuration starts day zero; warm resets retain it.
// This does not invent a native full-calendar register or alter PMM bytes.
module ngage_uem_clock #(
    parameter integer CLK_HZ = 104000000
) (
    input  wire        clk,
    input  wire [32:0] host_timestamp,
    input  wire        day_write,
    input  wire [ 7:0] day_data,
    output reg         valid = 0,
    output reg  [ 5:0] second = 0,
    output reg  [ 5:0] minute = 0,
    output reg  [ 4:0] hour = 0,
    output reg  [ 7:0] day = 0
);
    localparam integer          PW          = CLK_HZ > 1 ? $clog2(CLK_HZ) : 1;
    localparam         [   1:0] IDLE        = 0, DIVIDE = 1, HOURS = 2, MINUTES = 3;
    localparam         [PW-1:0] LAST_SECOND = CLK_HZ - 1;
    reg [PW-1:0] prescale = 0;
    reg          toggle = 0;
    reg [   1:0] state = IDLE;
    reg [  31:0] work = 0;
    reg [  16:0] remainder = 0;
    reg [7:0] host_days = 0, running_days = 0;
    reg  [ 5:0] bits_left = 0;
    reg  [ 4:0] next_hour = 0;
    reg  [ 5:0] next_minute = 0;
    wire [17:0] shifted = {remainder, work[31]};
    wire        take_bit = shifted >= 18'd86400;
    wire [17:0] reduced = take_bit ? shifted - 18'd86400 : shifted;
    wire        second_tick = valid && prescale == LAST_SECOND;

    always @(posedge clk) begin
        toggle <= host_timestamp[32];
        if (valid) begin
            if (second_tick) begin
                prescale <= 0;
                if (second != 59) second <= second + 1'b1;
                else begin
                    second <= 0;
                    if (minute != 59) minute <= minute + 1'b1;
                    else begin
                        minute <= 0;
                        if (hour != 23) hour <= hour + 1'b1;
                        else begin
                            hour         <= 0;
                            running_days <= running_days + 1'b1;
                            day          <= day + 1'b1;
                        end
                    end
                end
            end else prescale <= prescale + 1'b1;
        end

        // Serial constant division, once per host update. No wide combinational
        // Unix/calendar divider in the CPU or CBUS response path.
        case (state)
            DIVIDE: begin
                work      <= {work[30:0], 1'b0};
                remainder <= reduced[16:0];
                host_days <= {host_days[6:0], take_bit};
                bits_left <= bits_left - 1'b1;
                if (bits_left == 1) state <= HOURS;
            end
            HOURS: begin
                if (remainder >= 3600) begin
                    remainder <= remainder - 17'd3600;
                    next_hour <= next_hour + 1'b1;
                end else state <= MINUTES;
            end
            MINUTES: begin
                if (remainder >= 60) begin
                    remainder   <= remainder - 17'd60;
                    next_minute <= next_minute + 1'b1;
                end else begin
                    valid        <= 1;
                    prescale     <= 0;
                    second       <= remainder[5:0];
                    minute       <= next_minute;
                    hour         <= next_hour;
                    running_days <= host_days;
                    // Retain the firmware's day/base relationship on resync.
                    // If resync and midnight coincide, do not count it twice.
                    if (valid) day <= day + host_days - running_days;
                    else day <= 0;
                    state <= IDLE;
                end
            end
            default: ;
        endcase
        if (day_write) day <= day_data;
        if (host_timestamp[32] != toggle) begin
            work        <= host_timestamp[31:0];
            host_days   <= 0;
            remainder   <= 0;
            bits_left   <= 32;
            next_hour   <= 0;
            next_minute <= 0;
            state       <= DIVIDE;
        end
    end
endmodule
