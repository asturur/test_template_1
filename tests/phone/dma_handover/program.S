.syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start: b reset_entry
.rept 7
 b fail
.endr
.section .text,"ax"
.macro imm reg, value
 ldr \reg,=\value
.endm
.macro put base, off, value
 imm r1,\value
 str r1,[\base,#\off]
.endm
reset_entry:
 // All eight independently pending channels, normal memory count halfwords.
 imm r4,0x0c120300
 imm r5,0x0a002000
 imm r6,0x0a004000
 mov r7,#0
start_channels:
 put r4,0x04,1
 str r5,[r4,#0x14]
 put r4,0x18,1
 put r4,0x1c,32
 str r6,[r4,#0x20]
 put r4,0x24,1
 put r4,0x28,32
 put r4,0x2c,7
 put r4,0x08,1
 add r4,r4,#64
 add r5,r5,#32
 add r6,r6,#32
 add r7,r7,#1
 cmp r7,#8
 bne start_channels
 imm r4,0x0c120300
 mov r7,#0
wait_channels:
 ldr r1,[r4,#8]
 cmp r1,#0
 bne wait_channels
 add r4,r4,#64
 add r7,r7,#1
 cmp r7,#8
 bne wait_channels
 // Masking source 6 must leave channel 0 pending; reenable restores priority.
 imm r4,0x0c120100
 put r4,8,0x3fc0
 ldr r1,[r4,#20]
 cmp r1,#7
 bne fail
 put r4,12,0x40
 ldr r1,[r4,#20]
 cmp r1,#8
 bne fail
 put r4,8,0x40
 ldr r1,[r4,#20]
 cmp r1,#7
 bne fail
 imm r5,0x0c120300
 mov r7,#7
ack_channels:
 mov r1,#0
 str r1,[r5,#4]
 add r5,r5,#64
 add r7,r7,#1
 ldr r1,[r4,#20]
 cmp r7,#15
 moveq r7,#0
 cmp r1,r7
 bne fail
 cmp r7,#0
 bne ack_channels
 imm r0,0x0a000100
 put r0,0,1
 imm r0,0x0c121204
 put r0,0,1
 // Clear and select the original LCD request-line nibble for channel 1.
 imm r0,0x0c120064
 put r0,4,0xf0
 put r0,0,0x70
 // Initial full-frame normal command stream; no source-to-pixel shortcut.
 bl full_window
 bl memory_mode
 imm r4,0x0c120340
 imm r5,0x0a008000
 imm r6,18303
 bl lcd_start
 // A peer channel must finish while a queued LCD word is deliberately held.
 imm r9,0x0c120380
 put r9,4,1
 put r9,0x14,0x0a002000
 put r9,0x18,1
 put r9,0x1c,32
 put r9,0x20,0x0a004800
 put r9,0x24,1
 put r9,0x28,32
 put r9,0x2c,7
 put r9,8,1
peer_wait:
 ldr r1,[r9,#8]
 cmp r1,#0
 bne peer_wait
 imm r0,0x0a000100
 put r0,0,11
 put r9,4,0
 // Stop after a visible prefix and drain it without success IRQ.
 imm r0,0x0a000110
prefix_wait:
 ldr r1,[r0]
 cmp r1,#32
 blo prefix_wait
 put r4,8,0
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,2
 // Restart from a new memory-write command and commit a complete frame.
 bl memory_mode
 bl lcd_start
 // Editing the live request selector must not mutate this active job.
 imm r0,0x0c120068
 put r0,0,0xf0
 mov r8,#0
progress:
 add r8,r8,#1
 // Reasserting the pixel header is an ordered CPU FIFO command amid DMA.
 imm r0,0x0c121200
 put r0,0,0x8924d67f
 ldr r1,[r4,#8]
 cmp r1,#0
 bne progress
 imm r0,0x0a000100
 put r0,0,3
 put r4,4,0
 imm r0,0x0c120064
 put r0,0,0x70
 // A real row band at rows 3..10 from an unrelated SDRAM source location.
 imm r0,0x0c121200
 put r0,0,0x09200000
 put r0,8,0x75
 put r0,0,0x09240003
 put r0,8,0x00a00003
 put r0,8,0
 put r0,0,0x09200000
 put r0,8,0x5c
 put r0,0,0x89240737
 imm r5,0x0a000800
 imm r6,615
 bl lcd_start
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,4
 put r4,4,0
 // Accepted bus framing that cannot be a pixel must fail without success.
 imm r0,0x0c121200
 put r0,0,0x89240000
 mov r6,#0
 bl lcd_start
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,5
 put r4,8,0
 // Production router must reject the unsupported MMC alias as well.
 put r4,0x20,0x10120624
 put r4,0x08,2
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,6
 put r4,8,0
 // Proven non-SDRAM LCD sources retain the general routed-word fallback.
 imm r0,0x0c004020
 put r0,0,0x01230abc
 bl full_window
 bl memory_mode
 imm r0,0x0c120064
 put r0,0,0x70000
 imm r4,0x0c120400
 imm r5,0x0c004020
 mov r6,#0
 bl lcd_start
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,7
 put r4,8,0
 // Unsupported request lines and control-1 FIFO bypass both fail before I/O.
 imm r0,0x0c120068
 put r0,0,0xf0000
 imm r0,0x0c120064
 put r0,0,0x30000
 imm r5,0x0a000800
 bl lcd_start
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,8
 put r4,8,0
 put r4,8,1
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,9
 put r4,8,0
 // Transport reset invalidates the header even though panel mode persists.
 imm r0,0x0c120068
 put r0,0,0xf0000
 imm r0,0x0c120064
 put r0,0,0x70000
 bl memory_mode
 imm r6,18303
 bl lcd_start
 // Wait for a committed prefix so this is always a midstream reset.
 imm r0,0x0a000110
transport_prefix_wait:
 ldr r1,[r0]
 cmp r1,#4
 blo transport_prefix_wait
 imm r0,0x0c121204
 put r0,0,2
 bl wait_idle
 imm r0,0x0a000100
 put r0,0,10
 put r4,8,0
 imm r1,0x50415353
 str r1,[r0]
 b .
full_window:
 imm r0,0x0c121200
 put r0,0,0x09200000
 put r0,8,0x75
 put r0,0,0x09240003
 put r0,8,0x0d000000
 put r0,8,0
 put r0,0,0x09200000
 put r0,8,0x15
 put r0,0,0x09240003
 put r0,8,0x0b100002
 put r0,8,0
 bx lr
memory_mode:
 imm r0,0x0c121200
 put r0,0,0x09200000
 put r0,8,0x5c
 put r0,0,0x8924d67f
 bx lr
lcd_start:
 put r4,4,1
 str r5,[r4,#0x14]
 put r4,0x18,1
 put r4,0x1c,32
 put r4,0x20,0x10121208
 put r4,0x24,0
 put r4,0x28,32
 str r6,[r4,#0x2c]
 put r4,8,2
 bx lr
wait_idle:
 ldr r1,[r4,#8]
 cmp r1,#0
 bne wait_idle
 bx lr
fail:
 imm r0,0x0a000100
 imm r1,0xdeadbeef
 str r1,[r0]
 b .
.ltorg
