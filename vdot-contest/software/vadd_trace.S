/* Stage-1 trace program: one vadd.vv (SEW=8, LMUL=1, 16 lanes) on XiangShan.
 *
 * Run on the emu with --dump-wave to follow the instruction through decode,
 * rename, issue, the vialu functional unit, write-back and commit.
 * vs1 = [1..16], vs2 = [10,20,..,120,-10,-20,-30,-40] (signed lanes; the
 * last four lanes produce byte carries that must not leak into neighbours).
 */
#include "vdot_macros.h"

  .section .text.start
  .globl _start
_start:
  li t0, (3 << 9)
  csrs mstatus, t0
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, src1
  vle8.v v1, (t0)
  la t0, src2
  vle8.v v2, (t0)
  vadd.vv v3, v2, v1          /* vd[i] = vs2[i] + vs1[i] (mod 256) */
  la t0, result
  vse8.v v3, (t0)
  ld t1, 0(t0)
  la t2, expected
  ld t3, 0(t2)
  bne t1, t3, fail
  ld t1, 8(t0)
  ld t3, 8(t2)
  bne t1, t3, fail
  GOOD_TRAP
fail:
  BAD_TRAP 1

  .section .rodata
  .balign 16
src1:
  .byte 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16
src2:
  .byte 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, -10, -20, -30, -40
expected:
  .byte 11, 22, 33, 44, 55, 66, 77, 88, 99, 110, 121, 132, 3, -6, -15, -24

  .section .bss
  .balign 16
result:
  .zero 16
