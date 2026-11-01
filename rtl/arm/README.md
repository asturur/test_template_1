# ARM CPU (patched ZAP)

The N-Gage CPU core: [krevanth/ZAP](https://github.com/krevanth/ZAP) at the
commit pinned in `UPSTREAM.json`, with the ordered patch series in
`../../patches/zap/` applied. This is the only ZAP copy in the project: the
Quartus build (`files.qip`) and the Verilator boot simulations both compile
these files, so the FPGA runs the same CPU the simulation evidence came from.

- Integration boundary and configuration: `../ngage_cpu.sv`.
- What each patch changes and why: `docs/cpu-patches.md`.
- Edit rules: change files here, then record the change as the next numbered
  patch in `patches/zap/` (upstream-relative, `-p1`, `src/rtl/...` paths) and
  run `patches/zap/verify.sh`, which downloads the original upstream to
  `scratch/zap-upstream/` (reference only, git-ignored), checks it against the
  pin, applies the series and requires a byte-identical match with this folder.

License: GPL-3.0-or-later (`LICENSE`, from upstream).
