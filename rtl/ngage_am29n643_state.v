// Per-die command-state storage for the staged AM29N643 logical model.
// This is not yet the physical multiplexed address/data pin protocol: command
// decode and the DDR-backed contents remain in ngage_codeflash. Bits8..10
// retain erase setup/family and the original AMD programmer completion tail.
module ngage_am29n643_state (
    input  wire        clk,
    input  wire        reset,
    input  wire        update,
    input  wire [10:0] next_state,
    output reg  [10:0] state
);
    always @(posedge clk) begin
        if (reset) state <= 0;
        else if (update) state <= next_state;
    end
endmodule
