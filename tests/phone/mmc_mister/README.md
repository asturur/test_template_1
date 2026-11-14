# Authored ARM production MMC fixture

Run from the integration worktree root:

```sh
sh tests/phone/mmc_mister/run.sh
```

The runner assembles a small ARM920T program and runs the real ZAP CPU,
`ngage_mister`, UPP, native MMC host/card, owned HPS adapter, DMA router/RAM
mux and CPU/DMA arbiter in the existing offline simulator image. The program
is authored test code, not original EPBUS or a Symbian boot.

`prepare.py` creates nonprivate 2 KiB payload sectors and a strict NGAGEMMC v1
footer with generated CID/CSD/OCR. No user image is read or modified. SDRAM
and DDR use bounded behavioral memory with waits. The HPS peer supplies the
shared halfword interface, unrelated-slot noise and a final word with ACK
already low. The separate `mmc_hps` fixture tests actual local `hps_io`.

The ARM program identifies the card, checks all original test CID bytes,
selects it, sets a five-byte block length and performs selector-2 RX DMA with
eight-bit fixed FIFO and 32-bit incrementing RAM. The rounded eight-byte
transfer must contain five data bytes plus three zero padding bytes, with
the next word untouched. A three-byte PIO read from another sector checks
FIFO waits and padding. The program checks DMA channel ACK/ICU priority,
MMC IRQ21/23/24 and read-only R1 WP rejection. HPS writes are forbidden.

The same executable runs normally and with CPU Hold asserted halfway through
the initial metadata transfer. Owned backing reads must drain and retained
media must reload before the restarted program succeeds. Frozen results are
29,010 clocks / three HPS reads normally, and 29,424 / four reads with Hold.

This verifies the production composition and an authored client. It does not
establish original-driver execution, FAT mounting, game launch, writable
persistence, physical D550/AMA routing or FPGA timing. New hierarchy also
requires a fresh checkpoint lineage; the runner restores no snapshots.

## Full-sector verification (2026-11-14)

R2 identification now waits response-ready before reading CID, following the
native response order. The formerly unrun full-sector extension had placed512
in the source-width register1c and7 in count2c. It now correctly programs an
8-bit fixed FIFO source and count511 for512bytes. No production DMA behavior
was changed for this test repair. Full512-byte DMA/PIO, sentinel, identity, odd
lengths and read-only checks pass197627clocks/4HPSreads; CPU Hold recovery passes
198041clocks/5reads. These supersede the older short-only29010/29424 totals.

Native receive starts now use control2, matching original kernel5032170c.
The same full-sector/odd/Hold checks retain197627/198041clocks after correction
of production admission and internal RX-ready tagging.
