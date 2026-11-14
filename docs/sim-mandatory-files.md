# Native SIM rejection after serving

Build43565865117/d6cec18 fixes the received SELECT status: the actual native
inline LDRH now reads9F16, followed by complete DF, ICCID and EF replies. The
untouched display reaches **SIM card rejected**. A smaller observer records
070D/reason01 taking SIM_Server1→8 (serving), then070D/reason75 taking8→6.
Thus initial serving is reached; the later failure must not be described as
the old FIFO stall or solved by forcing the server state.

The native sender probe records470D/01 from5161518D, caller515131C9, then
470D/75 from the same helper, caller5150BB99. A separate filtered observer
positively catches dispatcher5150B65C receiving025F. Its attempted queued-message
dump is too late: R6 points to allocator poison after the preceding cleanup.
Discard that payload; it is not evidence of a functional guest use-after-free.
The earlier zero-only probe misses025F and cannot exclude the shared branch.

Original function5150F004 reads6F74/BCCH,6F7E/LOCI,6F20/Kc and6F7B/FPLMN in
that order with no optional services selected. A failed mandatory read leads to
025F; success leads to025E. Original dispatcher5150B65C maps025F to070D/reason75.
The existing card lacks6F74,6F20 and6F7B. Their required status and sizes16/9/12
are specified by [TS51.011 sections10.3.14,10.3.3 and10.3.16](https://www.etsi.org/deliver/etsi_ts/151000_151099/151011/04.03.00_60/ts_151011v040300p.pdf).
This establishes a concrete profile defect matching the observed rejection.
The exact failing file was inferred from the native sequence, not captured as
a live TX filename, and the correction was then qualified by the untouched boot below.

## Small card correction

The existing SELECT/GET RESPONSE/READ BINARY machinery now recognizes these
three GSM EFs. BCCH returns a zero bitmap, Kc returns eight zero bytes and the
standard no-key-available sequence07, and FPLMN returns twelveFF bytes for an
empty list. These are fabricated neutral test-card contents. Existing identity,
SST, PIN status, directory restrictions and unknown-file errors are unchanged.
No successful authentication, network service or writable-file behavior is
added. Future actual UPDATE requests require a separate bounded implementation;
this correction addresses the observed post-ready read phase.

Only combinational file selectors, lengths and constant bytes change. No new
state registers, packet buffers or RAM instances; one existing64-byte FIFO is
retained. Baseline is37,756ALMs/90%,508M10Ks/92%, card235.2ALMs/oneM10K.
The new fit measures239.7cardALMs (+4.5), oneM10K; full-core placement
is38,236ALMs/91%,508M10Ks/92%.78MHz PLL remains unchanged, with104MHz as the design objective.

## Qualification

- New independent literal APDU vectors fail the old RTL on SELECT (94 versus9F).
  Corrected RTL passes475returned bytes at CLOCK_DIV1 and32: exact metadata,
  contents, key sequence07, directory/length rejection and repeated FIFO wraps.
- Original NOS instructions at5150F004 and5150B65C execute in five Linux-Unicorn
  cases. Missing each mandatory file yields025F/reason75; all four available
  yield025E without rejection. File/directory/PMM leaves are spies, optional
  services absent; this does not execute the complete card driver or RTOS.
- Existing554-op card oracle,600-response FIFO stress, saturation/reset/CEN,
  four board presence/card selections and all eight original-RX ZAP cases pass.
  Real-card cached/uncached wait0/3 counts remain17651/18145/18381/18969clocks.
- Formatter and Quartus source-graph preflight pass. No other simulation or
  checkpoint changes.

All volatile observers were removed by reload. Full original ROM88fd596a...,
saved automatic Run/saveOff, C4a75e4cb... and PMM71189f7f... were verified.
One loader stall required Linux reboot; subsequent reload worked. No SD backups
or image replacement. The late BT59/02/shared ADSP waiter assertion remains a
separate scheduling-dependent gate; no passing BT response was invented.

Receipts: scratch/sim-fifo-byte-20261114, sim-state-20261114,
sim-reject-post-20261114, sim-reject-request-20261114 and
sim-mandatory-files-20261114. Maintained tests are
tests/phone/card_fixture/mandatory.v and tests/tools/test_native_sim_boot_files.py.
## Hardware result: original Phone and Menu

Run43572455384/seed44 passes timing at78MHz (setup+0.096ns,hold+0.176ns;
zero negative worst1000 paths). RBF SHA2564a63d5c2eb3a91545c88ee96767ed3cde93b05b415164ad24988493b21905373
was atomically deployed, with no card backup. The150s untouched control has
600snapshots/no gaps, no reset/panic/first-fault or queue/save error; ADSP42
completion/result-zero/positive ACK are all observed.

Accepting the normal Time and Date prompts reaches Phone idle. A short Menu
press opens the app grid; it takes tens of seconds to populate. Navigation and
Options work. All firmware, RAM code and deadlines are original, with the full
ROM hash verified; C and PMM files are unchanged. This uses the existing prepared
six-profile C image, not an empty-first-boot qualification. No native SIM-state
observer was installed this time: functional Phone/Menu success is the measured
result, not a direct sample proving state8 forever.

Calendar opens its header, but the main view remains blank beyond one minute.
Short Menu and End do not switch it away; a1s Menu hold opens the task switcher.
Selecting Telephone, then short Menu restores the populated grid. Calendar
remains backgrounded for further diagnosis. The core is left at that working
Menu with saveOff and no active observer/capture. Repeated HCI-33 remains, and
Calendar, save/MMC, empty-C profile creation and broader cold-boot reliability
are separate remaining gates. Runtime PC samples include FbsCli rendering code;
that alone does not diagnose the Calendar cause. Follow-up captures have initial
late-reader gaps, so do not use them for IO timing pairs across those gaps.

Do not confuse short Tab (Menu) with a1s hold (task switcher). Screens and
runtime-summary.json are in scratch/sim-mandatory-files-20261114; deployment,
fit and original-ROM/settings/disk verification receipts are alongside them.
