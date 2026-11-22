// Delayed, byte-enabled DDR transport peer. The transport's physical reset
// drain is tested separately; this peer cancels logical ownership on cold.
module upp_ddr_test_peer (
    input  wire        clk,
    input  wire        cold,
    input  wire        complete,
    input  wire        req,
    input  wire        we,
    input  wire [16:2] addr,
    input  wire [31:0] wdata,
    input  wire [ 3:0] be,
    output reg         ack = 0,
    output reg  [31:0] rdata = 0,
    input  wire        clear,
    output reg         clear_done = 0,
    output reg         pending = 0
);
  reg [63:0] memory[0:16383];
  reg [16:2] saved_addr;
  reg [31:0] saved_data;
  reg [3:0] saved_be;
  reg saved_we;
  reg [2:0] countdown;
  reg [13:0] scrub_index = 0;
  reg scrub_phase = 0;
  integer byte_lane;
  integer initial_index;
  integer clear_count = 0;
  integer accepted = 0;

  initial begin
    for (initial_index = 0; initial_index < 16384; initial_index = initial_index + 1)
    memory[initial_index] = 64'hdeadbeefbadf00d;
  end

  always @(posedge clk) begin
    if (cold) begin
      ack         <= 0;
      pending     <= 0;
      clear_done  <= 0;
      scrub_index <= 0;
      scrub_phase <= 0;
    end else begin
      if (!clear) clear_done <= 0;
      else if (!clear_done) begin
        if (req || pending || ack) $fatal(1, "DDR clear collided with a live raw request");
        // Make the DDR sweep finish after the local scrub to test
        // that init_done waits for both.
        scrub_phase <= !scrub_phase;
        if (scrub_phase) begin
          memory[scrub_index] <= 0;
          if (&scrub_index) begin
            clear_count <= clear_count + 1;
            clear_done  <= 1;
            scrub_index <= 0;
          end else scrub_index <= scrub_index + 1'b1;
        end
      end

      if (ack) begin
        if (!req) ack <= 0;
      end else if (pending) begin
        if (!req || {addr, we, wdata, be} !== {saved_addr, saved_we, saved_data, saved_be})
          $fatal(1, "UPP changed a request before completion");
        if (complete && countdown != 0) countdown <= countdown - 1'b1;
        if (complete && countdown == 0) begin
          if (saved_we) begin
            for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
            if (saved_be[byte_lane])
              memory[saved_addr[16:3]][{saved_addr[2], 5'b0} + byte_lane*8 +: 8] <=
                                    saved_data[byte_lane*8 +: 8];
          end else begin
            rdata <= saved_addr[2] ? memory[saved_addr[16:3]][63:32] :
                                                memory[saved_addr[16:3]][31:0];
          end
          pending <= 0;
          ack <= 1;
        end
      end else if (req) begin
        saved_addr <= addr;
        saved_data <= wdata;
        saved_be   <= be;
        saved_we   <= we;
        countdown  <= 3'd5;
        pending    <= 1;
        accepted   <= accepted + 1;
      end
    end
  end
endmodule
