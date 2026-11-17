#!/usr/bin/env python3
"""Prepare the exact Stop 3C fit-only tree without changing local Git state."""
from pathlib import Path
import hashlib, json, shutil, subprocess, tarfile

ROOT = Path(__file__).resolve().parents[2]
BASE = '9c948da8da413a882e0fe8e559c380ea0cadabf4'
OUT = ROOT / 'build/fit/probe-retime-20261116'
PROJECT = ROOT / 'scratch/probe-retime-matched-fit/project'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
# Historical replay freezes BASE explicitly; current master may be a descendant.
subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, 'HEAD'], cwd=ROOT, check=True)
assert not PROJECT.exists(), 'Do not overwrite a previous preparation'
OUT.mkdir(parents=True, exist_ok=True)
PROJECT.mkdir(parents=True)
subprocess.run(['git', 'archive', '--output', str(OUT / 'base.tar'), BASE], cwd=ROOT, check=True)
with tarfile.open(OUT / 'base.tar') as archive:
    archive.extractall(PROJECT)
qualified = json.loads((ROOT / 'docs/evidence/cache-probe-admission-retime-20261116.json').read_text())
payloads = {}
for name in ['cache_access.sv', 'cache_adapter.sv', 'cache_bank.sv', 'cache_tags.sv']:
    source = Path('tests/cpu/cache_probe_retime/rtl') / name
    assert sha(ROOT / source) == qualified['rtl_sha256'][str(source)]
    target = Path('rtl/arm920') / name
    shutil.copyfile(ROOT / source, PROJECT / target)
    payloads[str(target)] = sha(PROJECT / target)
support = PROJECT / 'tools/resident_store_fit'
support.mkdir()
shutil.copyfile(ROOT / 'tools/resident_store_fit/manifest.py', support / 'manifest.py')
manifest = (support / 'manifest.py').read_text().replace("'arm920_cache_access','arm920_cache_bank'", "'arm920_cache_adapter','arm920_cache_access','arm920_cache_bank'")
(support / 'manifest.py').write_text(manifest)
shutil.copyfile(ROOT / 'tools/probe_retime_fit/report.tcl', support / 'report.tcl')
bram = sha(PROJECT / 'rtl/ngage_bram.v')
assert bram == 'df7aa84abdca0e585b062c077cb01b0b9c9961316851b37a72622738e103ba71'
expected = dict(base=BASE, payloads=payloads, production_bram_sha256=bram, experiment='Stop 3D exact Stop 3C overlay', seed=42, debugger=True)
(support / 'expected.json').write_text(json.dumps(expected, indent=2)+'\n')
workflow = (ROOT / 'tools/probe_retime_fit/workflow.yml').read_text()
workflow = workflow.replace('Analyze resident store fit', 'Analyze retimed probe fit')
(PROJECT / '.github/workflows/ci_build.yml').write_text(workflow)
# Effective seed/debug + both host and /project graph spellings preflight.
qsf = (PROJECT / 'Template.qsf').read_bytes()
subprocess.run(['python3', 'tools/set_quartus_seed.py', 'Template.qsf', '--seed', '42'], cwd=PROJECT, check=True)
subprocess.run(['python3', 'tools/set_quartus_debug.py', 'Template.qsf', '--enabled', 'true'], cwd=PROJECT, check=True)
(PROJECT / 'output_files').mkdir(exist_ok=True)
graph = subprocess.check_output(['tclsh', 'tools/check_quartus_sources.tcl', '--list'], cwd=PROJECT, text=True)
for mode, text in [('host', graph), ('container', graph.replace(str(PROJECT), '/project'))]:
    path = OUT / f'preflight-{mode}-graph.txt'
    path.write_text(text)
    subprocess.run(['python3', 'tools/resident_store_fit/manifest.py', '--actual-commit', BASE+'+exact-3C-overlay', '--source-graph', str(path), '--output', str(OUT / f'preflight-{mode}-manifest.json')], cwd=PROJECT, check=True)
(PROJECT / 'Template.qsf').write_bytes(qsf)
entries = []
changed = []
for path in [*payloads, '.github/workflows/ci_build.yml', 'tools/resident_store_fit/manifest.py', 'tools/resident_store_fit/report.tcl', 'tools/resident_store_fit/expected.json']:
    entries.append(dict(path=path, mode='100644', type='blob', content=(PROJECT / path).read_text()))
    changed.append(path)
tracked = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
for path in tracked:
    if path in changed: continue
    original = subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)
    assert (PROJECT / path).read_bytes() == original, path
tree = subprocess.check_output(['git', 'rev-parse', BASE+'^{tree}'], cwd=ROOT, text=True).strip()
(OUT / 'tree-request.json').write_text(json.dumps(dict(base_tree=tree, tree=entries)))
(OUT / 'preparation.json').write_text(json.dumps(dict(expected=expected, changes=changed, base_tree=tree, project=str(PROJECT)), indent=2)+'\n')
print('PASS exact-base tree; four qualified cache payloads; production BRAM/PLL/constraints; both manifest path spellings')
