// Synthetic GSM T=0 test card matching scratch/simif-investigation/test_card.h.
// Fabricated test identities; this is not a physical card dump or a full SIM.
// Byte interface is a transaction-level bridge, not electrical SIM timing.
module ngage_test_sim (
    input  wire       clk,
    input  wire       reset,
    input  wire       tx_valid,
    input  wire [7:0] tx_data,
    input  wire       rx_pop,
    output wire       rx_valid,
    output wire [7:0] rx_data,
    output reg        overflow,
    output wire [6:0] available,
    output wire       tx_will_emit
);
    reg [7:0] fifo[0:63], header[0:3];
    reg [5:0] head, tail;
    reg [6:0] used;
    reg [15:0] selected, directory, file_id;
    reg     [ 2:0] header_count;
    reg     [ 1:0] select_left;
    reg     [ 7:0] terminal_left;
    reg     [ 5:0] next_tail;
    reg     [ 6:0] next_used;
    reg     [15:0] next_file;
    reg     [ 7:0] length;
    integer        i;
    assign tx_will_emit=tx_valid && ((terminal_left==1) ||
     (terminal_left==0 && select_left==1) ||
     (terminal_left==0 && select_left==0 && header_count==4));
    assign rx_valid = used != 0;
    assign rx_data = used != 0 ? fifo[head] : 8'b0;
    assign available = used;
    task emit;
        input [7:0] value;
        begin
            if (next_used < 64) begin
                fifo[next_tail] <= value;
                next_tail = next_tail + 1'b1;
                next_used = next_used + 1'b1;
            end else overflow <= 1;
        end
    endtask
    function supported_ef;
        input [15:0] f;
        begin
            case (f)
                16'h6fb7,16'h6f05,16'h6fae,16'h6f38,16'h6f7e,16'h6fad,16'h6f07,16'h6f78,16'h2fe2:
                supported_ef = 1;
                default: supported_ef = 0;
            endcase
        end
    endfunction
    function [7:0] ef_length;
        input [15:0] f;
        begin
            case (f)
                16'h6fb7: ef_length = 3;
                16'h6f38: ef_length = 16;
                16'h6f7e: ef_length = 11;
                16'h6fad: ef_length = 4;
                16'h6f07: ef_length = 9;
                16'h6f78: ef_length = 2;
                16'h2fe2: ef_length = 10;
                default:  ef_length = 1;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        if (reset) begin
            head          <= 0;
            tail          <= 0;
            used          <= 0;
            selected      <= 16'h3f00;
            directory     <= 16'h3f00;
            file_id       <= 0;
            header_count  <= 0;
            select_left   <= 0;
            terminal_left <= 0;
            overflow      <= 0;
            for (i = 0; i < 4; i = i + 1) header[i] <= 0;
        end else begin
            next_tail = tail;
            next_used = used;
            if (rx_pop && used != 0) begin
                head <= head + 1'b1;
                next_used = next_used - 1'b1;
            end
            if (tx_valid) begin
                if (terminal_left != 0) begin
                    terminal_left <= terminal_left - 1'b1;
                    if (terminal_left == 1) begin
                        emit(8'h90);
                        emit(0);
                    end
                end else if (select_left != 0) begin
                    next_file = {file_id[7:0], tx_data};
                    file_id     <= next_file;
                    select_left <= select_left - 1'b1;
                    if (select_left == 1) begin
                        if(next_file==16'h3f00 || next_file==16'h7f20 ||
         (next_file==16'h2fe2 && directory==16'h3f00) ||
         (supported_ef(
                                next_file
                            ) && next_file != 16'h2fe2 && directory == 16'h7f20)) begin
                            selected <= next_file;
                            if (next_file == 16'h3f00 || next_file == 16'h7f20)
                                directory <= next_file;
                            emit(8'h9f);
                            emit((next_file == 16'h3f00 || next_file == 16'h7f20) ? 8'h16 : 8'h0f);
                        end else begin
                            emit(8'h94);
                            emit(4);
                        end
                    end
                end else if (header_count != 4) begin
                    header[header_count[1:0]] <= tx_data;
                    header_count              <= header_count + 1'b1;
                end else begin
                    header_count <= 0;
                    if (header[0] != 8'ha0) begin
                        emit(8'h6e);
                        emit(0);
                    end
     else if(header[1]==8'h10 && header[2]==0 && header[3]==0 && tx_data!=0)begin
                        terminal_left <= tx_data;
                        emit(8'h10);
                    end
     else if(header[1]==8'ha4 && header[2]==0 && header[3]==0 && tx_data==2)begin
                        file_id     <= 0;
                        select_left <= 2;
                        emit(8'ha4);
                    end
     else if(header[1]==8'hc0 && header[2]==0 && header[3]==0 && tx_data==15 && supported_ef(
                            selected
                        )) begin
                        length = ef_length(selected);
                        emit(8'hc0);
                        emit(0);
                        emit(0);
                        emit(0);
                        emit(length);
                        emit(selected[15:8]);
                        emit(selected[7:0]);
                        emit(4);
                        emit(0);
                        emit(8'h0f);
                        emit(8'hff);
                        emit(8'hff);
                        emit(1);
                        emit(2);
                        emit(0);
                        emit(0);
                        emit(8'h90);
                        emit(0);
                    end else if(header[1]==8'hf2 && header[2]==0 && header[3]==0 && (tx_data==15 || tx_data==22))begin
                        emit(8'hf2);
                        emit(0);
                        emit(0);
                        emit(0);
                        emit(0);
                        emit(directory[15:8]);
                        emit(directory[7:0]);
                        emit(directory == 16'h3f00 ? 1 : 2);
                        emit(0);
                        emit(0);
                        emit(0);
                        emit(0);
                        emit(0);
                        emit(9);
                        emit(8'hb0);
                        emit(0);
                        if (tx_data == 22) begin
                            emit(0);
                            emit(2);
                            emit(0);
                            emit(8'h83);
                            emit(8'h8a);
                            emit(8'h83);
                            emit(8'h8a);
                        end
                        emit(8'h90);
                        emit(0);
                    end else if(header[1]==8'hb0 && header[2]==0 && header[3]==0 && tx_data==ef_length(
                            selected
                        ) && supported_ef(
                            selected
                        )) begin
                        emit(8'hb0);
                        case (selected)
                            16'h2fe2: begin
                                emit(8'h98);
                                emit(8'h10);
                                emit(8'h10);
                                emit(8'h32);
                                emit(8'h54);
                                emit(8'h76);
                                emit(8'h98);
                                emit(8'h10);
                                emit(8'h32);
                                emit(8'hf8);
                            end
                            16'h6f78: begin
                                emit(0);
                                emit(1);
                            end
                            16'h6f07: begin
                                emit(8);
                                emit(8'h09);
                                emit(8'h10);
                                emit(8'h10);
                                emit(8'h10);
                                emit(8'h32);
                                emit(8'h54);
                                emit(8'h76);
                                emit(8'h98);
                            end
                            16'h6fad: begin
                                emit(0);
                                emit(0);
                                emit(0);
                                emit(2);
                            end
                            16'h6f7e: begin
                                for (i = 0; i < 10; i = i + 1) emit(8'hff);
                                emit(1);
                            end
                            16'h6fae: emit(3);
                            16'h6f38: for (i = 0; i < 16; i = i + 1) emit(0);
                            16'h6f05: emit(1);
                            16'h6fb7: begin
                                emit(8'h11);
                                emit(8'hf2);
                                emit(8'hff);
                            end
                        endcase
                        emit(8'h90);
                        emit(0);
                    end else begin
                        emit(8'h6d);
                        emit(0);
                    end
                end
            end
            tail <= next_tail;
            used <= next_used;
        end
    end
endmodule
