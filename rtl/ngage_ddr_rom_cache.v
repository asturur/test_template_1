// Raw immutable ROM backing cache. Flash command/status handling and
// address-dependent descrambling remain above this boundary. DDR writes to
// ROM (including firmware erase/reload) invalidate all entries on acceptance.
module ngage_ddr_rom_cache #(
    parameter LINE_BITS   = 64,
              CACHE_BYTES = 1024
) (
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 req_valid,
    output wire                 req_ready,
    input  wire                 req_write,
    input  wire                 req_fetch,
    input  wire [         31:0] req_addr,
    input  wire [         31:0] req_wdata,
    input  wire [          3:0] req_be,
    output reg                  rsp_valid = 0,
    output reg  [         31:0] rsp_data = 0,
    output wire                 mem_valid,
    output wire [          7:0] mem_burst,
    input  wire                 mem_ready,
    output wire                 mem_write,
    output wire [         31:0] mem_addr,
    output wire [         31:0] mem_data,
    output wire [          3:0] mem_be,
    input  wire                 mem_done,
    input  wire [         31:0] mem_rdata,
    input  wire [LINE_BITS-1:0] mem_line
);
    localparam IDLE=0, LOOKUP=1, MISS=2, WAIT_LINE=3,
               SELECT=4, FILL=5, BYPASS=6, WAIT_BYPASS=7;
    reg [2:0] state = IDLE;
    reg [31:0] address = 0, data = 0;
    reg [3:0] mask = 0;
    reg write_op = 0;
    reg [$clog2(LINE_BITS/16)-1:0] beat = 0;
    reg [LINE_BITS-1:0] line = 0;
    wire rom = req_addr >= 32'h30000000 && req_addr < 32'h313f0000;
    wire invalidate = req_valid && req_ready && req_write && rom;
    // Present an accepted instruction address to both synchronous RAMs on
    // the same edge that captures this request. Then hold it until completion.
    // Live producer pins are ignored while a transaction is outstanding.
    wire [31:0] lookup_address = state == IDLE ? req_addr : address;
    wire lookup_valid = !reset && (state == IDLE ?
                        req_valid && rom && req_fetch && !req_write :
                        state != BYPASS && state != WAIT_BYPASS);
    wire cache_req, cache_ok;
    wire [23:0] fill_addr;
    wire [31:0] cache_data;
    wire [15:0] fill_word = line >> (beat * 16);
    wire        selected = !reset && (state == SELECT || state == FILL);
    ngage_jtframe_romrq_lcache #(
        .SDRAMW      (24),
        .AW          (24),
        .DW          (32),
        .CACHE_SIZE  (CACHE_BYTES),
        .BURSTLEN    (LINE_BITS),
        .TAG_RAM     (1),
        .HELD_ADDRESS(1)
    ) cache (
        .clk       (clk),
        .rst       (reset),
        .clr       (invalidate),
        .offset    (24'b0),
        .addr      (lookup_address[24:1]),
        .addr_ok   (lookup_valid),
        .data_ok   (cache_ok),
        .dout      (cache_data),
        .req       (cache_req),
        .sdram_addr(fill_addr),
        .xaddr     (),
        .xaddr_in  (24'b0),
        .din       (fill_word),
        .we        (selected),
        .dst       (state == FILL && beat == 0 && !reset),
        .din_ok    (state == FILL && beat == LINE_BITS / 16 - 1 && !reset)
    );
    assign req_ready = state == IDLE && !reset;
    assign mem_burst = state == MISS ? LINE_BITS / 64 : 1;
    assign mem_valid = !reset && (state == MISS || state == BYPASS);
    assign mem_write = state == BYPASS && write_op;
    assign mem_addr  = state == MISS ? 32'h30000000 + {7'b0, fill_addr, 1'b0} : address;
    assign mem_data  = data;
    assign mem_be    = mask;
    always @(posedge clk) begin
        rsp_valid <= 0;
        if (reset) begin
            state <= IDLE;
            beat  <= 0;
        end else
            case (state)
                IDLE:
                if (req_valid) begin
                    address  <= req_addr;
                    data     <= req_wdata;
                    mask     <= req_be;
                    write_op <= req_write;
                    state    <= rom && req_fetch && !req_write ? LOOKUP : BYPASS;
                end
                LOOKUP: begin
                    // Tag/data and their ownership were sampled together on
                    // acceptance. Keep the response registered, with no second
                    // lookup/history edge or combinational route to the CPU.
                    if (cache_ok) begin
                        rsp_data  <= cache_data;
                        rsp_valid <= 1;
                        state     <= IDLE;
                    end else if (cache_req) state <= MISS;
                end
                MISS:    if (mem_ready) state <= WAIT_LINE;
                WAIT_LINE:
                if (mem_done) begin
                    line  <= mem_line;
                    state <= SELECT;
                end
                SELECT: begin
                    beat  <= 0;
                    state <= FILL;
                end
                FILL:
                if (beat == LINE_BITS / 16 - 1) begin
                    state <= LOOKUP;
                end else beat <= beat + 1'b1;
                BYPASS:  if (mem_ready) state <= WAIT_BYPASS;
                WAIT_BYPASS:
                if (mem_done) begin
                    rsp_data  <= mem_rdata;
                    rsp_valid <= 1;
                    state     <= IDLE;
                end
                default: state <= IDLE;
            endcase
    end
endmodule
