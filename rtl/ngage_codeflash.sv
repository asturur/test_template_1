// Code NOR command/status and PMM sector controller. Backing words are in
// DDR; PMM programming uses physical 1->0 NOR semantics. This differs from
// the software overlay's first write to a seeded halfword and is documented.
module ngage_codeflash #(
    parameter [31:0] BASE = 32'h30000000
) (
    output wire [ 2:0] array_mode,
    input  wire        clk,
    input  wire        reset,
    input  wire        cold_reset,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire [31:0] req_address,
    input  wire [31:0] req_data,
    input  wire [ 3:0] req_be,
    output reg         rsp_valid,
    output reg         rsp_error,
    output reg  [31:0] rsp_data,
    output wire        mem_valid,
    input  wire        mem_ready,
    output reg         mem_write,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_data,
    output reg  [ 3:0] mem_be,
    input  wire        mem_done,
    input  wire [31:0] mem_rdata,
    output reg         dirty_valid,
    output reg  [13:0] dirty_sector,
    output wire        pending,
    output wire        idle
);
    localparam IDLE       = 0, ISSUE = 1, WAIT_MEM = 2;
    localparam READ_ARRAY = 0, PROGRAM_READ = 1, PROGRAM_WRITE = 2;
    reg [1:0] state = IDLE, operation = READ_ARRAY;
    // Separate state owner for each logical die. Mapping logical selects to
    // schematic references D310/D311/D313 still requires independent proof.
    wire [2:0] identify, sr_mode, intel_program, lock_mode;
    wire [1:0] unlock[0:2], lock_bank[0:2];
    wire [7:0] die_state[0:2];
    reg  [7:0] die_next;
    reg  [1:0] chip = 0;
    reg [31:0] saved_address = 0, saved_data = 0;
    reg [3:0] saved_be = 0;
    wire [31:0] aligned = {req_address[31:2], 2'b00};
    wire [31:0] half_address = aligned + (req_be == 12 ? 2 : 0);
    wire half_ok = req_be == 3 || req_be == 12;
    wire [15:0] value = req_be == 12 ? req_data[31:16] : req_data[15:0];
    wire [1:0] target = (aligned < 32'h01000000) ?
        0 : (aligned >= 32'h02000000 && aligned < 32'h03000000) ? 1 : 2;
    wire chip_hit = (aligned < 32'h01000000) || (aligned >= 32'h02000000 && aligned < 32'h03000000)
        || (aligned >= 32'h04000000 && aligned < 32'h05000000);
    wire [31:0] chip_offset = half_address -
        (target == 0 ? 32'h0 : (target == 1 ? 32'h02000000 : 32'h04000000));
    wire pmm_hit = half_address >= 32'h007f0000 && half_address < 32'h00800000;
    wire rom_hit, ram_hit, cdrive_hit, pmm_map;
    wire [24:0] rom_offset;
    wire die_update = req_valid && req_ready && req_write && chip_hit && !cdrive_hit && half_ok;
    genvar die;
    generate
        for (die = 0; die < 3; die = die + 1) begin : nor_die
            ngage_am29n643_state chip_state (
                .clk       (clk),
                .reset     (reset && state == IDLE),
                .update    (die_update && target == die),
                .next_state(die_next),
                .state     (die_state[die])
            );
            assign identify[die]      = die_state[die][0];
            assign sr_mode[die]       = die_state[die][1];
            assign intel_program[die] = die_state[die][2];
            assign lock_mode[die]     = die_state[die][3];
            assign unlock[die]        = die_state[die][5:4];
            assign lock_bank[die]     = die_state[die][7:6];
        end
    endgenerate
    ngage_rom_map mapper (
        aligned,
        rom_hit,
        rom_offset,
        ram_hit,
        cdrive_hit,
        pmm_map
    );
    wire [31:0] decoded;
    ngage_flash_read_decode dec (
        saved_address,
        mem_rdata,
        1'b1,
        1'b1,
        decoded
    );
    assign array_mode = ~(identify | sr_mode | intel_program | lock_mode |
                          {(|unlock[2]),(|unlock[1]),(|unlock[0])});
    assign idle = (state == IDLE);
    assign pending = (state != IDLE) || intel_program[0] || intel_program[1] || intel_program[2] ||
        unlock[0] != 0 || unlock[1] != 0 || unlock[2] != 0;
    assign req_ready = state == IDLE && !reset;
    assign mem_valid = state == ISSUE;
    function automatic [31:0] mask32(input [3:0] be);
        begin
            mask32 = {{8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}}};
        end
    endfunction
    function automatic [16:0] ident(input [31:0] a);
        begin
            case (a)
                0:       ident = {1'b1, 16'h0001};
                2:       ident = {1'b1, 16'h257e};
                6:       ident = {1'b1, 16'h0042};
                28:      ident = {1'b1, 16'h2502};
                30:      ident = {1'b1, 16'h2500};
                default: ident = 0;
            endcase
        end
    endfunction
    reg [16:0] idlo, idhi;
    always @* begin
        idlo = ident(aligned - (target == 0 ? 0 : target == 1 ? 32'h02000000 : 32'h04000000));
        idhi = ident(aligned + 2 - (target == 0 ? 0 : target == 1 ? 32'h02000000 : 32'h04000000));
    end
    // Decode only state transitions here; the selected die owns and resets
    // its state independently. Memory data transactions remain shared.
    always @* begin
        die_next = die_state[target];
        if (die_update) begin
            if (unlock[target] == 3 || intel_program[target]) begin
                die_next[5:4] = 0;
                die_next[2]   = 0;
                if (pmm_hit && intel_program[target]) die_next[1] = 1;
            end else if (value == 16'hff || value == 16'hf0) begin
                die_next[0]   = 0;
                die_next[1]   = 0;
                die_next[2]   = 0;
                die_next[3]   = 0;
                die_next[5:4] = 0;
            end else if (value == 16'h40) die_next[2] = 1;
            else if (value == 16'h50) die_next[1] = 0;
            else if (value == 16'h60) begin
                die_next[3]   = 1;
                die_next[7:6] = chip_offset[22:21];
            end else if (lock_mode[target] && (value == 16'h01 || value == 16'hd0)) die_next[3] = 0;
            else if ((chip_offset & 32'h7ff) == 32'h2aa && value == 16'haa) die_next[5:4] = 1;
            else if (unlock[target] == 1 && (chip_offset & 32'h7ff) == 32'h554 && value == 16'h55)
                die_next[5:4] = 2;
            else if (unlock[target] == 2 && (chip_offset & 32'h7ff) == 32'h2aa &&
                     value == 16'h90) begin
                die_next[0]   = 1;
                die_next[5:4] = 0;
            end else
                if (unlock[target] == 2 && (chip_offset & 32'h7ff) == 32'h2aa && value == 16'ha0)
                die_next[5:4] = 3;
            else if (unlock[target] == 2 && value == 16'hc0 &&
                     ((chip_offset >> 1) & 32'hfff) == 32'h555 && ((chip_offset >> 13) & 7) <= 5)
                die_next[5:4] = 0;
        end
    end
    always @(posedge clk) begin
        rsp_valid   <= 0;
        rsp_error   <= 0;
        dirty_valid <= 0;
        if (cold_reset) begin
            state     <= IDLE;
            operation <= READ_ARRAY;
        end else if (reset && state == IDLE) begin
            // Per-die modules reset their own state on this edge.
        end else
            case (state)
                IDLE:
                if (req_valid && req_ready) begin
                    rsp_data <= 0;
                    chip     <= target;
                    if (!chip_hit || cdrive_hit) begin
                        rsp_valid <= 1;
                        rsp_error <= 1;
                    end else if (req_write && !half_ok) begin
                        rsp_valid <= 1;
                        rsp_error <= 1;
                    end else if (req_write) begin
                        if (unlock[target] == 3 || intel_program[target]) begin
                            if (!pmm_hit) begin
                                rsp_valid <= 1;
                                rsp_error <= 1;
                            end else begin
                                saved_address <= aligned;
                                saved_data    <= req_data;
                                saved_be      <= req_be;
                                mem_addr      <= BASE + 32'h01800000 + (aligned - 32'h007f0000);
                                mem_write     <= 0;
                                mem_be        <= 15;
                                operation     <= PROGRAM_READ;
                                state         <= ISSUE;
                            end
                        end else if (value == 16'hff || value == 16'hf0) begin
                            rsp_valid <= 1;
                        end else if (value == 16'h40) begin
                            rsp_valid <= 1;
                        end else if (value == 16'h50) begin
                            rsp_valid <= 1;
                        end else if (value == 16'h60) begin
                            rsp_valid <= 1;
                        end else
                            if (lock_mode[target] && (value == 16'h01 || value == 16'hd0)) begin
                            rsp_valid <= 1;
                        end else if ((chip_offset & 32'h7ff) == 32'h2aa && value == 16'haa) begin
                            rsp_valid <= 1;
                        end else if (unlock[target] == 1 && (chip_offset & 32'h7ff) == 32'h554 &&
                                     value == 16'h55) begin
                            rsp_valid <= 1;
                        end else if (unlock[target] == 2 && (chip_offset & 32'h7ff) == 32'h2aa &&
                                     value == 16'h90) begin
                            rsp_valid <= 1;
                        end else if (unlock[target] == 2 && (chip_offset & 32'h7ff) == 32'h2aa &&
                                     value == 16'ha0) begin
                            rsp_valid <= 1;
                        end else if (unlock[target] == 2 && value == 16'hc0 &&
                                     ((chip_offset >> 1) & 32'hfff) == 32'h555 &&
                                     ((chip_offset >> 13) & 7) <= 5) begin
                            rsp_valid <= 1;
                        end else if ((chip_offset == 0 || chip_offset == 32'haaaa) &&
                                     value == 16'h90 && unlock[target] == 0)
                            rsp_valid <= 1;
                        else begin
                            rsp_valid <= 1;
                            rsp_error <= 1;
                        end
                    end else if (sr_mode[target]) begin
                        rsp_valid <= 1;
                        rsp_data  <= 32'h00800080 & mask32(req_be);
                    end else if (lock_mode[target] && aligned[22:21] == lock_bank[target]) begin
                        rsp_valid <= 1;
                        rsp_data  <= 32'h00010001 & mask32(req_be);
                    end else if (identify[target]) begin
                        rsp_valid <= 1;
                        if (((req_be & 3) != 0 && !idlo[16]) || ((req_be & 12) != 0 && !idhi[16]))
                            rsp_error <= 1;
                        else
                            rsp_data <= {
                                (req_be & 12) != 0 ? idhi[15:0] : 16'b0,
                                (req_be & 3) != 0 ? idlo[15:0] : 16'b0
                            };
                    end else if (rom_hit || pmm_map) begin
                        saved_address <= aligned;
                        mem_addr <= BASE + (
                            pmm_map ? 32'h01800000 + (aligned - 32'h007f0000) : {7'b0, rom_offset});
                        mem_write <= 0;
                        mem_be <= 15;
                        operation <= READ_ARRAY;
                        state <= ISSUE;
                    end else begin
                        rsp_valid <= 1;
                        rsp_error <= 1;
                    end
                end
                ISSUE:   if (mem_ready) state <= WAIT_MEM;
                WAIT_MEM:
                if (mem_done) begin
                    if (operation == READ_ARRAY) begin
                        rsp_data  <= decoded;
                        rsp_valid <= 1;
                        state     <= IDLE;
                    end else if (operation == PROGRAM_READ) begin
                        if ((mem_rdata & (saved_data | ~mask32(saved_be))) == mem_rdata) begin
                            rsp_valid <= 1;
                            state     <= IDLE;
                        end else begin
                            mem_write <= 1;
                            mem_data  <= mem_rdata & (saved_data | ~mask32(saved_be));
                            mem_be    <= saved_be;
                            operation <= PROGRAM_WRITE;
                            state     <= ISSUE;
                        end
                    end else begin
                        dirty_valid  <= 1;
                        dirty_sector <= 14'd8192 + {7'b0, saved_address[15:9]};
                        rsp_valid    <= 1;
                        state        <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
    end
endmodule
