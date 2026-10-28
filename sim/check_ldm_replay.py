#!/usr/bin/env python3
"""Report whether the known cold-cache LDM replay bug is fixed."""
import sys
import run


def main():
    info=run.environment();binary=run.build_simulator(info,'ngage')
    rom=run.assemble('ldm_base_coldcache');passed=True
    for latency in (0,3):
        name=f'ldm_base_coldcache-check-latency{latency}'
        try:
            result=run.run_case(binary,name,rom,latency=latency,expected_status='pass')
            print(f'PASS cold-cache LDM at latency {latency}')
        except RuntimeError as exc:
            path=run.BUILD/'runs'/name/'result.json'
            if not path.exists() or not path.stat().st_size:raise
            import json
            result=json.loads(path.read_text())
            if result.get('status')!='diagnostic_failure' or result.get('completion')!=0x21:
                raise RuntimeError(f'unexpected cold-cache test result: {exc}') from exc
            print(f'GAP cold-cache LDM replay changes base at latency {latency}')
            passed=False
    return 0 if passed else 1

if __name__=='__main__':
    try:sys.exit(main())
    except (OSError,ValueError,RuntimeError) as error:sys.exit(str(error))
