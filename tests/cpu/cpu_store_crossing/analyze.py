#!/usr/bin/env python3
"""Audit all scored resident-line crossings and the one bounded 5G attempt."""
from setup import *
import collections
import gzip
import re


def load(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return path.read_text() if path.exists() else gzip.open(str(path) + '.gz', 'rt').read()


def parse(line):
    return dict(re.findall(r'(\w+)=([^ ]+)', line))


def number(row, key):
    hexadecimal = {'opc', 'base', 'addr', 'apc', 'rpc', 'selected', 'va', 'pa',
                   'be', 'din', 'pmva', 'ptag', 'owner', 'tagaddr', 'lookup',
                   'tagpa', 'wm', 'wd', 'rfd'}
    return int(row[key], 16 if key in hexadecimal else 10)


def histogram(values):
    return dict(sorted(collections.Counter(values).items()))


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


paths = [ROOT / 'build/sim/spmark-payload' / n
         for n in ['crossing-control-02', 'crossing-candidate-01']]
results = [load(p / 'result.json') for p in paths]
manifests = [load(p / 'manifest.json') for p in paths]
assert all(r['status'] == 'PASS' for r in results)
changed = [n for n, h in manifests[0]['source']['files'].items()
           if manifests[1]['source']['files'][n] != h]
assert changed == ['rtl/arm920/cache_access.sv']
assert sha(HERE / 'rtl/arm920/cache_access.sv') == manifests[1]['source']['files'][changed[0]]
compiled = {n: h for n, h in manifests[0]['source']['files'].items()
            if n.startswith('rtl/') and Path(n).suffix in ['.v', '.sv', '.svh']}
assert len(compiled) == 60
for n, h in compiled.items():
    assert hashlib.sha256(subprocess.check_output(['git', 'show', BASE + ':' + n], cwd=ROOT)).hexdigest() == h
for field in ['image_id', 'harness_sha256', 'programs', 'payload_sha256',
              'original_rom_sha256', 'original_images', 'normal_import_link', 'repeat', 'profiles']:
    assert manifests[0][field] == manifests[1][field], field
assert results[0]['qualification'] == results[1]['qualification']
assert all(q['status'] == 'PASS' and q['wrong_output_rejected'] for q in results[1]['qualification'])
assert load(paths[0] / 'fixture.json') == load(paths[1] / 'fixture.json')
for p, m in zip(paths, manifests):
    # Completed compiler trees may be retired after this audit. Durable
    # manifests still identify exactly what was compiled and checked.
    if (p / 'obj').exists():
        assert sha(p / 'obj/Vbench') == m['executable_sha256']
    if (p / 'source').exists():
        for n, h in m['source']['files'].items():
            assert sha(p / 'source' / n) == h
    for n, h in load(p / 'fixture.json').items():
        assert sha(p / 'fixture' / n) == h

windows = []
row_summaries = []
traces = {}
for old, new in zip(results[0]['rows'], results[1]['rows']):
    case, profile = old['case'], old['profile']
    assert (case, profile) == (new['case'], new['profile'])
    for field in ['oracle', 'program_sha256', 'payload_windows', 'operations', 'unit']:
        assert old[field] == new[field], field
    assert old['deterministic_repeats'] == new['deterministic_repeats'] == 2
    assert len(old['windows']) == len(new['windows']) == 7
    start = 0x10002ae4 if case == 'fill16_tail' else 0x10002a3c
    count = 504 if case == 'fill16_tail' else 512
    value = 0x31a731a7 if case == 'fill16_tail' else 0x5a5a5a5a
    for version, path, result in zip(['control', 'candidate'], paths, [old, new]):
        name = f'{case}-{profile.replace(":", "-")}'
        logs = [read(path / (name + f'-{i}.log')) for i in range(2)]
        lines = logs[0].splitlines()
        journal = [[s for s in log.splitlines() if s.startswith('CROSS5G ')] for log in logs]
        assert journal[0] == journal[1], (version, case, profile)
        traces[str((path / (name + '-0.log')).relative_to(ROOT))] = hashlib.sha256(logs[0].encode()).hexdigest()
        events = []
        for line in journal[0]:
            raw = parse(line)
            events.append({k: number(raw, k) for k in raw})
        for w in range(2, 7):
            es = [e for e in events if e['w'] == w]
            assert len(es) == result['windows'][w]['cycles']
            assert all(b['e'] == a['e'] + 1 for a, b in zip(es, es[1:]))
            accepts = [e for e in es if e['accept'] and start <= e['selected'] < start + 32]
            issues = [e for e in es if e['pop'] and e['store'] and start <= e['opc'] < start + 32]
            retired = [e for e in es if e['ret'] and start <= e['rpc'] < start + 32]
            assert len(accepts) == len(retired) == count
            assert len(issues) >= count
            assert [e['selected'] for e in accepts] == [e['opc'] for e in issues[:count]] == [e['rpc'] for e in retired]
            writes = [e for e in es if e['wm']]
            last_write = -1
            group = []
            for n, (accepted, issue, retirement) in enumerate(zip(accepts, issues, retired)):
                va = 0x80004004 + n * 4
                pc = start + (n % 8) * 4
                assert accepted['va'] == va and accepted['selected'] == pc
                assert accepted['din'] == value and accepted['be'] == 15
                assert accepted['matches'] == 1
                assert accepted['tagpa'] == (accepted['pa'] & ~31) == (0x0a000000 + va - 0x80000000) & ~31
                assert retirement['rfwen'] and retirement['rfa'] == 0 and retirement['rfd'] == va + 4
                mask = 15 << ((va >> 2 & 7) * 4)
                physical = next(e for e in writes if e['e'] >= accepted['e'] and e['e'] > last_write
                                and e['wm'] == mask and e['ww'] == accepted['way'] and e['ws'] == (va >> 5 & 7))
                assert physical['wd'] >> ((va >> 2 & 7) * 32) & 0xffffffff == value
                last_write = physical['e']
                known = next(e for e in es if issue['e'] <= e['e'] <= accepted['e']
                             and e['adv'] and e['apc'] == pc and e['addr'] == va)
                offered = [e for e in es if issue['e'] <= e['e'] <= accepted['e']
                           and e['req'] and e['va'] == va and e['selected'] == pc]
                assert offered
                tag = next((e for e in es if accepted['e'] <= e['e'] <= physical['e']
                            and e['state'] == 1 and e['hit'] and e['tagaddr'] == va), None)
                probes = [e['e'] for e in es if issue['e'] <= e['e'] <= physical['e']
                          and e['pvalid'] and e['ptag'] == va >> 5]
                group.append(dict(n=n, pc=f'{pc:08x}', va=f'{va:08x}', pa=f'{accepted["pa"]:08x}',
                                  way=accepted['way'], issue=issue['e'], address=known['e'],
                                  offer=offered[0]['e'], accept=accepted['e'],
                                  tag_validation=tag['e'] if tag else None,
                                  probe_available=probes[0] if probes else None,
                                  ram_write=physical['e'], retire=retirement['e'],
                                  blocked_ready=sum(not e['ready'] for e in offered),
                                  certificate=accepted['known'], pending_at_accept=accepted['pending'],
                                  credit=accepted['credit'], old_pipe_mva=f'{offered[0]["pmva"]:08x}',
                                  old_pipe=offered[0]['pipe'], old_commit=offered[0]['commit']))
            first, last = group[0]['ram_write'], group[-1]['ram_write']
            assert len([e for e in writes if first <= e['e'] <= last]) == count
            crossings = [e for n, e in enumerate(group) if n and int(e['va'], 16) >> 5 != int(group[n-1]['va'], 16) >> 5]
            assert len(crossings) == (63 if case == 'fill16_tail' else 64)
            assert all(e['certificate'] == 0 and e['credit'] == 0 for e in crossings)
            assert all(e['probe_available'] is None for e in crossings)
            for e in crossings:
                if e['old_pipe']:
                    assert int(e['old_pipe_mva'], 16) == int(e['va'], 16) - 4
            buckets = parse(next(s for s in lines if s.startswith(f'CREDIT_WORK_PROFILE index={w} ')))
            buckets = {k: int(v) for k, v in buckets.items() if k != 'index'}
            assert sum(buckets.values()) == len(es)
            empty = lambda e: not e['stall'] and not (e['oval'] and e['lock']) and not e['oval']
            loop_starts = [issues[n]['e'] for n in range(0, count, 8)]
            interloop_empty = [sum(empty(e) and a <= e['e'] < b for e in es)
                               for a, b in zip(loop_starts, loop_starts[1:])]
            next_useful = next(e['e'] for e in issues[8:] if e['e'] > group[7]['issue'])
            origin = group[7]['issue']
            witness = {k: (group[7][k] - origin if group[7][k] is not None else None)
                       for k in ['issue', 'address', 'offer', 'accept', 'tag_validation', 'probe_available', 'ram_write', 'retire']}
            witness['next_committed_loop_issue'] = next_useful - origin
            windows.append(dict(version=version, case=case, profile=profile, window=w,
                                cycles=len(es), buckets=buckets, main_word_stores=count,
                                extra_operand_dequeues_not_retired=len(issues)-count,
                                crossing_count=len(crossings), blocked_ready_histogram=histogram(e['blocked_ready'] for e in crossings),
                                movable_accept_clocks=sum(e['blocked_ready'] for e in crossings),
                                crossing_issue_to_accept_histogram=histogram(e['accept']-e['issue'] for e in crossings),
                                crossing_issue_to_ram_histogram=histogram(e['ram_write']-e['issue'] for e in crossings),
                                crossing_issue_to_retire_histogram=histogram(e['retire']-e['issue'] for e in crossings),
                                loop_issue_spacing=histogram(b-a for a, b in zip(loop_starts, loop_starts[1:])),
                                interloop_empty_clocks=sum(interloop_empty), per_loop_empty_histogram=histogram(interloop_empty),
                                ordered_memory_and_base_sequence_sha256=digest([(e['pc'], e['va'], e['pa'], e['way'], value) for e in group]),
                                full_crossing_schedule_sha256=digest(crossings), first_crossing=witness,
                                first_crossing_absolute=group[7], last_crossing_absolute=crossings[-1],
                                all_retirement_PC_sha256=digest([e['rpc'] for e in es if e['ret']])))
            assert all(x == 0 for k, x in result['windows'][w].items() if k in ['reads', 'writes', 'lines', 'halfwords'])
    before = [x for x in windows if x['case'] == case and x['profile'] == profile and x['version'] == 'control']
    after = [x for x in windows if x['case'] == case and x['profile'] == profile and x['version'] == 'candidate']
    deltas = []
    for a, b in zip(before, after):
        assert a['ordered_memory_and_base_sequence_sha256'] == b['ordered_memory_and_base_sequence_sha256']
        assert a['all_retirement_PC_sha256'] == b['all_retirement_PC_sha256']
        delta = {k: b['buckets'][k]-a['buckets'][k] for k in a['buckets']}
        assert sum(delta.values()) == b['cycles']-a['cycles']
        deltas.append(delta)
    threshold = 1278 if case == 'fill16_tail' else 1581
    row_summaries.append(dict(case=case, profile=profile, control=old['body_cycles_median'],
                              candidate=new['body_cycles_median'], retention_maximum=threshold,
                              meets_threshold=new['body_cycles_median'] <= threshold,
                              control_scored=[e['cycles'] for e in old['windows'][2:]],
                              candidate_scored=[e['cycles'] for e in new['windows'][2:]],
                              disjoint_bucket_deltas=deltas))

assert len(windows) == 40 and len(row_summaries) == 4
assert all(r['candidate'] == (1264 if r['case'] == 'fill16_tail' else 1646) for r in row_summaries)
assert not all(r['meets_threshold'] for r in row_summaries)
history = load(ROOT / 'docs/evidence/cpu-store-postindex-20261117.json')
historical = next(x for x in history['workloads'] if x['case'] == 'fill8_tail' and x['profile'] == '0:0')
assert historical['profile_delta']['empty'] == 250 and sum(historical['profile_delta'].values()) == -525
record = dict(status='PASS_AUDIT_REJECT_CANDIDATE', control_commit=BASE,
              control_source_id=manifests[0]['source']['source_id'], candidate_source_id=manifests[1]['source']['source_id'],
              changed_isolated_files=changed, production_RTL_changed=False, rows=row_summaries, windows=windows,
              compiled_control_RTL_sha256=compiled, candidate_overlay_sha256=sha(HERE/'rtl/arm920/cache_access.sv'),
              helper_sha256={str(p.relative_to(ROOT)):sha(p) for p in [HERE/'setup.py', HERE/'bench.py', HERE/'analyze.py']},
              completed_build_trees_retired=all(not (p/n).exists() for p in paths for n in ['obj','source']),
              raw_trace_sha256=traces,
              run_receipt_sha256={str((p/name).relative_to(ROOT)):sha(p/name) for p in paths for name in ['manifest.json','result.json','fixture.json','oracle.json']},
              historical_5F_fill8_bucket_delta=historical['profile_delta'],
              historical_5F_evidence_sha256=sha(ROOT/'docs/evidence/cpu-store-postindex-20261117.json'),
              resource_estimate=dict(added_state_bits=0, added_RAM_ports=0, added_RAM_blocks=0, added_DSPs=0,
                                     added_cache_tag_comparators=0, added_logic='existing qualification plus segment inequality and ready OR; packing/timing unmeasured'),
              qualification=dict(tail_original_byte_math_Unicorn_guards_and_all_output_checks='PASS',
                                  seven_windows_two_exact_repeats_and_wrong_output_controls='PASS',
                                  all_scored_independent_physical_slot_mask_data_base_and_retirement_checks='PASS',
                                  broader_candidate_warm64_IRQ_fault_alias_permission_JPEG_and_other_kernels='NOT RUN: byte-tail retention gate fails; no candidate qualified or adopted'),
              excluded_observer_attempt=load(ROOT/'build/sim/spmark-payload/crossing-control-01/observer-exclusion.json'),
              decision='Reject sole prototype: halfword tail saves68 clocks, byte tail saves1; keep pinned5F production and stop without another design/fit.',
              physical_PLL_MHz=78, fit_CI_donor_hardware_or_deployment=False)
target=ROOT/'docs/evidence/cpu-store-crossing-20261117.json'
target.write_text(json.dumps(record,indent=2)+'\n')
print('PASS audit all40 scored version/case/profile windows; reject sole5G candidate:',target)
for r in row_summaries:
    print(r['case'],r['profile'],r['control'],r['candidate'],r['disjoint_bucket_deltas'][0])
