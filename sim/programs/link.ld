ENTRY(_start)
SECTIONS
{
    . = 0;
    .text : { *(.vectors) *(.text*) *(.rodata*) }
    .data : { *(.data*) }
    .bss : { *(.bss*) *(COMMON) }
}
