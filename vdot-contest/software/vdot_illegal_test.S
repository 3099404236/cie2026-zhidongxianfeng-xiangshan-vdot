/* Precise-exception tests for the CIE 2026 vdot.vv extension.
 *
 * vdot.vv is legal only when vill=0, SEW=e8, LMUL=m1, vm=1, vstart=0 and
 * mstatus.VS != Off. Every other configuration must raise an illegal
 * instruction exception (mcause = 2) and must leave vd unchanged.
 *
 * For each case: poison vd with a known pattern, create the illegal state,
 * execute vdot, let the handler count the trap and skip the instruction,
 * restore a legal state, and check that vd still holds the pattern.
 * Cases 14-17 apply the same rules to the accumulating variant vdota.vv.
 * Finally one legal vdot.vv must still produce 120.
 *
 * Failure: BAD TRAP, a0 = case number (or 0xbad0000|mcause from the handler).
 */
#include "vdot_macros.h"

#define NUM_ILLEGAL 17

/* Poison \vreg with 0x5a bytes (vl=16, e8, m1). */
.macro POISON vreg
  vsetivli zero, 16, e8, m1, ta, ma
  vmv.v.x \vreg, s5
.endm

/* Restore a legal vtype, then check \vreg still holds the 0x5a pattern. */
.macro EXPECT_UNTOUCHED vreg
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, result_buf
  vse8.v \vreg, (t0)
  ld t1, 0(t0)
  bne t1, s6, fail
  ld t1, 8(t0)
  bne t1, s6, fail
.endm

/* Expect exactly \n traps so far. */
.macro EXPECT_TRAPS n
  lw t0, 0(s0)
  li t1, \n
  bne t0, t1, fail
.endm

  .section .text.start
  .globl _start
_start:
  la t0, trap_handler
  csrw mtvec, t0
  li t0, (3 << 9)
  csrs mstatus, t0
  csrw vstart, zero

  la s0, trap_count
  sw zero, 0(s0)
  li s5, 0x5a
  li s6, 0x5a5a5a5a5a5a5a5a
  li s11, 0

  /* 1. vm = 0 does not match the vdot.vv encoding at all. */
  li s11, 1
  POISON v10
  VDOT_VV_MASKED 10, 8, 9
  EXPECT_UNTOUCHED v10
  EXPECT_TRAPS 1

  /* 2-4. SEW != e8 (LMUL = m1). */
  .irp sew, e16, e32, e64
  addi s11, s11, 1
  POISON v10
  vsetivli zero, 1, \sew, m1, ta, ma
  VDOT_VV 10, 8, 9
  EXPECT_UNTOUCHED v10
  .endr
  EXPECT_TRAPS 4

  /* 5. LMUL = m2 (all operands 2-aligned, so only LMUL is wrong). */
  li s11, 5
  POISON v10
  vsetivli zero, 16, e8, m2, ta, ma
  VDOT_VV 10, 8, 12
  EXPECT_UNTOUCHED v10
  /* 6. LMUL = m4 (operands 4-aligned). */
  li s11, 6
  POISON v12
  vsetivli zero, 16, e8, m4, ta, ma
  VDOT_VV 12, 8, 16
  EXPECT_UNTOUCHED v12
  /* 7. LMUL = m8 (operands 8-aligned). */
  li s11, 7
  POISON v16
  vsetivli zero, 16, e8, m8, ta, ma
  VDOT_VV 16, 8, 24
  EXPECT_UNTOUCHED v16
  EXPECT_TRAPS 7

  /* 8-10. Fractional LMUL. */
  .irp lmul, mf2, mf4, mf8
  addi s11, s11, 1
  POISON v10
  vsetivli zero, 1, e8, \lmul, ta, ma
  VDOT_VV 10, 8, 9
  EXPECT_UNTOUCHED v10
  .endr
  EXPECT_TRAPS 10

  /* 11. vstart != 0 (the handler clears vstart). */
  li s11, 11
  POISON v10
  li t0, 1
  csrw vstart, t0
  VDOT_VV 10, 8, 9
  EXPECT_UNTOUCHED v10
  EXPECT_TRAPS 11

  /* 12. vill = 1: vsetvl with a reserved vlmul encoding (0b100). */
  li s11, 12
  POISON v10
  li t1, 0x4
  vsetvl t2, zero, t1
  csrr t3, vtype
  srli t3, t3, 63               /* vill is vtype[XLEN-1] */
  beqz t3, fail
  VDOT_VV 10, 8, 9
  EXPECT_UNTOUCHED v10
  EXPECT_TRAPS 12

  /* 13. mstatus.VS = Off. */
  li s11, 13
  POISON v10
  vsetivli zero, 16, e8, m1, ta, ma
  li t0, (3 << 9)
  csrc mstatus, t0
  VDOT_VV 10, 8, 9              /* the handler turns VS back on */
  EXPECT_UNTOUCHED v10
  EXPECT_TRAPS 13

  /* 14-17. vdota.vv: vm = 0, SEW = e16, LMUL = m2, vstart != 0. */
  li s11, 14
  POISON v10
  VDOTA_VV_MASKED 10, 8, 9
  EXPECT_UNTOUCHED v10
  li s11, 15
  POISON v10
  vsetivli zero, 1, e16, m1, ta, ma
  VDOTA_VV 10, 8, 9
  EXPECT_UNTOUCHED v10
  li s11, 16
  POISON v10
  vsetivli zero, 16, e8, m2, ta, ma
  VDOTA_VV 10, 8, 12
  EXPECT_UNTOUCHED v10
  li s11, 17
  POISON v10
  li t0, 1
  csrw vstart, t0
  VDOTA_VV 10, 8, 9
  EXPECT_UNTOUCHED v10
  EXPECT_TRAPS NUM_ILLEGAL

  /* A legal vdot.vv still works afterwards: [1..8].[8..1] = 120. */
  li s11, 18
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, positive_lhs
  vle8.v v8, (t0)
  la t0, positive_rhs
  vle8.v v9, (t0)
  VDOT_VV 10, 8, 9
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.x.s t1, v10
  li t2, 120
  bne t1, t2, fail
  EXPECT_TRAPS NUM_ILLEGAL

pass:
  GOOD_TRAP

fail:
  mv a0, s11
  .word 0x0000006b

trap_handler:
  csrr t0, mcause
  li t1, 2                      /* illegal instruction */
  bne t0, t1, bad_cause
  lw t0, 0(s0)
  addi t0, t0, 1
  sw t0, 0(s0)
  li t0, (3 << 9)               /* VS back on (case 13) so vstart is accessible */
  csrs mstatus, t0
  csrw vstart, zero
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret
bad_cause:
  li a0, 0xbad0000
  or a0, a0, t0
  .word 0x0000006b

  .section .rodata
  .balign 16
positive_lhs:
  .byte 1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 0, 0, 0, 0, 0
positive_rhs:
  .byte 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0

  .section .bss
  .balign 16
result_buf:
  .zero 16
trap_count:
  .word 0
