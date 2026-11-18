# Calendar Avkon asset identity observer

Observation-only at lower scanline50559228. Exact prologue replay as in
calendar-scan-core-20261114; point0,0 and only dimensions30x40 or120x10.
One USER native RDebug::Print reports bitmap pointer,parent return,length.
Parent is read only for native caller5055969B: its enclosing50559600 frame
is60bytes, LR saved at originalSP+56 (observer SP+120). Other callers use LR.
288original/traced ABI cases pass; native debug Print service is spied.
No complete native-function/kernel/board correctness claim from that test.

Build trace.S/trace.ld using arm-none-eabi-as -march=armv4t,ld,objcopy,nm as
in the neighbouring scan-core README. Run test.py using existing Docker with
cached Linux Unicorn; prepare.py only afterward. Guarded fresh physical Hold
apply via mister-control skill, all ROM/checksum/zero-history checks required.
Restore original saved Run/saveOff; reload removes. No startup substitution,
firmware/deadline/data change, extra FPGA logic or production RTL modification.
Hardware results in docs/status.md and docs/phone-functions.md.
