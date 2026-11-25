// Serialize complete 32-bit CPU and DMA requests. A CPU lock reserves memory
// across the SWP read/write gap. The MiSTer top connects LCD DMA.
module ngage_sdram_arbiter #(
    parameter integer AW               = 25,
    parameter integer CPU_BLOCK_WRITES = 0,
    parameter integer CPU_POST_REPLY_REG = 0
) (
    input  wire          clk,
    input  wire          reset,
    input  wire          cpu_lock,
    input  wire          cpu_req,
    input  wire          cpu_we,
    input  wire [AW-1:0] cpu_addr,
    input  wire [  31:0] cpu_data,
    input  wire          cpu_write_block,
    input  wire [ 127:0] cpu_block_data,
    input  wire [   3:0] cpu_be,
    output wire          cpu_ack,
    output wire [  31:0] cpu_rdata,
    input  wire          dma_req,
    input  wire          dma_we,
    input  wire [AW-1:0] dma_addr,
    input  wire [  31:0] dma_data,
    input  wire [   3:0] dma_be,
    output wire          dma_ack,
    output wire [  31:0] dma_rdata,
    output wire          mem_req,
    output reg           mem_we,
    output reg  [AW-1:0] mem_addr,
    output reg  [  31:0] mem_data,
    output reg           mem_write_block,
    output reg  [ 127:0] mem_block_data,
    output reg  [   3:0] mem_be,
    input  wire          mem_ack,
    input  wire [  31:0] mem_rdata,
    output wire          cpu_accept,
    output wire          dma_accept,
    output wire          mem_lock,
    input  wire          mem_nonposted_ack
);
    localparam FREE = 0, ACTIVE = 1;
    reg [1:0] state = FREE;
    reg owner = 0, prefer_dma = 0;
    // This bit follows the accepted scalar packet. The live CPU lock only
    // arbitrates future grants and holds the reservation between SWP beats.
    (* dont_retime *) reg packet_lock = 0;
    assign mem_lock = packet_lock;
    wire choose_cpu = cpu_req && (cpu_lock || !dma_req || !prefer_dma);
    wire choose_dma = dma_req && !cpu_lock && !choose_cpu;
    assign cpu_accept = !reset && state == FREE && choose_cpu;
    assign dma_accept = !reset && state == FREE && choose_dma;
    assign mem_req    = (state == ACTIVE);
    wire cpu_owns_transfer = mem_req && !owner && !reset;
    generate
        if (CPU_POST_REPLY_REG) begin : g_cpu_post_reply
            (* dont_retime *) reg posted_reply = 0;
            // The raw completion releases the physical owner at this edge.
            // The CPU route keeps its token until the captured reply arrives.
            always @(posedge clk)
                posted_reply <= cpu_owns_transfer && mem_ack && mem_we && !packet_lock;
            assign cpu_ack = (cpu_owns_transfer && mem_nonposted_ack) ||
                             (!reset && posted_reply);
        end else begin : g_cpu_direct_reply
            assign cpu_ack = cpu_owns_transfer && mem_ack;
        end
    endgenerate
    assign dma_ack    = mem_req && owner && mem_ack && !reset;
    assign cpu_rdata  = mem_rdata;
    assign dma_rdata  = mem_rdata;
    always @(posedge clk) begin
        if (reset) begin
            state       <= FREE;
            owner       <= 0;
            prefer_dma  <= 0;
            packet_lock <= 0;
        end else
            case (state)
                FREE:
                if (choose_cpu || choose_dma) begin
                    owner           <= choose_dma;
                    prefer_dma      <= !choose_dma;
                    packet_lock     <= choose_cpu && cpu_lock;
                    mem_we          <= choose_dma ? dma_we : cpu_we;
                    mem_addr        <= choose_dma ? dma_addr : cpu_addr;
                    mem_data        <= choose_dma ? dma_data : cpu_data;
                    mem_write_block <= CPU_BLOCK_WRITES && choose_cpu && cpu_we && cpu_write_block;
                    if (CPU_BLOCK_WRITES && choose_cpu && cpu_we && cpu_write_block)
                        mem_block_data <= cpu_block_data;
                    mem_be <= choose_dma ? dma_be : cpu_be;
                    state  <= ACTIVE;
                end
                ACTIVE:  if (mem_ack) state <= FREE;
                default: state <= FREE;
            endcase
    end
endmodule
