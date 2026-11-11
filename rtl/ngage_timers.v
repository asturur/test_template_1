// Six UPP general timers. Original NEM-4 kernel helpers at 50324948..50324a44
// access control +04, acknowledge/status +08, live count +10 and reload +18.
// Timer 0 supplies the OS tick; medint uses timer 3 with reload/count 390.
// The board selects a 26 MHz enable (/3 at 78 MHz, /4 at 104 MHz).
module ngage_timers #(
    parameter integer CLOCK_DIV = 1
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
    output wire        claim,
    output wire        bad,
    output wire [31:0] dout,
    output wire        timer0_pending,
    output wire        unit1_pending,
    output wire        unit60_pending,
    output wire        timer0_rearm,
    output wire        periodic_active,
    input  wire        sysc74_seen,
    output wire [ 5:0] pending_sources,
    output wire        ready
);
    wire [31:0] a = {addr[31:2], 2'b00};
    wire [ 2:0] unit_index = addr[7:5];
    wire [ 2:0] register_index = addr[4:2];
    assign claim = req && a >= 32'h0c120a00 && a < 32'h0c120ac0;
    assign bad   = claim && (sel != 15 || addr[1:0] != 0);
    wire write_access = commit && claim && !bad && we;

    // Passive readback words have no counter-side effects. Keep their full
    // values in one M10K; validity flags provide immediate warm-reset zeroes.
    wire spare_word = register_index == 0 || register_index == 3 ||
        register_index == 5 || register_index == 7;
    wire [1:0] spare_index = register_index == 0 ? 2'd0 :
        register_index == 3 ? 2'd1 : register_index == 5 ? 2'd2 : 2'd3;
    wire [4:0] spare_address = {unit_index, spare_index};
    wire spare_write = write_access && spare_word && !reset;
    wire spare_read = claim && !bad && !we && spare_word;
    reg [23:0] spare_valid = 0;
    reg spare_read_pending = 0, spare_sample_valid = 0;
    reg  [ 4:0] spare_sample_address;
    wire [31:0] spare_data;
    ngage_bram #(
        .AW         (5),
        .DW         (32),
        .READ_ONLY_B(1)
    ) passive_words (
        .clk   (clk),
        .addr_a(spare_address),
        .addr_b(spare_address),
        .data_a(din),
        .data_b(32'b0),
        .we_a  (spare_write),
        .we_b  (1'b0),
        .q_a   (),
        .q_b   (spare_data)
    );
    assign ready = !spare_read || (spare_read_pending && spare_sample_address == spare_address);
    always @(posedge clk) begin
        if (reset) begin
            spare_valid          <= 0;
            spare_read_pending   <= 0;
            spare_sample_valid   <= 0;
            spare_sample_address <= 0;
        end else begin
            if (spare_write) spare_valid[spare_address] <= 1;
            spare_read_pending   <= spare_read;
            spare_sample_address <= spare_address;
            spare_sample_valid   <= spare_read && spare_valid[spare_address];
        end
    end
    // One short shared divider; each counter has its own parallel decrementer.
    // Bus admission/ACK never waits for this enable. Register writes override
    // a decrement on their edge; the first count follows on the next enable.
    reg  [1:0] divider = 0;
    wire       timer_ce = divider == CLOCK_DIV - 1;
    always @(posedge clk) begin
        if (reset || timer_ce) divider <= 0;
        else divider <= divider + 1'b1;
    end

    wire [31:0] read_data[0:5];
    wire [ 5:0] periodic;
    assign timer0_pending  = pending_sources[0];
    assign unit1_pending   = pending_sources[1];
    assign unit60_pending  = pending_sources[3];
    // Reload programming has no authority over the ICU mask.
    assign timer0_rearm    = 1'b0;
    assign periodic_active = periodic[0];
    // Independent one-hot selection; no priority chain through six counters.
    wire [31:0] selected_data[0:5];
    assign dout = spare_word ? (spare_sample_valid ? spare_data : 32'b0) :
        selected_data[0] | selected_data[1] | selected_data[2] |
        selected_data[3] | selected_data[4] | selected_data[5];

    genvar t;
    generate
        for (t = 0; t < 6; t = t + 1) begin : g_timer
            reg [31:0] control, count, reload, status;
            reg running, pending;
            reg  [31:0] data;
            wire        hit = write_access && unit_index == t;
            wire        count_write = hit && register_index == 4;
            wire        stopping = hit && register_index == 1 && din[1:0] == 0;
            wire        expiry = timer_ce && running && count == 1 && !count_write && !stopping;
            assign pending_sources[t] = pending;
            assign periodic[t]        = running && control[1] && reload != 0;
            assign read_data[t]       = data;
            assign selected_data[t]   = data & {32{unit_index == t}};
            always @* begin
                case (register_index)
                    0:       data = 0;
                    1:       data = control;
                    2:       data = status;
                    3:       data = 0;
                    4:       data = count;
                    5:       data = 0;
                    6:       data = reload;
                    7:       data = 0;
                    default: data = 0;
                endcase
            end
            always @(posedge clk) begin
                if (reset) begin
                    control <= 0;
                    count   <= 0;
                    reload  <= 0;
                    status  <= 0;
                    running <= 0;
                    pending <= 0;
                end else begin
                    if (timer_ce && running && !count_write && !stopping) begin
                        // Zero wraps naturally: a zero load takes 2^32 enables.
                        if (count == 1) begin
                            count <= control[1] ? reload : 0;
                            if (!control[1]) running <= 0;
                        end else count <= count - 1'b1;
                    end
                    if (t == 1 && clear_unit1) pending <= 0;
                    if (hit) begin
                        case (register_index)
                            1: begin
                                control <= din;
                                if (din[1:0] == 0) running <= 0;
                                else if (!running || expiry) running <= 1;
                            end
                            2: begin
                                status  <= din;
                                pending <= 0;
                            end
                            4: begin
                                count  <= din;
                                // Original 50323f4c programs and polls again
                                // without ACK: completion belongs to the new
                                // deadline. This transaction-level inference
                                // does not acknowledge an older IRQ event.
                                status <= 0;
                                if (control[1:0] != 0) running <= 1;
                            end
                            6: reload <= din;
                        endcase
                    end
                    // A coincident new expiry survives acknowledgement. Stop
                    // and count programming cancel the old deadline instead.
                    // Sub-clock hardware ordering remains unmeasured on NEM-4.
                    if (expiry) begin
                        status  <= 1;
                        pending <= 1;
                    end
                end
            end
        end
    endgenerate
endmodule
