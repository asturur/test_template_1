#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$root"
# Keep program.hex, generated fixture and build objects together. Rewriting
# only the shell output path would silently load another test's guest program.
python3 - <<'PY'
from pathlib import Path
import re
root=Path.cwd()
out=Path('build/sim/unit-completion-overlap')
out.mkdir(parents=True,exist_ok=True)
s=Path('tests/cpu/core/sim.sh').read_text()
s=re.sub(r'^root=.*$', 'root='+str(root), s, flags=re.M)
s=s.replace('build/sim/unit-core',str(out))
s=s.replace('tests/cpu/core/test.sv',str(out/'test.sv'))
s=s.replace('--rm --network none','--rm --pull=never --network none')
s=s.replace('--binary --timing','--binary -j 3 --timing')
(out/'run.sh').write_text(s)
(out/'test.sv').write_text(Path('tests/cpu/core/test.sv').read_text().replace(
    'build/sim/unit-core',str(out)))
PY
CPU_PROGRAM=completion_overlap CPU_RUN_ARGS=+completion_overlap_check \
CPU_LOAD_FORWARD_CHECK=1 CPU_BRANCH_OWNER_CHECK=1 \
sh build/sim/unit-completion-overlap/run.sh
