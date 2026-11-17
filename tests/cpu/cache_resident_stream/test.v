`timescale 1ns / 1ps
module test;
    reg clk = 0, reset = 1, req = 0, wr = 0, early = 1, enabled = 1;
    reg resident = 1, ordinary = 1;
    reg inv = 0, lock = 0, mv = 0, mc = 0, mi = 0;
    reg [31:0] address = 0, din = 0;
    reg [3:0] mask = 15;
    wire mr, md, ready, valid, error, bus_valid, bus_write, empty;
    wire [31:0] data, bus_address, bus_data;
    wire [3:0] bus_mask;
    reg [31:0] mem[0:32767], golden[0:32767];
    integer edge_id = 0, stream = 0, na = 0, nc = 0, nr = 0;
    integer ext_reads = 0, ext_writes = 0, writes = 0;
    integer accept_edge[0:255], commit_edge[0:255];
    reg [31:0] qa[0:255], qd[0:255], qbefore[0:255], qafter[0:255];
    reg [3:0] qm[0:255];
    reg [1:0] dirty[0:1];
    reg measuring = 0, corrupt = 0;
    reg held = 0;
    reg [68:0] held_payload;
    integer i, n, target, old_writes, line_id;
    integer ah[0:15], ch[0:15];
    always #5 clk = ~clk;
  arm920_cache_access dut (
      .clk(clk),
      .reset(reset),
      .discard_refill(1'b0),
      .req_valid(req),
      .req_ready(ready),
      .req_mva(address),
      .req_physical(address),
      .req_write(wr),
      .req_early_read(early),
      .req_ordinary_store(ordinary),
      .req_resident_access(resident),
      .req_cache_enable(enabled),
      .req_cacheable(enabled),
      .req_bufferable(1'b1),
      .req_wdata(din),
      .req_byte_enable(mask),
      .response_valid(valid),
      .response_error(error),
      .response_data(data),
      .write_buffer_empty(empty),
      .write_buffer_error(),
      .line_req(),
      .line_addr(),
      .line_ready(1'b0),
      .line_reject(1'b0),
      .line_valid(1'b0),
      .line_data(64'b0),
      .line_wide(1'b0),
      .line_last(1'b0),
      .line_error(1'b0),
      .fast_lookup_enable(1'b0),
      .fast_lookup_address(32'b0),
      .data_probe_valid(1'b0),
      .data_probe_address(32'b0),
      .fast_lookup_valid(),
      .fast_lookup_checked(),
      .fast_lookup_line(),
      .fast_lookup_word(),
      .invalidate_all(inv),
      .lock_write(lock),
      .lock_base_in(6'b0),
      .round_robin(1'b1),
      .maint_valid(mv),
      .maint_clean(mc),
      .maint_invalidate(mi),
      .maint_all(1'b1),
      .maint_by_mva(1'b0),
      .maint_address(32'b0),
      .maint_way(6'b0),
      .maint_segment(3'b0),
      .maint_ready(mr),
      .maint_done(md),
      .maint_error(),
      .bus_valid(bus_valid),
      .bus_write(bus_write),
      .bus_address(bus_address),
      .bus_wdata(bus_data),
      .bus_byte_enable(bus_mask),
      .bus_ack(bus_valid),
      .bus_error(1'b0),
      .bus_rdata(mem[bus_address[16:2]])
  );

    // All DUT hierarchy is isolated in this observation adapter.
    `include "tests/cpu/cache_resident_stream/observe.vh"

    function [31:0] initial_word(input [31:0] addr);
        initial_word = 32'h51000000 ^ addr;
    endfunction
    function [31:0] merged(input [31:0] old, value, input [3:0] enables);
        integer byte_id;
        begin
            merged = old;
            for (byte_id = 0; byte_id < 4; byte_id = byte_id + 1)
                if (enables[byte_id]) merged[byte_id*8+:8] = value[byte_id*8+:8];
        end
    endfunction
    // Generator uses only stream number and accepted count, never DUT state.
    task offer(input integer id);
        begin
            case (stream)
                0: address = 'h100 + 4 * (id % 8);
                1: address = (id % 2 ? 'h1100 : 'h100) + 4 * ((id / 2) % 8);
                2: address = 'h108;
                3: address = 'h100 + 4 * (id % 4);
                4: address = 'h110 + 4 * (id % 4);
            endcase
            din = 32'hb1732905 ^ (32'h01030507 * (id + 1)) ^ (stream << 24);
            mask = stream == 2 ? (1 << (id % 4)) : (id % 15) + 1;
        end
    endtask
    always @(posedge clk) begin
        edge_id = edge_id + 1;
        if (!reset) begin
            if (bus_valid) begin
                if (measuring) begin
                    if (bus_write) ext_writes = ext_writes + 1;
                    else ext_reads = ext_reads + 1;
                end
                if (bus_write) begin
                    writes = writes + 1;
                    mem[bus_address[16:2]] <= merged(mem[bus_address[16:2]], bus_data, bus_mask);
                end
            end
            if (measuring) begin
                if (held && (!req || {address,din,mask,wr} !== held_payload))
                    $fatal(1, "held offer changed before acceptance");
                held = req && !ready;
                held_payload = {address,din,mask,wr};
                if (req)
                    $display("OFFER stream=%0d edge=%0d ready=%0d address=%h data=%h mask=%h", stream, edge_id, ready, address, din, mask);
                if (na < 2 || nc < 2)
                    $display("EDGE stream=%0d edge=%0d offer=%0d ready=%0d accept=%0d response=%0d mutation=%0d state=%0d addr=%h", stream, edge_id, req, ready, req && ready, valid, obs_commit, obs_state, address);
                if (req && ready) begin
                    if (na >= 256 || !wr || !mask) $fatal(1, "bad acceptance");
                    qa[na] = address; qd[na] = din; qm[na] = mask;
                    qbefore[na] = golden[address >> 2];
                    qafter[na] = merged(qbefore[na], din, mask);
                    golden[address >> 2] = qafter[na];
                    accept_edge[na] = edge_id;
                    $display("ACCEPT stream=%0d id=%0d edge=%0d address=%h data=%h mask=%h", stream, na, edge_id, address, din, mask);
                    na = na + 1;
                end
                if (valid) begin
                    if (error || nr >= na) $fatal(1, "unowned/extra/error response");
                    $display("RESPONSE stream=%0d id=%0d edge=%0d", stream, nr, edge_id);
                    nr = nr + 1;
                end
                if (obs_commit) begin
                    check_commit();
                    commit_edge[nc] = edge_id;
                    $display("COMMIT stream=%0d id=%0d edge=%0d slot=%0d word=%0d mask=%h data=%h", stream, nc, edge_id, obs_slot, qa[nc][4:2], qm[nc], qd[nc]);
                    // Capture actual write-port address before nonblocking updates.
                    obs_sample_slot = obs_slot;
                    obs_sample_word = qa[nc][4:2];
                    obs_sample_expected = qafter[nc];
                    line_id = qa[nc][12] ? 1 : 0;
                    dirty[line_id] = dirty[line_id] | (qa[nc][4] ? 2'b10 : 2'b01);
                    nc = nc + 1;
                    #1;
                    if (obs_stored_word !== obs_sample_expected)
                        $fatal(1, "RAM bytes after write mismatch");
                    if (obs_stored_dirty !== dirty[line_id])
                        $fatal(1, "tag dirty halves mismatch: got %b expected %b", obs_stored_dirty, dirty[line_id]);
                end
                if (nr > nc) $fatal(1, "response preceded actual RAM mutation");
            end
        end
    end
    task check_commit;
        reg [31:0] expected_enable;
        reg [31:0] expected_data;
        begin
            if (nc >= na) $fatal(1, "extra/unowned commit");
            expected_enable = {28'b0,qm[nc]} << (4 * qa[nc][4:2]);
            expected_data = qd[nc];
            if (corrupt && nc == 0) expected_data = expected_data ^ 1;
            if (!obs_tag_valid || obs_line_address !== {qa[nc][31:5],5'b0})
                $fatal(1, "commit slot ownership mismatch");
            if (obs_enable !== expected_enable) $fatal(1, "commit byte/word mask mismatch");
            for (integer byte_id = 0; byte_id < 4; byte_id = byte_id + 1)
                if (qm[nc][byte_id] && obs_write_data[(qa[nc][4:2]*32)+(byte_id*8)+:8] !== expected_data[byte_id*8+:8])
                    $fatal(1, "checker byte mismatch (negative control=%0d)", corrupt);
        end
    endtask
    task tick;
        begin @(posedge clk); #2; @(negedge clk); end
    endtask
    task read_word(input [31:0] addr);
        begin
            while (!ready) tick();
            req = 1; wr = 0; address = addr; mask = 15;
            tick(); req = 0;
            while (!valid) tick();
            if (error || data !== golden[addr >> 2]) $fatal(1, "ordinary readback mismatch addr=%h", addr);
            tick();
        end
    endtask
    task clean;
        begin
            while (!mr) tick();
            mv = 1; mc = 1; tick(); mv = 0;
            while (!md) tick();
            tick();
            while (!empty) tick();
            mc = 0;
        end
    endtask
    initial begin
        corrupt = $test$plusargs("corrupt_expected");
        for (i = 0; i < 32768; i = i + 1) begin
            mem[i] = initial_word(i*4); golden[i] = initial_word(i*4);
        end
        repeat (3) tick(); reset = 0; tick();
        for (stream = 0; stream < 5; stream = stream + 1) begin
            // Real misses/refills followed by reads seed both checked records.
            read_word('h100); read_word('h1100);
            read_word('h100); read_word('h1100);
            na = 0; nc = 0; nr = 0; held = 0;
            dirty[0] = 0; dirty[1] = 0;
            ext_reads = 0; ext_writes = 0;
            measuring = 1; req = 1; wr = 1; offer(0);
            while (na < 256) begin
                target = na; tick();
                if (na != target && na < 256) offer(na);
            end
            req = 0;
            while (nc < 256 || nr < 256) tick();
            repeat (3) tick();
            measuring = 0;
            if (na != 256 || nc != 256 || nr != 256 || ext_reads || ext_writes)
                $fatal(1, "stream counts/external traffic mismatch");
            for (i = 0; i < 16; i = i + 1) begin ah[i] = 0; ch[i] = 0; end
            for (i = 1; i < 256; i = i + 1) begin
                if (accept_edge[i]-accept_edge[i-1] > 15 || commit_edge[i]-commit_edge[i-1] > 15)
                    $fatal(1, "histogram overflow");
                ah[accept_edge[i]-accept_edge[i-1]]++;
                ch[commit_edge[i]-commit_edge[i-1]]++;
            end
            $display("SUMMARY stream=%0d accepted=%0d committed=%0d responses=%0d first_accept=%0d last_accept=%0d first_commit=%0d last_commit=%0d latency=%0d ext_reads=%0d ext_writes=%0d", stream, na, nc, nr, accept_edge[0], accept_edge[255], commit_edge[0], commit_edge[255], commit_edge[0]-accept_edge[0], ext_reads, ext_writes);
            for (i = 0; i < 16; i = i + 1)
                if (ah[i] || ch[i]) $display("HIST stream=%0d interval=%0d accepts=%0d commits=%0d", stream, i, ah[i], ch[i]);
            // Ordinary reads and clean are excluded from the measured clocks.
            for (n = 0; n < 8; n = n + 1) begin
                read_word('h100 + 4*n); read_word('h1100 + 4*n);
            end
            old_writes = writes;
            clean();
            target = 4 * (integer'(dirty[0][0]) + integer'(dirty[0][1]) + integer'(dirty[1][0]) + integer'(dirty[1][1]));
            if (writes-old_writes != target) $fatal(1, "wrong half writeback count got=%0d expected=%0d", writes-old_writes, target);
            for (n = 0; n < 8; n = n + 1)
                if (mem['h40+n] !== golden['h40+n] || mem['h440+n] !== golden['h440+n])
                    $fatal(1, "clean backing bytes mismatch");
            old_writes = writes; clean();
            if (writes != old_writes) $fatal(1, "clean did not clear dirty halves");
            $display("VERIFIED stream=%0d dirty0=%b dirty1=%b clean_words=%0d second_clean_words=0", stream, dirty[0], dirty[1], target);
        end
        $display("PASS: five independent 256-store resident streams, RAM/response/dirty/readback checks");
        $finish;
    end
    initial begin #2000000; $fatal(1, "timeout"); end
endmodule
