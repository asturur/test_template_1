# Cache implementation decision and implementation plan

Sol investigation, 2026-10-28. Recommendation: repair ZAP's CPU/cache/TLB
request and completion protocol first, retain inferred RAM, and defer a
hardware-shaped cache rewrite until the phone's cache characteristics and
software-visible requirements are established.

## Evidence and limits

The ARM920T manual specifies separate 16 KiB instruction and data caches,
32-byte lines, 64-way associativity, virtually addressed tags, physical data
writeback tags, two dirty bits per line, replacement and lockdown. ARM9TDMI
is a CPU core with an external memory interface; its manual alone does not
prove that an integration has ARM920T caches. The saved N-Gage reference calls
the processor ARM920T, but the schematic identifies UPP_WD2 without specifying
its internal cache organization. A phone-derived CP15 cache-type/identification
capture or authoritative Nokia chip documentation is still missing.

The ZAP configuration uses 16 KiB/32-byte direct-mapped I/D caches. Do not
change CP15 to advertise a 64-way cache without implementing and validating the
corresponding software-visible maintenance operations. The current cache data
arrays use inferred RAM; Quartus mapping and 104 MHz timing are unmeasured.
Verilator lint with SYNTHESIS defined is not Quartus synthesis. The CPU is not
yet attached to the MiSTer top-level. Main cache data is 262,144 bits total;
26 M10Ks is only a capacity lower bound, not a fit estimate: tags, TLBs,
byte-enable packing, registers and routing add resources.

The original seven-patch core fails cold-cache base-in-list LDM but passes the
short firmware MD5. Scratch v3/v4 pass many LDM controls but fail short MD5
and next-load. V5 passes the isolated next-load but fails both MD5 tests at all
five tested memory latencies. These demonstrate request ownership/alignment
errors; neither direct mapping nor inferred RAM has been established as cause.

## Implementation order

1. Preserve all existing reproductions and baseline binaries. Require cold
   LDM, following-load, and unchanged 64/1024-byte firmware MD5 tests, plus
   spacing and immediate controls; never adjust expected digests to hide errors.
2. In scratch, define a request/completion contract carrying request identity,
   VA, access direction, data and byte enables, load transformation,
   destination register and translation context. Carry validity/identity
   through cache RAM and TLB stages; elapsed cycles and not-busy alone do not
   prove translation is valid. Assert that data, fault and ACK match the request.
3. Replace the pending/recovery counter experiments with explicit ownership and
   validity. Handle both the stalled request and following requests, flush,
   reset and outstanding asynchronous completions. The held request's completion
   must not corrupt alignment for its successor.
4. Resolve instruction-level LDM replay: an early asynchronous load must not
   change the base and then restart the whole instruction using the new base.
   Preserve original base and committed progress or use a genuinely blocking
   completion path integrated with the CPU pipeline. Cache ACK/ERR2 changes
   alone have failed in prior experiments.
5. Keep the existing direct-mapped geometry and inferred data/tag RAM while
   fixing correctness. Preserve the three enabled-cycle RAM behavior and
   read/write collision forwarding; verify before considering controller or RAM
   replacements.
6. Before another full firmware boot, pass original cold LDM and both short MD5
   tests together at latencies 0/3/7/15/31. Cover back-to-back load/store,
   repeated stalls, line/page crossings, base positions, STM writeback, dirty
   eviction, permissions, alignment, faults/FAR/FSR, interrupt and cancellation.
   Then run upstream regressions and synthesis-path lint. On the full firmware
   test require the correct digest, and record all device/firmware assumptions.
7. Audit firmware-used ARM920T cache/TLB maintenance, memory attributes,
   lockdown and CP15 registers separately. Pursue 64-way organization only
   when hardware evidence or a demonstrated software dependency warrants it.
8. After correctness, synthesize a CPU-only Cyclone V target with an available
   toolchain and inspect inferred memories, M10Ks, registers, logic and timing.
   If mapping is poor, try a scoped M10K inference hint; use an explicit
   vendor primitive wrapper only if measurements or required collision/clock
   semantics justify it, with an equivalent simulation backend. Do not fetch
   Quartus 17.0.2.

See [ldm-replay-investigation.md](ldm-replay-investigation.md) for actual
traces, failed prototypes and outstanding tests. This is an investigation
recommendation, not a hardware equivalence or synthesis claim.
