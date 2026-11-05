#!/usr/bin/env python3
"""Build the current ARM920 CPU with the preserved full boot board; do not run it."""
from pathlib import Path
import hashlib, json, subprocess, shutil, sys
root = Path(__file__).resolve().parents[2]
rtl = root / 'rtl/arm'
# The current board is the maintained source of this build. Never overwrite it
# with the older frozen board: it contains current flash and display fixes.
board = root / 'scratch/current-boot/board'
if not board.is_dir():
    raise SystemExit('Current board sources missing; restore scratch/current-boot/board')
hdl_board = '--hdl-board' in sys.argv[1:]
if any(arg != '--hdl-board' for arg in sys.argv[1:]):
    raise SystemExit('usage: build.py [--hdl-board]')
obj = root / ('build/sim/obj-current-hdl-board' if hdl_board else 'build/sim/obj-current-boot')
sources = [root/'rtl/ngage_cpu.sv', board/'ngage_cpu_sim.sv', *sorted(rtl.glob('*.sv')), *sorted((root/'rtl/arm920').glob('*.sv'))]
if hdl_board:
    sources += [root/'rtl'/name for name in ('ngage_board.v','ngage_bram_be.v','ngage_sparse_regs.v','ngage_icu.v','ngage_timers.v','ngage_nos_io.v','ngage_mdi_stub.v','ngage_cbus_uem.v','ngage_gpio_loopback.v','ngage_boot_regs.v','ngage_trace_sink.v')]
inputs = sources + sorted(rtl.glob('*.svh')) + [board/'main.cpp', board/'boot_profile.cpp', board/'boot_profile.h', board/'descramble_model.h', board/'nos_stub_blob.h', root/'scratch/modem/ngage_modem.c', root/'scratch/modem/ngage_modem.h', Path(__file__)]
command = ['docker','run','--rm','--network','none','--platform','linux/arm64','-v',f'{root}:/work','-w','/work','--entrypoint','verilator','jotego/simulator:arm64','--cc','--exe','--build','-j','4','--savable','--assert','-DNGAGE_RUNTIME_TRACE','-DNGAGE_ASSOC_EXPERIMENT','-Wno-fatal','-Wno-lint','--x-initial','0','--x-assign','0','--top-module','ngage_cpu_sim','--Mdir',str(obj.relative_to(root)),'-Irtl/arm',*[str(p.relative_to(root)) for p in sources],'/work/scratch/current-boot/board/main.cpp','/work/scratch/current-boot/board/boot_profile.cpp','/work/scratch/modem/ngage_modem.c']
if hdl_board:
    command[command.index('--top-module'):command.index('--top-module')] = ['-DNGAGE_HDL_BOARD','-CFLAGS','-DNGAGE_HDL_BOARD']
log = root/('build/sim/build-current-hdl-board.log' if hdl_board else 'build/sim/build-current-boot.log')
with log.open('w') as out:
    result = subprocess.run(command,cwd=root,stdout=out,stderr=subprocess.STDOUT)
if result.returncode:
    print('\n'.join(log.read_text(errors='replace').splitlines()[-30:]))
    raise SystemExit(result.returncode)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={'inputs':{str(p.relative_to(root)):sha(p) for p in inputs},'binary_sha256':sha(obj/'Vngage_cpu_sim'),'command':command}
(obj/'ngage-build-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Built',obj/'Vngage_cpu_sim')
