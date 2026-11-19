`timescale 1ns / 1ps

// One-entry, strictly ordered SDRAM write posting trial. A logical reset
// cannot revoke a write that upstream has already been allowed to complete.
module frame_gap_posted (
    input wire clk,
    input wire cold_reset,
    input wire client_reset,
    input wire lock,
    input wire req,
    input wire we,
    input wire [24:0] addr,
    input wire [31:0] data,
    input wire [3:0] mask,
    output wire ack,
    output wire line_idle,
    output wire backend_reset,
    output wire backend_req,
    output wire backend_we,
    output wire [24:0] backend_addr,
    output wire [31:0] backend_data,
    output wire [3:0] backend_mask,
    input wire backend_ack
);
  reg pending = 0, seen = 0, posted_ack = 0;
  reg [24:0] saved_addr;
  reg [31:0] saved_data;
  reg [3:0] saved_mask;
  wire post = req && we && !lock && !seen && !pending && !client_reset;

  assign ack = !client_reset && (posted_ack || (!pending && backend_ack));
  assign line_idle = !pending && !seen && !client_reset;
  assign backend_reset = cold_reset || (client_reset && !pending);
  assign backend_req = pending ? !backend_ack : req && !seen && !client_reset && !(we && !lock);
  assign backend_we = pending || we;
  assign backend_addr = pending ? saved_addr : addr;
  assign backend_data = pending ? saved_data : data;
  assign backend_mask = pending ? saved_mask : mask;

  always @(posedge clk) begin
    posted_ack <= 0;
    if (cold_reset) begin
      pending <= 0;
      seen <= 0;
    end else begin
      if (!req) seen <= 0;
      if (pending && backend_ack) pending <= 0;
      if (post) begin
        pending <= 1;
        seen <= 1;
        saved_addr <= addr;
        saved_data <= data;
        saved_mask <= mask;
        posted_ack <= 1;
      end
    end
  end
endmodule
