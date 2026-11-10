// Transfer a single C:/PMM sector between DDR and the HPS sector protocol.
// This is a transport component only: mounting, header validation, dirty
// scheduling, reset coordination and integration are separate responsibilities.
module ngage_save_sector_bridge #(
    parameter integer        C_SECTORS   = 8192,
    parameter integer        PMM_SECTORS = 128,
    parameter         [31:0] C_BASE      = 32'h31400000,
    parameter         [31:0] PMM_BASE    = 32'h31800000,
    parameter integer        RAW_IMAGES  = 0,
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
  MEM_ISSUE=5,MEM_WAIT=6,BUF_LOW=7,BUF_HIGH=8,START_WRITE=9,WAIT_WRITE=10,FAIL=11,LOAD_LO_WAIT=12,LOAD_HI_WAIT=13;
    reg [ 3:0] state = IDLE;
    reg        load_op = 0;
    reg [13:0] saved_sector = 0;
    reg [ 7:0] word_index = 0;
    reg [31:0] base = 0, snapshot = 0;
    reg [15:0] low = 0;
    wire sec_ready, sec_done, sec_error;
    wire [15:0] local_dout;
    wire sec_start = (state == START_READ || state == START_WRITE);
    wire [7:0] local_addr = {
        word_index[6:0], (state == LOAD_HI || state == LOAD_HI_WAIT || state == BUF_HIGH)
    };
    wire local_we = (state == BUF_LOW || state == BUF_HIGH);
    wire [15:0] local_data = state == BUF_HIGH ? snapshot[31:16] : snapshot[15:0];
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
    assign mem_valid = state == MEM_ISSUE;
    assign mem_be    = 4'hf;
    always @(posedge clk) begin
        done  <= 0;
        error <= 0;
        if (reset) begin
            state <= IDLE;
        end else
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
                        base<=sector_index<C_SECTORS ? C_BASE+({18'b0,sector_index}<<9) : PMM_BASE+(({18'b0,sector_index}-C_SECTORS)<<9);
                        if (load_from_disk) state <= START_READ;
                        else begin
                            mem_addr <= sector_index < C_SECTORS ?
                                C_BASE + ({18'b0, sector_index} << 9) :
                                PMM_BASE + (({18'b0, sector_index}-C_SECTORS) << 9);
                            mem_write <= 0;
                            state <= MEM_ISSUE;
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
                    end else state <= LOAD_LO_WAIT;
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
endmodule
