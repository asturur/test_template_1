"""Simulation overlay for the existing C: NOR erase engine."""
from run import change


def nor_erase_line(source):
    source = change(source, 'output wire [31:0] debug_state', '''output wire [31:0] debug_state,
    output wire        mem_line,
    input  wire        mem_beat_valid,
    input  wire [63:0] mem_beat_data,
    input  wire        mem_beat_last''')
    source = change(source, 'IDLE = 0, ISSUE = 1, WAIT_MEM = 2;', 'IDLE = 0, ISSUE = 1, WAIT_MEM = 2, ERASE_SCAN = 3;')
    source = change(source, '    assign mem_valid = (state == ISSUE);', '''    assign mem_valid = (state == ISSUE);
    assign mem_line = state == ISSUE && op == OP_ERASE_READ;
    reg [7:0] erase_changed;
    reg [2:0] erase_beats;
    wire erase_beat = mem_beat_valid && state == WAIT_MEM && op == OP_ERASE_READ;
    wire [1:0] changed_words = {mem_beat_data[63:32] != 32'hffffffff,
                               mem_beat_data[31:0] != 32'hffffffff};
    wire [7:0] changed_next = erase_changed |
        (erase_beat ? ({6'b0, changed_words} << {erase_beats[1:0], 1'b0}) : 8'b0);
    function automatic [2:0] first_changed(input [7:0] mask);
        casez (mask)
            8'b???????1: first_changed = 0;
            8'b??????10: first_changed = 1;
            8'b?????100: first_changed = 2;
            8'b????1000: first_changed = 3;
            8'b???10000: first_changed = 4;
            8'b??100000: first_changed = 5;
            8'b?1000000: first_changed = 6;
            default:     first_changed = 7;
        endcase
    endfunction
    wire [2:0] erase_word = first_changed(erase_changed);''')
    source = change(source, '    always @(posedge clk) begin\n        rsp_valid', '''    always @(posedge clk) begin
        if (state == ISSUE && mem_ready && op == OP_ERASE_READ) begin
            erase_changed <= 0;
            erase_beats <= 0;
        end else if (erase_beat) begin
            if (erase_beats >= 4 || mem_beat_last != (erase_beats == 3))
                $fatal(1, "incorrect erase line beat shape");
            erase_changed <= changed_next;
            erase_beats <= erase_beats + 1'b1;
        end else if (state == ERASE_SCAN && erase_changed != 0) begin
            erase_changed[erase_word] <= 0;
        end
    end
    always @(posedge clk) begin
        rsp_valid''')
    start = source.index('                    end else if (op == OP_ERASE_READ && mem_rdata')
    end = source.index('                default: state <= IDLE;', start)
    return source[:start] + '''                    end else if (op == OP_ERASE_READ) begin
                        if (erase_beats + {2'b0, erase_beat} != 4)
                            $fatal(1, "short erase line may not modify backing");
                        state <= ERASE_SCAN;
                    end else begin
                        dirty_valid  <= 1;
                        dirty_sector <= mem_offset[21:9];
                        state        <= ERASE_SCAN;
                    end
                end
                ERASE_SCAN:
                if (erase_changed != 0) begin
                    mem_addr  <= BASE + {10'b0, erase_cursor[21:5], erase_word, 2'b0};
                    mem_write <= 1;
                    op        <= OP_ERASE_WRITE;
                    state     <= ISSUE;
                end else if (erase_cursor[21:5] == erase_end[21:5]) begin
                    erase_pending <= 0;
                    erase_polled  <= 0;
                    rsp_data      <= erase_result;
                    rsp_valid     <= 1;
                    state         <= IDLE;
                end else begin
                    erase_cursor <= erase_cursor + 22'd32;
                    mem_addr     <= BASE + {10'b0, erase_cursor} + 32'd32;
                    mem_write    <= 0;
                    op           <= OP_ERASE_READ;
                    state        <= ISSUE;
                end
''' + source[end:]


def connect_erase_line(source):
    source = change(source, '  ngage_ddr_arbiter outer (', '''  wire erase_line, request_line, beat_valid, beat_last;
  wire [63:0] beat_data;
  ngage_ddr_arbiter outer (
      .c_line(erase_line && fmv && xa == fma && !xw),
      .req_line(request_line),''')
    source = change(source, '      fpending\n      ,,\n  );', '''      fpending,
      ,
      ,
      erase_line,
      beat_valid,
      beat_data,
      beat_last
  );''')
    source = change(source, '.BULK_PERSISTENCE (BULK)', '.BULK_PERSISTENCE (BULK),\n      .LINE_REFILL      (1)')
    return change(source, "      .req_line(1'b0),", '''      .req_line(request_line),
      .rsp_beat_valid(beat_valid),
      .rsp_beat_data(beat_data),
      .rsp_beat_last(beat_last),''')
