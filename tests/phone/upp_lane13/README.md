# UPP GPIO and EUART response edges

Run from the trial source root with Icarus Verilog from the offline
Jotego toolchain. Give the runner a source directory for the exact
unmodified control (`e9552bd` for the original timing comparison).

```sh
sh tests/phone/upp_lane13/run.sh /path/to/control
```

The bench connects the production registered bus bridge and request
stage to the registered peripheral responder. Its stimulus represents a
held CPU request and uses the board's registered peripheral-error rule.
It can independently hold commit or the bridge acknowledgment to
exercise the distinction between sampling a response and returning it.
The full-board mixed test covers the real CPU, local DMA and other bus
masters.

The runner compares cycle-stamped launch, authorization, response,
ownership and visible FIFO/IRQ events with and without the keypad
model. It also checks expected values and earliest cycles. At nominal
104 MHz, let E0 be the edge that captures the request. An immediate
access samples register data and performs authorized effects at E1,
raises the registered CPU response at E2 and consumes that response at E3.
A GPIO RAM read uses E1 for the synchronous RAM and samples at E2.
The bench offers the next request with CYC still asserted and no
extra idle clock after CPU consumption.

Cases include all EUART word/mask/direction combinations, byte
aliases, a neighboring GPIO address, GPIO BRAM writes and reads,
coincident RX and status sampling, SIMIF/EUART overlap and card
backpressure, NOS-owned status and GPIO loopback overlays, key changes
near authorization, a full and cancelled TX, and a held reply across
warm reset. Trace logs are written to `build/sim/unit-upp-lane13`.
