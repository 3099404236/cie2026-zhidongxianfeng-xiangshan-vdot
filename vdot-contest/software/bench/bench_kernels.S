/* Cycle-accurate micro-benchmarks: vdot.vv vs. standard RVV 1.0 sequences.
 *
 * Every kernel stores {mcycle delta, minstret delta} to ctr[0..1].
 * CSR reads of mcycle/minstret are executed non-speculatively by XiangShan,
 * so the counters bracket exactly the instructions in between.
 *
 * Latency kernels form a strict dependency chain through v10 and compute the
 * SAME values for vdot and baseline (v10 bytes 4..7 start at 0 and the
 * baseline uses tail-undisturbed), so their final v10 must be identical.
 */
#include "../vdot_macros.h"

.macro T_START
  csrr t5, mcycle
  csrr t4, minstret
.endm

.macro T_STOP ctr
  csrr t6, mcycle
  csrr t3, minstret
  sub t6, t6, t5
  sub t3, t3, t4
  sd t6, 0(\ctr)
  sd t3, 8(\ctr)
.endm

  .text
  .balign 64

/* void k_lat_vdot(u64 iters, const i8 a[16], const i8 b[16], i8 out[16], u64 ctr[2])
 * 8 dependent vdot.vv per iteration: v10 = vdot(v10, v9). */
  .globl k_lat_vdot
k_lat_vdot:
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v10, (a1)
  vle8.v v9, (a2)
  T_START
1:
  .rept 8
  VDOT_VV 10, 10, 9
  .endr
  addi a0, a0, -1
  bnez a0, 1b
  T_STOP a4
  vse8.v v10, (a3)
  ret

/* Same chain with the "naive" baseline used in vdot_baseline.S:
 * vwmul.vv @ e8,m1 (EMUL=2) + vwredsum.vs @ e16,m2, two vtype switches. */
  .globl k_lat_base_m1
k_lat_base_m1:
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v10, (a1)
  vle8.v v9, (a2)
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.v.i v14, 0
  T_START
1:
  .rept 8
  vsetivli zero, 8, e8, m1, ta, ma
  vwmul.vv v12, v10, v9
  vsetivli zero, 8, e16, m2, tu, ma
  vwredsum.vs v10, v12, v14
  .endr
  addi a0, a0, -1
  bnez a0, 1b
  T_STOP a4
  vsetivli zero, 16, e8, m1, ta, ma
  vse8.v v10, (a3)
  ret

/* Tuned baseline: vwmul.vv @ e8,mf2 (EMUL=1, one uop) + vwredsum.vs @ e16,m1. */
  .globl k_lat_base_mf2
k_lat_base_mf2:
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v10, (a1)
  vle8.v v9, (a2)
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.v.i v14, 0
  T_START
1:
  .rept 8
  vsetivli zero, 8, e8, mf2, ta, ma
  vwmul.vv v12, v10, v9
  vsetivli zero, 8, e16, m1, tu, ma
  vwredsum.vs v10, v12, v14
  .endr
  addi a0, a0, -1
  bnez a0, 1b
  T_STOP a4
  vsetivli zero, 16, e8, m1, ta, ma
  vse8.v v10, (a3)
  ret

/* Accumulate chain: 8 dependent vdota.vv per iteration (RAW through vd only). */
  .globl k_lat_vdota
k_lat_vdota:
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v8, (a1)
  vle8.v v9, (a2)
  vmv.v.i v10, 0
  T_START
1:
  .rept 8
  VDOTA_VV 10, 8, 9
  .endr
  addi a0, a0, -1
  bnez a0, 1b
  T_STOP a4
  vse8.v v10, (a3)
  ret

/* Throughput: 8 independent vdot.vv per iteration. */
  .globl k_thr_vdot
k_thr_vdot:
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v8, (a1)
  vle8.v v9, (a2)
  T_START
1:
  .irp r, 16, 17, 18, 19, 20, 21, 22, 23
  VDOT_VV \r, 8, 9
  .endr
  addi a0, a0, -1
  bnez a0, 1b
  T_STOP a4
  vse8.v v23, (a3)
  ret

/* Throughput baseline: 8 independent dot products per iteration, scheduled
 * as 8 vwmul.vv under one vtype, then 8 vwredsum.vs under the other. */
  .globl k_thr_base
k_thr_base:
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v8, (a1)
  vle8.v v9, (a2)
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.v.i v14, 0
  T_START
1:
  vsetivli zero, 8, e8, mf2, ta, ma
  .irp r, 16, 17, 18, 19, 20, 21, 22, 23
  vwmul.vv v\r, v8, v9
  .endr
  vsetivli zero, 8, e16, m1, ta, ma
  vwredsum.vs v24, v16, v14
  vwredsum.vs v25, v17, v14
  vwredsum.vs v26, v18, v14
  vwredsum.vs v27, v19, v14
  vwredsum.vs v28, v20, v14
  vwredsum.vs v29, v21, v14
  vwredsum.vs v30, v22, v14
  vwredsum.vs v31, v23, v14
  addi a0, a0, -1
  bnez a0, 1b
  T_STOP a4
  vsetivli zero, 16, e8, m1, ta, ma
  vse8.v v31, (a3)
  ret

/* ------------------------------------------------------------------------
 * INT8 GEMV  y[M] = W[M][K] . x[K]   (K % 32 == 0), int32 outputs.
 * void k_gemv_*(const i8 *W, const i8 *x, i32 *y, u64 M, u64 K, u64 ctr[2])
 * ---------------------------------------------------------------------- */

/* vdot.vv: 4 chunks of 8 per step, 4 independent int32 accumulators. */
  .globl k_gemv_vdot
k_gemv_vdot:
  T_START
  mv a6, a3
2:
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.v.i v24, 0
  vmv.v.i v25, 0
  vmv.v.i v26, 0
  vmv.v.i v27, 0
  mv t1, a1
  srli t2, a4, 5
1:
  vsetivli zero, 8, e8, m1, ta, ma
  vle8.v v8, (a0)
  vle8.v v9, (t1)
  VDOT_VV 16, 8, 9
  addi t0, a0, 8
  addi a7, t1, 8
  vle8.v v10, (t0)
  vle8.v v11, (a7)
  VDOT_VV 17, 10, 11
  addi t0, a0, 16
  addi a7, t1, 16
  vle8.v v12, (t0)
  vle8.v v13, (a7)
  VDOT_VV 18, 12, 13
  addi t0, a0, 24
  addi a7, t1, 24
  vle8.v v14, (t0)
  vle8.v v15, (a7)
  VDOT_VV 19, 14, 15
  vsetivli zero, 1, e32, m1, ta, ma
  vadd.vv v24, v24, v16
  vadd.vv v25, v25, v17
  vadd.vv v26, v26, v18
  vadd.vv v27, v27, v19
  addi a0, a0, 32
  addi t1, t1, 32
  addi t2, t2, -1
  bnez t2, 1b
  vadd.vv v24, v24, v25
  vadd.vv v26, v26, v27
  vadd.vv v24, v24, v26
  vmv.x.s t0, v24
  sw t0, 0(a2)
  addi a2, a2, 4
  addi a6, a6, -1
  bnez a6, 2b
  T_STOP a5
  ret

/* vdota.vv, 8-byte loads: 4 independent accumulators live in v24..v27 for the
 * whole row; no vtype switch and no vadd inside the K loop. */
  .globl k_gemv_vdota
k_gemv_vdota:
  T_START
  mv a6, a3
2:
  vsetivli zero, 16, e8, m1, ta, ma
  vmv.v.i v24, 0
  vmv.v.i v25, 0
  vmv.v.i v26, 0
  vmv.v.i v27, 0
  mv t1, a1
  srli t2, a4, 5
  vsetivli zero, 8, e8, m1, ta, ma
1:
  vle8.v v8, (a0)
  vle8.v v9, (t1)
  VDOTA_VV 24, 8, 9
  addi t0, a0, 8
  addi a7, t1, 8
  vle8.v v10, (t0)
  vle8.v v11, (a7)
  VDOTA_VV 25, 10, 11
  addi t0, a0, 16
  addi a7, t1, 16
  vle8.v v12, (t0)
  vle8.v v13, (a7)
  VDOTA_VV 26, 12, 13
  addi t0, a0, 24
  addi a7, t1, 24
  vle8.v v14, (t0)
  vle8.v v15, (a7)
  VDOTA_VV 27, 14, 15
  addi a0, a0, 32
  addi t1, t1, 32
  addi t2, t2, -1
  bnez t2, 1b
  vsetivli zero, 1, e32, m1, ta, ma
  vadd.vv v24, v24, v25
  vadd.vv v26, v26, v27
  vadd.vv v24, v24, v26
  vmv.x.s t0, v24
  sw t0, 0(a2)
  addi a2, a2, 4
  addi a6, a6, -1
  bnez a6, 2b
  T_STOP a5
  ret

/* vdota.vv, 16-byte loads: every loaded byte is used; the high 8 bytes reach
 * the low half through vslidedown.vi (vdota consumes only the low 64 bits). */
  .globl k_gemv_vdota16
k_gemv_vdota16:
  T_START
  mv a6, a3
2:
  vsetivli zero, 16, e8, m1, ta, ma
  vmv.v.i v24, 0
  vmv.v.i v25, 0
  vmv.v.i v26, 0
  vmv.v.i v27, 0
  mv t1, a1
  srli t2, a4, 5
1:
  vle8.v v8, (a0)
  vle8.v v9, (t1)
  addi t0, a0, 16
  addi a7, t1, 16
  vle8.v v12, (t0)
  vle8.v v13, (a7)
  VDOTA_VV 24, 8, 9
  vslidedown.vi v10, v8, 8
  vslidedown.vi v11, v9, 8
  VDOTA_VV 25, 10, 11
  VDOTA_VV 26, 12, 13
  vslidedown.vi v14, v12, 8
  vslidedown.vi v15, v13, 8
  VDOTA_VV 27, 14, 15
  addi a0, a0, 32
  addi t1, t1, 32
  addi t2, t2, -1
  bnez t2, 1b
  vsetivli zero, 1, e32, m1, ta, ma
  vadd.vv v24, v24, v25
  vadd.vv v26, v26, v27
  vadd.vv v24, v24, v26
  vmv.x.s t0, v24
  sw t0, 0(a2)
  addi a2, a2, 4
  addi a6, a6, -1
  bnez a6, 2b
  T_STOP a5
  ret

/* Same-function baseline: each 8-element chunk is vwmul.vv + vwredsum.vs,
 * accumulating through the reduction's scalar operand (vs1 == vd). */
  .globl k_gemv_base
k_gemv_base:
  T_START
  mv a6, a3
2:
  vsetivli zero, 4, e32, m1, ta, ma
  vmv.v.i v24, 0
  vmv.v.i v25, 0
  vmv.v.i v26, 0
  vmv.v.i v27, 0
  mv t1, a1
  srli t2, a4, 5
1:
  vsetivli zero, 8, e8, mf2, ta, ma
  vle8.v v8, (a0)
  vle8.v v9, (t1)
  vwmul.vv v16, v8, v9
  addi t0, a0, 8
  addi a7, t1, 8
  vle8.v v10, (t0)
  vle8.v v11, (a7)
  vwmul.vv v17, v10, v11
  addi t0, a0, 16
  addi a7, t1, 16
  vle8.v v12, (t0)
  vle8.v v13, (a7)
  vwmul.vv v18, v12, v13
  addi t0, a0, 24
  addi a7, t1, 24
  vle8.v v14, (t0)
  vle8.v v15, (a7)
  vwmul.vv v19, v14, v15
  vsetivli zero, 8, e16, m1, ta, ma
  vwredsum.vs v24, v16, v24
  vwredsum.vs v25, v17, v25
  vwredsum.vs v26, v18, v26
  vwredsum.vs v27, v19, v27
  addi a0, a0, 32
  addi t1, t1, 32
  addi t2, t2, -1
  bnez t2, 1b
  vsetivli zero, 1, e32, m1, ta, ma
  vadd.vv v24, v24, v25
  vadd.vv v26, v26, v27
  vadd.vv v24, v24, v26
  vmv.x.s t0, v24
  sw t0, 0(a2)
  addi a2, a2, 4
  addi a6, a6, -1
  bnez a6, 2b
  T_STOP a5
  ret

/* Best-effort full-width RVV 1.0: 16 bytes per load, widening products are
 * accumulated element-wise in two e32/m4 groups, one reduction per row. */
  .globl k_gemv_rvv
k_gemv_rvv:
  T_START
  mv a6, a3
2:
  vsetivli zero, 16, e32, m4, ta, ma
  vmv.v.i v24, 0
  vmv.v.i v28, 0
  mv t1, a1
  srli t2, a4, 5
1:
  vsetivli zero, 16, e8, m1, ta, ma
  vle8.v v8, (a0)
  vle8.v v9, (t1)
  addi t0, a0, 16
  addi a7, t1, 16
  vle8.v v10, (t0)
  vle8.v v11, (a7)
  vwmul.vv v16, v8, v9
  vwmul.vv v20, v10, v11
  vsetivli zero, 16, e16, m2, ta, ma
  vwadd.wv v24, v24, v16
  vwadd.wv v28, v28, v20
  addi a0, a0, 32
  addi t1, t1, 32
  addi t2, t2, -1
  bnez t2, 1b
  vsetivli zero, 16, e32, m4, ta, ma
  vadd.vv v24, v24, v28
  vmv.s.x v8, zero
  vredsum.vs v8, v24, v8
  vmv.x.s t0, v8
  sw t0, 0(a2)
  addi a2, a2, 4
  addi a6, a6, -1
  bnez a6, 2b
  T_STOP a5
  ret
