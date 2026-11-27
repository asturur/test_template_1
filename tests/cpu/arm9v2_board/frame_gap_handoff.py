"""Generate a pin-compatible v5 SDRAM scalar handoff experiment."""

from textwrap import indent

from frame_gap_early import original, swap


def generate(out, admit=False):
    adapter = original('rtl/ngage_sdram_adapter.v')
    adapter = swap(adapter, 'RESP = 3, WAIT_DROP = 4', 'WAIT_DROP = 4')
    response = '''if (discard || phone_reset) state <= IDLE;
else begin
    ack   <= 1;
    state <= WAIT_DROP;
end'''
    adapter = swap(adapter, 'state     <= line_op ? IDLE : RESP;',
                   'if (line_op) state <= IDLE;\n                            else ' +
                   indent(response, ' ' * 28).lstrip())
    adapter = swap(adapter, 'end else state <= RESP;', 'end else ' +
                   indent(response, ' ' * 24).lstrip())
    adapter = swap(adapter, '''                RESP: begin
                    if (discard || phone_reset) state <= IDLE;
                    else begin
                        ack   <= 1;
                        state <= WAIT_DROP;
                    end
                end
''', '')
    if admit:
        adapter = swap(adapter, '    wire [31:0] data = scrub ?',
                       '''    // IDLE may present a new scalar request while capturing that same request.
    // Thereafter the registered address and direction take over without a gap.
    wire launch = state == IDLE && scrub_done && req && !phone_reset && !rst && !init;
    wire bus_write = launch ? we : write_op;
    wire bus_line = !launch && line_op;
    wire bus_scrub = scrub && !launch;
    wire [24:0] bus_address = launch ? {addr[24:2], 2'b00} : address;
    wire bus_bank = bus_address[23];
    wire [31:0] data = bus_scrub ?''')
        adapter = swap(adapter, 'mask = scrub ?', 'mask = bus_scrub ?')
        adapter = swap(adapter, '{2{line_op || write_op}}', '{2{bus_line || bus_write}}')
        adapter = swap(adapter, "line_op ? address[22:1] : {address[22:2], 1'b0}",
                       "bus_line ? bus_address[22:1] : {bus_address[22:2], 1'b0}")
        adapter = swap(adapter, 'write_op && (high || selected_ack)',
                       '!launch && write_op && (high || selected_ack)')
        for direction, write_condition in [('rd', '!'), ('wr', '')]:
            adapter = swap(adapter, f"assign {direction}     = (state == ISSUE && {write_condition}write_op) ? (bank",
                           f"assign {direction}     = ((state == ISSUE || launch) && {write_condition}bus_write) ? (bus_bank")
    (out / 'ngage_sdram_adapter.v').write_text(adapter)
