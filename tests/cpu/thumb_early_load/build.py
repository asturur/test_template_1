"""Build the isolated Thumb experiment or the published banked integration."""
import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PEER = HERE.parent/'tlb_three_mapping'
sys.path.insert(0, str(PEER))
spec = importlib.util.spec_from_file_location('mapping_bench_build', PEER/'build.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)
from source import BASE, support

BANKED_THIRD = '1928aeef68cbd65699014854326c38101f5249a7'
CHANGED = {
    'rtl/arm/zap_core.sv', 'rtl/arm/zap_issue_main.sv', 'rtl/arm/zap_predecode_main.sv'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('variant', choices=['control', 'thumb', 'banked-third'])
    parser.add_argument('name')
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--full-scan', action='store_true')
    args = parser.parse_args()
    assert Path(args.name).name == args.name and args.name not in ('.','..')
    def snapshot(dest, third):
        if third:
            return support.snapshot(dest, BANKED_THIRD)
        original = bench_original_freeze(dest, False)
        if args.variant == 'control':
            return original
        subprocess.run(['git','apply','--no-index','--directory='+str(dest.relative_to(bench.ROOT)),str(HERE/'thumb-load.patch')],cwd=bench.ROOT,check=True)
        record = support.source_manifest(dest, BASE, '5L with Thumb early scalar loads')
        assert {k for k,h in original['files'].items() if record['files'][k]!=h} == CHANGED
        return record
    bench_original_freeze = bench.freeze
    bench.freeze = snapshot
    observer = (PEER/'observe.vh').read_text()
    extra = (HERE/'observe.vh').read_text()
    observer = extra + observer
    for task in ("begin", "sample", "end"):
        name = f"task mapping_{task};"
        after_begin = observer.index("    begin\n", observer.index(name))
        after_begin += len("    begin\n")
        observer = observer[:after_begin] + f"        thumb_{task}();\n" + observer[after_begin:]
    bench.build(bench.OUT/args.name, args.variant=='banked-third', args.jobs,
                args.full_scan, observer.encode())

if __name__ == '__main__':
    main()
