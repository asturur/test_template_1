"""Compile one passive test peer per frozen source closure."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

from source import HERE, IMAGE, ROOT, compiler_sources, freeze

OUT = ROOT/'build/sim/tlb-three-mapping'
CPU = ROOT/'tests/cpu'
DOCKER = ['docker', 'run', '--rm', '--pull=never', '--network', 'none',
          '--platform', 'linux/arm64', '-v', str(ROOT)+':/work', '-w', '/work', '--entrypoint']


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def sha(path):
    return digest(path.read_bytes())


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def cpath(path):
    return '/work/' + str(path.relative_to(ROOT))


def command(args, log, *, negative=False):
    args = [str(arg) for arg in args]
    with log.open('w') as out:
        out.write(json.dumps(args) + '\n')
        out.flush()
        code = subprocess.run(args, cwd=ROOT, stdout=out, stderr=subprocess.STDOUT).returncode
    if code and not negative:
        raise RuntimeError(f'command failed: {log}')
    return code


def replace(source, old, new):
    assert source.count(old) == 1, old
    return source.replace(old, new, 1)


def harness(full_scan=False):
    tb = (CPU/'spmark_payload/tb.v').read_text()
    # Same memory model and timing boundaries. JPEG chooses its original
    # firmware region, and game spans reuse the original operand-pop markers.
    tb = tb.replace("32'h10000000", 'payload_base').replace("32'h10100000", "(payload_base+32'h100000)")
    if full_scan:
        tb = tb.replace("ram[0:32767]","ram[0:65535]").replace("n<32768","n<65536")
        tb = tb.replace("32'h0a020000","32'h0a040000").replace("[16:2]","[17:2]")
        # The original virtual FbsCli code is backed by the firmware peer's
        # standard 0x50300000 physical window, leaving wait classification intact.
        tb = replace(tb, "if(retire_pc>=32'h50300000 && retire_pc<32'h50400000)",
                     "if(retire_pc>=32'h50500000 && retire_pc<32'h50600000)")
    return apply_instrumentation(tb)


def apply_instrumentation(tb):
    changes = [
        ('module bench;', """module bench;
    reg [31:0] payload_base=32'h10000000;
    integer span_mode=0;
    wire j_select=dut.u_zap.u_zap_core.data_select_p1;
    `include "observe.vh"
    `include "span.vh"
"""),
        ('            if(retire && retire_pc==begin_pc) begin',
         '''            mapping_sample();
            if(span_mode!=0)span_sample();
            if(retire && retire_pc==begin_pc) begin'''),
        ('start_helper_ops=helper_ops;', 'start_helper_ops=helper_ops;mapping_begin();'),
        ('                windows=windows+1;', '                mapping_end();\n                windows=windows+1;'),
        ('                        $display("RESULT ', '                        mapping_total();\n                        $display("RESULT '),
        ('    initial begin\n', '''    initial begin
        if(!$value$plusargs("payload_base=%h",payload_base))payload_base=32'h10000000;
        if(!$value$plusargs("mapping_trace=%d",trace_mode))trace_mode=0;
        if(!$value$plusargs("span_mode=%d",span_mode))span_mode=0;
        if(!$value$plusargs("stream_mode=%d",stream_mode))stream_mode=0;
'''),
    ]
    for old, new in changes:
        tb = replace(tb, old, new)
    return tb


def build(out, candidate, jobs, full_scan, observer=None):
    out.mkdir(parents=True, exist_ok=False)
    source = out/'source'
    frozen = freeze(source, candidate)
    (out/'tb.v').write_text(harness(full_scan))
    (out/'observe.vh').write_bytes(observer if observer is not None else (HERE/'observe.vh').read_bytes())
    span = (CPU/'super_monkey_ball/observe.vh').read_text()
    span = replace(span, '`SC.completion_next ?', 'j_select ?')
    span = replace(span, '        start_cycle=cycles;', '        mapping_begin();\n        start_cycle=cycles;')
    span = replace(span, '            windows=windows+1;', '            mapping_end();\n            windows=windows+1;')
    (out/'span.vh').write_text(span)
    image = subprocess.check_output(['docker', 'image', 'inspect', IMAGE, '--format', '{{.Id}}'], text=True).strip()
    exe = out/'obj/Vbench'
    manifest = dict(source=frozen, image=image, candidate=candidate, full_scan=full_scan,
                    harness={n: sha(out/n) for n in ('tb.v', 'observe.vh', 'span.vh')})
    save(out/'manifest.json', manifest)
    command(DOCKER+['verilator', IMAGE, '--binary', '--timing', '--assert', '-j', str(jobs),
                    '-Wno-fatal', '-Wno-lint', '-DNGAGE_RUNTIME_TRACE', '-DBENCH_HAS_LINE',
                    '-GLINE_ENABLE=1', '--top-module', 'bench', '--Mdir', cpath(exe.parent),
                    '-I'+cpath(out), '-I'+cpath(source/'rtl/arm')]
            + (['-DTHIRD_SLOT'] if candidate else [])
            + [cpath(path) for path in compiler_sources(source)] + [cpath(out/'tb.v')], out/'build.log')
    manifest['executable_sha256'] = sha(exe)
    save(out/'manifest.json', manifest)
    print(f'Built {out}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--candidate', action='store_true')
    parser.add_argument('--full-scan', action='store_true')
    parser.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    assert Path(args.name).name == args.name and args.name not in ('.', '..')
    build(OUT/args.name, args.candidate, args.jobs, args.full_scan)
