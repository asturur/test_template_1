#!/usr/bin/env python3
"""Research-only, frozen-readiness screen of one registered empty-head path.

This is an event counterfactual, not an RTL simulation or elapsed-time claim.
Every proposed clock must reach a free actual-dequeue opportunity. Later
readiness, predictor behavior and memory timing remain the measured control's.
"""
from pathlib import Path
from collections import Counter, defaultdict
from bisect import bisect_left, bisect_right
import gzip
import hashlib
import json
import re
import statistics
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tests/cpu/cpu_target_delivery'))
from timeline import audit, read

BASE = '8e70b1ebc16486443d09f008384b4c0bc41c071c'
OUT = ROOT/'build/sim/cpu-useful-target'
OUT.mkdir(parents=True, exist_ok=True)
sha = lambda b: hashlib.sha256(b).hexdigest()
load = lambda p: json.loads(p.read_text())


def executable_hash(directory):
    executable=directory/'obj/Vbench'
    if executable.exists():
        return sha(executable.read_bytes())
    return load(directory/'storage.json')['retired_artifacts']['obj/Vbench']['sha256']


def edges(path):
    return [dict(re.findall(r'(\w+)=([^ ]+)', s))
            for s in read(path).splitlines() if s.startswith('TARGET5E ')]


def instruction_class(word, thumb):
    if thumb:
        word &= 0xffff
        if word & 0xff00 == 0x4700: return 'BX'
        if word & 0xfe00 == 0xb400: return 'PUSH'
        if word & 0xfe00 == 0xbc00: return 'POP'
        if word & 0xf800 in [0xf000,0xf800]: return 'BL_halfword'
        if word & 0xe000 == 0x6000 or word & 0xf000 in [0x8000,0x9000] or word & 0xf800 == 0x4800:
            return 'load_store'
        return 'ALU_or_other_Thumb'
    if word & 0x0ffffff0 == 0x012fff10: return 'BX'
    if (word>>25)&7 == 5: return 'B_BL'
    if (word>>25)&7 == 4: return 'LDM_STM'
    if (word>>26)&3 == 1: return 'LDR' if word & (1<<20) else 'STR'
    return 'ALU_or_other_ARM'


def extend_transfers(es, old, thumb=False):
    """Include taken ordinary branches and wrapper transfers in the screen."""
    rows = old['records'][:]
    suffixes = {int(e['ppc'], 16) for e in es if e['pa'] == '1'
                and int(e['ins'], 16) >> 34
                and int(e['ins'], 16) & 0x0f000000 == 0x0b000000}
    canon = lambda pc: f'{int(pc,16)-(2 if int(pc,16) in suffixes else 0):08x}'
    rs = [(int(e['e']), e['rpc']) for e in es if e['ret'] == '1']
    by = {int(e['e']): e for e in es}
    maps = {k: defaultdict(list) for k in ['pop', 'pa', 'pre', 'decode', 'fetch', 'ack','btb']}
    clears = []
    for e in es:
        n = int(e['e'])
        clear = any(e[k] == '1' for k in ['ac', 'wbc', 'dc'])
        if clear:
            clears.append(n)
        for kind, flag, pc in [('pop', 'pop', 'opc'), ('pa', 'pa', 'ppc'),
                               ('pre', 'pv', 'ppc'), ('decode', 'dv', 'dpc')]:
            if e[flag] == '1' and e['ac'] == e['wbc'] == '0':
                maps[kind][e[pc]].append(n)
        if e['fv'] == '1' and e['code'] == '0' and not clear:
            maps['fetch'][e['fpc']].append(n)
        if e['req'] == e['ack'] == '1' and not clear:
            maps['ack'][e['addr']].append(n)
        if e['btbc']=='1' and e['code']==e['saved']=='0' and int(e['pc3'],16)>>32 and not clear:
            maps['btb'][f"{int(e['pc3'],16)&0xffffffff:08x}"].append(n)

    def first(kind, pc, lo, hi):
        xs = maps[kind][pc]
        j = bisect_left(xs, lo)
        assert j < len(xs) and xs[j] <= hi, (kind, pc, lo, hi)
        return xs[j]

    def last(kind, pc, hi, lo=-1):
        xs = maps[kind][pc]
        j = bisect_right(xs, hi)-1
        assert j >= 0 and xs[j] > lo, (kind, pc, lo, hi)
        return xs[j]

    existing = {(r['source_retire'], r['retire']) for r in rows}
    previous = {}
    occurrence = Counter()
    boundary = []
    for ri, ((r, pc), (tr, tp)) in enumerate(zip(rs, rs[1:])):
        prev = previous.get(pc, int(es[0]['e'])-1)
        previous[pc] = r
        size = 4 if int(pc,16) in suffixes or not (thumb and int(pc,16) >= 0x50000000) else 2
        if int(canon(tp), 16) == int(canon(pc),16)+size or (r,tr) in existing:
            continue
        si = last('pop', pc, r, prev)
        if not any(prev<n<=si for n in maps['pa'][pc]):
            assert si-int(es[0]['e']) < 16, (pc,si)
            boundary.append(dict(source=pc,target=canon(tp),source_retire=r,
                                 reason='source_predecode_precedes_sampled_window_no_credit'))
            continue
        k = last('pa', pc, si, prev)
        issue = first('pop', tp, k, tr)
        dec = first('decode', tp, k, issue)
        pre = first('pre', tp, k, dec)
        j = bisect_left(clears, pre)
        lc = clears[j-1] if j else -1
        target = canon(tp)
        f = last('fetch', target, pre, lc)
        ack = last('ack', target, f-1)
        req = ack
        while req-1 in by and by[req-1]['req'] == '1' and by[req-1]['addr'] == target:
            req -= 1
        e = by[k]
        ps=maps['btb'].get(pc,[])
        j=bisect_right(ps,k)-1
        prediction=ps[j] if j>=0 else None
        if prediction is not None and by[prediction]['btbt']!=e['pred'][-8:]:
            prediction=None
        rows.append(dict(kind='branch', source=canon(pc), packet_pc=pc,
                         occurrence=occurrence[pc], target=target, known=k,
                         prediction=prediction, predicted=e['pred'], needs_correction=e['wc']=='1',
                         hint_target=e['wt'], hint_matches_actual=(int(e['wt'],16)&~1)==int(target,16),
                         correction=None, source_issue=si, source_retire=r, request=req,
                         ack=ack, fetch=f, predecode=pre, decode=dec, issue=issue, retire=tr))
        occurrence[pc] += 1
    rows.sort(key=lambda r:r['source_retire'])
    return rows, rs, canon, boundary


def analyze(path, is_thumb=False):
    es = edges(path)
    try:
        old = audit(path)
    except statistics.StatisticsError:
        # The short byte control contains no recognized original BL calls.
        assert path.name.startswith('fill8_tail-')
        pcs=[e['rpc'] for e in es if e['ret']=='1']
        old=dict(records=[],retirements=len(pcs),
                 retirement_PC_sha256=sha('\n'.join(pcs).encode()),
                 canonical_retirement_histogram=dict(Counter(pcs)))
    by = {int(e['e']): e for e in es}
    held_edges=0
    for a,b in zip(es,es[1:]):
        if a['req']=='1' and a['ack']=='0':
            assert b['req']=='1' and b['addr']==a['addr'],(a['e'],a['addr'],b['addr'])
            held_edges+=1
    rows, retired, canon, boundary = extend_transfers(es, old, is_thumb)
    next_retirement={a:(b,canon(pc)) for (a,_),(b,pc) in zip(retired,retired[1:])}
    union = {}
    overlap = 0
    stage_totals = Counter()
    model = Counter()
    phase = defaultdict(Counter)
    delivery_union = {}
    free_slots=set()
    for r in rows:
        k, f, issue = r['known'], r['fetch'], r['issue']
        target, packet = r['target'], r['packet_pc']
        # A held F register already contains a permitted word even when the
        # next demand's code_stall inhibits its ordinary FIFO write.
        fp = f
        while fp-1 in by and by[fp-1]['fv']=='1' and by[fp-1]['fpc']==target \
                and all(by[fp-1][q]=='0' for q in ['ac','wbc','dc']):
            fp -= 1
        q = next(n for n in range(f,issue+1) if by[n]['qv']=='1' and canon(by[n]['qpc'])==target)
        m = next(n for n in range(q,issue+1) if by[n]['mv']=='1' and canon(by[n]['mpc'])==target)
        preout=next(n+1 for n in range(r['predecode'],r['decode'])
                    if by[n]['pv']=='1' and canon(by[n]['ppc'])==target
                    and by[n]['pstall']=='0' and by[n]['ac']==by[n]['wbc']==by[n]['dc']=='0')
        raw = k
        while raw-1 in by and by[raw-1]['pv']=='1' and by[raw-1]['ppc']==packet \
                and all(by[raw-1][q]=='0' for q in ['ac','wbc','dc']):
            raw -= 1
        pred = r['prediction']
        correct_pred = pred if pred is not None and (int(by[pred]['btbt'],16)&~1)==int(target,16) else None
        correction = next((n for n in range(r['source_issue'],r['source_retire']+1)
                           if by[n]['ac']=='1' and by[n]['data']=='0'
                           and (int(by[n]['at'],16)&~1)==int(target,16)), None)
        if not r['hint_matches_actual']:
            assert correction is not None, r
        pre_available = raw if r['hint_matches_actual'] else None
        availability = [n for n in [correct_pred,pre_available,correction] if n is not None]
        assert availability
        available = min(availability)
        source_f = next((n for n in range(raw,int(es[0]['e'])-1,-1)
                         if by[n]['fv']=='1' and by[n]['fpc']==packet),None)
        if source_f is not None:
            while source_f-1 in by and by[source_f-1]['fv']=='1' and by[source_f-1]['fpc']==packet \
                    and all(by[source_f-1][v]=='0' for v in ['ac','dc','wbc']):
                source_f-=1
        # The model never uses hindsight PC equality to select a packet. It
        # acts on every empty head; equality is only the observer's audit.
        assert by[issue]['pop']=='1' and canon(by[issue]['opc'])==target
        assert next_retirement[r['source_retire']]==(r['retire'],target)
        e = by[fp]
        response = by[fp-1]
        assert response['req']==response['ack']=='1' and response['addr']==target
        assert response['rawvalid']=='1' and by[fp]['ferr']=='0'
        word=int(response['rawword'],16) >> (16 if int(target,16)&2 else 0)
        target_thumb=is_thumb and int(target,16)>=0x50000000
        permitted = e['ferr']=='0' and e['cfault']=='0' and e['calign']=='0'
        eligible = e['qempty']=='1' and e['qv']=='0' and e['qclear']=='0' \
            and all(e[x]=='0' for x in ['ac','dc','wbc','cinv','cclean'])
        # Conservative straight-path witness: do not move target microcode,
        # replace an older operand, infer a new hold result, or pull issue
        # through a measured clear. Cases requiring a changed schedule get 0.
        proposed_issue = fp+5
        checks = [(fp+1,['mstall'],'assembly_hold'),
                  (fp+2,['pstall','pmem'],'predecode_hold'),
                  (fp+3,['data','busy','istall'],'decode_hold'),
                  (fp+4,['data','busy','istall'],'operand_arrival_hold'),
                  (proposed_issue,['data','busy','ll','sl','oval'],'operand_dequeue_occupied')]
        reason = None
        if not eligible:
            reason = 'existing_fifo_or_head_occupied_or_clear'
        elif not permitted:
            reason = 'not_normal_permitted_word'
        elif issue != f+6:
            reason = 'older_work_or_instruction_expansion_delays_baseline'
        else:
            reason = next((label for n,ks,label in checks if any(by[n][x]=='1' for x in ks)),None)
            if reason is None and any(any(by[n][x]=='1' for x in ['ac','dc','wbc']) for n in range(fp,proposed_issue)):
                reason = 'intervening_correction'
        saved = issue-proposed_issue if reason is None else 0
        assert saved >= 0
        # A second, hold-aware estimate of the SAME path: retain the inserted
        # packet in each existing register until the control's normal ready
        # condition permits it to advance. Source retirement is a conservative
        # certificate for older architectural register/flag producers. This
        # still cannot predict changed future memory or predictor phasing.
        def ready(start, flags, extra=lambda x: True):
            return next((n for n in range(start,issue+1)
                         if all(by[n][v]=='0' for v in flags) and extra(by[n])),issue+1)
        hold_schedule = None
        hold_saved = 0
        if eligible and permitted:
            hq=fp+1
            hm=ready(hq,['mstall'])+1
            hp=ready(hm,['pstall','pmem','dstall'])+1
            hd=ready(hp,['data','busy','istall'])+1
            ho=ready(hd,['data','busy','istall'])+1
            hf=ready(max(ho,issue-(f-fp+1)),['data','busy','ll','sl','oval'])
            hi=ready(max(ho,r['source_retire'],issue-(f-fp+1)),['data','busy','ll','sl','oval'])
            # Keep any observed extra instruction-assembly latency. The one
            # slot does not manufacture a missing Thumb halfword/micro-op.
            intrinsic = max(0,m-f-3)
            if intrinsic or any(any(by[n][v]=='1' for v in ['ac','wbc','dc'])
                                for n in range(fp,min(hi,issue))):
                hi=issue
            if intrinsic or any(any(by[n][v]=='1' for v in ['ac','wbc','dc'])
                                for n in range(fp,min(hf,issue))):
                hf=issue
            if hf<issue:
                free_slots.update(range(hf,issue))
            if hi<issue:
                hold_saved=issue-hi
                hold_schedule=dict(FIFO_head=hq,assembly=hm,predecode_output=hp,
                                   decode=hd,operand_arrival=ho,issue=hi)
        model['hold_aware_exposed_clocks'] += hold_saved
        model['hold_aware_events'] += hold_saved>0
        model['transfers'] += 1
        model['eligible'] += eligible
        model['local_delivery_budget'] += (f-fp+1) if eligible else 0
        model['straight_path_events'] += saved>0
        model['straight_path_free_slot_clocks'] += saved
        model[reason or 'straight_path_exposed'] += 1
        category = ('mature_BTB' if correct_pred is not None and not r['needs_correction'] else
                    ('later_corrected_return' if r['kind']=='return' else 'execution_corrected_branch') if not r['hint_matches_actual'] else
                    'correct_RAS' if r['kind']=='return' else 'predecode_direct')
        phase[category][f'phase_{int(target,16)%4}'] += 1
        phase[category][f'Faccepted_to_decode_{r["decode"]-f}'] += 1
        phase[category]['exposed_clocks'] += saved
        # First blocker on the path to this useful dequeue, exclusive per
        # occurrence. Union ownership is the earliest transfer in retirement
        # order; intersecting transfer intervals are never added twice.
        labels = Counter()
        runs = []
        for n in range(available,issue):
            x = by[n]
            if x['data']=='1': label='downstream_data_write' if x['wr']=='1' else 'downstream_data_read'
            elif x['busy']=='1': label='downstream_multiply'
            elif x['oval']=='1' and x['ll']=='1': label='downstream_load_dependency'
            elif x['oval']=='1' and x['sl']=='1': label='downstream_shift_dependency'
            elif x['pop']=='1' and x['ac']==x['wbc']=='0':
                # A popped packet can be an internal micro-op. Only call it
                # committed older work if a matching future prefix retirement
                # exists; otherwise retain the unmatched/wrong-path category.
                older=any(n<=rr<=r['source_retire'] and pc==x['opc'] for rr,pc in retired)
                label='useful_older_dequeue' if older else 'unmatched_or_wrong_path_dequeue'
            elif not r['hint_matches_actual'] and n < correction:
                label='await_later_execution_correction'
            elif n < r['request']:
                label='held_other_demand_owner' if x['req']=='1' and x['ack']=='0' and x['addr']!=target else 'target_selection_registered_edges'
            elif n < r['ack']:
                label='target_translation_pipeline' if x['tlb']=='1' or x['trans']=='1' else 'target_cache_owner_service'
            elif n < fp: label='permitted_response_to_F_register'
            elif n < f: label='F_held_by_successor_demand'
            elif n < q: label='FIFO_array_and_registered_head'
            elif n < m: label='ARM_Thumb_assembly_edge'
            elif n < r['decode']: label='predecode_and_decode_edges_or_holds'
            else: label='operand_queue_arrival_or_hold'
            labels[label] += 1
            if runs and runs[-1][2]==label and runs[-1][1]==n:
                runs[-1][1]=n+1
            else: runs.append([n,n+1,label])
            if n in union: overlap += 1
            else: union[n]=label
            if fp<=n<r['decode'] and n not in delivery_union:
                delivery_union[n]=label
        stage_totals.update(labels)
        r.update(correct_prediction_value_available=correct_pred,
                 source_complete_encoding_in_F=source_f,
                 predecode_correct_value_available=pre_available,
                 later_execution_correction=correction,
                 first_matching_target_value_available=available,
                 permitted_word_response=fp-1,permitted_physical_address=response['phys'],
                 target_instruction_class=instruction_class(word,target_thumb),
                 target_instruction_encoding=f'{word & (0xffff if target_thumb else 0xffffffff):0{4 if target_thumb else 8}x}',
                 target_state='Thumb' if target_thumb else 'ARM',
                 F_present=fp,F_accepted=f,FIFO_head=q,assembly=m,predecode_output=preout,
                 first_blocker_counts=dict(labels),first_blocker_intervals=runs,
                 target_phase=int(target,16)%4,category=category,
                 model=dict(eligible=eligible,local_delivery_budget=f-fp+1 if eligible else 0,
                            straight_path_free_slot_clocks=saved,
                            straight_path_screen_reason=reason or 'straight_path_exposed',
                            exposed_saved_clocks=hold_saved,proposed_schedule=hold_schedule,
                            straight_path_schedule=dict(FIFO_head=fp+1,assembly=fp+2,predecode_output=fp+3,
                                          decode=fp+4,issue=proposed_issue) if saved else None))
    assert sum(Counter(union.values()).values()) == len(union)
    # Proposed issue slots are unique. Empty-slot witnesses, not empty queue
    # occupancy, are the counted objects. Multi-clock gains must also be
    # disjoint; union the removed interval just before the original dequeue.
    saving_slots=set()
    for r in rows:
        s=r['model']['straight_path_free_slot_clocks']
        if s:
            ss=set(range(r['issue']-s,r['issue']))
            assert not (saving_slots & ss)
            saving_slots |= ss
    assert len(saving_slots)==model['straight_path_free_slot_clocks']
    hold_slots=set()
    for r in rows:
        s=r['model']['exposed_saved_clocks']
        hold_slots.update(range(r['issue']-s,r['issue']))
    model['hold_aware_interval_overlap']=model['hold_aware_exposed_clocks']-len(hold_slots)
    model['hold_aware_exposed_clocks']=len(hold_slots)
    model['plausibly_exposed_clocks']=len(hold_slots)
    model['free_issue_slot_clocks_without_source_retirement_certificate']=len(free_slots)
    return dict(path=str(path.relative_to(ROOT)),raw_log_sha256=sha(read(path).encode()),
                measured=dict(edges=len(es),retirements=old['retirements'],
                              held_instruction_request_edges_checked=held_edges,
                              retirement_PC_sha256=old['retirement_PC_sha256'],
                              original_canonical_histogram=old['canonical_retirement_histogram'],
                              transfer_count=len(rows),unobservable_boundary_transfers=boundary,
                              transfer_interval_union=len(union),
                              overlap_counted_once=overlap,union_first_blockers=dict(Counter(union.values())),
                              F_present_to_decode_union_first_blockers=dict(Counter(delivery_union.values())),
                              phase_and_type={k:dict(v) for k,v in phase.items()}),
                counterfactual=dict(model),records=rows)


def main():
    sources = [('matrix','spmark-payload/useful-target-5f-arm-02','matrix4',False,45736),
               ('fill8','spmark-payload/useful-target-5f-arm-02','fill8_tail',False,1647),
               ('jpeg','jpeg-payload/useful-target-5f-jpeg-01','diffuse_m10_8x8_jpeg',True,84353)]
    result=dict(format='step5h-useful-target-research-v1',status='PASS',base=BASE,
                production_RTL_changed=False,RTL_prototype_run=False,
                physical_PLL_MHz=78,registered_design_target_MHz=104,
                model='one-shot F-to-existing-empty-registered-FIFO-head delivery',
                model_cost=dict(added_state_bits=1,existing_payload_bits=100,added_word_storage_bits=0,
                                new_RAM_ports=0,new_tag_or_address_comparators=0,
                                payload_mux_bits=100,registered_edges_removed=1),
                limitations=['Frozen-readiness local counterfactual, not resimulated wall time.',
                             'No modeled response or request earlier than measured permitted F.',
                             'No extrapolation to unobserved sequential empty episodes or changed prediction phasing.',
                             'Only first scored window is stage-journaled; seven checked timing windows and two repeats remain.'],
                workloads={},artifacts={})
    for label,run,stem,thumb,cycles in sources:
        directory=ROOT/'build/sim'/run
        rr=load(directory/'result.json');assert rr['status']=='PASS'
        mf=load(directory/'manifest.json')
        compiled={n:h for n,h in mf['source']['files'].items()
                  if n.startswith('rtl/') and Path(n).suffix in ['.v','.sv','.svh']}
        assert len(compiled)==60
        for n,h in compiled.items():
            assert sha(subprocess.check_output(['git','show',BASE+':'+n],cwd=ROOT))==h,n
            assert sha((ROOT/n).read_bytes())==h,n
        for n,h in load(directory/'fixture.json').items():
            assert sha((directory/'fixture'/n).read_bytes())==h,n
        assert sha((directory/'tb.v').read_bytes())==mf['harness_sha256']
        if 'executable_sha256' in mf:
            assert mf['executable_sha256']==executable_hash(directory)
        d=analyze(directory/(stem+'-0-0-0.log'),thumb)
        row=next(r for r in rr['rows'] if r['case']==stem)
        timing=row['observation'] if thumb else row
        assert timing['body_cycles_median']==cycles
        assert len(timing['windows'])==7
        assert len([p for p in directory.glob(stem+'-0-0-*.log*')])==2
        bad=directory/(stem+'-wrong-output'+('.log' if thumb else '-0-0-0.log'))
        assert 'guest result check failed' in read(bad)
        d['measured']['timing_windows']=timing['windows']
        d['measured']['repeats']=2
        d['measured']['wrong_output_rejected']=True
        assert edges(directory/(stem+'-0-0-0.log'))==edges(directory/(stem+'-0-0-1.log'))
        if label in ['matrix','jpeg']:
            previous=load(ROOT/f'build/sim/cpu-target-delivery/{label}-control-0-0-timeline.json')
            assert previous['retirement_PC_sha256']==d['measured']['retirement_PC_sha256']
        if thumb:
            oracle=load(directory/'oracle.json')[stem]['pcs']
            actual={hex(int(k,16)):v for k,v in d['measured']['original_canonical_histogram'].items()
                    if 0x50500000<=int(k,16)<0x50600000}
            assert actual==oracle
        d['baseline_median_cycles']=cycles
        d['counterfactual']['exposed_percent_of_median']=100*d['counterfactual']['plausibly_exposed_clocks']/cycles
        result['workloads'][label]=d
        result['artifacts'][run]=dict(manifest_sha256=sha((directory/'manifest.json').read_bytes()),
                                     result_sha256=sha((directory/'result.json').read_bytes()),
                                     executable_sha256=executable_hash(directory),
                                     compiled_RTL_matches_base=len(compiled))
        print(label,d['counterfactual'])
    ws=result['workloads']
    choose=lambda case,predicate: next(r for r in ws[case]['records'] if predicate(r))
    result['witnesses']={
        'matrix_mature_BTB_call':choose('matrix',lambda r:r['kind']=='call' and r['category']=='mature_BTB'),
        'matrix_correct_RAS_return':choose('matrix',lambda r:r['kind']=='return' and r['hint_matches_actual']),
        'jpeg_common_direct_call':choose('jpeg',lambda r:r['kind']=='call' and r['source']=='505a9e42'),
        'jpeg_mature_BTB_call':choose('jpeg',lambda r:r['kind']=='call' and r['category']=='mature_BTB'),
        'jpeg_correct_RAS_return':choose('jpeg',lambda r:r['kind']=='return' and r['hint_matches_actual']),
        'jpeg_later_corrected_return':choose('jpeg',lambda r:r['kind']=='return' and not r['hint_matches_actual']),
        'byte_first_backedge':choose('fill8',lambda r:r['source']=='10002a60'),
        'byte_steady_backedge':choose('fill8',lambda r:r['source']=='10002a60' and r['occurrence']==1),
    }
    result['decision']='Do not fund this single-edge path as a 5% prototype; retain 5F. A larger owner/queue change needs a separate measured proposal.'
    events=dict(format='step5h-dynamic-events-v1',base=BASE,
                note='Predecode output is derived from the observed accepted head and the RTL registered edge.',
                workloads={label:d.pop('records') for label,d in ws.items()})
    raw=json.dumps(events,separators=(',',':')).encode()+b'\n'
    event_path=ROOT/'docs/evidence/cpu-useful-target-20261117.events.json.gz'
    event_path.write_bytes(gzip.compress(raw,compresslevel=9,mtime=0))
    result['dynamic_event_receipt']=dict(path=str(event_path.relative_to(ROOT)),
                                      raw_sha256=sha(raw),archive_sha256=sha(event_path.read_bytes()),
                                      raw_bytes=len(raw),archive_bytes=event_path.stat().st_size)
    target=ROOT/'docs/evidence/cpu-useful-target-20261117.json'
    target.write_text(json.dumps(result,separators=(',',':'))+'\n')
    print('PASS',target)


if __name__=='__main__':
    main()
