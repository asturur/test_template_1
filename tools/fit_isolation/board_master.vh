    // Drive only the ngage_cpu boundary. Each offer remains stable through
    // backpressure, and scalar fallback preserves the accepted line address.
    localparam [2:0] ISSUE = 0, SCALAR = 1, LINE_OFFER = 2, LINE_RETURN = 3, FALLBACK = 4;
    (* dont_retime *) reg [2:0] state;
    reg [3:0] operation;
    reg [2:0] fallback_word;
    reg       fallback_live;
    reg [31:0] locked_address;
    reg [31:0] entropy0, entropy1, entropy2, entropy3;
    (* dont_retime *) reg line_req_q, write_block_q, code_q;
    (* dont_retime *) reg [31:0] line_addr_q;
    (* dont_retime *) reg [127:0] block_q;
    // Keep actual registered timing endpoints for every received data bit.
    // The sink need not feed a synthetic checksum or high-fanout load.
    (* preserve, noprune, dont_retime *) reg [106:0] response_sample;

    assign line_req          = line_req_q;
    assign line_addr         = line_addr_q;
    assign wb_stb            = wb_cyc;
    assign wb_write_block    = write_block_q;
    assign wb_block_data     = block_q;
    assign wb_code           = code_q;
    assign debug_pc          = 0;
    assign debug_cpsr        = 0;
    assign debug_instruction = 0;
    assign debug_fetch       = 0;

    function [31:0] advance;
        input [31:0] value;
        advance = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    wire [31:0] ram_word = {8'h0a, entropy0[23:2], 2'b00};
    wire [31:0] ram_line = {ram_word[31:5], 5'b00000};
    wire [9:0] flash_line_region = entropy1[1] ? (entropy1[0] ? 10'h011 : 10'h010) :
                                     (entropy1[0] ? 10'h008 : 10'h000);
    wire [31:0] rom_line = {flash_line_region, entropy1[21:5], 5'b00000};
    wire [3:0] byte_mask = entropy2[3:0] == 0 ? 4'b0001 : entropy2[3:0];
    always @(posedge clk) begin
        response_sample <= {irq, fiq, line_ready, line_reject, line_valid, line_wide,
                            line_last, line_error, line_no_late_error, line_data,
                            wb_ack, wb_error, wb_read_data};
        if (reset) begin
            state          <= ISSUE;
            operation      <= 0;
            fallback_word  <= 0;
            fallback_live  <= 0;
            locked_address <= 0;
            entropy0       <= 32'ha09f32e5;
            entropy1       <= 32'h32817ccf;
            entropy2       <= 32'hf2982c17;
            entropy3       <= 32'hc169e835;
            line_req_q     <= 0;
            line_addr_q    <= 0;
            write_block_q  <= 0;
            code_q         <= 0;
            block_q        <= 0;
            wb_cyc         <= 0;
            wb_lock        <= 0;
            wb_address     <= 0;
            wb_write       <= 0;
            wb_write_data  <= 0;
            wb_byte_enable <= 0;
            wb_cycle_type  <= 0;
            wb_burst_type  <= 0;
        end else begin
            entropy0 <= advance(entropy0);
            entropy1 <= advance(entropy1);
            entropy2 <= advance(entropy2);
            entropy3 <= advance(entropy3);
            case (state)
                ISSUE: begin
                    wb_address     <= ram_word;
                    wb_write_data  <= entropy2;
                    wb_byte_enable <= 4'hf;
                    wb_write       <= 0;
                    wb_lock        <= operation == 3 || operation == 4;
                    wb_cycle_type  <= 0;
                    write_block_q  <= 0;
                    code_q         <= 0;
                    wb_cyc         <= 1;
                    state          <= SCALAR;
                    case (operation)
                        0: code_q <= entropy0[0];
                        1: begin
                            wb_write       <= 1;
                            wb_byte_enable <= byte_mask;
                        end
                        2: begin
                            wb_address    <= {ram_word[31:4], 4'b0000};
                            wb_write      <= 1;
                            write_block_q <= 1;
                            block_q       <= {entropy3, entropy2, entropy1, entropy0};
                        end
                        3: locked_address <= ram_word;
                        4: begin
                            wb_address     <= locked_address;
                            wb_write       <= 1;
                            wb_byte_enable <= byte_mask;
                        end
                        5: begin
                            wb_address <= rom_line;
                            code_q     <= 1;
                        end
                        6: begin
                            wb_address <= {entropy1[1] ? 10'h010 : 10'h008, entropy0[21:2], 2'b00};
                            code_q     <= entropy0[0];
                        end
                        7: wb_address <= {10'h009, entropy1[21:2], 2'b00};
                        8: wb_address <= 32'h0c120600; // MMC command/status window
                        9: begin
                            wb_address <= 32'h0c121208; // LCD data
                            wb_write   <= 1;
                        end
                        10, 11, 12: if (LINE_REFILL) begin
                            // Case 12 probes the board's unsupported backing
                            // response. It must reject before any line data.
                            line_addr_q <= operation == 10 ? ram_line :
                                operation == 11 ? rom_line : {10'h009, entropy1[21:5], 5'b00000};
                            line_req_q <= 1;
                            wb_cyc     <= 0;
                            state      <= LINE_OFFER;
                        end
                        13: begin
                            wb_address     <= {16'h0c12, entropy0[15:2], 2'b00};
                            wb_byte_enable <= byte_mask;
                            wb_write       <= entropy0[0];
                        end
                        14: wb_address <= 32'h007f0030;
                        15: begin
                            // Infrequent generic probe keeps unmapped and IRQ
                            // controller decode live. This offer is read only.
                            wb_address <= irq && fiq ? entropy3 : 32'h0c120100;
                        end
                    endcase
                end
                SCALAR: if (wb_ack || wb_error) begin
                    wb_cyc <= 0;
                    if (fallback_live && fallback_word != 7 && !wb_error) begin
                        fallback_word <= fallback_word + 1'b1;
                        state <= FALLBACK;
                    end else begin
                        if (operation == 4) wb_lock <= 0;
                        fallback_live <= 0;
                        operation <= operation + 1'b1;
                        state <= ISSUE;
                    end
                end
                LINE_OFFER: if (line_ready) begin
                    line_req_q <= 0;
                    state <= LINE_RETURN;
                end
                LINE_RETURN: begin
                    if (line_reject) begin
                        fallback_word <= 0;
                        fallback_live <= 1;
                        state <= FALLBACK;
                    end else if (line_valid && (line_last || line_error)) begin
                        operation <= operation + 1'b1;
                        state <= ISSUE;
                    end
                end
                FALLBACK: begin
                    wb_address     <= {line_addr_q[31:5], fallback_word, 2'b00};
                    wb_byte_enable <= 4'hf;
                    wb_cycle_type  <= fallback_word == 7 ? 3'b111 : 3'b010;
                    wb_write       <= 0;
                    wb_cyc         <= 1;
                    state          <= SCALAR;
                end
                default: state <= ISSUE;
            endcase
        end
    end
endmodule
