ENTRY(_start)
SECTIONS {
  . = 0x7000000;
  .multiboot : { KEEP(*(.multiboot)) }
  .text : { *(.text*) }
  .rodata : { *(.rodata*) }
  .data : { *(.data*) }
  .bss : { *(.bss*) *(COMMON) }
  /DISCARD/ : { *(.comment) *(.note*) }
}