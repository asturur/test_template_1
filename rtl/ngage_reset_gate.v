// Latch phone reset requests while a save/restore is active. The transport
// cold reset remains immediate; core reconfiguration/power removal is external.
module ngage_reset_gate (
    input  wire clk,
    input  wire cold_reset,
    input  wire reset_request,
    input  wire block_reset,
    output wire reset_pending,
    output reg  phone_reset = 1
);
    reg pending = 0;
    assign reset_pending = pending || reset_request;
    always @(posedge clk) begin
        if (cold_reset) begin
            pending     <= 0;
            phone_reset <= 1;
        end else if (block_reset) begin
            if (reset_request) pending <= 1;
            phone_reset <= 0;
        end else if (pending || reset_request) begin
            phone_reset <= 1;
            pending     <= reset_request;
        end else phone_reset <= 0;
    end
endmodule
