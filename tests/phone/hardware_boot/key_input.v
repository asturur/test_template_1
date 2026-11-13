// Simulation-only host input. All active hold state is serialized with the HDL.
module ngage_sim_keys (
    input wire clk,
    input wire reset,
    input wire [63:0] command_id,
    input wire [63:0] command_hold,
    input wire [26:0] command_mask,
    output reg [63:0] applied_id = 0,
    output reg [26:0] keys = 0
);
    reg [63:0] remaining = 0;
    always @(posedge clk) begin
        if (reset) begin
            applied_id <= 0;
            keys <= 0;
            remaining <= 0;
        end else if (command_id != applied_id) begin
            applied_id <= command_id;
            keys <= command_hold != 0 ? command_mask : 27'b0;
            remaining <= command_hold;
            $display("KEY_APPLIED id=%0d mask=%07x hold=%0d", command_id,
                     command_hold != 0 ? command_mask : 27'b0, command_hold);
        end else if (remaining != 0) begin
            remaining <= remaining - 1'b1;
            if (remaining == 1) begin
                keys <= 0;
                $display("KEY_RELEASED id=%0d", applied_id);
            end
        end
    end
endmodule
