# Phone function verification

Hardware: `2d9605f`, build43572455384/seed44, 78MHz timing passing.
Last fit: 38,236/41,910 ALMs (91%), 508/553 M10Ks (92%). The104MHz design
objective remains unchanged. No production RTL changes or new FPGA debug logic
have been made during this investigation.

Functional tests use original firmware and deadlines with the existing
initialized six-profile C: seed. Background save remains Off. No Flush, SD-card
backups, media replacement, or other-thread simulation changes. Guest filesystem
writes below do **not** qualify SD-card persistence. Temporary observation-only
hooks are listed separately; they retain the checksum check and original behavior.

The later MMC/SPMark row uses build43609237775/cd46abe/seed44, which misses
78MHz setup by0.270ns. Other rows retain their original hardware scope above.

## Results

| Function | Observed | Remaining |
| --- | --- | --- |
| Phone/Menu | Idle, populated grid, navigation, Options, task switcher; Menu restarts after closure | One original Menu app closure during Calendar control; reason unknown. Real RF/calls unimplemented or untested |
| Calendar | Memo create/save/reopen/delete; day/month/week; Exit | Initial blank body/repaint issue, described below |
| Contacts | Empty list; Test create/save/reopen/edit/delete | Search/groups/SIM import; SD persistence |
| Profiles | Six modes visible; General/Silent/Meeting/Outdoor/Pager activate; setting change/restore | Offline restart, audio/RF behavior |
| Messaging | Empty-recipient draft12345678 save/reopen/delete; second Close works | First Close shares redraw symptom; RF sending/MMS/email untested |
| Clock | Time progresses; alarm setup and native notification observed | Alarm dismissal unresponsive despite captured Stop; audio and precise rate unqualified |
| Calculator | 12+34=46 | Further operations |
| Notes | Test create/save/reopen/delete | Further operations |
| Log | Main recent-calls/duration/cost view | Actual call accounting |
| Apps | Applications/Downloaded tabs open, both empty | Actual install/launch from media |
| Favourites | Existing shortcuts visible; Notes shortcut opens editor | Shortcut editing not tested |
| To-do | Empty list; A create/save/reopen/delete, date/Normal priority verified | Alarm/completion/filter variants |
| Converter | Length selection; 1mile→1609.34399metres | Other units/currencies |
| Help | Category/topic navigation and full Installing applications text | Remaining articles |
| Settings | Device/General and Date/time fields load | Other settings and write/readback |
| Software Manager | Installed list opens/no data | Install/uninstall |
| Memory card UI / SPMark04 | Follow-up cd46abe: native16MB mount,1272kB used,15MB free; app launches and Options/results respond | Run All Tests:3D Game failed, score/fill/poly N/A; timing unqualified. See [MMC result](mmc-spmark04.md) |
| About | Native Nokia copyright view | — |
| Bluetooth UI | Off/default-name query opens; cancelled | Radio communication/timeouts remain unqualified |
| SIM directory | Launch did not produce its view; Tools needed focus recovery | Test card advertises no phonebook/ADN; reason unproven |
| Images | Phone thumbnails N-Gage1/2/3; card tab says no card; completes without focus | Full image view interrupted by alarm; other Media pending |

All our Calendar, Contacts, Messaging and Notes test records were deleted.
General is active and its original Ringing alert setting is restored.

## Calendar and shared redraw issue

Without an observer, a fresh Calendar launch shows its header but a blank body
at10,30,60,120,180seconds. It is **not** a proven permanent deadlock: its day
view becomes usable, and memo CRUD plus Month/Week work. The baseline Calendar
file is only365bytes and matches the live pre-test file, so large initial DB
creation is not established.

An early focus experiment reproduces the recovery on original firmware: blank
at10s, then long Menu,2s,Cancel,2s produces the complete day view by18.96s.
The task-switch screenshot already has the date header behind it while day rows
remain blank. This qualifies a workaround, not an HDL fix or a specific
scheduler/LCD/cache cause. Short Menu and End were ineffective in earlier tests.

The40s and180s uninstrumented samples concentrate userspace in FbsCli, Palette
and Gdi. The180s run has719snapshots and one initial reader gap:209FbsCli,
99Palette,62Gdi,158kernel,114EUser. No captured fatal fault/panic/reset. Shared
rendering PCs alone do not identify which app/thread owns the work.

A narrow observation of AGN-model's sync IPC import (`5085BAAC`, literal
`5085BAB4`) captures16 complete consecutive BEGIN/END pairs in gap-free epochs.
All return0; combined wait0.170160s, maximum0.115005s. IPC15 takes0.002788s.
One initial gap loses earlier calls; this is not complete startup I/O coverage.
No observed request explains the minutes-long blank. Under that observer an
early focus cycle also recovers the day view.24Linux-Unicorn native-thunk ABI
cases pass, with original sync lower/kernel service boundary spied. Observer
removed; full original ROM/settings/C/PMM verified afterward.

Messaging supplies a second case: its first text-editor launch takes roughly
a minute. Entering12345678 reduces the counter160→152; recipient stays empty.
The first Close leaves editor-looking output/cleared softkeys while similar
FbsCli/Palette work is sampled. Task-switch/Cancel recovers Messaging main;
Drafts contains the correct saved text. Reopen returns the exact body, and the
second Close works normally. Deleted the test draft; no Send action occurred.
Do not call the first symptom a stuck filesystem save solely from its picture.

### Rejected probes

The global FullName-based sync observer boot produced repeated
MediaServerTaskThread USER0 before Calendar launch. Its48 mocked ABI cases did
not qualify runtime service/stack cost. Discard that boot as Calendar evidence;
remove by reload. It establishes neither a new production defect nor causality
for the MediaServer panic.

Calendar's two local CIdle callbacks were decoded before running the proposed
idle probe. The+10 callback (`509A0539`) injects deferred key events through
CCoeEnv::SimulateKeyEventL; the-20 callback (`5099FE41`) creates a deferred dialog.
They are not established first-paint callbacks. That observer was installed only
in fresh Hold, **never executed**, then removed by another original-ROM Hold
reload. Its72 ABI cases are not hardware evidence. Do not repeat this detour.

### LCD submission experiment and kernel-observer correction

The first LCD entry observer (`scratch/calendar-lcd-20261114`) used the user
RDebug service inside kernel-driver code. It reached Menu, then entered ABT
loop50324294/98/9C before Calendar launched. Its later screenshots remain Menu.
Discard that run as production LCD evidence. Its66 user-mode differential tests
were insufficient for exception context. The exact low-level corruption cause
is not proven. Removed by reload; original full ROM/settings/C/PMM reverified.
**Do not reuse that prepared observer.**

The correction (`scratch/calendar-lcd-port-20261114`) writes ASCII/hex directly
to the original mapped debug59 sink atVA59000000/PA0DE00000. No debug-service/SWI,
heap or exception-state changes. It observes native window50400544,12-bit header
50400640,16-bit header50400668 and line50400EFC. All registers/flags/SP are
restored before the original first instruction/body executes. At DMA caller
5040184C it samples source pixel25 on row60 if inside the requested band, otherwise
the first band row; zero-count/other callers skip. Source follows the native
buffer+352*row,16-bit pixel calculation. No argument points outside the pending
DMA band. A direct single-line call samples its own original32-bit source pixel.

280Linux-Unicorn baseline/traced comparisons match all registers,CPSR,SPSR,SP/LR,
object/row/pixel memory and complete original port sequence in USR/SVC/IRQ/UND,
ARM/Thumb returns. Native176-pixel conversion runs modes10/7; port helpers spied.
DMA full/partial/zero-band samples are checked. No full kernel/panel qualification
claimed. 918fresh-Hold records/full-image/checksum verified; saved Run/saveOff restored,
CPU started and120s boot capture active. Next healthy Menu check then Calendar
source/transfer/focus comparison. The model accepts8924/RGB444;
actual runtime16-bit use remains unknown, not a bug finding.

## Data and input evidence

Calendar memo `.Adgjmpt` saves/reopens exactly, then Clear/Yes returns to empty
day. That is the correct Abc multi-tap result of12345678, not numeric input.
After Save the native Calendar file grows365→530bytes,
SHA1240a13a542c15d5a6d133634bd3b79a6a325951f7908a29827bf6a6047c5409.
Month/Week and Back/Exit work after recovery. No user entry was removed.

Contacts first asks Copy new SIM contacts?; declined. Created Test/12345678,
saved/reopened exact fields, edited number to192345678, saved/reopened, then
Clear/Yes prompts Delete Test? and returns to no contacts. Its new form needs
several seconds to draw; no permanent blank established. Native read-only LFFS
decode extracts79files with zero decoder writes/source unchanged. Contacts.cdb
changes5492→7272bytes,
SHA3d3e86d2de8749d261f8b016c3f9008cbd6db957ad1b5b184bc8579625d99795.
UI readback qualifies content; compressed DB strings are not plain UTF16.

Profiles names: General,Silent,Meeting,Outdoor,Pager,Offline. Each of the first
five has its active label verified. General customization displays Jungle.mid,
Ringing and volume defaults. Incoming alert Ringing→Beep once→Ringing verifies
setting write/read/restore. Offline explicitly asks for a device restart;
declined until the end-of-session restart test. No audio/RF success inferred.

Notes Test saves/reopens and Delete note?/Yes returns to no data. Calculator
12+34 returns46. Clock opens a progressing analog time/date view, but no measured
rate/alarm test. One rapid two-Down sequence opened Log rather than Calculator;
250ms holds/2s gaps avoid that missed input during icon redraw. This is test
pacing, not a keypad RTL bug finding. Slash is the independent Hash binding;
Shift+# additionally asserts the mapped phone Shift modifier.

Evidence/screens and stable read-only C: snapshots:
`scratch/phone-functions-20261114`. Native decoder:
`scratch/profile-root-cause-20261113/extract_linux.py`. Initial C: Calendar,
Contacts and Profile files match the baseline hashes before testing. Preserved
original ROM SHA88fd596a...; C:4a75e4cb...; PMM71189f7f...; saved CFG
`00000100000000000000000000000000` (Run On/save Off).

Corrected LCD hardware result: Phone/Menu healthy; Calendar blank15/40/75s.
180s719snapshots/one initial gap/no ABT or captured panic. Last body44..208,
43296byte header, source pixel25,row60FFF matches white view. No later LCD calls
in the remaining capture despite busy FbsCli/Palette samples. All retained
window/header pairs complete. Fixed-format final EOF header must be included;
its absent trailing delimiter briefly looked like a missing header in an early
parser version. This was a parser issue, not a native-driver stall.
Focus-follow retained records show body44..188/header38016bytes/sourceAAF with
complete day/blue highlight. Normal12-bit transfers in both stages; no16-bit
use observed. One pixel does not qualify a whole frame/DMA/coherence contract,
but this case points upstream of LCD decoding. A dedicated15s live capture
records held Down mask2 in4/59snapshots and no UI recovery. The earlier90s key
capture expired before input and is not evidence. Next trace busy bitmap
conversion arguments rather than change panel logic speculatively. Observer
was removed and the original firmware/settings/disks were reverified.

### Bitmap observation limits

A direct-MMIO USER bitmap probe faulted before setup and was discarded; no
Calendar evidence comes from it. Its Thumb trampoline passes an isolated actual
ZAP/Verilator fixture at bus waits0/3 after testbench corrections. A corrected
USER-only native RDebug::Print observer at505598A4 boots healthy Phone/Menu and
reproduces Calendar blank/focus recovery. It records only small25x23/depth1
bitmaps through that outer GetScanLine entry. No oversized bitmap or cause is
established. Next isolate the busy lower conversion entry50559228. Native
Menu numeric shortcut3 opens Calendar reliably; allow frame settling before
interpreting selections. No production RTL fix yet.

The lower50559228 observer repeats normal30x40 color and120x10 monochrome
scanline dimensions/lengths during blank Calendar. Three-line output overruns
the host reader often, so exact call rates/coverage are unqualified. After
focus recovery, a20s follow-up has79snapshots, one initial gap, no retained
matching repeated pattern and normal idle/NOS sampling. Native Avkon.mbm
contains progress-strip120x10 assets and many different30x40 icons; local
RLE-decoded shape previews cannot identify the exact runtime bitmap by size
alone. A smaller pointer/parent observer is preparing. This remains a lead,
not an HDL fix or a complete causal diagnosis.

Reduced pointer observation identifies exact original Avkon assets: blank
note image264 and rotating progress masks355..367 (odd indices). Exact full
Avkon.mbm file matches the firmware ROM, avoiding header-only ambiguity. The
90s instrumented capture has359snapshots/one initial gap/no stop or captured
panic. This is an active wait-animation path, not proof of oversized drawing.
The reason for continued waiting remains open. Next observe Calendar/Agenda
CIdle scheduling, actual ready status/priority, and execution around focus
recovery; CPU-bound animation starvation is a hypothesis, not a fixed defect.

The filtered CIdle Start/READY/RunL experiment retains no Calendar/Agenda
messages, including at recovery; it has not demonstrated CIdle starvation.
Other active-object classes/callback addresses/server work are outside its
coverage. No timer/CPU/priority change follows from this negative probe.
Observers are removed before remaining functional checks.

Uninstrumented startup-view control: Settings opens and the original Day
choice can be changed to Month. Verified Exit returns to Menu with Calendar
selected; relaunch is blank at12s with Month default too. The blocker is not
specific to Day rendering. Month is a temporary volatile guest setting; restore
Day or reload original before ending. SD files and Background save are unchanged.

A later original-firmware Calendar Month/focus/exit control reports “App.
closed Menu”. Menu key successfully restarts its full grid.79snapshot follow-up
has no panic-recorder reason; user-thread panic category remains unknown. Do
not attribute it to ViewSrv/OOM without an exit-tracer reproduction. Clock
navigation attempted while Calendar blank did not leave Calendar and supplies
no time-progression evidence.

Additional original-firmware Extras pass: Apps shows both empty Applications
and Downloaded tabs. Favourites displays Calendar/Inbox/Notes and launches its
Notes editor; closed empty without adding a note. To-do starts normally (after
Calendar/Agenda use), creates A with01/01/2003/Normal priority, saves/reopens
exact fields, then explicit Delete to-do note?/Yes restores no data. Converter
selects Length and displays1mile=1609.34399metres. Help category/topic navigation
opens the complete Installing applications text from ROM. No installs, network
requests or shortcut edits were attempted. Temporary Converter and Calendar
preferences are confined to volatile guest C pending final original reload.

Clock coarse interval: approximately9minutes of analog movement during539.05
wallseconds. Date/time settings subsequently show9:21AM/01-01-2003. Temporary
09:20alarm setup/readback is verified; firing is not, because active key input
could have dismissed a notification. No audio success or failed-alarm conclusion.
Settings, Manager, Memory/no-card, About and Bluetooth-Off/name-query views open.
SIM-directory attempt leaves Tools; a task-switch/focus cycle restores input.
No CPU stop; held Menu is captured. Card SST=0/noADN/READ_RECORD means phonebook
is not a supported capability yet, but does not itself prove the wait cause.

The alarm notification is now positively observed over Images, with Stop and
Snooze controls. Prior keys may have snoozed it, so timing is not qualified.
Stop tap/held1s does not visibly dismiss; mask20 reaches the core, no kernel
stop, active FbsCli/Palette/kernel. Exact blocker remains unknown; no ADSP cause
inferred solely from DEVSOUND logs. Original RBF reload clears temporary alarm,
Calendar Month and Converter settings; media originals reverified after loading.
