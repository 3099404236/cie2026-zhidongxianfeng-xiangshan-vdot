"""Executable architectural model for the CIE 2026 ``vdot.vv`` extension.

Also models the project's accumulating variant ``vdota.vv`` (funct6 = 001110):
``vd[31:0] = vd_old[31:0] + dot`` (int32 wrap-around), ``vd[127:32] = 0``.
"""

from __future__ import annotations

from collections.abc import Iterable

SEW = 8
VLEN = 128
DOT_ELEMENTS = 8

OPCODE_OP_V = 0x57
FUNCT3_OPMVV = 0b010
FUNCT6_VDOT = 0b001101
FUNCT6_VDOTA = 0b001110
VM_UNMASKED = 1

VDOT_MATCH = (FUNCT6_VDOT << 26) | (VM_UNMASKED << 25) | (FUNCT3_OPMVV << 12) | OPCODE_OP_V
VDOTA_MATCH = (FUNCT6_VDOTA << 26) | (VM_UNMASKED << 25) | (FUNCT3_OPMVV << 12) | OPCODE_OP_V
VDOT_MASK = 0xFE00707F


def signed_int8(value: int) -> int:
    """Interpret the low eight bits of *value* as a signed two's-complement byte."""

    value &= 0xFF
    return value - 0x100 if value & 0x80 else value


def vdot_values(vs1: Iterable[int], vs2: Iterable[int]) -> int:
    """Return the mathematical dot product of exactly eight signed INT8 values."""

    lhs = list(vs1)
    rhs = list(vs2)
    if len(lhs) != DOT_ELEMENTS or len(rhs) != DOT_ELEMENTS:
        raise ValueError(f"vdot.vv requires exactly {DOT_ELEMENTS} elements per source")
    return sum(signed_int8(a) * signed_int8(b) for a, b in zip(lhs, rhs, strict=True))


def unpack_low_bytes(vector: int) -> list[int]:
    """Extract the eight architecturally consumed low bytes from a 128-bit vector."""

    if vector < 0 or vector >= 1 << VLEN:
        raise ValueError("vector value must fit in 128 bits")
    return [signed_int8(vector >> (8 * index)) for index in range(DOT_ELEMENTS)]


def execute_vdot(vs1: int, vs2: int) -> int:
    """Execute vdot.vv and return the complete 128-bit destination register value.

    Bits 31:0 contain the signed two's-complement sum. Bits 127:32 are zero.
    """

    result = vdot_values(unpack_low_bytes(vs1), unpack_low_bytes(vs2))
    return result & 0xFFFFFFFF


def encode_vdot(vd: int, vs1: int, vs2: int) -> int:
    """Encode ``vdot.vv vd, vs1, vs2`` as one 32-bit OP-V instruction."""

    for name, register in (("vd", vd), ("vs1", vs1), ("vs2", vs2)):
        if not 0 <= register < 32:
            raise ValueError(f"{name} must be a vector register index in [0, 31]")
    return VDOT_MATCH | (vs2 << 20) | (vs1 << 15) | (vd << 7)


def is_vdot_instruction(instruction: int) -> bool:
    """Return whether a 32-bit word matches the custom vdot.vv encoding."""

    return instruction & VDOT_MASK == VDOT_MATCH


def execute_vdota(vd: int, vs1: int, vs2: int) -> int:
    """Execute vdota.vv: accumulate the dot product into vd[31:0] (int32 wrap).

    Only vd[31:0] of the old destination is read; the new vd[127:32] is zero.
    """

    if vd < 0 or vd >= 1 << VLEN:
        raise ValueError("vector value must fit in 128 bits")
    return ((vd & 0xFFFFFFFF) + vdot_values(unpack_low_bytes(vs1), unpack_low_bytes(vs2))) & 0xFFFFFFFF


def encode_vdota(vd: int, vs1: int, vs2: int) -> int:
    """Encode ``vdota.vv vd, vs1, vs2``."""

    return (encode_vdot(vd, vs1, vs2) & ~VDOT_MATCH) | VDOTA_MATCH


def is_vdota_instruction(instruction: int) -> bool:
    """Return whether a 32-bit word matches the vdota.vv encoding."""

    return instruction & VDOT_MASK == VDOTA_MATCH

