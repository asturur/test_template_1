# AGN-model-only sync IPC observer

Results/scope in docs/phone-functions.md. One local Thumb import literal at
5085BAB4 is redirected through a private pointer slot; no global SendReceive
hook, FullName service or IPC argument dereference. The wrapper invokes the
unchanged original sync body exactly once. Exit-only observer/checksum guards
come from tools/prepare_native_observer.py. No functional substitutions.

Build trace.S/trace.ld with local arm-none-eabi-gcc/ld/objcopy/nm as in the LCD
observer README, then run test.py in the existing jotego/simulator:arm64 image
with cached Linux Unicorn at scratch/profile-records-20261113/linux-unicorn/site.
Run prepare.py only after the blob exists. Never apply warm; use mister-control
software-observer procedure and generated full-image/fresh-Hold guards. Reload
and verify original ROM/settings/disks after capture.

24ABI cases pass; lower original sync/kernel response boundary spied. analyze.py
accepts only consecutive complete matching BEGIN/END within one gap-free epoch.
Capture had16valid pairs, all rc0, max115ms. The initial reader gap loses other
calls; no complete startup I/O or whole Calendar initialization timing claimed.
