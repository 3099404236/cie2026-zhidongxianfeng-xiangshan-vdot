/* Minimal bare-metal runtime for NEMU and the XiangShan emu (M-mode). */
  .section .text.start
  .globl _start
_start:
  la sp, __stack_top
  la t0, trap_entry
  csrw mtvec, t0
  li t0, (3 << 13) | (3 << 9)     /* mstatus.FS = mstatus.VS = Dirty */
  csrs mstatus, t0
  csrw vstart, zero
  la t0, __bss_start
  la t1, __bss_end
1:
  bgeu t0, t1, 2f
  sd zero, 0(t0)
  addi t0, t0, 8
  j 1b
2:
  call main
  .word 0x0000006b                /* trap with a0 = main's return value */

trap_entry:                       /* any trap here is a bug: report mcause */
  csrr a0, mcause
  li t0, 0xdead0000
  or a0, a0, t0
  .word 0x0000006b
