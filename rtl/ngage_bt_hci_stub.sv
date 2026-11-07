// SPDX-License-Identifier: GPL-3.0-or-later
// No-radio HCI responder for integration experiments. The wire transport is
// NOT established: this byte stream matches NGVM's HLE bt_driver framing,
// not a verified LRB-2 CBUS register interface. One command is outstanding;
// unknown opcodes return Unknown HCI Command rather than invented success.
module ngage_bt_hci_stub (
    input  logic       clk,
    input  logic       reset,
    input  logic       rx_valid,
    input  logic [7:0] rx_byte,
    output logic       rx_ready,
    output logic       tx_valid,
    output logic [7:0] tx_byte,
    input  logic       tx_ready
);
    typedef enum logic [2:0] {
        TYPE_LO,
        TYPE_HI,
        OP_LO,
        OP_HI,
        LENGTH,
        PARAMETERS,
        EVENT
    } state_t;
    state_t        state;
    logic   [15:0] opcode;
    logic   [ 7:0] remaining;
    logic [8:0] index, total;
    logic       inquiry_second;
    logic [7:0] result_length;
    logic [7:0] status;
    function automatic [7:0] payload_length(input logic [15:0] op);
        case (op)
            16'h1005:           payload_length = 7;
            16'h1001, 16'h1003: payload_length = 8;
            16'h1009:           payload_length = 6;
            16'h0c23:           payload_length = 3;
            16'h0c19:           payload_length = 1;
            16'h0c14:           payload_length = 248;
            default:            payload_length = 0;
        endcase
    endfunction
    function automatic logic known(input logic [15:0] op);
        case (op)
            16'h1005, 16'h1001, 16'h1003, 16'h1009, 16'h0c23, 16'h0c19, 16'h0c14, 16'h0c03,
                16'h0401:
            known = 1;
            default: known = 0;
        endcase
    endfunction
    function automatic [7:0] payload(input logic [15:0] op, input logic [8:0] n);
        begin
            payload = 0;
            case (op)
                16'h1005:
                case (n)
                    0:       payload = 8'h53;
                    1:       payload = 8'h01;
                    2:       payload = 8'h40;
                    3:       payload = 8'h08;
                    5:       payload = 8'h01;
                    default: ;
                endcase
                16'h1001:
                case (n)
                    0:       payload = 1;
                    3:       payload = 1;
                    4:       payload = 1;
                    default: ;
                endcase
                16'h1003:
                case (n)
                    0, 1:    payload = 8'hff;
                    2:       payload = 8'h0f;
                    default: ;
                endcase
                16'h1009:
                case (n)
                    0:       payload = 1;
                    3:       payload = 8'h47;
                    4:       payload = 8'h4e;
                    default: ;
                endcase
                16'h0c23:
                case (n)
                    0:       payload = 8'h04;
                    1:       payload = 8'h02;
                    2:       payload = 8'h5a;
                    default: ;
                endcase
                16'h0c14:
                case (n)
                    0:       payload = "N";
                    1:       payload = "-";
                    2:       payload = "G";
                    3:       payload = "a";
                    4:       payload = "g";
                    5:       payload = "e";
                    default: ;
                endcase
                default: ;
            endcase
        end
    endfunction
    assign rx_ready = state != EVENT;
    assign tx_valid = state == EVENT;
    always_comb begin
        tx_byte = 0;
        if (opcode == 16'h0401) begin
            if (!inquiry_second)
                case (index)
                    0:       tx_byte = 4;
                    1:       tx_byte = 0;
                    2:       tx_byte = 8'h0f;
                    3:       tx_byte = 4;
                    4:       tx_byte = 0;
                    5:       tx_byte = 1;
                    6:       tx_byte = opcode[7:0];
                    7:       tx_byte = opcode[15:8];
                    default: ;
                endcase
            else
                case (index)
                    0:       tx_byte = 4;
                    1:       tx_byte = 0;
                    2:       tx_byte = 1;
                    3:       tx_byte = 1;
                    4:       tx_byte = 0;
                    default: ;
                endcase
        end else
            case (index)
                0:       tx_byte = 4;
                1:       tx_byte = 0;
                2:       tx_byte = 8'h0e;
                3:       tx_byte = 4 + result_length;
                4:       tx_byte = 1;
                5:       tx_byte = opcode[7:0];
                6:       tx_byte = opcode[15:8];
                7:       tx_byte = status;
                default: tx_byte = payload(opcode, index - 8);
            endcase
    end
    task automatic start_event;
        begin
            result_length  <= payload_length(opcode);
            status         <= known(opcode) ? 0 : 1;
            index          <= 0;
            inquiry_second <= 0;
            total          <= opcode == 16'h0401 ? 9'd8 : 9'd8 + {1'b0, payload_length(opcode)};
            state          <= EVENT;
        end
    endtask
    always_ff @(posedge clk) begin
        if (reset) begin
            state          <= TYPE_LO;
            opcode         <= 0;
            remaining      <= 0;
            index          <= 0;
            total          <= 0;
            inquiry_second <= 0;
            result_length  <= 0;
            status         <= 0;
        end else
            case (state)
                TYPE_LO: if (rx_valid && rx_ready) state <= rx_byte == 1 ? TYPE_HI : TYPE_LO;
                TYPE_HI: if (rx_valid && rx_ready) state <= rx_byte == 0 ? OP_LO : TYPE_LO;
                OP_LO:
                if (rx_valid && rx_ready) begin
                    opcode[7:0] <= rx_byte;
                    state       <= OP_HI;
                end
                OP_HI:
                if (rx_valid && rx_ready) begin
                    opcode[15:8] <= rx_byte;
                    state        <= LENGTH;
                end
                LENGTH:
                if (rx_valid && rx_ready) begin
                    remaining <= rx_byte;
                    if (rx_byte == 0) start_event();
                    else state <= PARAMETERS;
                end
                PARAMETERS:
                if (rx_valid && rx_ready) begin
                    remaining <= remaining - 1'b1;
                    if (remaining == 1) start_event();
                end
                EVENT:
                if (tx_valid && tx_ready) begin
                    if (index + 1'b1 == total) begin
                        if (opcode == 16'h0401 && !inquiry_second) begin
                            index          <= 0;
                            total          <= 5;
                            inquiry_second <= 1;
                        end else begin
                            state <= TYPE_LO;
                            index <= 0;
                        end
                    end else index <= index + 1'b1;
                end
                default: state <= TYPE_LO;
            endcase
    end
endmodule
