# Two-edge UPP register responses

From the snapshot root, pass the unmodified `e7f1e31` source directory
to the comparison. Both runs use the production bus bridge and
request-stage modules. The test replaces only the upstream CPU master
and the board fault register.

```sh
sh tests/phone/upp_two_edge/run.sh /path/to/control
tclsh tests/phone/upp_two_edge/endpoints.tcl
```

The directed test compares ordered completions and owner/effect
samples with keypad enabled and disabled. It observes every bit of
the protected bank over E1. Both launch phases, repeated addresses
and narrow/invalid byte lanes are exercised. It checks cancellation,
a held response, warm reset, UART backpressure and coincident receive,
SIMIF overlap, unclaimed traffic, Timer0 expiry/acknowledgment,
MMC register access, and the unchanged fast comm-RAM path.

For an immediate peripheral register access, E0 captures the held
request, E1 matures it, E2 samples the live result and authorizes the
effect, E3 registers the CPU response and E4 consumes it. Another
immediate request can issue on E5. The original immediate sequence
was E0 through E3 with the next request on E4. GPIO RAM and passive
registers can prepare their synchronous data during E1. The separate
comm-RAM data lane may capture at E1 and keeps single-cycle timing.

The Tcl test exercises the endpoint selector with Quartus-style
register names and known excluded cells. The production CI timing
report enumerates the actual connected held-to-data setup/hold pairs
and checks ordinary-cycle witnesses. The offline test covers the
selector rules and protocol. It does not contain a routed netlist.
