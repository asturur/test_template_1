"""Capture original Sega Rally submissions and replay the PCM through the RTL."""
import argparse
from array import array
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[3]
ROM_SHA = 'be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524'
CARD_SHA = '074dc99c87bad88c246459508db8221532ae61cdd4722cf42f355cdd382c0c63'
BENCH_SHA = '0a404ad066c1b145cd6953d0d4725e23fc08a9a744d8baeee5e5b76c4f69b7e2'
KEYS = '24:a 24.25: 34:a 34.25: 45:rsoft 45.25:'


def capture(out, rom, card, reference, omit_initial_ack, bridge=False,
            keys=KEYS, seconds=55, screenshots=False, relaunch_at=None):
    assert hashlib.sha256(rom.read_bytes()).hexdigest() == ROM_SHA, 'unexpected NEM-4 ROM'
    raw = card.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == CARD_SHA, 'unexpected Sega Rally image'
    lba = int.from_bytes(raw[454:458], 'little')
    sectors = int.from_bytes(raw[458:462], 'little')
    partition = bytearray(raw[lba * 512:(lba + sectors) * 512])
    assert partition[510:512] == b'\x55\xaa'
    launch = b'NGVMRUN\0E:\\System\\Apps\\6R12\\6R12.app\0'
    partition[0x40:0x40 + len(launch)] = launch
    drive = out / 'game.img'
    drive.write_bytes(partition)

    guest = out / 'guest'
    for name in ('sw', 'tools'):
        shutil.copytree(reference / name, guest / name, ignore=shutil.ignore_patterns('__pycache__'))
    chan = guest / 'sw/kernel/chan.c'
    source = chan.read_text()
    old = '    if (n < 10 || m[9] == 0xF0) return KErrNone;'
    assert source.count(old) == 1
    source = source.replace(old, old + '''
    if (m[3] == 0xe8 && n >= 14) {
        kprintf("[pcm] msg %02x unit %d tx %02x rx %02x length %d\\n",
                m[9], c->unit, m[7], m[6], n);
    }''')
    if bridge:
        firmware = ROOT / 'firmware_overlays/game_pcm'
        for name in ('stream.c', 'stream.h'):
            shutil.copyfile(firmware / name, chan.with_name(name))
        first = source.index('static void dsp_send(')
        end = source.index('/* ---- the DSP\'s tone player', first)
        adapter = Path(__file__).with_name('reference_bridge.inc').read_text()
        source = '#include "stream.h"\n' + source[:first] + adapter + '\n' + source[end:]
        old = '    for (int q = 0; q < ISI_REPLIES; q++) {'
        start = source.index('static s32 nos_control(')
        at = source.index(old, start)
        source = source[:at] + '''    if (m[3] == PCM_RESOURCE) {
        bridge_send(c, m, n);
        return KErrNone;
    }
''' + source[at:]
        source = source.replace('        if (m[3] == 0xE8) dsp_request(c, m, n, r);\n', '')
        first = source.index('#define DSP_BASE')
        end = source.index('static void isi_post(', first)
        source = source[:first] + source[end:]
    elif omit_initial_ack:
        old = '        if (m[3] == 0xE8) dsp_request(c, m, n, r);'
        assert source.count(old) == 1
        source = source.replace(old, '''        if (m[3] == 0xE8) {
            dsp_request(c, m, n, r);
            if (m[9] == 0x23) return KErrNone;
        }''')
    chan.write_text(source)
    if relaunch_at is not None:
        launch = chan.with_name('launch.c')
        code = launch.read_text()
        code = code.replace('    if (state != 2) {', '    if (state != 2 && state != 4) {')
        code = code.replace('    state = 3;\n    launch_due = ~0ull;',
                            f'    int restart = state == 4;\n'
                            f'    state = restart ? 3 : 4;\n'
                            f'    launch_due = restart ? ~0ull : {round(relaunch_at * 1e6)}ull;')
        code = code.replace('    if (f_msv_connect) {', '    if (!restart && f_msv_connect) {')
        launch.write_text(code)
    with (out / 'guest-build.log').open('w') as log:
        subprocess.run(['make', '-C', guest / 'sw/kernel'], stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=120)
    wav = out / 'guest.wav'
    with (out / 'guest.log').open('w') as log:
        frames = ['--frames-to', out / 'screens', '--frame-every', '120'] if screenshots else []
        subprocess.run([sys.executable, '-B', guest / 'tools/ngvm/ngvm.py',
                        '--rom', rom, '--drive', drive, '--seconds', str(seconds), '--mips', '100',
                        '--stamp', '--keys', keys, '--wav', wav, *frames], stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=120)

    log = (out / 'guest.log').read_text()
    events = Counter(re.findall(r'\[pcm\] msg ([0-9a-f]{2}) unit', log))
    assert events['20'] and events['23']
    assert (events['27'] == 0) if omit_initial_ack else events['27'] > 0
    if bridge:
        assert '[bridge] unhandled' not in log
    lifecycle = re.findall(r'^\[\s*([0-9.]+) s\] \[bridge\] reply (21|2b) bytes (\d+)',
                           log, re.MULTILINE)
    if relaunch_at is not None:
        assert bridge and [item[1] for item in lifecycle[:3]] == ['21', '2b', '21']
        assert events['20'] >= 2 and events['23'] >= 2
        assert log.count('[bridge] first nonzero sample') >= 2
    with wave.open(str(wav), 'rb') as file:
        assert (file.getnchannels(), file.getsampwidth(), file.getframerate()) == (2, 2, 16000)
        stereo = array('h', file.readframes(file.getnframes()))
    assert stereo[::2] == stereo[1::2], 'original stream is expected to be mono'
    mono = stereo[::2]
    audible = next((i for i, sample in enumerate(mono) if sample), None)
    assert audible is not None and len(mono) - audible >= 32000, 'missing game audio'
    mono_wav = out / 'mono.wav'
    with wave.open(str(mono_wav), 'wb') as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(16000)
        if sys.byteorder != 'little':
            mono.byteswap()
        file.writeframes(mono[audible:].tobytes())
    return dict(events=events, lifecycle=lifecycle, frames=len(mono), nonzero_frames=sum(v != 0 for v in mono),
                first_audible_frame=audible, wav_sha256=hashlib.sha256(mono_wav.read_bytes()).hexdigest())


def replay(out, donor):
    bench = donor / 'sim/harness/haudio_main.cpp'
    assert hashlib.sha256(bench.read_bytes()).hexdigest() == BENCH_SHA, 'unexpected donor verifier'
    source = bench.read_text().replace('Vupp_haudio', 'Vngage_game_pcm')
    substitutions = (
        ('\tuint32_t done = 0;', '\tuint32_t done = 0, firmware_context = 0;'),
        ('\t\tcase 0x2C: return played;', '\t\tcase 0x2C: return played;\n'
         '\t\tcase 0x30: return firmware_context;'),
        ('\t\tcase 0x28: volume = std::min(v, 0x100u); break;',
         '\t\tcase 0x28: volume = std::min(v, 0x100u); break;\n'
         '\t\tcase 0x30: firmware_context = v; break;'),
        ('\tfor (uint32_t o = 0x30;', '\tCHECK_EQ(b.read(0x30), 0, "CONTEXT resets to zero");\n'
         '\tb.write(0x30, 0x80123400);\n'
         '\tCHECK_EQ(b.read(0x30), 0x80123400, "CONTEXT round trip");\n'
         '\tfor (uint32_t o = 0x34;'),
    )
    for before, after in substitutions:
        assert source.count(before) == 1, before
        source = source.replace(before, after)
    (out / 'bench.cpp').write_text(source)
    shutil.copyfile(bench.with_name('common.h'), out / 'common.h')
    subprocess.run(['docker', 'run', '--rm', '--pull', 'never', '--network', 'none',
                    '--platform', 'linux/arm64', '-v', f'{ROOT}:/repo', '-w', '/repo',
                    '--entrypoint', '/bin/sh', 'jotego/simulator:arm64', '-ec', '''
verilator --cc --exe --build -j 3 -Wno-fatal --assert --top-module ngage_game_pcm \
    -GCLK_HZ=78000000 --Mdir "$1/obj" rtl/ngage_game_pcm.v "$1/bench.cpp" > "$1/rtl-build.log" 2>&1
"$1/obj/Vngage_game_pcm" --clk-hz 78000000 --wav "$1/mono.wav" --wav-frames 32000 --out "$1" > "$1/rtl.log"
''', 'replay', f'/repo/{out.relative_to(ROOT)}'], check=True, timeout=180)
    log = (out / 'rtl.log').read_text()
    assert 'haudio: all checks passed' in log and '32000 frames of' in log and 'skipped' not in log
    print(log, end='')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('name')
    p.add_argument('--mmc', required=True, type=Path)
    p.add_argument('--rom', default=ROOT / 'build/firmware/nem4-factory/core.bin', type=Path)
    p.add_argument('--reference', default=ROOT / 'build/tool-cache/ngvm4', type=Path)
    p.add_argument('--donor', default=ROOT.parent / 'ngage2', type=Path)
    p.add_argument('--omit-initial-ack', action='store_true')
    p.add_argument('--bridge', action='store_true')
    p.add_argument('--keys', default=KEYS)
    p.add_argument('--seconds', type=float, default=55)
    p.add_argument('--screenshots', action='store_true')
    p.add_argument('--relaunch-at', type=float, help='Schedule a second AppRun at this virtual second')
    a = p.parse_args()
    assert a.name == Path(a.name).name and a.name not in ('', '.', '..')
    out = ROOT / 'build/sim' / a.name
    out.mkdir()
    evidence = capture(out, a.rom, a.mmc, a.reference, a.omit_initial_ack,
                       a.bridge, a.keys, a.seconds, a.screenshots, a.relaunch_at)
    (out / 'receipt.json').write_text(json.dumps(evidence, indent=2) + '\n')
    replay(out, a.donor)
