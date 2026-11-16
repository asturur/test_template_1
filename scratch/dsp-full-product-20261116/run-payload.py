from pathlib import Path
import sys,importlib.util
root=Path.cwd();directory=root/'tests/cpu/spmark_payload';sys.path.insert(0,str(directory))
spec=importlib.util.spec_from_file_location('isolated_payload_run',directory/'run.py');runner=importlib.util.module_from_spec(spec);spec.loader.exec_module(runner)
original_support=runner.support
def support():
    bench=original_support();original=bench.snapshot
    def snapshot(destination,revision=None,root=root):
        result=original(destination,revision,root)
        candidate=(root/'scratch/dsp-full-product-20261116/candidate.sv').read_text().replace('dsp_full_product_candidate','zap_shifter_multiply')
        (destination/'rtl/arm/zap_shifter_multiply.sv').write_text(candidate)
        return bench.source_manifest(destination,result['commit'],'isolated-dsp-full-product')
    bench.snapshot=snapshot
    return bench
runner.support=support
runner.main()
