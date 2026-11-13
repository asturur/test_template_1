# Phone startup: profile database recreation — 2026-11-13

## Confirmed native path

On b656156/seed44, the repeated Phone/ViewSrv11 is not evidence of an
indefinitely unacknowledged flash request. Scoped native EStor imports show
successful positional writes and flushes. Phone opens then replaces
`C:\system\apps\profileApp\dbProfile.db` and builds its profile database.
One detailed run catches Phone executing the EStor Unicode compressor at
508BCF18 when killed; another catches a file wait. Both are points within
ongoing initialization, not a demonstrated permanent I/O deadlock.

The minimal native probe proves **5 existing profiles versus6 expected** with
the original restored C image af5017dc... . ProfileEngine ConstructL
50A11A60 reads R-Offline via RSharedDataClient::GetInt, clamps it to0/1,
and expects6+that value. Its helper50A134A8 constructs `select * from
ProfileLookup` and returns native RDbRowSet::CountL. Compare50A11B40 skips
recreation only when the count agrees. The mismatch enters50A11B44 and
reopens/recreates the database through50A1351C.

This is a row-count comparison, **not a database-format version check**.
The original native CountL returns5 and the actual CProfileDb expected-count
field is6. RDbStoreDatabase::OpenL is void: its incidental r0 (the observer
return address) is not an error code. Successful return proves it did not
leave on that call; do not diagnose corruption from that r0.

The restored baseline needs first-run initialization. Its mismatch alone is
not evidence of a bad NAND conversion or an incorrect NOR program completion.
Repeated cold loads with Background save Off restore that same baseline.

## Measurement and limits

Phone-only EStor probes record file, handle, offset, byte count, native caller
and thread FullName; Open/Replace also record the requested pathname. Original
API implementations and return values remain in use. The detailed run spans
33.431078s of Phone I/O before ViewSrv11. In54 complete consecutive gap-free
entry/return pairs, all return success:32 Writes total0.747655s (max0.071890s),
18 Flushes total2.733429s (max1.683711s), three Opens and one Replace.
These are a subset, not complete totals; software instrumentation adds cost.
DDR packet timestamps approximate call boundaries; printf overhead is included.
Do not infer the remaining elapsed time is exclusively Phone computation:
other threads, scheduler activity and observer work also contribute.

Broad and Phone-only dense captures with the old host reader contain72/31
reader gaps (79,436/64,209 skipped sequence values), despite zero producer
FIFO drops. Broken lines must not be paired FIFO-style across gaps. Only
complete adjacent messages within one gap-free epoch are timed. Large earlier
5–6s estimates from naive pairing are rejected. Reader scanning and polling
were improved separately; dense-stream hardware qualification remains pending.

## C-only matched comparison

Use the identical minimal observer and original PMM71189f7f..., changing only
volatile C to the captured initialized image4a75e4cb... from the prior native
Menu session. Full ROM, PMM, original restored C, fresh-Hold and save-Off
hash/state guards pass. Card files remain untouched. No ready-SIM, BT, deadline,
self-test or other functional ROM changes are included.

The native query now returns **6 versus6**, twice, and skips recreation.
This compares whole C images, not a single-file replacement. Other initialized
files also differ; a complete UI success would not isolate every later benefit
to dbProfile.db alone. The600-snapshot/150s matched control has no ViewSrv11, no reset/queue fault
and no reader gap. Phone reaches Insert SIM; digit1 appears and responds,
while Menu remains unavailable. The baseline with the same minimal observer
captures ViewSrv11 and count5/expected6. The initialized image was captured
after the prior software-assisted Menu session; this qualifies a warm-data
comparison, not factory-erased startup or native RF/DSP/SIM completeness.

A reusable initialized C copy is `build/mister/initialized-c/boot0.vhd`,
SHA4a75e4cb... . Card files were unchanged during the matched comparison. Do not replace PMM
with the old synthetic policy experiment as part of this C-only result.

[Maintained evidence](evidence/phone-profile-startup-2026-11-13.json).

## Probes and verification

Sources/scripts and bounded captures: `scratch/flush-latency-20261113/`.
Research probes use existing verified exit tracer c76a4d88..., retain boot-MD5
checks by recomputing only the diagnostic expected digest, and require a fresh
held CPU. No FPGA recorder, PLL or other-thread simulation changes.

I/O observer101371b0... and minimal profile observer10e80e43... pass actual
ZAP tests at memory waits0/3: original arguments/results, callee registers,
returned flags, stack and ARM/Thumb return. The expected-count probe reads
CProfileDb+0xDD8 only at the verified native caller50A13501, whose frame retains
the object+4 pointer at SP+328. Host-side generation validates every original
word and post-write full-image hash. Reload removes all diagnostic hooks.

The Mac Unicorn DSY test remains SIGILL; the existing offline simulator image
has no Unicorn package. No filesystem modification is claimed from those tools.
Existing extracted C files remain useful: the prior fully booted profile DB is
3812bytes/SHA256 e3f08227..., whereas ROM's template is3250bytes/b226e244... .

## Repeatable card input

After the matched comparison and a completely unmodified-ROM boot both reach
responsive Phone/Insert SIM, install only the tested C image as
`/media/fat/games/ngage1/boot0.vhd`. The original image is reproducible from
`scratch/overnight/cdrive-11b.img` (SHAaf5017dc...) and the held readback
`scratch/flush-latency-20261113/original-c.vhd`. The temporary SD backup was
removed at the user's request, along with its empty directory. **Do not create
SD-card backups of rebuildable files.** Keep sources/manifests locally.

Full source/target hash checks, staging readback and atomic replacement protect
the deployment. PMM71189f7f... and both firmware files are unchanged. Background
save stays Off and saved CPU Run is restored. Normal automatic reload passes
150s/600 snapshots with reset generation0, no queue fault and no reader gaps.
It reaches Insert SIM and accepts digit input. Final full-ROM hash is original
88fd596a...; saved Run/save-Off and C/PMM hashes are verified. No debugger
DDR/ROM writes are applied to that boot. Menu remains unavailable. This
addresses repeatability with initialized data, not erased-first-boot speed.
