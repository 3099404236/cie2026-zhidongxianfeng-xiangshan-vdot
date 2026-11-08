/* Full architectural test for the CIE 2026 vdot.vv extension.
 *
 * Runs unchanged on the NEMU interpreter and on the XiangShan emu with
 * difftest (NEMU as REF), so every vector-register write is cross-checked
 * at commit time as well as by the explicit comparisons below.
 *
 *   section 1  61 golden-model vectors (13 directed + 48 random), vl=16.
 *              vd is poisoned with 0xFF first: proves vd[127:32] := 0.
 *              High 64 bits of vs1/vs2 carry noise: proves they are ignored.
 *   section 2  vl independence: vl = 1, 8 and 0 give the same result.
 *   section 3  back-to-back RAW/WAW chain through the bypass network.
 *   section 4  register overlap: vd==vs1, vd==vs2, vs1==vs2, vd==v0, v31.
 *   section 5  consumers in other FUs (vmv.x.s, vadd.vv @e32, vslidedown)
 *              and vxsat is left untouched.
 *
 * Failure: BAD TRAP with a0 = (section << 16) | case index.
 */
#include "vdot_macros.h"

/* Store \vreg (all 16 bytes) to result_buf, compare with 16 bytes at a1. */
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
  li t0, (3 << 9)              /* mstatus.VS = Dirty */
  csrs mstatus, t0
  csrw vstart, zero

/* ---------------- section 1: generated vectors ---------------- */
  li s11, 1
  la s0, vdot_cases
  la t0, vdot_num_cases
  ld s1, 0(t0)
  li s2, 0
1:
  beqz s1, 2f
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v8, (s0)
  addi t0, s0, 16
  vle8.v v9, (t0)
  vmv.v.i v10, -1
  VDOT_VV 10, 8, 9
  addi a1, s0, 32
  CHECK v10
  addi s0, s0, 48
  addi s1, s1, -1
  addi s2, s2, 1
  j 1b
2:

/* ---------------- section 2: vl independence ---------------- */
  li s11, 2
  li s2, 0
  la s0, vdot_cases             /* case 0: positive, expected 120 */
  addi a1, s0, 32
  .irp avl, 1, 8, 0
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v8, (s0)
  addi t0, s0, 16
  vle8.v v9, (t0)
  vmv.v.i v10, -1
  vsetivli zero, \avl, e8, m1, ta, ma
  VDOT_VV 10, 8, 9
  CHECK v10
  addi s2, s2, 1
  .endr

/* ---------------- section 3: dependent chain ---------------- */
  li s11, 3
  li s2, 0
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, chain_a
  vle8.v v8, (t0)
  la t0, chain_b1
  vle8.v v9, (t0)
  la t0, chain_b2
  vle8.v v12, (t0)
  la t0, chain_b3
  vle8.v v13, (t0)
  vmv.v.i v10, -1
  vmv.v.i v11, -1
  VDOT_VV 10, 8, 9              /* v10 = vdot(A, B1)            */
  VDOT_VV 11, 10, 12            /* v11 = vdot(v10, B2)   RAW     */
  VDOT_VV 10, 11, 13            /* v10 = vdot(v11, B3)   RAW+WAW */
  la a1, chain_r2
  CHECK v11
  li s2, 1
  la a1, chain_r3
  CHECK v10

/* ---------------- section 4: register overlap ---------------- */
  li s11, 4
  li s2, 0
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, ovl_p
  vle8.v v8, (t0)
  la t0, ovl_q
  vle8.v v9, (t0)
  VDOT_VV 8, 8, 9               /* vd == vs1 */
  la a1, ovl_pq
  CHECK v8

  li s2, 1
  la t0, ovl_p
  vle8.v v8, (t0)
  VDOT_VV 9, 8, 9               /* vd == vs2 */
  la a1, ovl_pq
  CHECK v9

  li s2, 2
  la t0, ovl_p
  vle8.v v17, (t0)
  vmv.v.i v16, -1
  VDOT_VV 16, 17, 17            /* vs1 == vs2: sum of squares */
  la a1, ovl_pp
  CHECK v16

  li s2, 3
  la t0, ovl_q
  vle8.v v9, (t0)
  la t0, ovl_p
  vle8.v v8, (t0)
  vmv.v.i v0, -1
  VDOT_VV 0, 8, 9               /* vd == v0 (separate v0 regfile in KMH) */
  la a1, ovl_pq
  CHECK v0

  li s2, 4
  la t0, ovl_p
  vle8.v v30, (t0)
  la t0, ovl_q
  vle8.v v29, (t0)
  vmv.v.i v31, -1
  VDOT_VV 31, 30, 29            /* highest register numbers */
  la a1, ovl_pq
  CHECK v31

/* ---------------- section 5: consumers and vxsat ---------------- */
  li s11, 5
  li s2, 0
  csrwi vxsat, 1
  vsetivli zero, 16, e8, m1, ta, ma
  la t0, ovl_p
  vle8.v v8, (t0)
  la t0, ovl_q
  vle8.v v9, (t0)
  vmv.v.i v10, -1
  VDOT_VV 10, 8, 9
  csrr t1, vxsat                /* vdot must not touch vxsat */
  li t2, 1
  bne t1, t2, fail
  csrwi vxsat, 0
  VDOT_VV 10, 8, 9
  csrr t1, vxsat
  bnez t1, fail

  li s2, 1
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.x.s t1, v10               /* sign-extended vd[31:0] */
  la t0, ovl_pq
  lw t3, 0(t0)
  bne t1, t3, fail

  li s2, 2
  vadd.vv v11, v10, v10         /* lane 0 = 2*r, lanes 1..3 = 0 */
  vmv.x.s t2, v11
  slliw t3, t3, 1
  bne t2, t3, fail

  li s2, 3
  vslidedown.vi v12, v10, 1
  vmv.x.s t1, v12
  bnez t1, fail
  vslidedown.vi v12, v10, 2
  vmv.x.s t1, v12
  bnez t1, fail
  vslidedown.vi v12, v10, 3
  vmv.x.s t1, v12
  bnez t1, fail

pass:
  GOOD_TRAP

fail:
  slli a0, s11, 16
  or a0, a0, s2
  .word 0x0000006b

trap_handler:                   /* no trap is expected in this test */
  csrr a0, mcause
  li t0, 0xdead0000
  or a0, a0, t0
  .word 0x0000006b

/* Compare 16 bytes at result_buf with 16 expected bytes at a1. */
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

#include "vdot_cases.inc"
