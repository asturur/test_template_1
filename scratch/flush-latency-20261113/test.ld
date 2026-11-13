ENTRY(_start)
SECTIONS { .text 0 : { *(.text*) } /DISCARD/ : { *(.ARM.attributes) *(.comment) *(.note*) } }
