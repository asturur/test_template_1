ENTRY(_start)
SECTIONS {
  . = 0x5149d000;
  .init : { *(.init) }
  . = 0x5149d284;
  .entry : { *(.entry) }
}
