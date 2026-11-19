@ memtest.S: data integrity of the SDRAM service under the real CPU (the
@ flash image, as membench.S). Word, byte and halfword stores and loads,
@ uncached (scalar accesses) and cached (posted stores, line reads, dirty
@ lines written back on eviction), over more memory than the D-cache holds.
@ Prints "memtest: NAME ok" or "memtest: NAME FAIL" on the STI window.

	.equ	SD,	0x0A000000
	.equ	STI,	0x0DE00000
	.equ	TTB,	0x0A100000
	.equ	UNC,	0x8A000000
	.equ	STACKP,	0x0A300000
	.equ	STACKV,	0x8A300000
	.equ	BUFA,	0x0A400000
	.equ	BUFC,	0x0A480000
	.equ	N,	16384			@ words: 64 KB
	.equ	CR_M, 0x0001
	.equ	CR_C, 0x0004
	.equ	CR_W, 0x0008
	.equ	CR_I, 0x1000

	.text
	.arm
	.global	_start
_start:
	b	start
	.rept	7
	b	exception
	.endr
exception:
	ldr	r0, =s_exc
	bl	puts
	ldr	r0, =s_end
	bl	puts
1:	b	1b

start:
	ldr	sp, =STACKP
	ldr	r0, =TTB
	ldr	r1, =0xC12
	mov	r2, #0
1:	orr	r3, r1, r2, lsl #20
	str	r3, [r0, r2, lsl #2]
	add	r2, r2, #1
	cmp	r2, #4096
	bne	1b
	mov	r2, #0
1:	add	r3, r1, r2, lsl #20
	orr	r3, r3, #0xC
	str	r3, [r0, r2, lsl #2]
	add	r3, r1, #SD
	add	r3, r3, r2, lsl #20
	add	r5, r0, #(SD >> 20) << 2
	add	r6, r0, #(UNC >> 20) << 2
	str	r3, [r6, r2, lsl #2]
	orr	r3, r3, #0xC
	str	r3, [r5, r2, lsl #2]
	add	r2, r2, #1
	cmp	r2, #16
	bne	1b
	mcr	p15, 0, r0, c2, c0, 0
	mvn	r1, #0
	mcr	p15, 0, r1, c3, c0, 0
	mov	r1, #0
	mcr	p15, 0, r1, c8, c7, 0
	mcr	p15, 0, r1, c7, c7, 0
	mrc	p15, 0, r1, c1, c0, 0
	orr	r1, r1, #(CR_M | CR_C | CR_W)
	orr	r1, r1, #CR_I
	mcr	p15, 0, r1, c1, c0, 0
	nop
	nop
	ldr	sp, =STACKV
	ldr	r0, =s_hello
	bl	puts

	@ 1: uncached: every store and load a scalar access
	ldr	r0, =(UNC + 0x400000)
	mov	r1, r0
	mov	r2, #2048
	bl	fill
	ldr	r0, =(UNC + 0x400000)
	mov	r1, r0
	mov	r2, #2048
	bl	check
	ldr	r0, =n_unc
	bl	verdict

	@ 2: cached stores (posted, then dirty lines), read back cached
	ldr	r0, =BUFA
	mov	r1, r0
	mov	r2, #N
	bl	fill
	ldr	r0, =BUFA
	mov	r1, r0
	mov	r2, #N
	bl	check
	ldr	r0, =n_cached
	bl	verdict

	@ 3: the same memory through the uncached alias, after another 64 KB
	@ has been read through the cache (every dirty line written back)
	ldr	r0, =BUFC
	mov	r2, #N
1:	ldr	r1, [r0], #4
	subs	r2, r2, #1
	bne	1b
	mov	r0, #0
	mcr	p15, 0, r0, c7, c10, 4		@ drain the write buffer
	ldr	r0, =(UNC + 0x400000)
	ldr	r1, =BUFA
	mov	r2, #N
	bl	check
	ldr	r0, =n_back
	bl	verdict

	@ 4: written uncached, read cached (line reads of known data)
	ldr	r0, =(UNC + 0x480000)
	ldr	r1, =BUFC
	mov	r2, #N
	bl	fill
	mov	r0, #0
	mcr	p15, 0, r0, c7, c6, 0		@ invalidate the D-cache
	ldr	r0, =BUFC
	mov	r1, r0
	mov	r2, #N
	bl	check
	ldr	r0, =n_lines
	bl	verdict

	ldr	r0, =s_done
	bl	puts
	ldr	r0, =s_end
	bl	puts
1:	b	1b

@ The word for index r4 at address key r5 -> r6 (r7, r8 scratch): a product,
@ then one byte replaced, then for every other index the upper half.
expect:
	ldr	r7, =0x9E3779B1
	add	r8, r4, r5, lsr #2
	mul	r6, r8, r7
	and	r7, r4, #3
	mov	r7, r7, lsl #3
	mov	r8, #0xFF
	bic	r6, r6, r8, lsl r7
	eor	r8, r4, #0x5A
	and	r8, r8, #0xFF
	orr	r6, r6, r8, lsl r7
	tst	r4, #4
	moveq	pc, lr
	add	r8, r4, r4, lsl #1
	mov	r8, r8, lsl #16
	mov	r6, r6, lsl #16
	mov	r6, r6, lsr #16
	orr	r6, r6, r8
	mov	pc, lr
	.ltorg

@ r0 = where to store, r1 = the address key, r2 = words. Three passes: the
@ words, then a byte of each, then the upper halfword of every other one.
fill:
	stmfd	sp!, {r4-r11, lr}
	mov	r9, r0
	mov	r5, r1
	ldr	r7, =0x9E3779B1
	mov	r4, #0
1:	add	r8, r4, r5, lsr #2
	mul	r6, r8, r7
	str	r6, [r9, r4, lsl #2]
	add	r4, r4, #1
	cmp	r4, r2
	bne	1b
	mov	r4, #0
1:	and	r7, r4, #3
	eor	r8, r4, #0x5A
	add	r6, r9, r4, lsl #2
	strb	r8, [r6, r7]
	add	r4, r4, #1
	cmp	r4, r2
	bne	1b
	mov	r4, #0
1:	tst	r4, #4
	beq	2f
	add	r8, r4, r4, lsl #1
	add	r6, r9, r4, lsl #2
	strh	r8, [r6, #2]
2:	add	r4, r4, #1
	cmp	r4, r2
	bne	1b
	ldmfd	sp!, {r4-r11, pc}
	.ltorg

@ r0 = where to load, r1 = the address key, r2 = words; r10 = mismatches
check:
	stmfd	sp!, {r4-r9, r11, lr}
	mov	r9, r0
	mov	r5, r1
	mov	r10, #0
	mov	r4, #0
1:	bl	expect
	ldr	r7, [r9, r4, lsl #2]
	cmp	r7, r6
	addne	r10, r10, #1
	add	r4, r4, #1
	cmp	r4, r2
	bne	1b
	@ and by bytes and halfwords, every 61st word
	mov	r4, #0
1:	bl	expect
	add	r11, r9, r4, lsl #2
	ldrb	r7, [r11, #1]
	mov	r8, r6, lsr #8
	and	r8, r8, #0xFF
	cmp	r7, r8
	addne	r10, r10, #1
	ldrh	r7, [r11, #2]
	mov	r8, r6, lsr #16
	cmp	r7, r8
	addne	r10, r10, #1
	add	r4, r4, #61
	cmp	r4, r2
	blo	1b
	ldmfd	sp!, {r4-r9, r11, pc}

verdict:
	stmfd	sp!, {r4, lr}
	mov	r4, r0
	ldr	r0, =s_name
	bl	puts
	mov	r0, r4
	bl	puts
	cmp	r10, #0
	ldreq	r0, =s_ok
	ldrne	r0, =s_fail
	bl	puts
	ldmfd	sp!, {r4, pc}

puts:
	ldr	r1, =STI
1:	ldrb	r2, [r0], #1
	cmp	r2, #0
	strneb	r2, [r1]
	bne	1b
	mov	pc, lr
	.ltorg

n_unc:		.asciz	"uncached"
n_cached:	.asciz	"cached"
n_back:		.asciz	"written back"
n_lines:	.asciz	"line reads"
s_hello:	.asciz	"memtest: start\n"
s_name:		.asciz	"memtest: "
s_ok:		.asciz	" ok\n"
s_fail:		.asciz	" FAIL\n"
s_done:		.asciz	"memtest: done\n"
s_exc:		.asciz	"memtest: exception\n"
s_end:		.asciz	"\n#END\n"
	.align	2
