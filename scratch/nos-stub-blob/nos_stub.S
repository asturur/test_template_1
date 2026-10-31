@ SYNTHETIC minimal NOS provider. NOT authentic baseband. Entry at VA
@ 0x5149d284 (nosstarter target). Installs a minimal kernel power model and
@ registers Variant interfaces #3/#6. The interface vtable returns 0 for most
@ methods, but the "read parameter" slots (+0x48/+0x50) zero-fill their output
@ buffer so consumers (e.g. product_info) get in-range (0) values instead of
@ uninitialised heap.
    .section .entry, "ax"
    .global _start
_start:
    b   nos_init

    .section .init, "ax"
nos_init:
    stmfd sp!, {r4, r5, lr}
    ldr   r0, =0x5149e000       @ power-model object (board RW window)
    ldr   r3, =0x5033c8f8
    mov   lr, pc
    mov   pc, r3
    ldr   r4, =0x8000038c
    ldr   r4, [r4]
    cmp   r4, #0
    beq   2f
    ldr   r5, [r4]
    mov   r0, r4
    mov   r1, #3
    ldr   r2, =iface
    mov   lr, pc
    ldr   pc, [r5, #0xfc]
    ldr   r5, [r4]
    mov   r0, r4
    mov   r1, #6
    ldr   r2, =iface
    mov   lr, pc
    ldr   pc, [r5, #0xfc]
    ldr   r5, [r4]
    mov   r0, r4
    mov   r1, #13              @ kernel boot waiter polls for iface 13
    ldr   r2, =iface           @ (0x50331a50 loop; observed 2026-10-29)
    mov   lr, pc
    ldr   pc, [r5, #0xfc]
    ldr   r5, [r4]
    mov   r0, r4
    @ vtable+0x128 is the ecust Variant's startup-state SETTER (str r1,[this,
    @ #0x90]). 3 is the only VALID "ready" state (bit1 = NOS ready, bit0 =
    @ baseband present): bit1 alone (2) makes the Variant PANIC (VARIANT
    @ 0x1000c), bit0 alone / neither (0) hangs ecust's spin (0x50348a58 tst
    @ r0,#2). So we keep 3 and instead ANSWER helper.ldd's startup-reason query
    @ (request 1 -> iface #3 pread id 12) in pread below: that is the authentic
    @ "the modem answers" path (and the shape that becomes a modem in HDL).
    mov   r1, #3
    mov   lr, pc
    ldr   pc, [r5, #0x128]
2:
    mov   r0, #0
    ldmfd sp!, {r4, r5, pc}

    .org  0xc0              @ keep iface_vt at VA 0x5149d0c0 (kNosPowerVtable)
iface_vt:
    .rept 18
    .word ret0
    .endr
    .word pread2              @ +0x48 read parameter (completing variant)
    .word ret0                @ +0x4c
    .word pread               @ +0x50 read parameter (id 0x1ff etc.)
    .rept 27
    .word ret0
    .endr

    .align 4
iface:
    .word iface_vt


ret0:
    mov   r0, #0
    bx    lr

@ Read-parameter stub: (r0=this, r1=id, r2, r3=dest, [sp]=?, [sp+4]=byte len).
@ Zero-fill the output and return 0, so callers read valid 0 values.
@ A zero length means no output buffer: write NOTHING (the kernel passes
@ length 0 with a non-writable r3 during epbus-phase queries; storing there
@ data-aborted the boot, observed 2026-10-29 at 0x5149d09c).
pread:
    @ CACHE-COHERENCE RULE (learned the hard way, boot-v15-logo4 crash): on a
    @ resume the idle loop keeps these lines hot in the VIVT I-cache, so the
    @ bytes at ALREADY-EXECUTED addresses must stay IDENTICAL to the blob the
    @ checkpoint was made with (5f9e8c7). New behavior goes to the virgin
    @ line at 0x200 (pread2) and is reached by flipping the +0x48 VTABLE
    @ word (data), so either generation of cached code stays self-coherent.
    cmp   r1, #0xc
    moveq r0, #0x64
    bxeq  lr
    ldr   r2, [sp, #4]         @ byte length (caller stack arg)
    cmp   r2, #0x40
    movhi r2, #4               @ sanity cap -> default 4 bytes
    mov   r1, #0
pr_loop:
    subs  r2, r2, #1
    movmi r0, #0
    bxmi  lr
    strb  r1, [r3, r2]
    b     pr_loop
    .ltorg

    .org  0x200             @ VIRGIN line: never executed before this blob
pread2:
    @ id 12 (0xc) = HelperDrv request 1, the software startup reason
    @ (helper.ldd 0x5038425c: r1=0xc, r2=channel+0x44, r3=channel+0x54).
    @ Returning the reason as pread's value does NOT complete the client's
    @ TRequestStatus (proven: Nokia.dsy blocked forever in WaitForRequest at
    @ nokia+0x1842, roll-r4900 autopsy 2026-10-31): the async path expects
    @ the NOS to complete the request, as helper's own sync path does at
    @ 0x50384278. So answer like the NOS: complete request 1 with 100 (the
    @ normal startup reason == ngvm sw_reason) via helper's RequestComplete
    @ thunk, then return KErrNone. The r3==r2+0x10 check keeps other id-12
    @ callers (ecust reuses this slot with its own buffers) on the fill path.
    cmp   r1, #0xc
    bne   p2_fill
    add   ip, r2, #0x10
    cmp   ip, r3
    bne   p2_fill
    stmfd sp!, {lr}
    sub   r0, r2, #0x44        @ the helper channel
    mov   r1, #1               @ request number 1
    mov   r2, #0x64            @ software startup reason 100
    ldr   ip, =0x50384828      @ helper's RequestComplete thunk -> ekern
    mov   lr, pc
    mov   pc, ip
    ldmfd sp!, {lr}
    mov   r0, #0
    bx    lr
p2_fill:                       @ self-contained copy: never jump into old code
    ldr   r2, [sp, #4]
    cmp   r2, #0x40
    movhi r2, #4
    mov   r1, #0
p2_loop:
    subs  r2, r2, #1
    movmi r0, #0
    bxmi  lr
    strb  r1, [r3, r2]
    b     p2_loop
    .ltorg
    .space 0x8, 0
