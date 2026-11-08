OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text : { *(.text.start) *(.text*) }
  .rodata : { *(.rodata*) *(.srodata*) }
  .data : { *(.data*) *(.sdata*) }
  . = ALIGN(16);
  __bss_start = .;
  .bss : { *(.bss*) *(.sbss*) *(COMMON) }
  . = ALIGN(16);
  __bss_end = .;
  . = . + 0x10000;
  . = ALIGN(16);
  __stack_top = .;
  /DISCARD/ : { *(.note*) *(.comment) }
}
