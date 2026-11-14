# SIM reply FIFO: one physical write port

On940c0f6, native SIM initialization reads its ATR, sends SELECT A0A4000002,
receives procedure byteA4, sends7F20 and then stalls. A differential-tested tap
of the original inline LDRH at51635C3C records actual bytesA4,00,16. The expected
SELECT completion is9F16. Earlier read-only native buffer samples agree with
00,16. This is a received-byte discrepancy, not evidence that an optional SIM
file or the native SIM-ready state should be overwritten.

The old RTL calls emit() up to25times in one clock, writing separate locations
in a64×8 array. Build43557629525's actual Quartus RAM summary and inferred entity
parameters show fifo_rtl_0 as one64×8 simple-dual-port M10K: one8-bit write port
and one read port. A single A4 works; the leading byte of the two-byte reply is
zero on hardware. That supports the RAM-write lowering as the next concrete
hardware suspect. The exact old synthesized write-data equation has not been
recovered, so final causality and the correction remain board qualification.
RTL simulation alone does not reproduce the Quartus lowering: both the original
RX routine in Unicorn and a ZAP/production-card fixture receive9F16 correctly.

The correction uses explicit ngage_bram with one write per system clock. A
small response descriptor and byte index replace the parallel emit task; bytes
come from the same synthetic card profile. There is no response packet buffer,
new card identity, service or SIM-state override. The existing64-byte FIFO still
requires one M10K. busy holds controller admission while bytes are written;
occupancy/tail publish atomically after the last write and a read-settle edge.
Lookahead on a committed pop samples the next head into the synchronous RAM
read port. Overflow truncation/stickiness and reset cancellation are retained.
A25-byte reply takes26system clocks after decode, below0.34us at78MHz; the
existing CEN input pipeline remains separate. No PLL change; the serializer
avoids a multiwrite memory and wide same-cycle emission path toward104MHz.
Actual ALMs/timing must be measured in the next fit.

Qualification before build:

- Unchanged C++ card oracle:554operations, every byte/FIFO count matches.
- Independent600-response scoreboard: saturation, wrap, concurrent pop and
  private occupancy until publication; overflow and mid-emission reset pass.
- CEN32 versus full-speed equivalence, captured data and reset pass. Its bound
  now includes the maximum26write/publication clocks in addition to two CENs.
- All four presence/card selections, native-style31/194operation controller
  comparisons and shared SIM/UART CTSI/FIQ routing pass.
- New tests/phone/native_sim_rx executes the unchanged original RX routine on
  ZAP with an authored FIFO or production SIMIF/card, MMU/cache off/on and waits
  0/3. All eight cases pass; real-card counts17651/18145/18381/18969clocks.
  Authored setup drives the observed SELECT; scheduler import is a no-op leaf.
  This is not a full RTOS or full production SDRAM-stream qualification.
- MiSTer CPU/board SIMIF, LCD/DMA, IRQ/FIQ and SDRAM regression; peripheral
  ownership and33held-response/authorization checks;177-source/9QIP preflight pass.

All board observers were removed by reload. Original backing88fd596a..., saved
Run/saveOff and unchanged C4a75e4cb.../PMM71189f7f... were verified. The inline
byte-tap run later took an RF timeout and late-BT/ADSP assertion: logging changes
scheduling and this RBF has failed setup timing. That does not invalidate the
other measured nativeRF00/ADSP00 and NORMAL/READY observations, nor establish
reliable untouched boot. No functional guest patches or SD backups were used.

Local source/receipts: scratch/sim-byte-20261114 (exact read),
scratch/sim-buffer-20261114 (Unicorn and prior buffer),
scratch/sim-fifo-single-write-20261114 (tests and previous RTL). Next build must
first verify identity/fit/timing, then original-ROM boot, native SELECT9F16,
later APDUs, native SIM readiness and Phone/Menu. Keep the original deadlines
and card images. Do not add unverified passing response values.

## FPGA qualification, build43565865117 / d6cec18

Seed44 fits37,756/41,910ALMs (90%),508/553M10Ks (92%). The card is
235.2ALMs/190registers/oneM10K, versus504.9ALMs before serialization. This
correction saves about270cardALMs and290coreALMs. Setup remains-0.462ns
on CPU cache-control paths (14negative worst1000paths, none in the card);
hold+0.243ns. This retained RBF is diagnostic, not timing-qualified.

The untouched150s control has600snapshots, no reader gaps, reset-generation
change, panic or save-queue fault. Native ADSP42 result/positive ACK milestones
are all set. Display now reaches **SIM card rejected**. That is progress from
the earlier transfer stall, not a working SIM/menu claim.

An observation-only exact native LDRH tap now recordsA4,9F,16, followed by
complete25-byte DF status, ICCID, EF metadata, SST, AD/IMSI/ACC reads and
TERMINAL PROFILE9000. Thus the leading-byte correction is observed in actual
native execution, beyond its RTL tests. The57received response packets are
in scratch/sim-fifo-byte-20261114/packets.json. Original code/deadlines and
SD images remain unchanged apart from temporary, checksum-preserving tracing.
The later rejection is070D/reason75 after an initial serving transition. See
[the mandatory-file correction](sim-mandatory-files.md) for its025F producer
and the missing standard EFs. Prefer profile-byte/logic corrections within the
existing card; avoid new buffers or diagnostic RTL with only10%ALM/8%M10K
headroom. Sustained native SIM readiness and untouched Phone/Menu remain pending.
