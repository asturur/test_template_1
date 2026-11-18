"""Exercise copied instruction-line ownership through the real cache adapter."""
import argparse
import json
from pathlib import Path

from experiment import HERE, peer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('name')
    parser.add_argument('--build', required=True)
    parser.add_argument('--negative', action='store_true')
    args = parser.parse_args()
    for name in (args.name, args.build):
        assert Path(name).name == name and name not in ('.', '..')
    out = peer.OUT / args.name
    out.mkdir(exist_ok=False)
    build = peer.OUT / args.build
    manifest = json.loads((build / 'manifest.json').read_text())
    source = build / 'source'
    rtl = [source / 'rtl/ngage_bram.v', *sorted((source / 'rtl/arm920').glob('*.sv'))]
    for path in rtl:
        assert peer.sha(path) == manifest['source']['files'][str(path.relative_to(source))]
    test = HERE / 'stream_safety.sv'
    exe = out / 'obj/Vtest'
    peer.command(peer.DOCKER + ['verilator', peer.IMAGE, '-j', '2', '--binary', '--timing',
        '--assert', '-Wno-fatal', '-Wno-lint', '--top-module', 'test', '--Mdir', peer.cpath(exe.parent)]
        + [peer.cpath(path) for path in (*rtl, test)], out / 'build.log')
    result = out / 'run.log'
    rc = peer.command(peer.DOCKER + [peer.cpath(exe), peer.IMAGE], result, negative=args.negative)
    line = 'fast path at 80001020' if args.negative else 'PASS resident alternation'
    assert (rc != 0) == args.negative and line in result.read_text(), result
    peer.save(out / 'result.json', dict(status='PASS', negative=args.negative, source=manifest['source'],
                                       test=peer.sha(test), log=peer.sha(result)))
    print(next(s for s in result.read_text().splitlines() if line in s))


if __name__ == '__main__':
    main()
