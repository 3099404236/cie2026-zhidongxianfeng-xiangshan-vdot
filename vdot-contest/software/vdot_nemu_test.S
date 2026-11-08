/* Bare-metal NEMU smoke test for the CIE 2026 vdot.vv extension.
 *
 * The custom word encodes: vdot.vv v10, v8, v9
 *   funct6=001101, vm=1, funct3=010, opcode=0x57
 */

  .section .text.start
  .globl _start
_start:
  la t0, trap_handler
  csrw mtvec, t0

  /* Enable vector state in mstatus.VS. */
  li t0, (3 << 9)
  csrs mstatus, t0

  /* Positive case: [1..8] dot [8..1] = 120. */
  la a0, positive_lhs
  la a1, positive_rhs
  li a2, 120
  jal ra, run_case
  bnez a0, fail

  /* Negative case: [-1..-8] dot [1..8] = -204. */
  la a0, negative_lhs
  la a1, negative_rhs
  li a2, -204
  jal ra, run_case
  bnez a0, fail

  /* Boundary case: 8 * (-128 * -128) = 131072. */
  la a0, boundary_lhs
  la a1, boundary_rhs
  li a2, 131072
  jal ra, run_case
  bnez a0, fail

pass:
  li a0, 0
  .word 0x0000006b       /* nemu_trap: good trap when a0 == 0 */

fail:
  li a0, 1
  .word 0x0000006b

trap_handler:
  csrr a0, mcause
  .word 0x0000006b

/* a0=lhs address, a1=rhs address, a2=expected signed 32-bit result.
 * Return a0=0 on success, 1 on mismatch.
 */
run_case:
  vsetivli zero, 8, e8, m1, ta, ma
  vle8.v v8, (a0)
  vle8.v v9, (a1)
  .word 0x36942557       /* vdot.vv v10, v8, v9 */

  /* Reinterpret the low result lane as signed e32 for scalar comparison. */
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.x.s t1, v10
  xor t1, t1, a2
  snez a0, t1
  ret

  .section .rodata
  .balign 16
positive_lhs:
  .byte 1, 2, 3, 4, 5, 6, 7, 8
  .zero 8
positive_rhs:
  .byte 8, 7, 6, 5, 4, 3, 2, 1
  .zero 8
negative_lhs:
  .byte -1, -2, -3, -4, -5, -6, -7, -8
  .zero 8
negative_rhs:
  .byte 1, 2, 3, 4, 5, 6, 7, 8
  .zero 8
boundary_lhs:
  .byte -128, -128, -128, -128, -128, -128, -128, -128
  .zero 8
boundary_rhs:
  .byte -128, -128, -128, -128, -128, -128, -128, -128
  .zero 8
