import random
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reference"))

from vdot_model import (  # noqa: E402
    VDOT_MATCH,
    VDOTA_MATCH,
    encode_vdot,
    encode_vdota,
    execute_vdot,
    execute_vdota,
    is_vdot_instruction,
    is_vdota_instruction,
    signed_int8,
    vdot_values,
)


def pack(values, high=0):
    value = high << 64
    for index, item in enumerate(values):
        value |= (item & 0xFF) << (8 * index)
    return value


class VDotModelTests(unittest.TestCase):
    def test_positive_values(self):
        lhs = [1, 2, 3, 4, 5, 6, 7, 8]
        rhs = [8, 7, 6, 5, 4, 3, 2, 1]
        self.assertEqual(vdot_values(lhs, rhs), 120)
        self.assertEqual(execute_vdot(pack(lhs), pack(rhs)), 120)

    def test_negative_result_is_encoded_in_low_32_bits(self):
        lhs = [-1, -2, -3, -4, -5, -6, -7, -8]
        rhs = [1, 2, 3, 4, 5, 6, 7, 8]
        expected = sum(a * b for a, b in zip(lhs, rhs, strict=True))
        self.assertLess(expected, 0)
        self.assertEqual(execute_vdot(pack(lhs), pack(rhs)), expected & 0xFFFFFFFF)

    def test_signed_boundaries_do_not_overflow(self):
        self.assertEqual(vdot_values([-128] * 8, [-128] * 8), 131072)
        self.assertEqual(vdot_values([127] * 8, [127] * 8), 129032)
        self.assertEqual(vdot_values([-128] * 8, [127] * 8), -130048)

    def test_zero_and_mixed_boundaries(self):
        lhs = [-128, 127, 0, 1, -1, 64, -64, 0]
        rhs = [127, -128, 5, -1, 1, -64, 64, 0]
        expected = sum(a * b for a, b in zip(lhs, rhs, strict=True))
        self.assertEqual(execute_vdot(pack(lhs), pack(rhs)), expected & 0xFFFFFFFF)

    def test_upper_half_of_sources_is_ignored(self):
        low_lhs = [1] * 8
        low_rhs = [2] * 8
        baseline = execute_vdot(pack(low_lhs), pack(low_rhs))
        self.assertEqual(execute_vdot(pack(low_lhs, 0xFFFFFFFFFFFFFFFF), pack(low_rhs, 0x0123456789ABCDEF)), baseline)

    def test_result_upper_96_bits_are_zero(self):
        result = execute_vdot(pack([-128] * 8), pack([127] * 8))
        self.assertEqual(result >> 32, 0)

    def test_byte_sign_extension(self):
        self.assertEqual(signed_int8(0x00), 0)
        self.assertEqual(signed_int8(0x7F), 127)
        self.assertEqual(signed_int8(0x80), -128)
        self.assertEqual(signed_int8(0xFF), -1)

    def test_encoding_round_trip_and_reserved_fields(self):
        word = encode_vdot(vd=10, vs1=8, vs2=9)
        self.assertEqual(word, VDOT_MATCH | (9 << 20) | (8 << 15) | (10 << 7))
        self.assertTrue(is_vdot_instruction(word))
        self.assertFalse(is_vdot_instruction(word ^ (1 << 26)))
        self.assertFalse(is_vdot_instruction(word ^ (1 << 25)))

    def test_random_vectors_match_python_reference(self):
        randomizer = random.Random(0x2026)
        for _ in range(10_000):
            lhs = [randomizer.randint(-128, 127) for _ in range(8)]
            rhs = [randomizer.randint(-128, 127) for _ in range(8)]
            expected = sum(a * b for a, b in zip(lhs, rhs, strict=True)) & 0xFFFFFFFF
            self.assertEqual(execute_vdot(pack(lhs), pack(rhs)), expected)

    def test_rejects_invalid_operand_lengths_and_registers(self):
        with self.assertRaises(ValueError):
            vdot_values([1] * 7, [2] * 8)
        with self.assertRaises(ValueError):
            encode_vdot(32, 1, 2)

    # ---- vdota.vv: accumulating variant --------------------------------
    def test_vdota_with_zero_accumulator_equals_vdot(self):
        lhs, rhs = pack([-1, -2, -3, -4, -5, -6, -7, -8]), pack([1, 2, 3, 4, 5, 6, 7, 8])
        self.assertEqual(execute_vdota(0, lhs, rhs), execute_vdot(lhs, rhs))

    def test_vdota_accumulates_and_reads_only_vd_low_32_bits(self):
        lhs, rhs = pack([1, 2, 3, 4, 5, 6, 7, 8]), pack([8, 7, 6, 5, 4, 3, 2, 1])
        old_vd = (0xDEADBEEF_DEADBEEF_DEADBEEF << 32) | 1000
        self.assertEqual(execute_vdota(old_vd, lhs, rhs), 1120)

    def test_vdota_wraps_like_int32(self):
        lhs, rhs = pack([1, 2, 3, 4, 5, 6, 7, 8]), pack([8, 7, 6, 5, 4, 3, 2, 1])
        self.assertEqual(execute_vdota(0x7FFFFFFF, lhs, rhs), 0x80000077)
        neg = pack([-128] * 8), pack([127] * 8)
        self.assertEqual(execute_vdota(0x80000000, *neg), (0x80000000 - 130048) & 0xFFFFFFFF)

    def test_vdota_chain_equals_long_dot_product(self):
        randomizer = random.Random(7)
        acc, total = 0, 0
        for _ in range(64):
            lhs = [randomizer.randint(-128, 127) for _ in range(8)]
            rhs = [randomizer.randint(-128, 127) for _ in range(8)]
            acc = execute_vdota(acc, pack(lhs, randomizer.getrandbits(64)), pack(rhs, randomizer.getrandbits(64)))
            total += sum(a * b for a, b in zip(lhs, rhs, strict=True))
        self.assertEqual(acc, total & 0xFFFFFFFF)

    def test_vdota_encoding(self):
        word = encode_vdota(vd=10, vs1=8, vs2=9)
        self.assertEqual(word, 0x3A942557)
        self.assertTrue(is_vdota_instruction(word))
        self.assertFalse(is_vdot_instruction(word))
        self.assertFalse(is_vdota_instruction(encode_vdot(10, 8, 9)))
        self.assertEqual(VDOTA_MATCH ^ VDOT_MATCH, (0b001110 ^ 0b001101) << 26)


if __name__ == "__main__":
    unittest.main()
