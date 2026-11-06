// Per-die command-state storage for the staged AM29N643 logical model.
// This is not yet the physical multiplexed address/data pin protocol: command
// decode and the DDR-backed contents remain in ngage_codeflash.
module ngage_am29n643_state(
 input wire clk,reset,update,input wire [7:0] next_state,
 output reg [7:0] state
);
 always @(posedge clk)begin
  if(reset)state<=0;
  else if(update)state<=next_state;
 end
endmodule
