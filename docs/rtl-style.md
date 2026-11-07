# Phone RTL style

The maintained phone modules and `Template.sv` use the readable structure of
the pinned Nortido MiSTer reference: one explicit ANSI port per line, aligned
port/parameter connections and declarations, separated statements, and clear
block indentation. This repository's formatter uses four-space indentation
and a 100-column target. Long boolean groups retain their explicit line breaks.
Identifiers, comments, values and logic are preserved.

Scope: `Template.sv` and `rtl/ngage*.v` / `rtl/ngage*.sv`. Imported ZAP,
JTFRAME/SDRAM, PLL-generated and MiSTer framework sources keep their existing
styles. Tests and host tools are outside this RTL formatting command.

## Reproduce

Use Verible **v0.0-4298-g085eef05**, from the chipsalliance/verible release,
with the checked-in `.rules.verible_format` settings:

```sh
python3 tools/format_phone_rtl.py --formatter /path/to/verible-verilog-format
python3 tools/format_phone_rtl.py --formatter /path/to/verible-verilog-format --check
```

`--check` is read-only. An optional file list limits the scope. The script
expands inherited ANSI port declarations, for example `input wire clk, reset`
into explicit declarations for both ports, without changing their order or
types. For the timer's legal Verilog-2001 identifier `units`, which is a
SystemVerilog keyword, the formatter uses a same-width temporary identifier
and restores it before writing; the source identifier is never renamed.

The initial formatting pass was checked with Verible's token-equivalence
comparison against originals with only that explicit-port normalization.
All 51 files match. Formatter check mode is idempotent; source/QIP preflight,
structural top elaboration and existing board integration checks also pass.
The before/after hashes and comparison evidence are local under
`scratch/rtl-format/`.

Formatting changes source hashes. Existing simulation checkpoints remain
bound to their saved compiled executable; use the documented `--use-saved-build`
option rather than bypassing restore guards. The already-running frozen
12B simulation is independent of edits to these source files.
