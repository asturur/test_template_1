ENTRY(pcm_route_entry)

SECTIONS {
    .text 0x511b6000 : {
        KEEP(*(.text.entry))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
    }
    .data : { *(.data*) *(.bss*) *(COMMON) }
    /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) }
}

ASSERT(SIZEOF(.text) <= 4096, "PCM code crosses its audited empty page")
ASSERT(SIZEOF(.data) == 0, "PCM code must be ROM-resident")
