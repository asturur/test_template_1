"""Isolated state-tagged instruction frontend overlay.

The halfword-aligned PC record uses bit zero internally for speculative fetch
state. Physical accesses keep canonical addresses. The pipeline carries a
state tag to the inflater and predecoder, and verifies it at branch resolution.
"""

def edit(text, old, new, count=1):
    assert text.count(old)==count,old
    return text.replace(old,new)


def wb(text):
    text=edit(text,'    input logic i_mode16,','    output wire o_fetch_thumb,')
    for name,stage in [('o_pc','pc_del3_ff'),('o_pc_check','pc_del2_ff'),('o_pc_nxt','pc_ff')]:
        line=next(l for l in text.splitlines() if f'assign {name} ' in l)
        text=edit(text,line,line.replace(f'{stage}[31:0]',"{"+stage+"[31:1], 1'b0}"))
    text=edit(text,'  assign o_shelve       = shelve_ff;',
              '''  assign o_shelve       = shelve_ff;
  // State belongs to the requested PC, including while the fetch is held.
  assign o_fetch_thumb = pc_del3_ff[0];''')
    text=edit(text,"      mapped[0] = 1'b0;\n","")
    text=edit(text,"mapped + (i_mode16 ? 32'd2 : 32'd4)","mapped + (mapped[0] ? 32'd2 : 32'd4)")
    text=edit(text,"pc_ff[31:0] + (i_mode16 ? 32'd2 : 32'd4)",
              "pc_ff[31:0] + (pc_ff[0] ? 32'd2 : 32'd4)")
    text=edit(text,'`zap_pc_shelve(mode32 ? i_pc_plus_8_buf_ff - 8 : i_pc_plus_8_buf_ff - 4);',
              "`zap_pc_shelve((mode32 ? i_pc_plus_8_buf_ff - 8 : i_pc_plus_8_buf_ff - 4) | {31'b0, cpsr_ff[T]});")
    text=edit(text,'`zap_pc_shelve(i_wr_data_1);',
              "`zap_pc_shelve({i_wr_data_1[31:1], (i_l4_enable ? i_flags[T] : i_wr_data_1[0])});")
    text=edit(text,'''    // Lower bit of PC is always zero.
    pc_nxt[24:0] = {pc_nxt_tmp[24:1], 1'd0};''',
              '''    // Bit zero represents fetched instruction state, not a bus address.
    pc_nxt[24:0] = pc_nxt_tmp[24:0];''')
    text=edit(text,"pc_ff      <= {1'd1, RESET_VECTOR};","pc_ff      <= {1'd1, RESET_VECTOR[31:1], CPSR_INIT[T]};")
    return text


def btb(text):
    text=edit(text,"localparam [31:0] MAX_WDT = 32 + 2 + TAG_WDT;",
              "localparam [31:0] MAX_WDT = 32 + 3 + TAG_WDT;")
    text=edit(text,'assign unused = |{i_rd_addr[0], i_rd_addr[31:$clog2(', 'assign unused = |{i_rd_addr[31:$clog2(')
    text=edit(text,'i_rd_addr_del[$clog2(\n      BP_ENTRIES\n  ):0], i_fb_branch_src_address[0]}',
              'i_rd_addr_del[$clog2(\n      BP_ENTRIES\n  ):1]}')
    text=edit(text,'logic [TAG_WDT-1:0] tag;','logic [TAG_WDT-1:0] tag;\n    logic source_thumb;')
    text=edit(text,'assign mem_wr_data.tag    = fb_src_addr.tag;',
              'assign mem_wr_data.tag    = fb_src_addr.tag;\n  assign mem_wr_data.source_thumb = fb_src_addr.offset;')
    return edit(text,'rd_addr_del_cast.tag == mem_rd_data.tag;',
                'rd_addr_del_cast.tag == mem_rd_data.tag &&\n                            rd_addr_del_cast.offset == mem_rd_data.source_thumb;')


def predecode(text):
    text=edit(text,'logic [139:0] skid;','logic [140:0] skid;\n  wire skid_thumb = o_stall_from_decode ? skid[140] : i_cpu_mode_t;')
    text=edit(text,'            skid <= {\n              i_pred,','            skid <= {\n              i_cpu_mode_t,\n              i_pred,')
    # All predecode consumers use the buffered state. The raw input is used
    # only to record the current state when taking a skid entry.
    lines=text.splitlines(keepends=True)
    for n,line in enumerate(lines):
        if ('input logic' not in line and 'wire skid_thumb' not in line and
            line.strip()!='i_cpu_mode_t,'):
            lines[n]=line.replace('i_cpu_mode_t','skid_thumb')
    text=''.join(lines)
    text=edit(text,'w_pc_from_decode = skid_pc_plus_8_ff + addr_final;',
              "w_pc_from_decode = (skid_pc_plus_8_ff + addr_final) | {31'b0, skid_thumb};")
    text=edit(text,"ras_nxt[ras_ptr_ff] = skid_pc_ff + (skid_thumb ? 32'd2 : 32'd4);",
              "ras_nxt[ras_ptr_ff] = (skid_pc_ff + (skid_thumb ? 32'd2 : 32'd4)) | {31'b0, skid_thumb};")
    text=edit(text,'w_pc_from_decode = ras_ff[ras_ptr_nxt];',
              '''w_pc_from_decode = ras_ff[ras_ptr_nxt];
        // ARMv4 MOV/LDM to PC keeps the original state. Only BX uses the
        // return-stack tag as its predicted new state on this path.
        if (!(mode32_instruction[31:0] ==? BX_INST)) w_pc_from_decode[0] = skid_thumb;''')
    text=edit(text,"    end\n        else if (\n                         mode32_instruction_valid",
              """    end else if (mode32_instruction_valid && mode32_instruction[31:0] ==? BX_INST) begin
      // Register-indirect BX (including interworking veneers) accepts the
      // learned PC/state pair. The ALU still checks both against Rm.
      if (skid_pred[32]) ppc_nxt = skid_pred[31:0];
    end
        else if (
                         mode32_instruction_valid""")
    text=edit(text,"ppc_nxt             = skid_pc_ff + (skid_thumb ? 32'd2 : 32'd4);",
              "ppc_nxt             = (skid_pc_ff + (skid_thumb ? 32'd2 : 32'd4)) | {31'b0, skid_thumb};",2)
    return edit(text,"w_pc_from_decode    = skid_pc_ff + (skid_thumb ? 32'd2 : 32'd4);",
                "w_pc_from_decode    = (skid_pc_ff + (skid_thumb ? 32'd2 : 32'd4)) | {31'b0, skid_thumb};")


def alu(text):
    text=edit(text,'    output logic [31:0] o_pc_from_alu,','    output logic [31:0] o_pc_from_alu,\n    output reg [31:0] o_feedback_source,')
    text=edit(text,"      w_pc_from_alu_btarget <= {tmp_sum[31:1], 1'b0};\n      w_pc_from_alu_resync <= i_pc_ff + (flags_ff[T] ? 32'd2 : 32'd4);",
              """      o_feedback_source <= {i_pc_ff[31:1], flags_ff[T]};
      w_pc_from_alu_btarget <= {tmp_sum[31:1], flags_nxt[T]};
      w_pc_from_alu_resync <= (i_pc_ff + (flags_ff[T] ? 32'd2 : 32'd4)) | {31'b0, flags_nxt[T]};""")
    text=edit(text,'''        // A/T mode switch. Resync anyway.
        if (i_switch_ff && flags_nxt[T] != tmp_sum[0]) begin
          w_clear_from_alu = BRANCH_TARGET;
          flags_nxt[T]     = tmp_sum[0];
        end  // Incorrectly predicted. Need to branch.
        else if (i_taken_ff == SNT || i_taken_ff == WNT) begin''',
              '''        // Commit the architectural state even on a correctly predicted BX.
        // A tag mismatch still discards all younger speculative packets.
        if (i_switch_ff) flags_nxt[T] = tmp_sum[0];
        if (i_taken_ff == SNT || i_taken_ff == WNT || i_ppc_ff[0] != flags_nxt[T]) begin''')
    return edit(text,'''            // Compare fetch addresses. Bit0 is not an instruction address bit;
            // the BX mode-change check above still requires a real redirect.''',
                '''            // Address and instruction state are verified separately.''')

def core(text):
    text=edit(text,'  logic [31:0] fetch_pc_plus_8_ff;', '''  wire instr_fetch_thumb;
  wire fetch_thumb, fifo_thumb, mode16_thumb;
  wire [31:0] feedback_source;
  logic [31:0] fetch_pc_plus_8_ff;''')
    text=edit(text,'.i_cpsr_ff_t           (alu_flags_ff[T]),','.i_cpsr_ff_t           (instr_fetch_thumb),\n      .o_thumb(fetch_thumb),')
    text=edit(text,'.WDT  (67 + 33),','.WDT  (68 + 33),')
    text=edit(text,'        fetch_pc_plus_8_ff, fetch_instr_abort, fetch_instruction, fetch_bp_state, fetch_pred',
              '        fetch_thumb, fetch_pc_plus_8_ff, fetch_instr_abort, fetch_instruction, fetch_bp_state, fetch_pred')
    text=edit(text,'.o_instr({fifo_pc_plus_8, fifo_instr_abort, fifo_instruction, fifo_bp_state, fifo_pred}),',
              '.o_instr({fifo_thumb, fifo_pc_plus_8, fifo_instr_abort, fifo_instruction, fifo_bp_state, fifo_pred}),')
    text=edit(text,".i_cpsr_ff_t   (alu_flags_ff[T]),\n      .i_pc_ff       (alu_flags_ff[T] ? fifo_pc_plus_8 - 32'd4 : fifo_pc_plus_8 - 32'd8),",
              ".i_cpsr_ff_t   (fifo_thumb),\n      .o_thumb(mode16_thumb),\n      .i_pc_ff       (fifo_thumb ? fifo_pc_plus_8 - 32'd4 : fifo_pc_plus_8 - 32'd8),")
    text=edit(text,".i_pc_ff       (alu_flags_ff[T] ? mode16_pc_plus_8_ff - 32'd4 : mode16_pc_plus_8_ff - 32'd8),",
              ".i_pc_ff       (mode16_thumb ? mode16_pc_plus_8_ff - 32'd4 : mode16_pc_plus_8_ff - 32'd8),")
    text=edit(text,'.i_cpu_mode_t   (alu_flags_ff[T]),','.i_cpu_mode_t   (mode16_thumb),')
    text=edit(text,'.o_pc_from_alu                    (pc_from_alu),',
              '.o_pc_from_alu                    (pc_from_alu),\n      .o_feedback_source(feedback_source),')
    text=edit(text,".i_alu_pc_ff       (alu_flags_ff[T] ? alu_pc_plus_8_ff - 32'd4 : alu_pc_plus_8_ff - 32'd8),",
              ".i_alu_pc_ff       (feedback_source),")
    return edit(text,'.i_mode16(alu_flags_ff[T]),  // To indicate mode16 state.',
                '.o_fetch_thumb(instr_fetch_thumb),')

def latch_thumb(text, accepted):
    text=edit(text,'    input logic i_cpsr_ff_t,','    output reg o_thumb,\n    input logic i_cpsr_ff_t,')
    text=edit(text,'    if (i_reset) begin','    if (i_reset) begin\n      o_thumb <= 1\'b0;')
    return edit(text,accepted,accepted+'\n      o_thumb <= i_cpsr_ff_t;')


def overlay(destination):
    rules={
        'zap_writeback.sv':wb,'zap_btb.sv':btb,'zap_predecode_main.sv':predecode,
        'zap_alu_main.sv':alu,'zap_core.sv':core,
        'zap_fetch_main.sv':lambda text:latch_thumb(text,'else if (i_valid && !i_code_stall) begin'),
        'zap_mode16_decoder_main.sv':lambda text:latch_thumb(text,'end else if (!stall) begin'),
    }
    for name,modify in rules.items():
        path=destination/'rtl/arm'/name
        path.write_text(modify(path.read_text()))
