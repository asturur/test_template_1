// One owned DMA word at a time. Local targets admit a word only when their
// CPU arbiter and endpoint can accept it. A waiting word owns no local bus.
module ngage_dma_route #(
    parameter LOCAL_ENABLE = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        cpu_lock,
    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire        cmd_write,
    input  wire [31:0] cmd_addr,
    input  wire [31:0] cmd_data,
    input  wire [ 3:0] cmd_be,
    output wire        rsp_valid,
    output wire        rsp_error,
    output wire [31:0] rsp_data,
    output wire        ram_req,
    output wire        ram_write,
    output wire [24:0] ram_addr,
    output wire [31:0] ram_data,
    output wire [ 3:0] ram_be,
    input  wire        ram_ack,
    input  wire [31:0] ram_rdata,
    output wire        local_valid,
    input  wire        local_ready,
    output wire        local_write,
    output wire [31:0] local_addr,
    output wire [31:0] local_data,
    output wire [ 3:0] local_be,
    input  wire        local_done,
    input  wire        local_error,
    input  wire [31:0] local_rdata,
    output wire        local_waiting
);
    localparam IDLE = 3'd0, RAM = 3'd1, LOCAL_WAIT = 3'd2, LOCAL_ACTIVE = 3'd3, REJECT = 3'd4, LOCAL_RESPONSE = 3'd5;
    localparam [31:0] LCD_FIFO = 32'h0c121208;
    reg [ 2:0] state = IDLE;
    reg        local_response_error = 0;
    reg [31:0] local_response_data = 0;

    wire legal_word = cmd_addr[1:0] == 0 && cmd_be != 0;
    wire ram_hit = cmd_addr[31:24] == 8'h0a;
    // The NOS4K RAM shares this page with boot scratch at 0x4748..0x47f8.
    wire chip_ram_hit = cmd_addr[31:12] == 20'h0c004 &&
        (cmd_addr[11:0] < 12'h748 || cmd_addr[11:0] > 12'h7f8);
    wire lcd_hit = cmd_addr == LCD_FIFO || cmd_addr == 32'h10121208;
    wire mmc_hit = cmd_addr == 32'h0c120624 || cmd_addr == 32'h10120624;
    wire byte_lane = cmd_be == 1 || cmd_be == 2 || cmd_be == 4 || cmd_be == 8;
    wire mmc_offer = LOCAL_ENABLE && legal_word && mmc_hit && byte_lane;
    reg held_write;
    reg [31:0] held_addr, held_data;
    reg  [3:0] held_be;
    wire       live_mmc = state == IDLE && mmc_offer;
    assign local_write = live_mmc ? cmd_write : held_write;
    assign local_addr  = live_mmc ? 32'h0c120624 : held_addr;
    assign local_data  = live_mmc ? cmd_data : held_data;
    assign local_be    = live_mmc ? cmd_be : held_be;
    wire local_hit = LOCAL_ENABLE && (chip_ram_hit || (lcd_hit && cmd_write && cmd_be == 4'hf));

    assign cmd_ready = !reset && !cpu_lock && state == IDLE && (!mmc_offer || local_ready);
    wire accept = cmd_valid && cmd_ready;
    // Launch on the capture edge to keep the existing LCD read latency.
    // A grant that waits for the outer SDRAM arbiter uses the held packet.
    wire start_ram = accept && legal_word && ram_hit;
    assign ram_req   = !reset && (start_ram || state == RAM);
    assign ram_write = start_ram ? cmd_write : local_write;
    assign ram_addr  = start_ram ? cmd_addr[24:0] : local_addr[24:0];
    assign ram_data  = start_ram ? cmd_data : local_data;
    assign ram_be    = start_ram ? cmd_be : local_be;

    assign local_valid   = !reset && !cpu_lock && (state == LOCAL_WAIT || (live_mmc && cmd_valid));
    // Generic local admission derives only from the captured request state.
    // Live MMC already owns a separate registered UPP reservation; do not
    // feed its cancelable cmd_valid back into CPU request exclusion.
    assign local_waiting = !reset && !cpu_lock && state == LOCAL_WAIT;
    wire take_local = local_valid && local_ready;
    wire local_response = (take_local || state == LOCAL_ACTIVE) && local_done;
    assign rsp_valid = !reset && ((state == RAM && ram_ack) || state == LOCAL_RESPONSE || state == REJECT);
    assign rsp_error = rsp_valid && (state == REJECT || (state == LOCAL_RESPONSE && local_response_error));
    assign rsp_data  = state == RAM ? ram_rdata :
        state == LOCAL_RESPONSE ? local_response_data : local_rdata;

    always @(posedge clk) begin
        if (reset) begin
            state                <= IDLE;
            local_response_error <= 0;
            local_response_data  <= 0;
        end else begin
            // Local ACK includes the UPP owner mux and peripheral decode.
            // Capture its exact data/error once; engines consume the registered
            // response. SDRAM and the dedicated fast LCD route are unchanged.
            if (local_response) begin
                local_response_error <= local_error;
                local_response_data  <= local_rdata;
            end
            case (state)
                IDLE:
                if (accept) begin
                    held_write <= cmd_write;
                    held_addr  <= lcd_hit ? LCD_FIFO : mmc_hit ? 32'h0c120624 : cmd_addr;
                    held_data  <= cmd_data;
                    held_be    <= cmd_be;
                    if (legal_word && ram_hit) state <= RAM;
                    else if (mmc_offer) state <= local_done ? LOCAL_RESPONSE : LOCAL_ACTIVE;
                    else if (legal_word && local_hit) state <= LOCAL_WAIT;
                    else state <= REJECT;
                end
                RAM:            if (ram_ack) state <= IDLE;
                LOCAL_WAIT:     if (take_local) state <= local_done ? LOCAL_RESPONSE : LOCAL_ACTIVE;
                LOCAL_ACTIVE:   if (local_done) state <= LOCAL_RESPONSE;
                LOCAL_RESPONSE: state <= IDLE;
                REJECT:         state <= IDLE;
                default:        state <= IDLE;
            endcase
        end
    end
endmodule
