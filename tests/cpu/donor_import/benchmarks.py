"""First ARM benchmark batch. Expected results come from host integer models.

The benchmark kernels are unchanged across historical and working-tree sources.
These are CPU/cache tests with a synthetic backing store, not SDRAM pin timing.
"""

MASK = (1 << 32) - 1


def cases():
    multiply = 1
    accumulated = 7
    for _ in range(16):
        multiply = (multiply * 1664525) & MASK
        accumulated = (accumulated + multiply * 3) & MASK
    shifted = 0
    for _ in range(32):
        shifted ^= 3 << 3
        shifted = ((shifted >> 1) | (shifted << 31)) & MASK
    long_product = (-2147483647 * -3 * 2) & ((1 << 64) - 1)
    result = [
        dict(id="add_dependent", group="C", operations=128,
             asm=".rept 128\n add r0,r0,#1\n.endr", expected={0: 128}),
        dict(id="alu_independent", group="C", operations=128,
             asm=".rept 32\n add r0,r0,#1\n add r1,r1,#3\n add r2,r2,#5\n add r3,r3,#7\n.endr",
             expected={0: 32, 1: 99, 2: 165, 3: 231}),
        dict(id="carry_flags", group="C", operations=128,
             asm=".rept 32\n adds r0,r0,#1\n adc r1,r1,#0\n subs r2,r2,#1\n sbc r3,r3,#0\n.endr",
             expected={0: 32, 1: 3, 2: (-27) & MASK, 3: 6}, flags=0xA0000000),
        dict(id="shift_dependent", group="C", operations=64,
             asm=".rept 32\n eor r0,r0,r1,lsl #3\n mov r0,r0,ror #1\n.endr",
             expected={0: shifted}),
        dict(id="multiply_accumulate", group="D", operations=32,
             init="mov r0,#1\nldr r2,=1664525",
             initial_registers={0: 1, 2: 1664525},
             asm=".rept 16\n mul r0,r2,r0\n mla r3,r0,r1,r3\n.endr",
             expected={0: multiply, 3: accumulated}),
        dict(id="multiply_long", group="D", operations=32,
             init="ldr r2,=0x80000001\nmvn r3,#2",
             initial_registers={2: 0x80000001, 3: 0xFFFFFFFD},
             asm=".rept 16\n smull r0,r1,r2,r3\n smlal r0,r1,r2,r3\n.endr",
             expected={0: long_product & MASK, 1: long_product >> 32}),
        dict(id="load_dependent", group="E", operations=32,
             asm=".rept 32\n ldr r0,[r4]\n add r0,r0,#1\n.endr",
             expected={0: 0x101}),
        dict(id="load_independent", group="E", operations=128,
             asm=".rept 32\n ldr r0,[r4]\n ldr r1,[r4,#4]\n ldr r2,[r4,#8]\n ldr r3,[r4,#12]\n.endr",
             expected={0: 0x100, 1: 0x101, 2: 0x102, 3: 0x103}),
        dict(id="load_formats", group="E", operations=128,
             asm=".rept 32\n ldrb r0,[r4,#1]\n ldrsb r1,[r4,#34]\n ldrsh r2,[r4,#34]\n ldrh r3,[r4,#32]\n.endr",
             expected={0: 1, 1: MASK, 2: 0xFFFF80FF, 3: 0x7F01}),
        dict(id="store_reload", group="E", operations=32,
             asm=".rept 32\n add r0,r0,#1\n str r0,[r6]\n ldr r1,[r6]\n.endr",
             expected={0: 32, 1: 32}),
        dict(id="block_copy", group="F", operations=64,
             asm=".rept 16\n ldmia r5!,{r0-r3}\n stmia r6!,{r0-r3}\n.endr",
             expected={0: 0x103C, 1: 0x103D, 2: 0x103E, 3: 0x103F},
             checks="ldr r5,=0x80003000\nldr r6,=0x1000\nmov r7,#64\n"
                    "copy_check:\nldr r0,[r5],#4\ncmp r0,r6\nbne fail\n"
                    "add r6,r6,#1\nsubs r7,r7,#1\nbne copy_check"),
        dict(id="direct_branch", group="B", operations=64,
             asm="mov r8,#64\nbranch_loop:\nadd r0,r0,#1\nsubs r8,r8,#1\nbne branch_loop",
             expected={0: 64}),
        dict(id="call_return", group="B", operations=32,
             asm=".rept 32\n bl return_leaf\n.endr", expected={0: 32},
             tail="return_leaf:\nadd r0,r0,#1\nmov pc,lr"),
        dict(id="cp15_reads", group="F", operations=64,
             asm=".rept 32\n mrc p15,0,r0,c3,c0,0\n mrc p15,0,r1,c2,c0,0\n.endr",
             expected={0: 1, 1: 0x0A004000}),
        dict(id="cache_line_stride", group="G", operations=65,
             init="ldr r5,=0x80010000", cold_data=True,
             initial_registers={5: 0x80010000},
             asm=".rept 65\n ldr r0,[r5],#256\n.endr", expected={0: 0x240}),
    ]
    for item in result:
        item.setdefault("warmups", 2)
        item.setdefault("samples", 3)
    return result


def assembly(case):
    checks = []
    if "flags" in case:
        checks += ["mrs r7,cpsr", "and r7,r7,#0xf0000000",
                   f"ldr r8,=0x{case['flags']:08x}", "cmp r7,r8", "bne fail"]
    for register, expected in case["expected"].items():
        checks += [f"ldr r8,=0x{expected:08x}", f"cmp r{register},r8", "bne fail"]
    # The section table is initialized by the guest, not a mocked translation.
    # VA80000000 maps to real modeled backing at PA0A000000, the line-port target.
    return f""".syntax unified
.cpu arm920t
.arm
.section .vectors,"ax"
.global _start
_start:
 b reset_entry
.rept 7
 b fail
.endr
.text
reset_entry:
 ldr sp,=0x0a01f000
 ldr r4,=0x0a004000
 mov r0,#0
 mov r1,#4096
clear_table:
 str r0,[r4],#4
 subs r1,r1,#1
 bne clear_table
 ldr r4,=0x0a004000
 ldr r0,=0x00000c0e
 str r0,[r4]
 ldr r0,=0x0a000c0e
 str r0,[r4,#640]
 add r5,r4,#0x2000
 str r0,[r5]
 ldr r0,=0xf0000c02
 add r5,r4,#0x3c00
 str r0,[r5]
 mcr p15,0,r4,c2,c0,0
 mov r0,#1
 mcr p15,0,r0,c3,c0,0
 mrc p15,0,r0,c1,c0,0
 orr r0,r0,#5
 orr r0,r0,#0x1000
 mcr p15,0,r0,c1,c0,0
 mov r10,#{case['warmups'] + case['samples']}
sample_loop:
 {('mov r0,#0' + chr(10) + 'mcr p15,0,r0,c7,c14,0') if case.get('cold_data') else 'nop'}
 mov r0,#0
 mov r1,#3
 mov r2,#5
 mov r3,#7
 ldr r4,=0x80001000
 ldr r5,=0x80002000
 ldr r6,=0x80003000
 mov r7,#1
 mov r8,#0
 {case.get('init', 'nop')}
 bl kernel
 subs r10,r10,#1
 bne sample_loop
 ldr r0,=0x50415353
 b finish
kernel:
 mov r9,lr
.global body_begin
body_begin:
 nop
 {case['asm']}
.global body_end
body_end:
 nop
 {chr(10).join(checks)}
 {case.get('checks', 'nop')}
 bx r9
 {case.get('tail', '')}
fail:
 ldr r0,=0x4641494c
finish:
 ldr r1,=0xf0000000
 str r0,[r1]
 b .
.ltorg
"""
