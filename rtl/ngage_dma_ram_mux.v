// Share the outer CPU/DMA RAM arbiter between the LCD reader, general DMA
// and game PCM reader. A free port forwards its selected request immediately;
// ownership is captured when the outer arbiter accepts it. That arbiter owns
// the payload snapshot; this mux keeps only the response tag and fairness bit.
// Payload outputs are meaningful at acceptance, not while a request is owned.
// Producers keep a captured word until ACK. Reset must also cancel/drain
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
    input  tri0        pcm_req,
    input  wire [24:0] pcm_addr,
    output wire        pcm_ack,
    output wire [31:0] pcm_rdata,
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
    reg owner_pcm, prefer_pcm;
    // Under contention let at most one PCM word pass before the next LCD/DMA
    // grant. PCM service leaves the established LCD/DMA alternation intact.
    wire select_pcm = owned ? owner_pcm : pcm_req && (prefer_pcm || (!lcd_req && !dma_req));
    wire select_dma = owned ? owner_dma : dma_req && (!lcd_req || prefer_dma);
    wire offered = lcd_req || dma_req || pcm_req;
    assign mem_req   = !reset && (owned || offered);
    assign mem_write = !select_pcm && select_dma && dma_write;
    assign mem_addr  = select_pcm ? pcm_addr : select_dma ? dma_addr : lcd_addr;
    assign mem_data  = !select_pcm && select_dma ? dma_data : 32'd0;
    assign mem_be    = !select_pcm && select_dma ? dma_be : 4'hf;
    wire accepted = !reset && !owned && offered && mem_accept;
    wire response = !reset && mem_ack && (owned || accepted);
    wire response_dma = owned ? owner_dma : select_dma;
    assign lcd_accept = accepted && !select_pcm && !select_dma;
    assign lcd_ack    = response && !select_pcm && !response_dma;
    assign dma_ack    = response && !select_pcm && response_dma;
    assign pcm_ack    = response && select_pcm;
    assign lcd_rdata  = mem_rdata;
    assign dma_rdata  = mem_rdata;
    assign pcm_rdata  = mem_rdata;
    always @(posedge clk) begin
        if (reset) begin
            owned      <= 0;
            owner_dma  <= 0;
            prefer_dma <= 0;
            owner_pcm  <= 0;
            prefer_pcm <= 0;
        end else begin
            if (accepted) begin
                owned     <= 1;
                owner_dma <= select_dma;
                owner_pcm <= select_pcm;
            end
            if (response) begin
                owned      <= 0;
                prefer_pcm <= !select_pcm;
                if (!select_pcm) prefer_dma <= !response_dma;
            end
        end
    end
endmodule
