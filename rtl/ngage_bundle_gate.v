// The mounted save owns C:/PMM DDR. A new bundle may be loaded only after
// the working save is safely unmounted; rejected attempts are visible.
module ngage_bundle_gate(input wire clk,reset,input wire request,input wire save_mounted,save_busy,save_error,
 output wire download,output reg blocked=0);
 assign download=request && !save_mounted && !save_busy && !save_error;
 always @(posedge clk)begin
  if(reset)blocked<=0;
  else if(request && !download)blocked<=1;
  else if(download)blocked<=0;
 end
endmodule
