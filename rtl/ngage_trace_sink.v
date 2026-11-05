// Write-only debug sinks observed in the staged board. Events retain bus
// lanes and address; a later diagnostic module must buffer/export them.
module ngage_trace_sink(input wire clk,input wire reset,input wire req,input wire commit,input wire we,
 input wire [31:0] addr,input wire [31:0] din,input wire [3:0] sel,
 output wire claim,output wire bad,output reg trace_valid,output reg [31:0] trace_addr,trace_data,output reg [3:0] trace_sel);
 wire [31:0] a={addr[31:2],2'b00};
 wire byte_sink=(a>=32'h0de00000 && a<32'h0de01000)||(a>=32'h0dfd0000 && a<32'h0dfd0010);
 wire word_sink=a>=32'h0def0000 && a<32'h0def1000;
 assign claim=req && (byte_sink||word_sink);
 assign bad=claim && (!we || (byte_sink && !(sel==1 || sel==2 || sel==4 || sel==8)));
 always @(posedge clk)begin
  trace_valid<=0;
  if(reset)begin trace_addr<=0;trace_data<=0;trace_sel<=0;end
  else if(commit && claim && !bad)begin trace_valid<=1;trace_addr<=a;trace_data<=din;trace_sel<=sel;end
 end
endmodule
