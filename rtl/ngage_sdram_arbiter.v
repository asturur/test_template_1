// Serialize complete 32-bit CPU and DMA requests. A CPU lock reserves memory
// across the SWP read/write gap. The MiSTer top connects LCD DMA.
module ngage_sdram_arbiter(
 input wire clk, input wire reset, input wire cpu_lock,
 input wire cpu_req, input wire cpu_we, input wire [24:0] cpu_addr,
 input wire [31:0] cpu_data, input wire [3:0] cpu_be,
 output wire cpu_ack, output wire [31:0] cpu_rdata,
 input wire dma_req, input wire dma_we, input wire [24:0] dma_addr,
 input wire [31:0] dma_data, input wire [3:0] dma_be,
 output wire dma_ack, output wire [31:0] dma_rdata,
 output wire mem_req, output reg mem_we, output reg [24:0] mem_addr,
 output reg [31:0] mem_data, output reg [3:0] mem_be,
 input wire mem_ack, input wire [31:0] mem_rdata
);
 localparam FREE=0, ACTIVE=1;
 reg [1:0] state=FREE; reg owner=0, prefer_dma=0;
 wire choose_cpu=cpu_req && (cpu_lock || !dma_req || !prefer_dma);
 wire choose_dma=dma_req && !cpu_lock && !choose_cpu;
 assign mem_req=(state==ACTIVE);
 assign cpu_ack=mem_req && !owner && mem_ack && !reset;
 assign dma_ack=mem_req && owner && mem_ack && !reset;
 assign cpu_rdata=mem_rdata; assign dma_rdata=mem_rdata;
 always @(posedge clk) begin
  if(reset) begin state<=FREE;owner<=0;prefer_dma<=0; end
  else case(state)
   FREE: if(choose_cpu || choose_dma) begin
     owner<=choose_dma; prefer_dma<=!choose_dma;
     mem_we<=choose_dma ? dma_we : cpu_we;
     mem_addr<=choose_dma ? dma_addr : cpu_addr;
     mem_data<=choose_dma ? dma_data : cpu_data;
     mem_be<=choose_dma ? dma_be : cpu_be;
     state<=ACTIVE;
   end
   ACTIVE: if(mem_ack) state<=FREE;
   default: state<=FREE;
  endcase
 end
endmodule
