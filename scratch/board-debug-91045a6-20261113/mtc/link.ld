ENTRY(mtc_entry)
SECTIONS { .text 0x511bd000 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }
