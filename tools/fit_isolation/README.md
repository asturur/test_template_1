# CPU and platform timing isolation

The **CI Build** workflow accepts `fit_scope=cpu-only` and
`fit_scope=board-only`. Both select the existing Quartus 17.0.2
Cyclone V project, fitter settings, physical 104 MHz PLL and fitter
seed. The diagnostic job requires DDR debugging off and publishes
reports only. `fit_scope=production` selects the normal build.

- **CPU only** fits the production `ngage_cpu` wrapper with its two
  16 KiB caches, TLBs, 32-byte line refill and block writeback. A
  synchronous peer returns scalar and narrow or wide line responses.
  Its small ARM guest enables the MMU and I-cache and exercises RAM
  and SWP. Synchronized switches select varying data, line rejection
  and narrow beats. The fixture SDC constrains the real PLL input and
  identifies asynchronous switches and visual readouts. SDRAM pin
  checks apply to the board fit.
- **Board only** fits the production MiSTer shell and phone platform
  with its original SDC. In a Git archive of the selected commit, one
  UPP instance selects a registered transaction peer with the same
  port signature. It issues SDRAM scalar and block commands, bus
  locks, flash and peripheral accesses, native lines and eight scalar
  fallback reads after a line rejection. All scalar and line output
  packets are registered, and the response sink captures both data
  buses and control.

`tools/fit_isolation/run-smoke.sh` uses the installed offline simulator.
It exercises the real CPU on the registered peer and the generated
board peer on the real CPU memory route with modeled subordinate
responses. Quartus separately elaborates the full board fit and
reports its physical pin registers.

Each artifact includes selected source hashes, fitted hierarchy, the
official RAM and Fitter reports, physical clock evidence, constraint
coverage and 1,000 setup paths across the design plus 1,000 within
`clk_sys` per operating corner. The four path groups split same-clock
DUT and fixture endpoints by fitted hierarchy. Their reports include
full routing details for the worst paths. The pin and report coverage
checks are separate from measured setup slack.

Removing a device changes placement, utilization, and some boundary
logic. Compare each seed to the same production seed. Use the two
diagnostic distributions to localize timing pressure. The fixtures
use authored traffic and their boundary measurements describe that
traffic and placement.
