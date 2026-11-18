`timescale 1ns / 1ps
module contract;
  reg clk = 0, reset = 1;
  always #5 clk = !clk;

  wire cyc, stb, write, code, lock, ack, error, line;
  wire [31:0] address, wdata, rdata, pc;
  wire [3:0] be;
  wire [2:0] cti;
  reg irq = 0, fiq = 0;
  ngage_cpu #(
      .LINE_REFILL(1)
  ) cpu (
      .clk(clk),
      .reset(reset),
      .irq(irq),
      .fiq(fiq),
      .wb_cyc(cyc),
      .wb_stb(stb),
      .wb_write(write),
      .wb_code(code),
      .wb_lock(lock),
      .wb_address(address),
      .wb_write_data(wdata),
      .wb_byte_enable(be),
      .wb_cycle_type(cti),
      .wb_burst_type(),
      .wb_ack(ack),
      .wb_error(error),
      .wb_read_data(rdata),
      .line_req(line),
      .line_addr(),
      .line_ready(1'b0),
      .line_reject(1'b0),
      .line_valid(1'b0),
      .line_data(64'b0),
      .line_wide(1'b0),
      .line_last(1'b0),
      .line_error(1'b0),
      .debug_pc(pc),
      .debug_cpsr(),
      .debug_instruction(),
      .debug_fetch()
  );

  wire slow_cyc, slow_stb, slow_idle, slow_ack, slow_error;
  wire [31:0] slow_rdata;
  wire ram_req, ram_write, ram_accept, ram_ack;
  wire [31:0] ram_address, ram_wdata, ram_rdata;
  wire [3:0] ram_be;
  ngage_cpu_memory_route route (
      .clk(clk),
      .reset(reset),
      .master_cyc(cyc),
      .master_stb(stb),
      .master_we(write),
      .master_code(code),
      .master_address(address),
      .master_data(wdata),
      .master_sel(be),
      .master_ack(ack),
      .master_error(error),
      .master_rdata(rdata),
      .slow_cyc(slow_cyc),
      .slow_stb(slow_stb),
      .slow_idle(slow_idle),
      .slow_ack(slow_ack),
      .slow_error(slow_error),
      .slow_rdata(slow_rdata),
      .ram_req(ram_req),
      .ram_we(ram_write),
      .ram_code(),
      .ram_address(ram_address),
      .ram_wdata(ram_wdata),
      .ram_be(ram_be),
      .ram_accept(ram_accept),
      .ram_ack(ram_ack),
      .ram_rdata(ram_rdata),
      .ram_pending(),
      .ram_response()
  );

  wire bridge_cyc, bridge_stb, bridge_write, bridge_code;
  wire [31:0] bridge_address, bridge_wdata;
  wire [3:0] bridge_be;
  wire device_cyc, device_stb, device_write, device_code, device_ack, device_error;
  wire [31:0] device_address, device_wdata, device_rdata;
  wire [3:0] device_be;
  ngage_upp_bus_bridge #(
      .REGISTERED_MASTER(1)
  ) bridge (
      .clk(clk),
      .reset(reset),
      .master_cyc(slow_cyc),
      .master_stb(slow_stb),
      .master_we(write),
      .master_code(code),
      .master_address(address),
      .master_data(wdata),
      .master_sel(be),
      .master_ack(slow_ack),
      .master_error(slow_error),
      .master_read_data(slow_rdata),
      .bus_cyc(bridge_cyc),
      .bus_stb(bridge_stb),
      .bus_we(bridge_write),
      .bus_code(bridge_code),
      .bus_address(bridge_address),
      .bus_data(bridge_wdata),
      .bus_sel(bridge_be),
      .bus_ack(device_ack),
      .bus_error(device_error),
      .bus_read_data(device_rdata),
      .idle(slow_idle)
  );
  ngage_upp_request_stage stage (
      .clk(clk),
      .reset(reset),
      .in_cyc(bridge_cyc),
      .in_stb(bridge_stb),
      .in_we(bridge_write),
      .in_code(bridge_code),
      .in_address(bridge_address),
      .in_data(bridge_wdata),
      .in_sel(bridge_be),
      .out_cyc(device_cyc),
      .out_stb(device_stb),
      .out_we(device_write),
      .out_code(device_code),
      .out_address(device_address),
      .out_data(device_wdata),
      .out_sel(device_be)
  );

  reg [31:0] rom[0:2047], ram[0:8191];
  integer cycle = 0, slow_delay = 0, ram_delay = 0, wait_words = 0;
  integer scalar_faults = 0, refill_faults = 0, refill_words = 0, clean_writes = 0;
  integer irq_writes = 0, fiq_writes = 0, swap_beats = 0;
  reg ram_pending = 0, ram_saved_write;
  reg [12:0] ram_index;
  reg [31:0] ram_saved_data;
  reg [ 3:0] ram_saved_be;
  integer lane, wait_cycles;
  reg [4095:0] program_file;
  wire fault_address = device_address == 32'h0c000020 || device_address == 32'h00001008;
  wire ready = device_cyc && device_stb && slow_delay == wait_cycles;
  assign device_ack = ready && !fault_address;
  assign device_error = ready && fault_address;
  assign device_rdata = (device_address < 8192) ? rom[device_address[12:2]] : 32'b0;
  assign ram_accept = ram_req && !ram_pending;
  assign ram_ack = ram_pending && ram_delay == 0;
  assign ram_rdata = ram[ram_index];

  always @(posedge clk)
    if (!reset) begin
      cycle <= cycle + 1;
      if (cycle == 30000) $fatal(1, "Watchdog PC=%h", pc);
      if (line) $fatal(1, "Unexpected 32-byte line request");
      if (cyc && stb && !ack && !error) wait_words <= wait_words + 1;

      if (device_cyc && !ready) slow_delay <= slow_delay + 1;
      else slow_delay <= 0;
      if (device_error && device_address == 32'h0c000020) begin
        if (device_code) $fatal(1, "Data abort classified as code");
        scalar_faults <= scalar_faults + 1;
        $display("DATA_FAULT cycle=%0d address=%h", cycle, device_address);
      end
      if (device_ack && device_address >= 32'h1000 && device_address < 32'h1008) begin
        if (!device_code || cti != 3'b010) $fatal(1, "Bad instruction burst");
        refill_words <= refill_words + 1;
      end
      if (device_error && device_address == 32'h1008) begin
        if (!device_code || (refill_faults == 0 && refill_words != 2))
          $fatal(1, "Missing preceding refill words");
        refill_faults <= refill_faults + 1;
        $display("REFILL_FAULT cycle=%0d address=%h good_words=%0d", cycle, device_address,
                 refill_words);
      end
      if (device_ack && device_write) begin
        case (device_address)
          32'h0c000000: begin
            irq <= device_wdata[0];
            irq_writes <= irq_writes + 1;
          end
          32'h0c000004: begin
            fiq <= device_wdata[0];
            fiq_writes <= fiq_writes + 1;
          end
          32'hf0000000: begin
            if (device_wdata != 32'h50415353 || scalar_faults != 1 || refill_faults == 0 ||
                        irq_writes != 2 || fiq_writes != 2 || swap_beats != 2 || clean_writes != 1 ||
                        ram[0] != 32'h55667788)
              $fatal(
                  1,
                  "Guest result=%h scalar_faults=%0d refill_faults=%0d IRQ=%0d FIQ=%0d SWP=%0d clean=%0d RAM0=%h",
                  device_wdata,
                  scalar_faults,
                  refill_faults,
                  irq_writes,
                  fiq_writes,
                  swap_beats,
                  clean_writes,
                  ram[0]
              );
            $display("PASS cycles=%0d scalar_wait_cycles=%0d swp_beats=%0d clean_writes=%0d",
                     cycle, wait_words, swap_beats, clean_writes);
            $finish;
          end
          default: $fatal(1, "Unexpected device write %h", device_address);
        endcase
      end

      if (swap_beats == 1 && !lock) $fatal(1, "SWPB lock dropped between beats");
      if (ram_accept) begin
        if (lock) begin
          if (ram_address[31:2] != 30'h02800000 || (ram_write != (swap_beats == 1)) ||
                    (ram_write && (ram_be != 4'b0010 || ram_wdata[15:8] != 8'haa)))
            $fatal(
                1,
                "Bad swap beat address=%h write=%b be=%h data=%h",
                ram_address,
                ram_write,
                ram_be,
                ram_wdata
            );
          swap_beats <= swap_beats + 1;
        end
        ram_pending <= 1;
        ram_delay <= wait_cycles + 1;
        ram_index <= ram_address[14:2];
        ram_saved_write <= ram_write;
        ram_saved_data <= ram_wdata;
        ram_saved_be <= ram_be;
      end else if (ram_ack) begin
        ram_pending <= 0;
        if (ram_saved_write) begin
          for (lane = 0; lane < 4; lane = lane + 1)
          if (ram_saved_be[lane]) ram[ram_index][lane*8+:8] <= ram_saved_data[lane*8+:8];
          if (ram_index == 0 && ram_saved_data == 32'h55667788 && ram_saved_be == 15)
            clean_writes <= clean_writes + 1;
        end
      end else if (ram_pending) ram_delay <= ram_delay - 1;
    end

  initial begin
    if (!$value$plusargs("program=%s", program_file) || !$value$plusargs("wait=%d", wait_cycles))
      $fatal(1, "Specify the guest image and wait profile");
    $readmemh(program_file, rom);
    repeat (4) @(negedge clk);
    reset = 0;
  end
endmodule
