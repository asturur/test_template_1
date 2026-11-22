`timescale 1ns / 1ps
module tb;
  reg clk = 0;
  always #5 clk = ~clk;

  reg reset = 1, cold = 1, req = 0, write_op = 0;
  reg [31:0] address = 0, write_data = 0;
  reg [3:0] lanes = 15;
  wire done, claim, bad, init_done;
  wire [31:0] read_data;

  ngage_board #(
      .SIMIF_ENABLE (1),
      .KEYPAD_ENABLE(1)
  ) dut (
      .clk(clk),
      .rst(reset),
      .init_rst(cold),
      .cyc(req),
      .stb(req),
      .we(write_op),
      .adr(address),
      .din(write_data),
      .sel(lanes),
      .commit(req && !reset),
      .cfg_lcd(1'b1),
      .cfg_keypad(1'b1),
      .cfg_clocks(1'b1),
      .keys(27'd0),
      .sim_present(1'b1),
      .dma_irq_pending(1'b0),
      .sim_fiq_pending(1'b0),
      .claim(claim),
      .ready(done),
      .unmodeled(bad),
      .dout(read_data),
      .init_done(init_done)
  );
  defparam dut.upp.peripherals.REGISTER_RESPONSES = 1;

  task step;
    begin
      @(negedge clk);
      #1;
    end
  endtask

  task transfer;
    input wr, expected_error;
    input [31:0] addr, data, expected;
    input [3:0] mask;
    integer clocks;
    begin
      step();
      req = 1;
      write_op = wr;
      address = addr;
      write_data = data;
      lanes = mask;
      clocks = 0;
      while (!done) begin
        step();
        clocks = clocks + 1;
        if (clocks > 128) $fatal(1, "Request timeout at %h", addr);
      end
      if (!claim || bad !== expected_error || (!wr && read_data !== expected))
        $fatal(
            1, "Request failed at %h data=%h expected=%h error=%b", addr, read_data, expected, bad
        );
      repeat (2) step();
      req = 0;
      step();
    end
  endtask

  task put;
    input [31:0] addr, value;
    input [3:0] mask;
    begin
      transfer(1, 0, addr, value, 0, mask);
    end
  endtask

  task read_word;
    input [31:0] addr, expected;
    begin
      transfer(0, 0, addr, 0, expected, 15);
    end
  endtask

  localparam UPLOAD = 32'h0c030000;
  localparam NOS = 32'h0c1003f0;
  localparam UPLOAD_END = 32'h0c03fffc;
  localparam NOS_END = 32'h0c10fffc;
  localparam MDI_PTR = 32'h0c1003e8;
  localparam AUX = 32'h0c06ff00;
  initial begin
    repeat (4) step();
    cold = 0;
    wait (init_done);
    step();
    reset = 0;
    read_word(UPLOAD, 0);
    read_word(NOS, 0);
    read_word(UPLOAD_END, 0);
    read_word(NOS_END, 0);
    put(UPLOAD, 32'h12345678, 15);
    put(UPLOAD + 4, 32'h01020304, 15);
    put(NOS, 32'haabbccdd, 15);
    put(NOS + 4, 32'h11223344, 15);
    put(UPLOAD_END, 32'h89abcdef, 15);
    put(NOS_END, 32'h76543210, 15);
    put(UPLOAD, 32'hff, 1);
    put(UPLOAD, 32'h8000, 2);
    put(UPLOAD, 32'h510000, 4);
    put(UPLOAD, 32'h23000000, 8);
    put(NOS, 32'h2345, 3);
    put(NOS, 32'hff000000, 12);
    transfer(1, 1, NOS, 32'h0, 0, 5);
    put(MDI_PTR, 32'h00030002, 15);
    put(AUX, 32'h3a4b5c6d, 15);
    read_word(MDI_PTR, 32'h00030002);
    read_word(UPLOAD, 32'h235180ff);
    read_word(NOS, 32'hff002345);
    read_word(UPLOAD + 4, 32'h01020304);
    read_word(NOS + 4, 32'h11223344);

    // Reject a request whose owner withdraws before authorization.
    step();
    req = 1;
    write_op = 1;
    address = NOS_END;
    write_data = 32'hdeadbeef;
    reset = 1;
    step();
    req   = 0;
    reset = 0;
    read_word(MDI_PTR, 0);
    read_word(UPLOAD, 32'h235180ff);
    read_word(NOS, 32'hff002345);
    read_word(UPLOAD_END, 32'h89abcdef);
    read_word(NOS_END, 32'h76543210);
    read_word(AUX, 32'h3a4b5c6d);

    step();
    reset = 1;
    cold  = 1;
    step();
    if (init_done) $fatal(1, "Cold reset left initialization complete");
    cold = 0;
    wait (init_done);
    step();
    reset = 0;
    read_word(UPLOAD, 0);
    read_word(NOS, 0);
    read_word(UPLOAD + 4, 0);
    read_word(NOS + 4, 0);
    read_word(UPLOAD_END, 0);
    read_word(NOS_END, 0);
    read_word(AUX, 0);
    $display(
        "PASS upload and NOS lanes, bank/beat isolation, MDI/aux exclusion, warm retain, and cold re-clear");
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "Timeout");
  end
endmodule
