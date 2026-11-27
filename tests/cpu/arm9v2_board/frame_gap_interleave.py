"""Build a test-only JTFRAME overlay with donor-style SDRAM bank selection."""

from frame_gap_early import original, swap


def generate(out):
    adapter = original('rtl/ngage_sdram_adapter.v')
    adapter = swap(adapter, 'output wire [ 1:0] ba_line', 'output wire [ 3:0] ba_line')
    adapter = swap(adapter, '{2{line_op || write_op}}', '{4{line_op || write_op}}')
    adapter = swap(adapter, 'wire                    bank = address[23];',
                   'wire [1:0]              bank = address[13:12];')
    adapter = adapter.replace("[{1'b0, bank}]", '[bank]')
    adapter = adapter.replace("(bank ? 4'b0010 : 4'b0001)", "(4'b0001 << bank)")
    adapter = swap(adapter, "    assign ba_addr = line_op ? address[22:1] : {address[22:2], 1'b0};",
                   """    wire [21:0] bank_address = {1'b0, address[23:14], address[11:1]};
    assign ba_addr = line_op ? bank_address : {bank_address[21:1], 1'b0};""")
    (out / 'ngage_sdram_adapter.v').write_text(adapter)

    controller = original('rtl/sdram/jtframe_sdram64.v')
    controller = swap(controller, 'input  wire [1:0] line_read', 'input  wire [3:0] line_read')
    controller = swap(controller, "wire [1:0] column_requests;\n  assign stop_requests[3:2] = 2'b0;",
                      'wire [3:0] column_requests;')
    for bank in (2, 3):
        controller = swap(controller, f""".BALEN    (BA{bank}_LEN),
          .AUTOPRECH(BA{bank}_AUTOPRECH)
      ) u_bank{bank} (
          .line_read     (1'b0),
          .stop_request  (),
          .column_request(),""", f""".BALEN    (BA{bank}_LEN),
          .AUTOPRECH(BA{bank}_AUTOPRECH),
          .DYNAMIC_LINE(DYNAMIC_LINE),
          .SHORT_READS (SHORT_READS)
      ) u_bank{bank} (
          .line_read     (line_read[{bank}]),
          .stop_request  (stop_requests[{bank}]),
          .column_request(column_requests[{bank}]),""")
    controller = swap(controller, 'end else begin : no_extra_banks',
                      "end else begin : no_extra_banks\n      assign stop_requests[3:2] = 2'b0, column_requests[3:2] = 2'b0;")
    controller = swap(controller, "else if (stop_requests[1] || column_requests[1]) bg = 4'b0010;",
                      """else if (stop_requests[1] || column_requests[1]) bg = 4'b0010;
      else if (stop_requests[2] || column_requests[2]) bg = 4'b0100;
      else if (stop_requests[3] || column_requests[3]) bg = 4'b1000;""")
    (out / 'jtframe_sdram64.v').write_text(controller)



def overlay_phone(bench):
    bench = swap(bench, 'wire [1:0] ba_line;', 'wire [3:0] ba_line;')
    bench = swap(bench, '.BA2_LEN(16),.BA3_LEN(16)', '.BANKS(4),.BA2_LEN(256),.BA3_LEN(256)')
    bench = swap(bench, '.BA0_WEN(1),.BA1_WEN(1)', '.BA0_WEN(1),.BA1_WEN(1),.BA2_WEN(1),.BA3_WEN(1)')
    for bank in (2, 3):
        bench = swap(bench, f".ba{bank}_addr(22'b0)", f".ba{bank}_addr(ba_addr)")
        bench = swap(bench, f".ba{bank}_din(16'b0)", f".ba{bank}_din(ba_din)")
        bench = swap(bench, f".ba{bank}_dsn(2'b11)", f".ba{bank}_dsn(ba_dsn)")
    return bench
