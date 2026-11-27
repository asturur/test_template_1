`define WZ cpu.u_arm925t.u_zap
`define WD `WZ.l_generate_with_cache_mmu.u_data_cache
`define WM `WZ.l_merger_for_core_with_cache_mmu.u_zap_wb_merger
wire         obs_valid = `WM.o_wb_cyc && `WM.o_wb_stb;
wire         obs_write = obs_valid && `WM.o_wb_wen;
wire         obs_ack = obs_valid && `WM.i_wb_ack && !`WM.i_wb_err;
wire         obs_error = obs_valid && `WM.i_wb_err;
wire [  3:0] obs_owner = `WM.o_dbg_data_owner ? `WD.state_ff : 4'd0;
wire [  7:0] obs_ctl = {`WM.o_wb_cti, `WM.o_wb_sel, block_write};
wire [127:0] obs_block = block_write ? block_data : 128'd0;
wire [200:0] obs_payload = {lock, address, obs_ctl, wdata, obs_block};
wire         eviction = `WD.u_zap_cache_fsm.state_ff[`WD.u_zap_cache_fsm.CLEAN_SINGLE];
reg stalled = 0, prev_ack = 0, prev_write = 0, prev_eob = 0;
reg [200:0] previous_payload;
reg [  3:0] previous_owner;
integer offer_clocks = 0, stall_clocks = 0, read_acks = 0, write_acks = 0, wr_errors = 0;
integer tag_acks = 0, scalar_evict_acks = 0, block_evict_acks = 0, posted_acks = 0;
integer read_to_write = 0, write_changed = 0, tag_changed = 0, owner_changes = 0;
integer last_beat_handoffs = 0, stalled_resets = 0;
reg [63:0] write_hash = 64'hcbf29ce484222325;

function automatic [63:0] hash_write;
    input [63:0] h, value;
    hash_write = (h ^ value) * 64'h00000100000001b3;
endfunction

always @(posedge clk)
    if (reset) begin
        stalled  = 0;
        prev_ack = 0;
    end else begin
        if (obs_ack && !obs_write) read_acks++;
        if (prev_ack && prev_eob && obs_valid && previous_owner != obs_owner) last_beat_handoffs++;
        if (stalled && (!obs_write || obs_payload !== previous_payload))
            $fatal(1, "Changed write packet before completion at %h", address);
        if (obs_write) begin
            offer_clocks++;
            if (!obs_ack && !obs_error) stall_clocks++;
            if (obs_error) wr_errors++;
            if (obs_ack) begin
                write_acks++;
                if (obs_owner == 4'b0010) tag_acks++;
                if (obs_owner == 4'b1000) posted_acks++;
                if (obs_owner == 4'b0001 && eviction) begin
                    if (block_write) block_evict_acks++;
                    else scalar_evict_acks++;
                end
            end
            if (prev_ack && !prev_write) read_to_write++;
            if (prev_ack && prev_write) begin
                if (obs_payload[159:0] !== previous_payload[159:0]) write_changed++;
                if (previous_owner != obs_owner) owner_changes++;
                else if (obs_owner == 4'b0010 && obs_payload[159:128] !== previous_payload[159:128])
                    tag_changed++;
            end
            write_hash =
                hash_write(write_hash, {address, cycle[21:0], obs_ctl, obs_ack, obs_error});
            write_hash = hash_write(write_hash, {31'd0, lock, wdata});
            if (block_write) begin
                write_hash = hash_write(write_hash, block_data[63:0]);
                write_hash = hash_write(write_hash, block_data[127:64]);
            end
        end
        stalled          = obs_write && !obs_ack && !obs_error;
        prev_ack         = obs_ack;
        prev_eob         = obs_ctl[7:5] == 3'b111;
        prev_write       = obs_write;
        previous_owner   = obs_owner;
        previous_payload = obs_payload;
    end

// Reset the modeled peer after it captures a stalled write and restart
// the checked guest. Neither old nor new request ownership may survive.
initial
    if ($test$plusargs("reset-in-write")) begin
        @(negedge reset);
        wait (ram_pending && ram_saved_write && !ram_ack && stalled);
        @(negedge clk);
        stalled_resets++;
        reset = 1;
        repeat (6) @(negedge clk);
        if (obs_valid || ram_pending) $fatal(1, "Reset left an owned write");
        reset = 0;
    end

task check_wb_data;
    begin
        if (!tag_acks || !tag_changed || !stall_clocks || !posted_acks || !wr_errors)
            $fatal(
                1,
                "Incomplete write census tag=%0d changed=%0d stalls=%0d post=%0d errs=%0d",
                tag_acks,
                tag_changed,
                stall_clocks,
                posted_acks,
                wr_errors
            );
        if ($test$plusargs("reset-in-write") && stalled_resets != 1)
            $fatal(1, "Stalled write reset did not fire");
        $display(
            "WB_DATA offer=%0d stalled=%0d read_ack=%0d write_ack=%0d write_error=%0d tag=%0d evict_scalar=%0d evict_native=%0d post=%0d read_to_write=%0d changed=%0d tag_changed=%0d owner_changes=%0d last_beat_handoffs=%0d stalled_resets=%0d hash=%h",
            offer_clocks, stall_clocks, read_acks, write_acks, wr_errors, tag_acks,
            scalar_evict_acks, block_evict_acks, posted_acks, read_to_write, write_changed,
            tag_changed, owner_changes, last_beat_handoffs, stalled_resets, write_hash);
    end
endtask
`undef WM
`undef WD
`undef WZ
