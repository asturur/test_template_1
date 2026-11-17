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
  `build/tool-cache/zap-upstream-<commit>/` using `gh`, checks it against the
  pin, applies the series and requires a byte-identical match with this folder.

License: GPL-3.0-or-later (`LICENSE`, from upstream).

Patch0073 reconciles the already-qualified integration baseline (including its
formatting/full-product multiplier) so strict byte replay works. Patch0074 carries
the exact qualified resident-store/CPU overlap/frontend payloads through5A. The
legacy scratch upstream checkout is not modified by verification. See
[5A source/build and timing](../../docs/cpu-frontend-delivery-fit.md).

Patch0075 separates private owner payload selection from final demand qualification;
see docs/cpu-owner-split.md. The private direction extension is in arm920/cache_adapter.sv.
