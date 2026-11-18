    .syntax unified
    .cpu arm920t
    .arm
    .section .text.entry,"ax",%progbits
    .global pcm_route_entry
    .type pcm_route_entry,%function
pcm_route_entry:
    ldr     ip, =0x514a17d0       @ Return from DoControl(4)'s router call.
    cmp     lr, ip
    beq     native_pcm_route
    ldr     ip, =0x514bce39       @ Another stock caller shares this thunk.
    bx      ip
    .ltorg
    .size pcm_route_entry, .-pcm_route_entry
