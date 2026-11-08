/* Architectural test for the accumulating variant vdota.vv (funct6 = 001110):
 *
 *   vd[31:0] = vd_old[31:0] + sum_i sext(vs1[i]) * sext(vs2[i])   (int32 wrap)
 *   vd[127:32] = 0
 *
 *   section 1  39 golden-model records (old vd | vs1 | vs2 | expected vd),
 *              incl. int32 wrap-around and garbage in old vd[127:32]
 *   section 2  64-step accumulation chain through the same vd (RAW on vd)
 *   section 3  register overlap: vd==vs1, vd==vs2, vd==v0
 *   section 4  vdot.vv and vdota.vv interleaved on the same registers
 *
 * Failure: BAD TRAP with a0 = (section << 16) | case index.
 */
#include "vdot_macros.h"

.macro CHECK vreg
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, result_buf
  vse8.v \vreg, (t0)
  jal ra, cmp16
  bnez a0, fail
.endm

  .section .text.start
  .globl _start
_start:
  la t0, trap_handler
  csrw mtvec, t0
  li t0, (3 << 9)
  csrs mstatus, t0
  csrw vstart, zero

/* ---------------- section 1: generated records ---------------- */
  li s11, 1
  li s2, 0
  la s0, vdota_cases
  la t0, vdota_num_cases
  ld s1, 0(t0)
1:
  beqz s1, 2f
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v10, (s0)              /* old vd */
  addi t0, s0, 16
  vle8.v v8, (t0)               /* vs1 */
  addi t0, s0, 32
  vle8.v v9, (t0)               /* vs2 */
  VDOTA_VV 10, 8, 9
  addi a1, s0, 48
  CHECK v10
  addi s0, s0, 64
  addi s1, s1, -1
  addi s2, s2, 1
  j 1b
2:

/* ---------------- section 2: 64-step accumulation chain ---------------- */
  li s11, 2
  li s2, 0
  vsetivli zero, 16, e8, m1, ta, ma
  vmv.v.i v20, 0
  la s0, vdota_chain
  li s1, 64
3:
  vle8.v v8, (s0)
  addi t0, s0, 16
  vle8.v v9, (t0)
  VDOTA_VV 20, 8, 9             /* v20 += dot(A_i, B_i) */
  addi s0, s0, 32
  addi s1, s1, -1
  bnez s1, 3b
  la a1, vdota_chain_result
  CHECK v20

/* ---------------- section 3: register overlap ---------------- */
  li s11, 3
  li s2, 0
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, vdota_p
  vle8.v v8, (t0)
  la t0, vdota_q
  vle8.v v9, (t0)
  VDOTA_VV 8, 8, 9              /* vd == vs1: old vd is P */
  la a1, vdota_p_pq
  CHECK v8

  li s2, 1
  la t0, vdota_p
  vle8.v v8, (t0)
  la t0, vdota_q
  vle8.v v9, (t0)
  VDOTA_VV 9, 8, 9              /* vd == vs2: old vd is Q */
  la a1, vdota_q_pq
  CHECK v9

  li s2, 2
  la t0, vdota_q
  vle8.v v9, (t0)
  vmv.v.i v0, -1                /* old v0 = all ones -> acc = -1 */
  VDOTA_VV 0, 8, 9              /* vd == v0 (separate v0 regfile in KMH) */
  la a1, vdota_m1_pq
  CHECK v0

/* ---------------- section 4: vdot / vdota interleaved ---------------- */
  li s11, 4
  li s2, 0
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, vdota_p
  vle8.v v8, (t0)
  la t0, vdota_q
  vle8.v v9, (t0)
  vmv.v.i v12, -1
  VDOT_VV 12, 8, 9              /* v12 = dot(P,Q), upper bits cleared */
  VDOTA_VV 12, 8, 9             /* v12 = 2 * dot(P,Q)                 */
  VDOTA_VV 12, 8, 9             /* v12 = 3 * dot(P,Q)                 */
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.x.s t1, v12
  vsetivli zero, 16, e8, m1, ta, ma
  vmv.v.i v13, 0
  VDOTA_VV 13, 8, 9
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.x.s t2, v13               /* dot(P,Q) */
  slliw t3, t2, 1
  addw t3, t3, t2               /* 3 * dot */
  bne t1, t3, fail
  li s2, 1
  vslidedown.vi v14, v12, 1     /* lanes 1..3 must be zero */
  vmv.x.s t1, v14
  bnez t1, fail

pass:
  GOOD_TRAP

fail:
  slli a0, s11, 16
  or a0, a0, s2
  .word 0x0000006b

trap_handler:
  csrr a0, mcause
  li t0, 0xdead0000
  or a0, a0, t0
  .word 0x0000006b

cmp16:
  ld t1, 0(t0)
  ld t2, 0(a1)
  bne t1, t2, 1f
  ld t1, 8(t0)
  ld t2, 8(a1)
  bne t1, t2, 1f
  li a0, 0
  ret
1:
  li a0, 1
  ret

  .section .bss
  .balign 16
result_buf:
  .zero 16

#include "vdota_cases.inc"
