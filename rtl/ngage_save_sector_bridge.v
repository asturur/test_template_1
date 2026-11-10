// Transfer a single C:/PMM sector between DDR and the HPS sector protocol.
// This is a transport component only: mounting, header validation, dirty
// scheduling, reset coordination and integration are separate responsibilities.
module ngage_save_sector_bridge #(
    parameter integer        C_SECTORS   = 8192,
    parameter integer        PMM_SECTORS = 128,
    parameter         [31:0] C_BASE      = 32'h31400000,
    parameter         [31:0] PMM_BASE    = 32'h31800000,
    parameter integer        RAW_IMAGES  = 0,
    parameter integer        BULK        = 0,
    parameter integer        SD_TIMEOUT  = 104000000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        load_from_disk,
    input  wire [13:0] sector_index,
    output wire        ready,
    output reg         done,
    output reg         error,
    output wire        mem_valid,
    input  wire        mem_ready,
    output reg         mem_write,
    output reg  [31:0] mem_addr,
    output reg  [31:0] mem_data,
    output wire [ 3:0] mem_be,
    input  wire        mem_done,
    input  wire [31:0] mem_rdata,
    input  wire        bulk_error,
    input  wire        bulk_read_valid,
    output wire        bulk_read_ready,
    input  wire [63:0] bulk_read_data,
    input  wire        bulk_read_last,
    output wire        bulk_write_valid,
    input  wire        bulk_write_ready,
    output wire [63:0] bulk_write_data,
    output wire        bulk_write_last,
    output wire [31:0] sd_lba,
    output wire        sd_rd,
    output wire        sd_wr,
    input  wire        sd_ack,
    input  wire [12:0] hps_addr,
    input  wire [15:0] hps_dout,
    input  wire        hps_we,
    output wire [15:0] hps_din
);
    localparam IDLE=0,START_READ=1,WAIT_READ=2,LOAD_LO=3,LOAD_HI=4,
  MEM_ISSUE=5,MEM_WAIT=6,BUF_LOW=7,BUF_HIGH=8,START_WRITE=9,WAIT_WRITE=10,FAIL=11,LOAD_LO_WAIT=12,LOAD_HI_WAIT=13,
  BULK_ISSUE=14,BULK_READ=15,BULK_COPY=16,BULK_READ_END=17,
  BULK_LOAD_ADDR=18,BULK_LOAD_WORD=19,BULK_WRITE=20,BULK_WRITE_END=21;
    reg [ 4:0] state = IDLE;
    reg        load_op = 0;
    reg [13:0] saved_sector = 0;
    reg [ 7:0] word_index = 0;
    reg [31:0] base = 0, snapshot = 0;
    reg [15:0] low = 0;
    wire sec_ready, sec_done, sec_error;
    wire [15:0] local_dout;
    wire sec_start = (state == START_READ || state == START_WRITE);
    reg [5:0] sector_beat = 0;
    reg [1:0] halfword = 0;
    reg [63:0] beat_data = 0;
    reg bulk_complete = 0;
    wire [1:0] load_address = state == BULK_LOAD_WORD && halfword != 3 ? halfword + 1'b1 : halfword;
    wire [7:0] scalar_local_addr = {
        word_index[6:0], (state == LOAD_HI || state == LOAD_HI_WAIT || state == BUF_HIGH)
    };
    wire [7:0] local_addr = BULK != 0 ? {sector_beat, load_address} : scalar_local_addr;
    wire local_we = BULK != 0 ? state == BULK_COPY : (state == BUF_LOW || state == BUF_HIGH);
    wire [15:0] scalar_local_data = state == BUF_HIGH ? snapshot[31:16] : snapshot[15:0];
    wire [15:0] local_data = BULK != 0 ? beat_data[halfword*16+:16] : scalar_local_data;
    assign bulk_read_ready  = BULK != 0 && state == BULK_READ && !reset;
    assign bulk_write_valid = BULK != 0 && state == BULK_WRITE && !reset;
    assign bulk_write_data  = beat_data;
    assign bulk_write_last  = &sector_beat;
    wire [31:0] file_lba = RAW_IMAGES ? (saved_sector < C_SECTORS ?
        {18'b0, saved_sector} : {18'b0, saved_sector} - C_SECTORS) :
        32'd1 + {18'b0, saved_sector};
    ngage_sd_sector #(
        .TIMEOUT(SD_TIMEOUT)
    ) sector (
        .clk         (clk),
        .reset       (reset),
        .start       (sec_start),
        .write_sector(state == START_WRITE),
        .start_lba   (file_lba),
        .ready       (sec_ready),
        .done        (sec_done),
        .error       (sec_error),
        .local_addr  (local_addr),
        .local_din   (local_data),
        .local_we    (local_we),
        .local_dout  (local_dout),
        .sd_lba      (sd_lba),
        .sd_rd       (sd_rd),
        .sd_wr       (sd_wr),
        .sd_ack      (sd_ack),
        .hps_addr    (hps_addr),
        .hps_dout    (hps_dout),
        .hps_we      (hps_we),
        .hps_din     (hps_din)
    );
    assign ready     = state == IDLE && !reset;
    assign mem_valid = !reset && (state == MEM_ISSUE || state == BULK_ISSUE);
    assign mem_be    = 4'hf;
    always @(posedge clk) begin
        done  <= 0;
        error <= 0;
        if (reset) begin
            state         <= IDLE;
            bulk_complete <= 0;
        end else if (BULK != 0 && state != IDLE && state != FAIL && mem_done && bulk_error) begin
            done  <= 1;
            error <= 1;
            state <= FAIL;
        end else begin
            if (BULK != 0 && mem_done) bulk_complete <= 1;
            case (state)
                IDLE:
                if (start && ready) begin
                    if (sector_index >= C_SECTORS + PMM_SECTORS) begin
                        done  <= 1;
                        error <= 1;
                    end else begin
                        saved_sector <= sector_index;
                        load_op <= load_from_disk;
                        word_index <= 0;
                        sector_beat <= 0;
                        halfword <= 0;
                        bulk_complete <= 0;
                        base<=sector_index<C_SECTORS ? C_BASE+({18'b0,sector_index}<<9) : PMM_BASE+(({18'b0,sector_index}-C_SECTORS)<<9);
                        if (load_from_disk) state <= START_READ;
                        else begin
                            mem_addr <= sector_index < C_SECTORS ?
                                C_BASE + ({18'b0, sector_index} << 9) :
                                PMM_BASE + (({18'b0, sector_index}-C_SECTORS) << 9);
                            mem_write <= 0;
                            state <= BULK != 0 ? BULK_ISSUE : MEM_ISSUE;
                        end
                    end
                end
                START_READ: if (sec_ready) state <= WAIT_READ;
                WAIT_READ:
                if (sec_done) begin
                    if (sec_error) begin
                        done  <= 1;
                        error <= 1;
                        state <= FAIL;
                    end else if (BULK != 0) begin
                        mem_addr  <= base;
                        mem_write <= 1;
                        state     <= BULK_ISSUE;
                    end else state <= LOAD_LO_WAIT;
                end
                BULK_ISSUE: if (mem_ready) state <= load_op ? BULK_LOAD_ADDR : BULK_READ;
                BULK_READ:
                if (bulk_read_valid) begin
                    if (bulk_read_last != (&sector_beat)) begin
                        done  <= 1;
                        error <= 1;
                        state <= FAIL;
                    end else begin
                        beat_data <= bulk_read_data;
                        halfword  <= 0;
                        state     <= BULK_COPY;
                    end
                end
                BULK_COPY: begin
                    halfword <= halfword + 1'b1;
                    if (halfword == 3) begin
                        if (&sector_beat) state <= BULK_READ_END;
                        else begin
                            sector_beat <= sector_beat + 1'b1;
                            state       <= BULK_READ;
                        end
                    end
                end
                BULK_READ_END: if (bulk_complete) state <= START_WRITE;
                BULK_LOAD_ADDR: state <= BULK_LOAD_WORD;
                BULK_LOAD_WORD: begin
                    beat_data[halfword*16+:16] <= local_dout;
                    halfword                   <= halfword + 1'b1;
                    if (halfword == 3) state <= BULK_WRITE;
                end
                BULK_WRITE:
                if (bulk_write_ready) begin
                    if (&sector_beat) state <= BULK_WRITE_END;
                    else begin
                        sector_beat <= sector_beat + 1'b1;
                        state       <= BULK_LOAD_ADDR;
                    end
                end
                BULK_WRITE_END:
                if (mem_done) begin
                    done  <= 1;
                    state <= IDLE;
                end
                LOAD_LO_WAIT: state <= LOAD_LO;
                LOAD_HI_WAIT: state <= LOAD_HI;
                LOAD_LO: begin
                    low   <= local_dout;
                    state <= LOAD_HI_WAIT;
                end
                LOAD_HI: begin
                    mem_addr  <= base + ({24'b0, word_index} << 2);
                    mem_data  <= {local_dout, low};
                    mem_write <= 1;
                    state     <= MEM_ISSUE;
                end
                MEM_ISSUE: if (mem_ready) state <= MEM_WAIT;
                MEM_WAIT:
                if (mem_done) begin
                    if (load_op) begin
                        if (word_index == 127) begin
                            done  <= 1;
                            state <= IDLE;
                        end else begin
                            word_index <= word_index + 1'b1;
                            state      <= LOAD_LO_WAIT;
                        end
                    end else begin
                        snapshot <= mem_rdata;
                        state    <= BUF_LOW;
                    end
                end
                BUF_LOW: state <= BUF_HIGH;
                BUF_HIGH: begin
                    if (word_index == 127) state <= START_WRITE;
                    else begin
                        word_index <= word_index + 1'b1;
                        mem_addr   <= base + (({24'b0, word_index} + 1) << 2);
                        mem_write  <= 0;
                        state      <= MEM_ISSUE;
                    end
                end
                START_WRITE: if (sec_ready) state <= WAIT_WRITE;
                WAIT_WRITE:
                if (sec_done) begin
                    done  <= 1;
                    error <= sec_error;
                    state <= sec_error ? FAIL : IDLE;
                end
                FAIL: state <= FAIL;  // An uncertain HPS transaction requires explicit reset.
                default: state <= FAIL;
            endcase
        end
    end
endmodule
