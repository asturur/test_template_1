 // Stereo with distinct negative left and positive right samples.
 mov r12,#70
 ldr r0,=0x0c1f0000
 ldr r1,[r0]
 ldr r2,=0x41554431
 cmp r1,r2
 bne fail
 ldr r1,=0x0a001c00
 ldr r2,=0x0800f000
 mov r4,#64
pcm_pattern:
 str r2,[r1],#4
 subs r4,r4,#1
 bne pcm_pattern
 put r0,0x08,1
 put r0,0x0c,48000
 put r0,0x10,0x0a001c00
 put r0,0x18,64
 put r0,0x04,3
