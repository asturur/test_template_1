// Read-only board observations. PC is the instruction FETCH virtual address,
// not an architectural retirement PC. Counters are modulo 2^32 except waits.
// Observations enter history one clock later. Cold reset clears history; CPU Hold/warm reset retain the fault context.
module ngage_debug_monitor (
    input  wire         clk,
    input  wire         cold_reset,
    input  wire         cpu_reset,
    input  wire [ 31:0] pc,
    input  wire [ 31:0] cpsr,
    input  wire [ 31:0] instruction,
    input  wire         fetch,
    input  wire         bus_active,
    input  wire         bus_ack,
    input  wire         bus_error,
    input  wire         bus_write,
    input  wire [ 31:0] bus_address,
    input  wire [ 31:0] bus_write_data,
    input  wire [ 31:0] bus_read_data,
    input  wire [ 31:0] bus_flags,
    input  wire         fault,
    input  wire [ 31:0] fault_flags,
    input  wire [  2:0] fault_reason,
    input  wire [ 31:0] boot_flags,
    input  wire [ 31:0] cpu_flags,
    input  wire [ 26:0] keys,
    output wire [767:0] values
);
    // Capture an unconditional transaction record first. Late fault/ACK
    // predicates drive only their event bits, not every sticky-context mux.
    // Warm CPU reset does not discard an event sampled on the previous edge.
    reg sample_reset = 1, sample_fetch = 0, sample_active = 0;
    reg sample_ack = 0, sample_error = 0, sample_fault = 0;
    reg [31:0] sample_pc, sample_instruction, sample_address, sample_data;
    reg [31:0] sample_fault_flags;
    reg [ 2:0] sample_reason;
    always @(posedge clk) begin
        sample_reset       <= cold_reset || cpu_reset;
        sample_fetch       <= !cold_reset && fetch;
        sample_active      <= !cold_reset && bus_active;
        sample_ack         <= bus_ack;
        sample_error       <= bus_error;
        sample_fault       <= !cold_reset && fault;
        sample_pc          <= pc;
        sample_instruction <= instruction;
        sample_address     <= bus_address;
        sample_data        <= bus_write ? bus_write_data : bus_read_data;
        sample_fault_flags <= fault_flags;
        sample_reason      <= fault_reason;
    end
    reg [31:0] cycles = 0, fetches = 0, acks = 0, errors = 0, wait_now = 0, wait_max = 0;
    reg [31:0] last_pc = 0, last_instruction = 0, last_address = 0, last_data = 0;
    reg fault_seen = 0;
    reg [31:0] first_address = 0, first_pc = 0, first_data = 0, first_flags = 0;
    reg [2:0] first_reason = 0;
    always @(posedge clk) begin
        if (cold_reset) begin
            cycles           <= 0;
            fetches          <= 0;
            acks             <= 0;
            errors           <= 0;
            wait_now         <= 0;
            wait_max         <= 0;
            last_pc          <= 0;
            last_instruction <= 0;
            last_address     <= 0;
            last_data        <= 0;
            fault_seen       <= 0;
            first_address    <= 0;
            first_pc         <= 0;
            first_data       <= 0;
            first_flags      <= 0;
            first_reason     <= 0;
        end else begin
            if (!sample_reset) cycles <= cycles + 1'b1;
            if (!sample_reset && sample_fetch) begin
                fetches          <= fetches + 1'b1;
                last_pc          <= sample_pc;
                last_instruction <= sample_instruction;
            end
            if (!sample_reset && sample_active && (sample_ack || sample_error)) begin
                last_address <= sample_address;
                last_data    <= sample_data;
                if (sample_ack) acks <= acks + 1'b1;
                if (sample_error) errors <= errors + 1'b1;
            end
            if (!sample_reset && sample_active && !sample_ack && !sample_error) begin
                if (wait_now != 32'hffffffff) wait_now <= wait_now + 1'b1;
                if (wait_now >= wait_max && wait_now != 32'hffffffff) wait_max <= wait_now + 1'b1;
            end else wait_now <= 0;
            if (!sample_reset && sample_fault && !fault_seen) begin
                fault_seen    <= 1;
                first_address <= sample_address;
                first_pc      <= sample_pc;
                first_data    <= sample_data;
                first_flags   <= sample_fault_flags;
                first_reason  <= sample_reason;
            end
        end
    end
    assign values = {
        {5'b0, keys},
        cpu_flags,
        boot_flags,
        {29'b0, first_reason},
        first_flags,
        first_data,
        first_pc,
        first_address,
        last_data,
        last_address,
        wait_max,
        wait_now,
        errors,
        acks,
        bus_flags,
        bus_read_data,
        bus_write_data,
        bus_address,
        fetches,
        cycles,
        cpsr,
        last_instruction,
        last_pc,
        pc
    };
endmodule
