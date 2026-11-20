module refill_candidate_tb;
  reg clk = 0;
  reg reset = 1;
  reg code_request = 0, data_request = 0;
  reg [31:0] code_addr = 0, data_addr = 0;
  reg write = 0;
  reg [3:0] sel = 4'hf;
  reg [2:0] code_cti = 3'b010, data_cti = 3'b010;
  reg [1:0] bte = 0;
  wire cyc, stb, selected_write, candidate, data_owner;
  wire [31:0] addr;
  wire [ 3:0] selected_sel;
  wire [ 2:0] cti;
  wire [ 1:0] selected_bte;
  reg lock = 0, scalar_ack = 0, line_ready = 0, line_reject = 0;
  wire cpu_ack, cpu_error, cpu_no_late_error;
  wire scalar, scalar_lock, line_req;

  ngage2_zap_wb_merger merger (
      .i_clk(clk),
      .i_reset(reset),
      .i_c_wb_stb(code_request),
      .i_c_wb_cyc(code_request),
      .i_c_wb_wen(write),
      .i_c_wb_sel(sel),
      .i_c_wb_dat(32'd0),
      .i_c_wb_adr(code_addr),
      .i_c_wb_cti(code_cti),
      .i_c_wb_bte(bte),
      .i_d_wb_stb(data_request),
      .i_d_wb_cyc(data_request),
      .i_d_wb_wen(write),
      .i_d_wb_sel(sel),
      .i_d_wb_dat(32'd0),
      .i_d_wb_adr(data_addr),
      .i_d_wb_cti(data_cti),
      .i_d_wb_bte(bte),
      .o_wb_cyc(cyc),
      .o_wb_stb(stb),
      .o_wb_wen(selected_write),
      .o_wb_sel(selected_sel),
      .o_wb_adr(addr),
      .o_wb_cti(cti),
      .o_wb_bte(selected_bte),
      .o_wb_line_candidate(candidate),
      .o_dbg_data_owner(data_owner),
      .i_wb_ack(cpu_ack),
      .i_wb_err(cpu_error),
      .i_wb_no_late_error(cpu_no_late_error)
  );

  ngage_arm9v2_refill #(
      .ENABLE(1)
  ) refill (
      .clk(clk),
      .reset(reset),
      .cpu_cyc(cyc && stb),
      .cpu_lock(lock),
      .cpu_line_candidate(candidate),
      .cpu_address(addr),
      .cpu_write(selected_write),
      .cpu_sel(selected_sel),
      .cpu_cti(cti),
      .cpu_bte(selected_bte),
      .cpu_ack(cpu_ack),
      .cpu_error(cpu_error),
      .cpu_no_late_error(cpu_no_late_error),
      .line_no_late_error(1'b1),
      .wb_cyc(scalar),
      .wb_lock(scalar_lock),
      .wb_ack(scalar_ack),
      .wb_error(1'b0),
      .wb_data(32'd0),
      .line_req(line_req),
      .line_ready(line_ready),
      .line_reject(line_reject),
      .line_valid(1'b0),
      .line_data(64'd0),
      .line_wide(1'b0),
      .line_last(1'b0),
      .line_error(1'b0)
  );

  task tick;
    begin
      #1 clk = 1;
      #1 clk = 0;
      #1;
    end
  endtask

  task check_packet;
    input data;
    input [31:0] address;
    input expected;
    begin
      reset = 1;
      tick;
      if (candidate || scalar || line_req || cyc || stb)
        $fatal(1, "Unexpected request during reset");
      reset = 0;
      code_request = !data;
      data_request = data;
      code_addr = data ? 32'h0c000000 : address;
      data_addr = data ? address : 32'h0c000000;
      tick;
      if (data_owner !== data || !cyc || !stb || addr !== address)
        $fatal(1, "Wrong arbitration packet for %h owner=%b", address, data);
      if (candidate !== expected || line_req !== expected || scalar !== !expected)
        $fatal(1, "Wrong classification at %h owner=%b", address, data);
    end
  endtask

  integer owner;
  initial begin
    for (owner = 0; owner < 2; owner = owner + 1) begin
      check_packet(owner[0], 32'h00000000, 1);
      check_packet(owner[0], 32'h007effe0, 1);
      check_packet(owner[0], 32'h007f0000, 0);
      check_packet(owner[0], 32'h01ffffe0, 0);
      check_packet(owner[0], 32'h02000000, 1);
      check_packet(owner[0], 32'h023fffe0, 1);
      check_packet(owner[0], 32'h02400000, 0);
      check_packet(owner[0], 32'h03ffffe0, 0);
      check_packet(owner[0], 32'h04000000, 1);
      check_packet(owner[0], 32'h047fffe0, 1);
      check_packet(owner[0], 32'h04800000, 0);
      check_packet(owner[0], 32'h09ffffe0, 0);
      check_packet(owner[0], 32'h0a000000, 1);
      check_packet(owner[0], 32'h0affffe0, 1);
      check_packet(owner[0], 32'h0b000000, 0);
      check_packet(owner[0], 32'hffffffe0, 0);
      check_packet(owner[0], 32'h0a000004, 0);

      write = 1;
      check_packet(owner[0], 32'h0a000000, 0);
      write = 0;
      sel   = 4'h7;
      check_packet(owner[0], 32'h0a000000, 0);
      sel = 4'hf;
      bte = 2'd1;
      check_packet(owner[0], 32'h0a000000, 0);
      bte = 0;
      code_cti = 3'b111;
      data_cti = 3'b111;
      check_packet(owner[0], 32'h0a000000, 0);
      code_cti = 3'b010;
      data_cti = 3'b010;
    end

    // A scalar final acknowledgement changes owner and classifier together.
    code_cti = 3'b111;
    check_packet(0, 32'h0a000000, 0);
    data_addr = 32'h02000020;
    data_request = 1;
    scalar_ack = 1;
    tick;
    scalar_ack = 0;
    if (!data_owner || addr != data_addr || !candidate || !line_req || scalar)
      $fatal(1, "Candidate did not advance with the data owner");

    // Before readiness, cancelling the client's request drops the offer.
    code_request = 0;
    data_request = 0;
    tick;
    if (cyc || stb || scalar || line_req)
      $fatal(1, "Cancelled request reached the line or scalar peer");

    check_packet(1, 32'h0a000000, 1);
    lock = 1;
    #1;
    if (line_req || !scalar || !scalar_lock)
      $fatal(1, "A live lock must send the request to the scalar peer");
    tick;
    lock = 0;
    #1;
    if (line_req || !scalar) $fatal(1, "A locked burst must keep scalar ownership");

    check_packet(1, 32'h04000000, 1);
    line_ready = 1;
    tick;
    line_ready = 0;
    if (line_req || scalar || cpu_ack) $fatal(1, "Accepted line leaked a scalar request");
    line_reject = 1;
    tick;
    line_reject = 0;
    scalar_ack  = 1;
    #1;
    if (!scalar || !cpu_ack || line_req || cpu_no_late_error)
      $fatal(1, "Rejected line did not fall back to an ordinary scalar acknowledgement");
    scalar_ack = 0;

    $display("PASS range edges, owner handoff, cancellation, lock and scalar fallback");
    $finish;
  end
endmodule
