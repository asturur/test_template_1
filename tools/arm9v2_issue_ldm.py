"""Generate two-word ARM LDM issue with an address hint and serial fallback."""


def issue_hinted_ldm(source, edit):
    source = wire_paired_load_data(source, edit)
    source = edit(source, "w_cls_next = w_cls_of(w_next);\n            memory_state_next = 4'd4;",
                  "w_cls_next = w_cls_of(w_next);\n            memory_state_next = 4'd5;")
    source = edit(source, 'wire [31:2] lookup_address =', 'wire [31:2] nominal_lookup_address =')
    source = edit(source, '\tassign o_data_wb_adr_nxt =', '''    // Point the D-cache RAM at the second word on the split edge. Its
    // registered tag/data then align with the second request's check address.
    wire [31:2] lookup_address = paired_ldm_split ? w[398:369] + 30'd1 : nominal_lookup_address;
\tassign o_data_wb_adr_nxt =''')
    start = source.index('module ngage2_arm9v2_decode (')
    end = source.index('\nendmodule', start)
    decode = issue_decode_overlay(source[start:end], edit)
    decode = avoid_known_crossings(decode, edit)
    source = source[:start] + decode + source[end:]
    start = source.index('module ngage2_arm9v2_front_decode (')
    end = source.index('\nendmodule', start)
    front = pair_dependency_port(source[start:end], edit)
    front = edit(front, '\t\t.i_locked(i_locked),', '\t\t.i_locked(i_locked),\n        .i_pair_dependencies(i_pair_dependencies),')
    source = source[:start] + front + source[end:]
    return check_collapsed_packets(source, edit)


def wire_paired_load_data(source, edit):
    start = source.index('module ngage2_arm9v2_core (')
    end = source.index('\nendmodule', start)
    source = source[:start] + issue_core_overlay(source[start:end], edit) + source[end:]
    start = source.index('module ngage2_zap_dcache (')
    end = source.index('\nendmodule', start)
    source = source[:start] + cache_overlay(source[start:end], edit) + source[end:]
    source = edit(source, '\twire [31:0] dc_short_data;', '''\twire [31:0] dc_short_data;
    wire [31:0] dc_short_next_word;
    wire dc_short_next_valid;
    wire [31:0] dc_pair_m_address;''')
    source = edit(source, '.i_data_short_data(dc_short_data),', '''.i_data_short_data(dc_short_data),
                .i_data_short_next_word(dc_short_next_word),
                .i_data_short_next_valid(dc_short_next_valid),
                .o_dc_pair_m_address(dc_pair_m_address),''')
    source = edit(source, '.o_short_data(dc_short_data),', '''.o_short_data(dc_short_data),
                .o_short_next_word(dc_short_next_word),
                .o_short_next_valid(dc_short_next_valid),
                .i_pair_m_address(dc_pair_m_address),''')
    return edit(source, '\t\t\tngage2_zap_cache #(\n\t\t\t\t.CACHE_SIZE(CODE_CACHE_SIZE),', '''
            // synthesis translate_off
`ifndef SYNTHESIS
            always @(posedge i_clk)
                if (!s_reset && g_arm9.u_arm9_core.paired_ldm_first)
                    if (u_data_cache.short_pair_matches_w !=
                        (u_data_cache.short_pair_address == cpu_daddr))
                        $fatal(1, "Retimed LDM cache address match diverged at %h", cpu_daddr);
`endif
            // synthesis translate_on
\t\t\tngage2_zap_cache #(
\t\t\t\t.CACHE_SIZE(CODE_CACHE_SIZE),'''.lstrip('\n'))


def pair_dependency_port(module, edit):
    module = edit(module, '\ti_locked,', '\ti_locked,\n    i_pair_dependencies,')
    return edit(module, '\tinput wire [39:0] i_locked;', '\tinput wire [39:0] i_locked;\n    input wire [15:0] i_pair_dependencies;')


def issue_decode_overlay(decode, edit):
    decode = pair_dependency_port(decode, edit)
    decode = edit(decode, '\t\t\t\tdecoded[42] = front[27-:5] == 1;', '''\t\t\t\tdecoded[42] = front[27-:5] == 1;
                // ARM LDMIA with two ordinary destinations and no base writeback.
                if (!front[18] && !front[17] && front[201:197] == 5'b01001 &&
                    front[27-:5] == 2 && !front[64] && front[196:193] != 15 &&
                    decoded[80+:6] < 15 && bank({1'b0, first16(front[47:33])}, transfer_mode) < 15) begin
                    decoded[42] = 1;
                    decoded[86+:6] = bank({1'b0, first16(front[47:33])}, transfer_mode);
                end''')
    label = '\t\t\tK_BLOCK: '
    start = decode.index(label + 'decoded[79-:2] = ')
    end = decode.index('\n', start)
    decode = (decode[:start] + label + 'begin\n                ' + decode[start+len(label):end] + '''
                if (decoded[42] && front[27-:5] == 2) decoded[79] = 1;
            end''' + decode[end:])
    return edit(decode, '\tassign o_hazard = d2_valid && ', '''    reg pair_dependency;
    always @(*) begin : check_pair_dependency
        integer src;
        pair_dependency = 0;
        for (src = 0; src < 4; src = src + 1)
            if (d2[96+src] && d2[100+6*src+:6] < 16)
                pair_dependency = pair_dependency | i_pair_dependencies[d2[100+6*src+:4]];
    end
\tassign o_hazard = d2_valid && (pair_dependency || ''').replace('|| |early_hazard);', '|| |early_hazard));')


def avoid_known_crossings(decode, edit):
    return edit(decode, '\t\t\td2[372-:241] = d2_bank[d2_owner];', '''\t\t\td2[372-:241] = d2_bank[d2_owner];
        // Use the low bits of the base available in decode as a hint only.
        // W rechecks the effective address after operand forwarding.
        if (d2[131-:4] == K_BLOCK && d2[43] && d2[42] && d2[40-:5] == 2 &&
            d2[79] && (base_address_hint[1:0] != 0 || base_address_hint[4:2] == 7)) begin
            d2[42] = 0;
            d2[79] = 0;
        end''').replace('reg [372:0] d2;', '''reg [372:0] d2;
    wire [4:0] base_address_hint = i_wen && i_wr_pair && i_wr_tag_b == d2_q[100+:6] ? i_wr_data_b[4:0] :
        i_wen && i_wr_tag_a == d2_q[100+:6] ? i_wr_data_a[4:0] : i_rf_value[4:0];''')


def issue_core_overlay(core, edit):
    core = edit(core, '\ti_data_short_data,', '\ti_data_short_data,\n    i_data_short_next_word,\n    i_data_short_next_valid,\n    o_dc_pair_m_address,')
    core = edit(core, '\tinput wire [31:0] i_data_short_data;', '''\tinput wire [31:0] i_data_short_data;
    input wire [31:0] i_data_short_next_word;
    input wire i_data_short_next_valid;
    output wire [31:0] o_dc_pair_m_address;
    assign o_dc_pair_m_address = {m[366:337], 2'b00};''')
    core = edit(core, '\twire load_trust =', '''    localparam [3:0] LDM_PAIR = 4'd15;
    wire paired_ldm_w = w[541] && w[8-:4] == LDM_PAIR;
    wire paired_ldm_first = paired_ldm_w && w[537];
    wire paired_ldm_response = paired_ldm_first && !wb_flush && !w_exception &&
        request_done && !retry && !resp_err && (memory_state == 0 || memory_state == 1);
    wire paired_ldm = paired_ldm_response && ack_now && w[336:335] == 0 &&
        w[339:337] != 7 && w_load_hit && i_data_short_next_valid && !i_dc_lock_any;
    wire paired_ldm_split = paired_ldm_response && !paired_ldm;
    wire paired_ldm_shape = paired_ldm_first;
    wire decoded_ldm_pair = d_valid && d_kind == BLOCK && d_first && d_last &&
        d_reg_count == 2 && d_writes[1] && !d_instruction[21];
    wire execute_ldm_pair = a_a_valid && a_kind == BLOCK && a_first && a_last &&
        a_a_write[1] && !a_instruction[21];
    function automatic [15:0] pair_destinations;
        input valid;
        input [11:0] tags;
        begin
            pair_destinations = valid ? (16'h1 << tags[5:0]) | (16'h1 << tags[11:6]) : 16'b0;
        end
    endfunction
    // Keep dependent readers out of issue until both tags have data. A live
    // paired completion can use the normal same-edge register write-through.
    wire [15:0] pair_dependencies = pair_destinations(decoded_ldm_pair, d_dest) |
        pair_destinations(execute_ldm_pair, a_a_dest) |
        pair_destinations(m[541] && m[8-:4] == LDM_PAIR, m[103-:12]) |
        pair_destinations(skid[541] && skid[8-:4] == LDM_PAIR, skid[103-:12]) |
        pair_destinations(paired_ldm_w && !paired_ldm, w[103-:12]);
\twire load_trust =''')
    core = edit(core, '.i_locked(locked),', '.i_locked(locked),\n        .i_pair_dependencies(pair_dependencies),')
    core = edit(core, 'input_record[8-:4] = a_kind;', '''input_record[8-:4] =
            (a_kind == BLOCK && a_first && a_last && a_write[1] && !a_instruction[21]) ? 4'd15 : a_kind;''')
    core = edit(core, 'assign mw_value[64+:64] = {w[60+:32],',
                'assign mw_value[64+:64] = {paired_ldm ? i_data_short_next_word : w[60+:32],')
    core = edit(core, 'if ((request_done && resp_err) && w_blkwb)\n\t\t\t\t\tcomplete_class[consumer] = 0;', '''if ((request_done && resp_err) && w_blkwb)
                complete_class[consumer] = 0;
            if (consumer != 0 && paired_ldm_split)
                complete_class[consumer] = 0;''')
    core = edit(core, '\t\tif (wb_flush) begin\n\t\t\tm_next[541] = 0;', '''        if (paired_ldm_split) begin
            // The first request completed in order. Retain the instruction
            // in W and use the ordinary memory path for the second address.
            w_next = w;
            w_next[366-:32] = w[366-:32] + 32'd4;
            w_next[398-:32] = w[398-:32] + 32'd4;
            w_next[92+:6] = w[98+:6];
            w_next[98+:6] = 6'd16;
            w_next[537] = 0;
            w_next[27-:2] = 0;
            w_cls_next = w_cls_of(w_next);
            memory_state_next = 4'd4;
        end
\t\tif (wb_flush) begin
\t\t\tm_next[541] = 0;''')
    core = edit(core, 'wb_last = w[536] && !wb_restore;', 'wb_last = w[536] && !wb_restore && !paired_ldm_split;')
    core = edit(core, '\t\tif ((w[8-:4] == BX) && w[540])', '''        if (paired_ldm_w) begin
            wb_tag0 = paired_ldm ? w[98+:6] : 6'd16;
            wb_data0 = i_data_short_next_word;
        end
\t\tif ((w[8-:4] == BX) && w[540])''')
    return edit(core, '\t\t\tm <= m_next;', '''            if (paired_ldm_split)
                w_load_select <= 64'd1 << w[98+:6];
\t\t\tm <= m_next;''')


def cache_overlay(cache, edit):
    cache = edit(cache, '\to_short_data,', '\to_short_data,\n    o_short_next_word,\n    o_short_next_valid,\n    i_pair_m_address,')
    cache = edit(cache, '\toutput wire [31:0] o_short_data;', '''\toutput wire [31:0] o_short_data;
    output reg [31:0] o_short_next_word;
    output wire o_short_next_valid;
    input wire [31:0] i_pair_m_address;''')
    return edit(cache, '\tassign compare_address = i_address_check;', '''    localparam integer WORD_INDEX_WIDTH = LINE_W - 2;
    wire [WORD_INDEX_WIDTH-1:0] next_word = compare_address[LINE_W-1:2] + 1'b1;
    wire [CACHE_LINE*8-1:0] short_hit_line = raw_way_line[(raw_cache_word_sel && WAYS > 1) * CACHE_LINE*8 +: CACHE_LINE*8];
    reg [31:0] short_next_word;
    reg [31:0] short_pair_address;
    (* dont_retime *) reg short_pair_matches_w;
    wire sample_pair = !hold && !i_stall;
    wire [31:0] pair_sample_address = sample_pair ? compare_address : short_pair_address;
    wire pair_matches_m = pair_sample_address == i_pair_m_address;
    wire pair_matches_w = pair_sample_address == i_address;

    always @(*) begin : forward_pair_store
        integer lane;
        short_next_word = short_hit_line[32*next_word +: 32];
        if (forward_store && cache_write_way == (raw_cache_word_sel && WAYS > 1) &&
            i_address[LINE_W-1:2] == next_word)
            for (lane = 0; lane < 4; lane = lane + 1)
                if (i_ben[lane]) short_next_word[8*lane +: 8] = i_dat[8*lane +: 8];
    end
    always @(posedge i_clk) begin
        if (sample_pair) begin
            o_short_next_word <= short_next_word;
            short_pair_address <= compare_address;
        end
        // A held cache sample can outlive its original W owner. Select the
        // incoming M address on the same edge that advances W. A split
        // instead leaves a second beat in W, which cannot merge a pair.
        short_pair_matches_w <= i_lock_owner_move ? pair_matches_m : pair_matches_w;
    end
    assign o_short_next_valid = o_short_hit && live_trust && short_pair_matches_w;
\tassign compare_address = i_address_check;''')


def check_collapsed_packets(source, edit):
    return edit(source, '''`ifndef SYNTHESIS
    // A collapsed list must still fail in execute, with no memory or GPR effects.
    wire [15:0] predicate_list = a_instruction[15:0];
    wire predicate_multiple = |(predicate_list & (predicate_list - 16'd1));
    always @(posedge i_clk)
        if (!i_reset && a_valid && a_kind == BLOCK && a_first && a_last && !a_thumb && predicate_multiple)
            if (a_condition_pass || a_memory || |a_write)
                $fatal(1, "Collapsed block transfer passed at %h", a_pc);
`endif''', '''    // synthesis translate_off
`ifndef SYNTHESIS
    // A fused pair and a collapsed failed predicate can both be first/last.
    // Track the actual collapse across the two handoffs for this assertion.
    reg collapsed_s;
    reg collapsed_a;
    always @(posedge i_clk)
        if (i_reset || wb_flush) begin
            collapsed_s <= 0;
            collapsed_a <= 0;
        end else begin
            if (u_front_decode.u_decode.step)
                collapsed_s <= u_front_decode.u_decode.collapse_failed_list;
            if (u_execute.accept)
                collapsed_a <= collapsed_s;
        end
    always @(posedge i_clk)
        if (!i_reset && a_valid && collapsed_a)
            if (a_condition_pass || a_memory || |a_write)
                $fatal(1, "Collapsed block transfer passed at %h", a_pc);
`endif
    // synthesis translate_on''')
