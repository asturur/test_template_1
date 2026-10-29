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
    .word pread               @ +0x48 read parameter
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
    .space 0x3c, 0
