# Vendored Verible formatter

`macos/bin/verible-verilog-format` is the unmodified official macOS ARM64
binary from Verible **v0.0-4298-g085eef05**. It runs natively on Apple Silicon
without Docker. Only the formatter is vendored, not the rest of the tool suite.

`manifest.json` records the release URL, archive checksum and executable checksum.
The official project license and bundled notices are retained in `LICENSE`.

Run the executable directly with its default style:

```sh
tools/verible/macos/bin/verible-verilog-format path/to/file.v
```

The default command prints formatted code. Add `--inplace` to update the file.

Enable the tracked shell hook once per checkout:

```sh
git config --local core.hooksPath .githooks
```

The hook calls the executable directly in `--verify` mode on staged contents.
It uses the default style, with no Python wrapper or custom configuration.
It rejects unformatted commits without rewriting or staging files.

Coverage is `Template.sv`, top-level `rtl/ngage*.v` / `rtl/ngage*.sv`, and staged
`.v` / `.sv` files under `tests/` and `scratch/`. Imported CPU/framework sources
and generated PLL sources retain their existing styles.

The bundled binary is ARM64. Other platforms can set `VERIBLE_FORMATTER` to a
matching local executable. No formatter runs when the commit has no covered files.
