// UPP internal DSP MDI transaction model. This is not the D550 audio DSP.
// Original MDI tasks use two250-halfword rings and publish producer pointers
// only after payload stores. Serial DSP instructions/electrical timing are
// outside this synthetic protocol model. Original firmware remains unchanged.
module ngage_upp_mdi #(
    parameter integer ANNOUNCE_TICKS = 20
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        tick,
    input  wire        periodic_active,
    input  wire        req,
    input  wire        commit,
    input  wire        we,
    input  wire [31:0] addr,
    input  wire [31:0] din,
    input  wire [ 3:0] sel,
    output wire        claim,
    output wire        bad,
    output wire        ready,
    output reg  [31:0] dout,
    output reg  [15:0] irq_events
);
    localparam IDLE=0, READ_WORD=1, TAKE_WORD=2, RX_HIGH=3, RX_LOW=4,
               TX_HIGH=5, TX_LOW=6, TX_WRITE=7, ANN_WRITE=8;
    localparam integer TW = ANNOUNCE_TICKS > 1 ? $clog2(ANNOUNCE_TICKS) : 1;
    reg [3:0] state;
    reg [31:0] control, pointers, receive_ptr;
    reg pointers_seen, receive_seen, announced, announce_due;
    reg [TW-1:0] elapsed;
    reg [   7:0] read_address;
    reg          read_seen;
    reg [15:0] incoming_word, outgoing_word;
    reg [15:0] word_index;
    reg [16:0] byte_index, frame_bytes;
    reg [7:0] write_index;
    reg [7:0] high_byte;
    reg reply_end;
    reg [1:0] announce_index;
    wire [31:0] a = {addr[31:2], 2'b00};
    wire ram_hit = a >= 32'h0c100000 && a < 32'h0c1003e8;
    wire valid_sel = sel==1 || sel==2 || sel==4 || sel==8 || sel==3 || sel==12 || sel==15;
    wire [31:0] mask = {{8{sel[3]}}, {8{sel[2]}}, {8{sel[1]}}, {8{sel[0]}}};
    wire accepted = req && commit && claim && !bad && ready;
    wire running = control[15:0] == 16'h0500;
    wire [7:0] producer = pointers[7:0];
    wire [7:0] consumer = pointers[23:16];
    wire [7:0] output_producer = receive_ptr[7:0];
    wire [7:0] output_consumer = receive_ptr[23:16];
    wire [8:0] output_used = output_producer >= output_consumer ?
        {1'b0,output_producer}-{1'b0,output_consumer} :
        {1'b0,output_producer}+9'd250-{1'b0,output_consumer};
    wire [8:0] output_free = 9'd249 - output_used;
    wire pointer_valid = pointers[15:0] < 250 && pointers[31:16] < 250 &&
                         receive_ptr[15:0] < 250 && receive_ptr[31:16] < 250;
    function [7:0] next_index;
        input [7:0] index;
        begin
            next_index = index == 249 ? 0 : index + 1'b1;
        end
    endfunction
    wire       peer_rx_valid = state == RX_HIGH || state == RX_LOW;
    wire       peer_rx_last = word_index >= 2 && byte_index + 17'd1 == frame_bytes;
    wire [7:0] peer_rx_data = state == RX_HIGH ? incoming_word[15:8] : incoming_word[7:0];
    wire peer_rx_ready, peer_tx_valid, peer_tx_last;
    wire [7:0] peer_tx_data;
    wire       peer_tx_ready = state == TX_HIGH || state == TX_LOW;
    ngage_upp_dsp_peer peer (
        .clk        (clk),
        .reset      (reset || !running),
        .rx_valid   (peer_rx_valid),
        .rx_ready   (peer_rx_ready),
        .rx_data    (peer_rx_data),
        .rx_last    (peer_rx_last),
        .tx_valid   (peer_tx_valid),
        .tx_ready   (peer_tx_ready),
        .tx_data    (peer_tx_data),
        .tx_last    (peer_tx_last),
        .unsupported()
    );
    wire [8:0] output_half_address = 9'd250 + {1'b0, write_index};
    wire [7:0] engine_address = (state == TX_WRITE || state == ANN_WRITE) ?
        output_half_address[8:1] : {1'b0,consumer[7:1]};
    reg [15:0] engine_half_data;
    always @* begin
        engine_half_data = outgoing_word;
        if (state == ANN_WRITE) begin
            case (announce_index)
                0: engine_half_data = 16'h0000;
                1: engine_half_data = 16'h7cd0;
                2: engine_half_data = 16'h0001;
                3: engine_half_data = 16'h0400;
            endcase
        end
    end
    wire engine_write = running && pointer_valid && (state == TX_WRITE || state == ANN_WRITE);
    wire [3:0] engine_be = engine_write ? (write_index[0] ? 4'hc : 4'h3) : 4'b0;
    wire [31:0] engine_data = write_index[0] ? {engine_half_data,16'b0} : {16'b0,engine_half_data};
    wire [31:0] cpu_q, engine_q;
    ngage_bram #(
        .AW        (8),
        .DW        (32),
        .BYTE_WIDTH(8)
    ) shared_ring (
        .clk   (clk),
        .addr_a(addr[9:2]),
        .addr_b(engine_address),
        .data_a(din),
        .data_b(engine_data),
        .we_a  (accepted && we && ram_hit ? sel : 4'b0),
        .we_b  (engine_be),
        .q_a   (cpu_q),
        .q_b   (engine_q)
    );
    assign claim = req && (ram_hit || a == 32'h0c14b004 || a == 32'h0c1003e8 || a == 32'h0c1003ec);
    assign bad   = claim && !valid_sel;
    assign ready = !ram_hit || we || (read_seen && read_address == addr[9:2]);
    always @* begin
        dout = 0;
        if (ram_hit) dout = cpu_q;
        else
            case (a)
                32'h0c14b004: dout = control;
                32'h0c1003e8: dout = pointers;
                32'h0c1003ec: dout = receive_ptr;
            endcase
        dout = dout & mask;
    end
    always @(posedge clk) begin
        if (reset) begin
            control        <= 0;
            pointers       <= 0;
            receive_ptr    <= 0;
            pointers_seen  <= 0;
            receive_seen   <= 0;
            read_seen      <= 0;
            read_address   <= 0;
            state          <= IDLE;
            announced      <= 0;
            announce_due   <= 0;
            elapsed        <= 0;
            incoming_word  <= 0;
            outgoing_word  <= 0;
            word_index     <= 0;
            byte_index     <= 0;
            frame_bytes    <= 0;
            write_index    <= 0;
            high_byte      <= 0;
            reply_end      <= 0;
            announce_index <= 0;
            irq_events     <= 0;
        end else begin
            irq_events   <= 0;
            read_seen    <= req && ram_hit && !we;
            read_address <= addr[9:2];
            if (accepted) begin
                if (a == 32'h0c14b004 && we) control <= (control & ~mask) | (din & mask);
                if (a == 32'h0c1003e8) begin
                    pointers_seen <= 1;
                    if (we) pointers <= (pointers & ~mask) | (din & mask);
                end
                if (a == 32'h0c1003ec) begin
                    receive_seen <= 1;
                    if (we) receive_ptr <= (receive_ptr & ~mask) | (din & mask);
                end
            end
            if (!running) begin
                state        <= IDLE;
                word_index   <= 0;
                byte_index   <= 0;
                frame_bytes  <= 0;
                announced    <= 0;
                announce_due <= 0;
                elapsed      <= 0;
            end else begin
                if (tick && periodic_active && pointers_seen && receive_seen && !announce_due && !announced) begin
                    if (elapsed == ANNOUNCE_TICKS - 1) announce_due <= 1;
                    else elapsed <= elapsed + 1'b1;
                end
                if (pointer_valid)
                    case (state)
                        IDLE: begin
                            if (announce_due && !announced && output_free >= 4) begin
                                write_index    <= output_producer;
                                announce_index <= 0;
                                state          <= ANN_WRITE;
                            end else if (peer_tx_valid && output_free >= 8) begin
                                write_index <= output_producer;
                                state       <= TX_HIGH;
                            end else if (!peer_tx_valid && producer != consumer) state <= READ_WORD;
                        end
                        READ_WORD: state <= TAKE_WORD;
                        TAKE_WORD: begin
                            incoming_word <= consumer[0] ? engine_q[31:16] : engine_q[15:0];
                            if (word_index == 2)
                                frame_bytes <= {1'b0,(consumer[0] ? engine_q[31:16] : engine_q[15:0])} + 17'd6;
                            state <= RX_HIGH;
                        end
                        RX_HIGH, RX_LOW:
                        if (peer_rx_valid && peer_rx_ready) begin
                            byte_index <= byte_index + 1'b1;
                            if (peer_rx_last || state == RX_LOW) begin
                                pointers[31:16] <= {8'b0, next_index(consumer)};
                                irq_events[9]   <= 1;
                                if (peer_rx_last) begin
                                    word_index  <= 0;
                                    byte_index  <= 0;
                                    frame_bytes <= 0;
                                end else word_index <= word_index + 1'b1;
                                state <= IDLE;
                            end else state <= RX_LOW;
                        end
                        TX_HIGH:
                        if (peer_tx_valid) begin
                            high_byte <= peer_tx_data;
                            state     <= TX_LOW;
                        end
                        TX_LOW:
                        if (peer_tx_valid) begin
                            outgoing_word <= {high_byte, peer_tx_data};
                            reply_end     <= peer_tx_last;
                            state         <= TX_WRITE;
                        end
                        TX_WRITE: begin
                            write_index <= next_index(write_index);
                            if (reply_end) begin
                                receive_ptr[15:0] <= {8'b0, next_index(write_index)};
                                irq_events[10]    <= 1;
                                state             <= IDLE;
                            end else state <= TX_HIGH;
                        end
                        ANN_WRITE: begin
                            write_index    <= next_index(write_index);
                            announce_index <= announce_index + 1'b1;
                            if (announce_index == 3) begin
                                receive_ptr[15:0] <= {8'b0, next_index(write_index)};
                                irq_events[10]    <= 1;
                                announced         <= 1;
                                state             <= IDLE;
                            end
                        end
                        default:   state <= IDLE;
                    endcase
            end
        end
    end
endmodule
