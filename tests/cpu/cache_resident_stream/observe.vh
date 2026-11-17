// DUT-specific adapter. Commit means the actual data-RAM write enable sampled
// BEFORE the rising edge, not a queued request, store intent or early response.
// Ports below feed the independent checker; update only this file if hierarchy
// changes. Post-edge memory taps verify that the port write really took effect.
wire [3:0] obs_state = dut.state;
wire [31:0] obs_enable = dut.bank.lines.write_enable;
wire obs_commit = |obs_enable;
wire [8:0] obs_slot = dut.bank.lines.write_index;
wire [255:0] obs_write_data = dut.bank.lines.write_line;
reg [8:0] obs_sample_slot = 0;
reg [2:0] obs_sample_word = 0;
reg [31:0] obs_sample_expected;
wire [31:0] obs_tag[0:63], obs_post_tag[0:63];
wire [31:0] obs_words[0:7];
genvar ow, ot;
generate
    for (ow = 0; ow < 8; ow = ow + 1) begin : observe_words
        assign obs_words[ow] = dut.bank.lines.words[ow].ram.memory[obs_sample_slot];
    end
    for (ot = 0; ot < 64; ot = ot + 1) begin : observe_tags
        assign obs_tag[ot] = dut.bank.tags.ways[ot].packed_dirty_tags.tag_ram.memory[obs_slot[2:0]];
        assign obs_post_tag[ot] = dut.bank.tags.ways[ot].packed_dirty_tags.tag_ram.memory[obs_sample_slot[2:0]];
    end
endgenerate
wire obs_tag_valid = dut.bank.tags.valid[obs_slot[2:0]][obs_slot[8:3]];
wire [31:0] obs_line_address = {obs_tag[obs_slot[8:3]][23:0], obs_slot[2:0], 5'b0};
wire [31:0] obs_stored_word = obs_words[obs_sample_word];
wire [1:0] obs_stored_dirty = obs_post_tag[obs_sample_slot[8:3]][25:24];
