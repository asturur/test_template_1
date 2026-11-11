// Share the outer CPU/DMA RAM arbiter between the fast LCD reader and the
// general DMA router. A free port forwards its selected request immediately;
// ownership and payload are captured only when the outer arbiter accepts it.
// Both producers keep a captured word until ACK. Reset must also cancel/drain
// the outer arbiter and physical RAM adapter before fresh ownership resumes.
module ngage_dma_ram_mux (
    input  wire        clk,
    input  wire        reset,
    input  wire        lcd_req,
    input  wire [24:0] lcd_addr,
    output wire        lcd_accept,
    output wire        lcd_ack,
    output wire [31:0] lcd_rdata,
    input  wire        dma_req,
    input  wire        dma_write,
    input  wire [24:0] dma_addr,
    input  wire [31:0] dma_data,
    input  wire [ 3:0] dma_be,
    output wire        dma_ack,
    output wire [31:0] dma_rdata,
    output wire        mem_req,
    output wire        mem_write,
    output wire [24:0] mem_addr,
    output wire [31:0] mem_data,
    output wire [ 3:0] mem_be,
    input  wire        mem_accept,
    input  wire        mem_ack,
    input  wire [31:0] mem_rdata
);
    reg owned, owner_dma, prefer_dma;
    reg         saved_write;
    reg  [24:0] saved_addr;
    reg  [31:0] saved_data;
    reg  [ 3:0] saved_be;
    wire        select_dma = dma_req && (!lcd_req || prefer_dma);
    wire        offered = lcd_req || dma_req;
    assign mem_req   = !reset && (owned || offered);
    assign mem_write = owned ? saved_write : select_dma && dma_write;
    assign mem_addr  = owned ? saved_addr : select_dma ? dma_addr : lcd_addr;
    assign mem_data  = owned ? saved_data : select_dma ? dma_data : 32'd0;
    assign mem_be    = owned ? saved_be : select_dma ? dma_be : 4'hf;
    wire accepted = !reset && !owned && offered && mem_accept;
    wire response = !reset && mem_ack && (owned || accepted);
    wire response_dma = owned ? owner_dma : select_dma;
    assign lcd_accept = accepted && !select_dma;
    assign lcd_ack    = response && !response_dma;
    assign dma_ack    = response && response_dma;
    assign lcd_rdata  = mem_rdata;
    assign dma_rdata  = mem_rdata;
    always @(posedge clk) begin
        if (reset) begin
            owned      <= 0;
            owner_dma  <= 0;
            prefer_dma <= 0;
        end else begin
            if (accepted) begin
                owned       <= 1;
                owner_dma   <= select_dma;
                saved_write <= mem_write;
                saved_addr  <= mem_addr;
                saved_data  <= mem_data;
                saved_be    <= mem_be;
            end
            if (response) begin
                owned      <= 0;
                prefer_dma <= !response_dma;
            end
        end
    end
endmodule
