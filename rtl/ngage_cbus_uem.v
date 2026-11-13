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
    input  wire        power_pressed
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
    reg         payload_forward;
    reg  [15:0] payload_value;
    wire        payload_write = !reset && commit && claim && !bad && we && a == 32'h0c150424;
    wire        command_write = commit && claim && !bad && we && a == 32'h0c150420 && sel == 12;
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
                                  16'h0000 : 16'h0010) | 16'h0008 | rtc_status;
                else if (regno == 8'h36 && !written[regno]) read_value = 0;
                else if (cfg == 7 && regno >= 8'h31 && regno <= 8'h33) read_value = 0;
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
