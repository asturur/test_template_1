#!/usr/bin/env python3
"""Run existing owner/reset fixtures sequentially in a dedicated output tree."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

root = Path(__file__).resolve().parents[3]
out = root / "build/sim/peripheral-memory-placement-20261117"
out.mkdir(parents=True, exist_ok=True)
receipt = []
for name in ("regional_ownership", "board_wrapper", "board_inventory"):
    source = root / f"tests/phone/{name}/run.sh"
    script = re.sub(r"build/sim/unit-[a-z-]+",
                    f"build/sim/peripheral-memory-placement-20261117/{name}",
                    source.read_text())
    start = time.monotonic()
    run = subprocess.run([
        "docker", "run", "--rm", "-i", "--network", "none", "--platform", "linux/arm64",
        "-v", f"{root}:/work", "-w", "/work", "--entrypoint", "sh",
        "jotego/simulator:arm64", "-s"], input=script, text=True, capture_output=True)
    (out / f"{name}.log").write_text(run.stdout + run.stderr)
    receipt.append(dict(test=name, exit_code=run.returncode,
                        seconds=round(time.monotonic() - start, 3),
                        runner_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                        pass_lines=[s for s in run.stdout.splitlines() if s.startswith("PASS")]))
    print(receipt[-1], flush=True)
    if run.returncode:
        break
(out / "tests.json").write_text(json.dumps(receipt, indent=2) + "\n")
assert len(receipt) == 3 and all(r["exit_code"] == 0 and r["pass_lines"] for r in receipt)
