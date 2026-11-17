#!/usr/bin/env python3
"""Reuse probe/admission tests with the 4C cache and adapter, credits disabled."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
path=ROOT/'tests/cpu/cache_probe_retime/run.py'
text=path.read_text()
old='src=[overlay/s.name if (overlay/s.name).exists() else s for s in src]'
new="candidate=ROOT/'tests/cpu/cpu_load_overlap/rtl/arm920'\nsrc=[candidate/s.name if (candidate/s.name).exists() else overlay/s.name if (overlay/s.name).exists() else s for s in src]"
text=text.replace("(out/'test.v').write_text(tb)", """tb=tb.replace(".fast_enable(", ".load_pair_enable(1'b0),.store_overlap_enable(1'b0),.fast_enable(").replace(".fast_lookup_enable(", ".data_probe_pair(1'b0),.req_store_credit_enable(1'b0),.fast_lookup_enable(")
(out/'test.v').write_text(tb)""")
assert text.count(old)==1
exec(compile(text.replace(old,new),str(path),'exec'),{'__file__':str(path),'__name__':'__main__'})
