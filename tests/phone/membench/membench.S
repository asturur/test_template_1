@ membench.S: the same bare-metal program on two N-Gage cores (both model
@ the UPP_WD2: NOR flash at 0, SDRAM at 0x0A000000, the STI text window at
@ 0x0DE00000). It is the flash image; it runs from reset, builds its page
@ tables and data with the MMU off, switches the MMU and both caches on and
@ runs a list of loops. Each loop is run twice. Around each run the program
@ writes the byte 0x01 to the STI window: the bench prints its clock count
@ there, so a loop's cost is the difference of two stamps in the bench's
@ own clocks (no timer of the core is used).
@
@ The main program stays below 0xA000 (one core descrambles flash reads from
@ there to 0x2B3000); the long straight-line code blocks sit at 0x300000.

	.equ	SD,	0x0A000000
	.equ	STI,	0x0DE00000
	.equ	TTB,	0x0A100000
	.equ	L2T,	0x0A104000		@ three coarse tables
	.equ	UNC,	0x8A000000		@ the SDRAM again: uncached, unbuffered
	.equ	STACKP,	0x0A300000		@ the stack, physical
	.equ	STACKV,	0x8A300000		@ and through the uncached alias
	.equ	BUFA,	0x0A400000
	.equ	BUFB,	0x0A800000
	.equ	RCODE,	0x0A600000		@ the code blocks copied to RAM
	.equ	LIST,	0x0A900000		@ 4096 nodes over 1 MB
	.equ	ALIAS,	0x4E400000		@ -> 0x0AC00000; VA[25:20] as BUFA's
	.equ	ALIASP,	0x0AC00000
	.equ	SPG,	0x60000000		@ three small pages, 1 MB apart
	.equ	SPGP,	0x0AD00000
	.equ	FDATA,	0x00500000		@ flash, read as data
	.equ	CR_M, 0x0001
	.equ	CR_C, 0x0004
	.equ	CR_W, 0x0008
	.equ	CR_I, 0x1000

@ ---- straight-line code, at 0x300000 in flash ----
	.section .blocks, "ax"
	.arm
	.align	5
blk_start:
	.macro	block name, words
	.align	5
\name:
	.rept	\words - 1
	add	r6, r6, #1
	.endr
	mov	pc, lr
	.endm
	block	blk16, 4096
	block	blk12, 3072
	block	blk24, 6144
	block	blk96, 24576
	.align	5
blk_end:

	.section .text
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
	@ ---- with the MMU off: tables and data, physical ----
	@ level 1: everything identity, uncached, AP 11, domain 0
	ldr	r0, =TTB
	ldr	r1, =0xC12
	mov	r2, #0
1:	orr	r3, r1, r2, lsl #20
	str	r3, [r0, r2, lsl #2]
	add	r2, r2, #1
	cmp	r2, #4096
	bne	1b
	@ flash (16 MB at 0) and the SDRAM (16 MB) cached and bufferable;
	@ the SDRAM again at UNC, uncached
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
	@ ALIAS: one cached section
	ldr	r3, =(ALIASP | 0xC1E)
	ldr	r5, =(TTB + ((ALIAS >> 20) << 2))
	str	r3, [r5]
	@ SPG: three coarse tables, one small page each (entry 0), cached
	ldr	r5, =L2T
	mov	r2, #0
	mov	r3, #0
1:	str	r3, [r5, r2, lsl #2]
	add	r2, r2, #1
	cmp	r2, #768
	bne	1b
	ldr	r6, =(TTB + ((SPG >> 20) << 2))
	mov	r2, #0
1:	add	r3, r5, r2, lsl #10		@ the table
	orr	r3, r3, #0x11
	str	r3, [r6, r2, lsl #2]
	ldr	r3, =(SPGP | 0xFFE)
	add	r3, r3, r2, lsl #12
	add	r7, r5, r2, lsl #10
	str	r3, [r7]
	add	r2, r2, #1
	cmp	r2, #3
	bne	1b
	@ the code blocks to RAM
	ldr	r0, =blk_start
	ldr	r1, =RCODE
	ldr	r2, =blk_end
1:	ldr	r3, [r0], #4
	str	r3, [r1], #4
	cmp	r0, r2
	blo	1b
	@ the list: node i at LIST + perm(i) * 256, perm(i) = (i * 1237) & 4095
	@ (1237 is odd: a permutation); each node holds the next node's address
	ldr	r0, =LIST
	ldr	r4, =1237
	ldr	r5, =4095
	mov	r2, #0
1:	mul	r3, r2, r4
	and	r3, r3, r5
	add	r6, r2, #1
	and	r6, r6, r5
	mul	r7, r6, r4
	and	r7, r7, r5
	add	r7, r0, r7, lsl #8
	str	r7, [r0, r3, lsl #8]
	add	r2, r2, #1
	cmp	r2, #4096
	bne	1b
	@ a palette for tex: 256 halfwords at BUFA + 0x100000
	ldr	r0, =(BUFA + 0x100000)
	mov	r2, #0
1:	add	r3, r2, r2, lsl #5
	strh	r3, [r0], #2
	add	r2, r2, #1
	cmp	r2, #256
	bne	1b

	@ ---- the MMU and the caches ----
	ldr	r0, =TTB
	mcr	p15, 0, r0, c2, c0, 0
	mvn	r1, #0
	mcr	p15, 0, r1, c3, c0, 0		@ every domain manager
	mov	r1, #0
	mcr	p15, 0, r1, c8, c7, 0		@ TLBs
	mcr	p15, 0, r1, c7, c7, 0		@ caches
	mrc	p15, 0, r1, c1, c0, 0
	orr	r1, r1, #(CR_M | CR_C | CR_W)
	orr	r1, r1, #CR_I
	mcr	p15, 0, r1, c1, c0, 0
	nop
	nop
	ldr	sp, =STACKV

	ldr	r0, =s_hello
	bl	puts
	ldr	r4, =table
1:	ldr	r5, [r4], #4			@ the loop
	cmp	r5, #0
	beq	2f
	ldr	r6, [r4], #4			@ its name
	ldr	r7, [r4], #4			@ its count
	mov	r0, r6
	bl	puts
	bl	once
	bl	once
	mov	r0, #'\n'
	bl	putc
	b	1b
2:	ldr	r0, =s_done
	bl	puts
	ldr	r0, =s_end
	bl	puts
1:	b	1b

@ r5 = the loop, r7 = its count. The write buffer is drained and the
@ D-cache invalidated first (every data line absent), then the loop runs
@ between two stamps.
once:
	stmfd	sp!, {r4-r11, lr}
	mov	r0, #0
	mcr	p15, 0, r0, c7, c10, 4		@ drain the write buffer
	mcr	p15, 0, r0, c7, c6, 0		@ invalidate the D-cache
	ldr	r8, =STI
	mov	r1, #1
	ldr	r0, =BUFA
	ldr	r3, =BUFB
	mov	r2, r7
	mov	r4, #0
	mov	r6, #0
	strb	r1, [r8]			@ stamp
	mov	lr, pc
	mov	pc, r5
	ldr	r8, =STI
	mov	r1, #1
	strb	r1, [r8]			@ stamp
	ldmfd	sp!, {r4-r11, pc}
	.ltorg

@ ---- the loops: r0 = BUFA, r3 = BUFB, r2 = count, r4 = r6 = 0 ----
@ r1, r4-r11 free; lr holds the return address.

	.align	5
l_alu:						@ registers only
1:	add	r4, r4, r2
	eor	r6, r6, r4, lsl #3
	sub	r1, r6, r4, lsr #2
	orr	r4, r4, r1, ror #7
	and	r6, r6, #0xFF00
	add	r6, r6, r1
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_mul:						@ multiplies
	mov	r7, #3
	orr	r7, r7, #0x1500
1:	mul	r1, r7, r2
	mla	r4, r1, r7, r4
	umull	r8, r9, r1, r4
	add	r6, r6, r9
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_branch:					@ branches on the bits of an LFSR
	mov	r7, #1
	orr	r7, r7, #0xAC00
1:	movs	r7, r7, lsr #1
	eorcs	r7, r7, #0xB400
	addcs	r4, r4, #1
	bcs	2f
	add	r6, r6, #3
2:	tst	r7, #4
	beq	3f
	add	r4, r4, r6
3:	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_call:						@ calls with a frame on a cached stack
	mov	r11, sp
	mov	r10, lr
	add	sp, r0, #0x1000
1:	bl	leaf
	subs	r2, r2, #1
	bne	1b
	mov	sp, r11
	mov	pc, r10
leaf:	stmfd	sp!, {r4-r6, lr}
	add	r4, r4, #1
	ldmfd	sp!, {r4-r6, pc}

	.align	5
l_hit:						@ loads, one line
1:	ldr	r1, [r0]
	add	r6, r6, #16
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_sthit:					@ stores, one line
	ldr	r1, [r0]
1:	str	r6, [r0]
	add	r6, r6, #16
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_seq:						@ loads 16 bytes apart
1:	ldr	r1, [r0], #16
	add	r6, r6, #16
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_rdw:						@ loads word after word
1:	ldr	r1, [r0], #4
	add	r6, r6, r1
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_wrw:						@ stores word after word
1:	str	r6, [r0], #4
	add	r6, r6, #1
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_fill16:					@ halfword fill, four a pass
1:	strh	r6, [r0], #2
	strh	r6, [r0], #2
	strh	r6, [r0], #2
	strh	r6, [r0], #2
	subs	r2, r2, #4
	bne	1b
	mov	pc, lr

	.align	5
l_copy:						@ 32 bytes a pass, as Mem::Copy
	mov	r12, lr
1:	ldmia	r0!, {r1, r4-r10}
	stmia	r3!, {r1, r4-r10}
	subs	r2, r2, #1
	bne	1b
	mov	pc, r12

	.align	5
l_rmw:						@ load, change, store back
1:	ldr	r1, [r0]
	add	r1, r1, #0x10
	str	r1, [r0], #4
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr

	.align	5
l_row:						@ a new SDRAM row each load
	ldr	r7, =1040
1:	ldr	r1, [r0], r7
	add	r6, r6, #16
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_list:						@ a linked list over 1 MB
	ldr	r0, =LIST
1:	ldr	r0, [r0]
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_unc:						@ uncached loads
	ldr	r0, =(UNC + 0x400000)
1:	ldr	r1, [r0], #4
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_uncw:						@ uncached, unbuffered stores
	ldr	r0, =(UNC + 0x400000)
1:	str	r6, [r0], #4
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_dws12:					@ 16 passes over 12 KB, a load a 16 bytes
	mov	r8, #16
2:	mov	r7, r0
	mov	r9, #768
1:	ldr	r1, [r7], #16
	add	r6, r6, r1
	subs	r9, r9, #1
	bne	1b
	subs	r8, r8, #1
	bne	2b
	mov	pc, lr

	.align	5
l_dws24:					@ 16 passes over 24 KB
	mov	r8, #16
2:	mov	r7, r0
	mov	r9, #1536
1:	ldr	r1, [r7], #16
	add	r6, r6, r1
	subs	r9, r9, #1
	bne	1b
	subs	r8, r8, #1
	bne	2b
	mov	pc, lr

	.align	5
l_tex:						@ a textured span: a byte texel from a
	ldr	r7, =(BUFA + 0x100000)		@ 64 KB texture, a palette entry, a pixel
	mov	r8, #0				@ u, 8.8
	mov	r9, #0				@ v
	ldr	r10, =0x0193			@ du
	ldr	r11, =0x0047			@ dv
1:	mov	r1, r8, lsr #8
	and	r1, r1, #0xFF
	mov	r4, r9, lsr #8
	and	r4, r4, #0xFF
	orr	r1, r1, r4, lsl #8
	ldrb	r1, [r3, r1]
	add	r1, r7, r1, lsl #1
	ldrh	r1, [r1]
	strh	r1, [r0], #2
	add	r8, r8, r10
	add	r9, r9, r11
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_frd:						@ flash read as data, word after word
	ldr	r0, =FDATA
1:	ldr	r1, [r0], #4
	add	r6, r6, r1
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_tlbx:						@ two sections with the same VA[25:20]
	ldr	r3, =ALIAS
1:	ldr	r1, [r0]
	ldr	r6, [r3]
	subs	r2, r2, #2
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_tlbs:						@ three small pages 1 MB apart
	ldr	r7, =SPG
	add	r8, r7, #0x100000
	add	r8, r8, #0x100
	add	r9, r7, #0x200000
	add	r9, r9, #0x200
1:	ldr	r1, [r7]
	ldr	r4, [r8]
	ldr	r6, [r9]
	subs	r2, r2, #3
	bne	1b
	mov	pc, lr
	.ltorg

	.align	5
l_sti:						@ a peripheral write
	ldr	r0, =STI
	mov	r1, #'\r'
1:	strb	r1, [r0]
	subs	r2, r2, #1
	bne	1b
	mov	pc, lr
	.ltorg

@ the code blocks: in flash where they are, in RAM at RCODE + offset
	.macro	codeloop name, blk, ram, inval
	.align	5
\name:
	mov	r12, lr
	.if	\inval
	mov	r1, #0
	mcr	p15, 0, r1, c7, c5, 0		@ invalidate the I-cache
	.endif
	ldr	r7, 8f
	.if	\ram
	ldr	r8, 9f
	add	r7, r7, r8
	.endif
1:	mov	lr, pc
	mov	pc, r7
	subs	r2, r2, #1
	bne	1b
	mov	pc, r12
	.if	\ram
8:	.word	RCODE
9:	.word	\blk - blk_start
	.else
8:	.word	\blk
	.endif
	.endm

	codeloop l_ifl,     blk16, 0, 1		@ 16 KB from flash, the I-cache emptied
	codeloop l_ifr,     blk16, 1, 1		@ and from RAM
	codeloop l_fcode12, blk12, 0, 0		@ 12 KB of flash code, 8 passes
	codeloop l_fcode24, blk24, 0, 0
	codeloop l_fcode96, blk96, 0, 0
	codeloop l_rcode12, blk12, 1, 0		@ the same in RAM
	codeloop l_rcode24, blk24, 1, 0
	codeloop l_rcode96, blk96, 1, 0

putc:
	ldr	r1, =STI
	strb	r0, [r1]
	mov	pc, lr
puts:
	ldr	r1, =STI
1:	ldrb	r2, [r0], #1
	cmp	r2, #0
	strneb	r2, [r1]
	bne	1b
	mov	pc, lr
	.ltorg

table:
	.word	l_alu,     n_alu,     16384
	.word	l_mul,     n_mul,     8192
	.word	l_branch,  n_branch,  16384
	.word	l_call,    n_call,    8192
	.word	l_hit,     n_hit,     16384
	.word	l_sthit,   n_sthit,   16384
	.word	l_seq,     n_seq,     8192
	.word	l_rdw,     n_rdw,     16384
	.word	l_wrw,     n_wrw,     16384
	.word	l_fill16,  n_fill16,  36608
	.word	l_copy,    n_copy,    2048
	.word	l_rmw,     n_rmw,     16384
	.word	l_row,     n_row,     4096
	.word	l_list,    n_list,    4096
	.word	l_tex,     n_tex,     36608
	.word	l_dws12,   n_dws12,   0
	.word	l_dws24,   n_dws24,   0
	.word	l_unc,     n_unc,     2048
	.word	l_uncw,    n_uncw,    2048
	.word	l_frd,     n_frd,     16384
	.word	l_tlbx,    n_tlbx,    4096
	.word	l_tlbs,    n_tlbs,    4098
	.word	l_sti,     n_sti,     1024
	.word	l_ifl,     n_ifl,     1
	.word	l_ifr,     n_ifr,     1
	.word	l_fcode12, n_fcode12, 8
	.word	l_fcode24, n_fcode24, 8
	.word	l_fcode96, n_fcode96, 4
	.word	l_rcode12, n_rcode12, 8
	.word	l_rcode24, n_rcode24, 8
	.word	l_rcode96, n_rcode96, 4
	.word	0
n_alu:		.asciz	"alu"
n_mul:		.asciz	"mul"
n_branch:	.asciz	"branch"
n_call:		.asciz	"call"
n_hit:		.asciz	"hit"
n_sthit:	.asciz	"sthit"
n_seq:		.asciz	"seq"
n_rdw:		.asciz	"rdw"
n_wrw:		.asciz	"wrw"
n_fill16:	.asciz	"fill16"
n_copy:		.asciz	"copy"
n_rmw:		.asciz	"rmw"
n_row:		.asciz	"row"
n_list:		.asciz	"list"
n_tex:		.asciz	"tex"
n_dws12:	.asciz	"dws12"
n_dws24:	.asciz	"dws24"
n_unc:		.asciz	"unc"
n_uncw:		.asciz	"uncw"
n_frd:		.asciz	"frd"
n_tlbx:		.asciz	"tlbx"
n_tlbs:		.asciz	"tlbs"
n_sti:		.asciz	"sti"
n_ifl:		.asciz	"ifl"
n_ifr:		.asciz	"ifr"
n_fcode12:	.asciz	"fcode12"
n_fcode24:	.asciz	"fcode24"
n_fcode96:	.asciz	"fcode96"
n_rcode12:	.asciz	"rcode12"
n_rcode24:	.asciz	"rcode24"
n_rcode96:	.asciz	"rcode96"
s_hello:	.asciz	"membench: start\n"
s_done:		.asciz	"membench: done\n"
s_exc:		.asciz	"membench: exception\n"
s_end:		.asciz	"\n#END\n"
	.align	2
