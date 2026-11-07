#!/usr/bin/env python3
"""Format maintained phone RTL with Verible; leave imported CPU/framework alone.

Use Verible v0.0-4298-g085eef05 (see docs/rtl-style.md). --check is read-only.
Shared ANSI port declarations are expanded before formatting so every port
explicitly states its direction/type, as in the Nortido reference.
"""
import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Keep offsets stable while locating syntax: comments and strings cannot
# contribute parentheses or commas to a module header.
TRIVIA = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"', re.S)
PORT = re.compile(
    r'^\s*((?:input|output|inout)\b\s*'
    r'(?:(?:wire|reg|logic|tri|var|bit|signed|unsigned|integer|int)\b\s*|\[[^\]]*\]\s*)*)'
)


def explicit_ports(text):
    masked = TRIVIA.sub(lambda m: ' ' * len(m[0]), text)
    edits = []
    for module in re.finditer(r'\bmodule\s+\w+\s*', masked):
        pos = module.end()
        if masked[pos:pos + 1] == '#':
            pos = masked.index('(', pos)
            depth = 1
            pos += 1
            while depth:
                depth += (masked[pos] == '(') - (masked[pos] == ')')
                pos += 1
            while masked[pos].isspace():
                pos += 1
        if masked[pos:pos + 1] != '(':
            continue
        start = pos + 1
        parens, brackets, braces = 1, 0, 0
        segments = []
        while parens:
            pos += 1
            ch = masked[pos]
            if ch == '(':
                parens += 1
            elif ch == ')':
                parens -= 1
            elif ch == '[':
                brackets += 1
            elif ch == ']':
                brackets -= 1
            elif ch == '{':
                braces += 1
            elif ch == '}':
                braces -= 1
            if (ch == ',' and parens == 1 and not brackets and not braces) or not parens:
                segments.append((start, pos))
                start = pos + 1
        qualifier = None
        for begin, end in segments:
            part = masked[begin:end]
            match = PORT.match(part)
            if match:
                qualifier = match[1].strip() + ' '
            elif qualifier and part.strip():
                # Insert after leading trivia, preserving comments verbatim.
                name = re.search(r'\S', part)
                edits.append((begin + name.start(), qualifier))
    for pos, value in reversed(edits):
        text = text[:pos] + value + text[pos:]
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--formatter', default='verible-verilog-format')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('files', nargs='*', type=Path)
    args = parser.parse_args()
    files = args.files or [Path('Template.sv')] + sorted(
        p for p in Path('rtl').glob('ngage*') if p.suffix in ('.v', '.sv')
    )
    changed = []
    for path in files:
        original = path.read_text()
        expanded = explicit_ports(original)
        # "units" is a legal Verilog-2001 identifier used by our timer,
        # but a SystemVerilog keyword to Verible. Use an equal-width temporary
        # identifier only inside the formatter, then restore the exact token.
        if re.search(r'\b_unit\b', expanded):
            raise SystemExit(f'{path}: reserved formatter placeholder already present')
        masked = TRIVIA.sub(lambda m: ' ' * len(m[0]), expanded)
        safe = expanded
        for match in reversed(list(re.finditer(r'\bunits\b', masked))):
            safe = safe[:match.start()] + '_unit' + safe[match.end():]
        result = subprocess.run(
            [args.formatter, '--flagfile=.rules.verible_format',
             '--stdin_name=' + str(path), '-'],
            input=safe, text=True, capture_output=True,
        )
        if result.returncode:
            raise SystemExit(f'{path}: {result.stderr.strip()}')
        formatted = re.sub(r'\b_unit\b', 'units', result.stdout)
        if formatted != original:
            changed.append(str(path))
            if not args.check:
                path.write_text(formatted)
    print(f'{len(files)} files checked; {len(changed)} ' +
          ('need formatting' if args.check else 'formatted'))
    if args.check and changed:
        raise SystemExit(1)


if __name__ == '__main__':
    if Path.cwd() != ROOT:
        raise SystemExit('Run from the repository root')
    main()
