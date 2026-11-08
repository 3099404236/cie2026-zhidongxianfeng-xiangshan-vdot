/* Shared assembler helpers for the CIE 2026 vdot.vv tests.
 *
 * Binutils does not know the custom instruction, so it is emitted as a raw
 * 32-bit word:
 *
 *   31      26 25 24  20 19  15 14 12 11   7 6      0
 *   | 001101 | 1 | vs2 | vs1 | 010 |  vd  | 1010111 |
 *
 * Operand order follows the project convention `vdot.vv vd, vs1, vs2`
 * (the operation is commutative, so the order never changes the result).
 * Example: VDOT_VV 10, 8, 9  ==  0x36942557  ==  vdot.vv v10, v8, v9
 */
#ifndef VDOT_MACROS_H
#define VDOT_MACROS_H

#define VDOT_FUNCT6 0x0d

.macro VDOT_VV vd, vs1, vs2
  .word (VDOT_FUNCT6 << 26) | (1 << 25) | ((\vs2) << 20) | ((\vs1) << 15) | (0x2 << 12) | ((\vd) << 7) | 0x57
.endm

/* Same encoding with vm=0. It must NOT decode as vdot.vv (illegal). */
.macro VDOT_VV_MASKED vd, vs1, vs2
  .word (VDOT_FUNCT6 << 26) | (0 << 25) | ((\vs2) << 20) | ((\vs1) << 15) | (0x2 << 12) | ((\vd) << 7) | 0x57
.endm

/* Accumulating variant: vd[31:0] += dot(vs1, vs2), vd[127:32] = 0.
 * VDOTA_VV 10, 8, 9  ==  0x3A942557  ==  vdota.vv v10, v8, v9 */
#define VDOTA_FUNCT6 0x0e

.macro VDOTA_VV vd, vs1, vs2
  .word (VDOTA_FUNCT6 << 26) | (1 << 25) | ((\vs2) << 20) | ((\vs1) << 15) | (0x2 << 12) | ((\vd) << 7) | 0x57
.endm

.macro VDOTA_VV_MASKED vd, vs1, vs2
  .word (VDOTA_FUNCT6 << 26) | (0 << 25) | ((\vs2) << 20) | ((\vs1) << 15) | (0x2 << 12) | ((\vd) << 7) | 0x57
.endm

/* nemu_trap / XiangShan trap: a0 == 0 is HIT GOOD TRAP. */
.macro GOOD_TRAP
  li a0, 0
  .word 0x0000006b
.endm

.macro BAD_TRAP code
  li a0, \code
  .word 0x0000006b
.endm

#endif
