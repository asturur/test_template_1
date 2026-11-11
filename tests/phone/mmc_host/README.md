# Standalone Verilog-2001 MMC host

`rtl/ngage_mmc_host.v` ports the reviewed donor `rtl/upp/upp_mmc.sv`, SHA-256
`ff319b6ed1347b735d2fe2ec72748274ac9e723b9db49756cd697d98309b5ef5`.
The SPDX license and donor register/protocol provenance remain in the module.
This fixture verifies the standalone host. P3.3 subsequently wires it into
production UPP; see [MMC production details](../../../docs/mmc-port.md).

```sh
sh tests/phone/mmc_host/run.sh
sh tests/phone/mmc_host/run-pinned.sh
```

The first command uses host Icarus in strict `-g2001` mode. The second repeats
the same tests in the existing offline `jotego/simulator:arm64` image, checks
the pinned Verible format and runs Verilator with `--language 1364-2001`.
The pinned formatter is the existing local executable at
`scratch/ngage2-integration/tools/verible-verilog-format`; no tool is downloaded.
Generated binaries/logs live in `build/sim/unit-mmc-host/`.

## Ported behavior and observed results

The port changes syntax and sizing, retaining the donor's state machines,
register side effects, reset/start priority and CMD16 accepted-length guard.
Named Verilog-2001 block locals replace sequential SV temporaries. Private loop
indices replace SV loop declarations. Explicit zero-extension/modulo FIFO
helpers replace sized casts; a local constant function replaces `$clog2`.

`cmd16_tb.v` is the existing independent register/CMD/DAT0 fixture with a
selectable module name. It passes **31 pin-observed cached-length probes in
118,914 clocks**, exactly matching the reviewed donor. It covers every
classified R1 rejection bit, CRC/index/transmission/end errors, R2/R3, timeout,
software CRC suppression, successful status-only fields and reset. Every
rejection is followed by a length-register-zero data transfer that exposes the
last accepted size on DAT0, without reading internal cache state.

`data_tb.v` adds **28 cases** with independent CRC7/CRC16 polynomial division:

- Exact 1/2/3/5/511/512-byte TX and RX, including rounded-four FIFO accesses.
  TX padding and an extra write are discarded; RX partial-word/overread lanes
  return zero. Every actual wire/FIFO payload byte is compared with its oracle.
- Initial and mid-block empty TX FIFO clock stalls, and full RX FIFO stalls.
  The peer waits through backpressure; clock stoppage and subsequent progress
  are checked through public pins and registers.
- RX CRC/end errors, negative/missing TX CRC tokens, card-busy timeout and
  missing RX-start timeout, with the inherited status bits checked.
- Command-first, data-only middle and final-data-before-CMD12 ordering for
  types 5/6/7 and 8/9/10. The final TX command follows card busy release; the
  final RX command follows the data end bit.
- Reset during empty-TX and full-RX stalls, cleared public ownership/status/FIFO,
  followed by fresh successful transfers.

The data peer passes at DIV=4/FIFO=16 in **82,004 clocks**, and at
DIV=12/FIFO=8 in **244,751 clocks**. Running the identical public-pin fixtures
against the retained donor produces identical PASS summaries and clock counts.
These are bounded model results, not physical phone timing or original-driver
execution. The two parameter combinations exercise clock and FIFO-width
conversion; they do not validate arbitrary parameter values.

Icarus `-Wall` notes that `@*` is sensitive to all FIFO memory words. Verilator
reports intentionally unused upper bits in the explicit modulo-truncation
helpers. These notices are retained in logs; this is not a notice-free lint
claim. Pinned formatting passes unchanged.

## Retained assumptions and remaining work

This standalone native CMD/DAT0 pin model is a named transaction-level shortcut
for the unmodeled D550/AMA board path. The inherited QD-derived clock/divider,
register timeout meanings, type-4/R1busy timing and IRQ22=data-busy policy are
not verified for NEM-4. The peer uses falling-edge changes/rising-edge samples,
synthetic response delays and CRC/status tokens; it is independent of the card
RTL and cannot establish physical routing or timing.

General malformed-response delivery/error/status behavior remains unchanged.
The reviewed CMD16 guard prevents cache poisoning but does not invent a new
framing-error status flag or change general data-engine abort policy. Malformed
CRC-token terminal-bit behavior is likewise not changed or established here.
Concurrent command/argument register edits during an active transaction remain
unsupported, as do inherited invalid parameter cases (for example non-power-of-
two/small FIFO depths or invalid dividers). Normal caller qualification of
`wr`/`rd` remains the responsibility of the future bus owner.

Card/host combined tests, original NEM-4 driver execution, DMA/FIFO/IRQ production
integration, media reset/drain generations, physical FPGA checks and protected
card launch remain separate gates. Passing this host-only slice does **not**
complete P3.2 or enable an MMC endpoint in production.
