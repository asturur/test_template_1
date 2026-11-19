ENTRY(_start)
SECTIONS
{
    . = 0;
    .text : { *(.text*) *(.rodata*) }
    ASSERT(. <= 0xA000, "the main program must end below 0xA000")
    . = 0x300000;
    .blocks : { *(.blocks*) }
}
