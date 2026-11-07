// Read-only board observations. PC is the instruction FETCH virtual address,
// not an architectural retirement PC. Counters are modulo 2^32 except waits.
// Cold reset clears history; CPU Hold/warm reset retain the fault context.
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
            if (!cpu_reset) cycles <= cycles + 1'b1;
            if (!cpu_reset && fetch) begin
                fetches          <= fetches + 1'b1;
                last_pc          <= pc;
                last_instruction <= instruction;
            end
            if (!cpu_reset && bus_active && (bus_ack || bus_error)) begin
                last_address <= bus_address;
                last_data    <= bus_write ? bus_write_data : bus_read_data;
                if (bus_ack) acks <= acks + 1'b1;
                if (bus_error) errors <= errors + 1'b1;
            end
            if (!cpu_reset && bus_active && !bus_ack && !bus_error) begin
                if (wait_now != 32'hffffffff) wait_now <= wait_now + 1'b1;
                if (wait_now >= wait_max && wait_now != 32'hffffffff) wait_max <= wait_now + 1'b1;
            end else wait_now <= 0;
            if (!cpu_reset && fault && !fault_seen) begin
                fault_seen    <= 1;
                first_address <= bus_address;
                first_pc      <= pc;
                first_data    <= bus_write ? bus_write_data : bus_read_data;
                first_flags   <= fault_flags;
                first_reason  <= fault_reason;
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
