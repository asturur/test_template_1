 // The guest observes and acknowledges buffer 0 completion, then silences it.
 mov r12,#71
 ldr r0,=0x0c1f0000
pcm_done:
 ldr r1,[r0,#0x20]
 tst r1,#1
 beq pcm_done
 ldr r2,=0x0c120110
 ldr r1,[r2]
 tst r1,#0x20
 beq fail
 put r0,0x20,1
 ldr r1,[r0,#0x20]
 tst r1,#1
 bne fail
 ldr r1,[r2]
 tst r1,#0x20
 bne fail
 put r0,0x04,0
