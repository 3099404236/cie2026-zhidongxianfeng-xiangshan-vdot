/* Existing-RVV baseline for one signed INT8 dot product.
 *
 * Inputs: v8/v9 contain eight signed bytes.
 * Output: low 32 bits of v14 contain the exact dot product.
 * Clobbers: v10-v14.
 */

  .section .text
  .globl vdot_baseline
vdot_baseline:
  /* Eight INT8 products become eight INT16 elements in the m2 v10 group. */
  vsetivli zero, 8, e8, m1, ta, ma
  vwmul.vv v10, v8, v9

  /* Widening reduction accumulates INT16 products into one INT32 element. */
  vsetivli zero, 8, e16, m2, ta, ma
  vmv.v.i v12, 0
  vwredsum.vs v14, v10, v12
  ret

