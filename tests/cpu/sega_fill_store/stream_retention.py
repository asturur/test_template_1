"""Retain completed instruction lines across harmless serialized hits."""
from build import replace


def apply(source):
    rtl = source / 'rtl/arm920/cache_access.sv'
    text = rtl.read_text()
    text = replace(text,
        '''  wire stream_hit = stream_valid[req_mva[5]] && stream_epoch[req_mva[5]] == fast_epoch &&
                      stream_tag[req_mva[5]] == req_mva[31:5];''',
        '''  // I-cache demand ownership changes cancel in-flight lookahead, but a
  // completed resident line survives an unrelated hit. Revoke both copies
  // before a refill, cache operation or translation-context change.
  wire instruction_stream_revoke = !fast_lookup_enable || control_wait ||
      maint_valid || apply_invalidate || apply_lock || refill_busy || fill ||
      state == WAIT_REFILL;
  wire stream_hit = stream_valid[req_mva[5]] &&
      (READ_ONLY ? !instruction_stream_revoke : stream_epoch[req_mva[5]] == fast_epoch) &&
      stream_tag[req_mva[5]] == req_mva[31:5];''')
    text = replace(text, '''        fast_result_valid <= 0;
        stream_valid <= 0;
      end else if (fast_result_valid''', '''        fast_result_valid <= 0;
        if (!READ_ONLY || instruction_stream_revoke) stream_valid <= 0;
      end else if (fast_result_valid''')
    text = replace(text,
        '''      // A serialized read seeds its own returned line, after all older
      // speculative tokens have been killed. Other stream slot stays dead.
      if (!DATA_PROBE && state == READ_LINE && enabled && cacheable) begin''',
        '''      // A serialized read records its own returned line. Avoid publishing
      // a copied instruction line on the same edge as a revocation.
      if (!DATA_PROBE && state == READ_LINE && enabled && cacheable &&
          (!READ_ONLY || !instruction_stream_revoke)) begin''')
    rtl.write_text(text)


def redirect_lookahead(source):
    rtl = source / 'rtl/arm/zap_cache.sv'
    text = replace(rtl.read_text(), '      .fast_next_address(i_address + 32\'d16),',
        '''      // A bubble still carries an old PC. Look at the next checked PC
      // instead of reading beyond the discarded fallthrough stream.
      .fast_next_address(i_rd ? i_address + 32'd16 : i_address_check),''')
    rtl.write_text(text)
