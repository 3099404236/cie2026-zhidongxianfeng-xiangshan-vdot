#!/usr/bin/env python3
"""Emit synthesizable Verilog for several vdot.vv datapath variants.

Every variant computes  sum_{k<8} sext(a_k) * sext(b_k)  (a_k, b_k = signed
bytes of vs1/vs2[63:0]) as a 19-bit two's-complement value, sign-extended to
vd[31:0], vd[127:32] = 0, with the same 2-cycle register structure as the
XiangShan VDot128 module (stage-1 register, stage-2 register).

For per-stage timing each variant is also emitted as two purely combinational
modules <name>_s1 (inputs -> cut) and <name>_s2 (cut -> 19-bit sum).

  v1_cpa    8 multipliers + adder tree, cut after the 4->2 sums (old version)
  v2_csa    8 multipliers + word-level 3:2 CSA tree (current submission)
  v3_dadda  fused bit-level design: modified Baugh-Wooley partial products of
            all 8 lanes form ONE bit matrix (512 bits + 2 constant bits) that a
            single Dadda tree reduces to 2 rows; pipeline cut inside the tree;
            one 19-bit carry-propagate adder at the very end.
"""

from __future__ import annotations

import argparse
from pathlib import Path

W = 19          # result width: |sum| <= 131072 < 2^18, so 19 bits suffice
LANES = 8
EW = 8          # element width (SEW = 8)

# --------------------------------------------------------------------------
# helpers shared by all variants


def header(name: str, ports: str) -> list[str]:
    return [f"module {name} (", ports, ");"]


TOP_PORTS = """  input          clock,
  input          reset,
  input          io_en,
  input  [127:0] io_vs1,
  input  [127:0] io_vs2,
  output [127:0] io_result"""


# --------------------------------------------------------------------------
# v1 / v2: word-level designs (same as the previous hand-written Verilog)


def word_products() -> list[str]:
    lines = []
    for i in range(LANES):
        lines.append(f"  wire signed [7:0] a{i} = io_vs1[{8*i+7}:{8*i}];")
        lines.append(f"  wire signed [7:0] b{i} = io_vs2[{8*i+7}:{8*i}];")
        lines.append(f"  wire signed [15:0] p{i} = a{i} * b{i};")
    return lines


def v1_stage1(name: str) -> list[str]:
    out = header(name, "  input [127:0] io_vs1,\n  input [127:0] io_vs2,\n  output [17:0] q0,\n  output [17:0] q1")
    out += word_products()
    out += [
        "  wire signed [16:0] s0 = p0 + p1;",
        "  wire signed [16:0] s1 = p2 + p3;",
        "  wire signed [16:0] s2 = p4 + p5;",
        "  wire signed [16:0] s3 = p6 + p7;",
        "  wire signed [17:0] t0 = s0 + s1;",
        "  wire signed [17:0] t1 = s2 + s3;",
        "  assign q0 = t0;",
        "  assign q1 = t1;",
        "endmodule",
    ]
    return out


def v1_stage2(name: str) -> list[str]:
    out = header(name, "  input [17:0] q0,\n  input [17:0] q1,\n  output [18:0] sum")
    out += ["  assign sum = $signed(q0) + $signed(q1);", "endmodule"]
    return out


def csa(a: str, b: str, c: str, s: str, k: str) -> list[str]:
    return [
        f"  wire [18:0] {s} = {a} ^ {b} ^ {c};",
        f"  wire [18:0] {s}_m = ({a} & {b}) | ({b} & {c}) | ({a} & {c});",
        f"  wire [18:0] {k} = {{{s}_m[17:0], 1'b0}};",
    ]


def v2_stage1(name: str) -> list[str]:
    out = header(name, "  input [127:0] io_vs1,\n  input [127:0] io_vs2,\n  output [75:0] cut")
    out += word_products()
    out += [f"  wire [18:0] e{i} = {{{{3{{p{i}[15]}}}}, p{i}}};" for i in range(LANES)]
    out += csa("e0", "e1", "e2", "s10", "c10")
    out += csa("e3", "e4", "e5", "s11", "c11")
    out += csa("s10", "c10", "s11", "s20", "c20")
    out += csa("c11", "e6", "e7", "s21", "c21")
    out += ["  assign cut = {c21, s21, c20, s20};", "endmodule"]
    return out


def v2_stage2(name: str) -> list[str]:
    out = header(name, "  input [75:0] cut,\n  output [18:0] sum")
    out += [
        "  wire [18:0] r0 = cut[18:0];",
        "  wire [18:0] r1 = cut[37:19];",
        "  wire [18:0] r2 = cut[56:38];",
        "  wire [18:0] r3 = cut[75:57];",
    ]
    out += csa("r0", "r1", "r2", "s30", "c30")
    out += csa("s30", "c30", "r3", "s40", "c40")
    out += ["  assign sum = s40 + c40;", "endmodule"]
    return out


# --------------------------------------------------------------------------
# v3: fused Baugh-Wooley + Dadda tree


class Netlist:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.n = 0

    def wire(self, expr: str) -> str:
        self.n += 1
        name = f"n{self.n}"
        self.lines.append(f"  wire {name} = {expr};")
        return name


def bw_matrix(net: Netlist) -> list[list[str]]:
    """Modified Baugh-Wooley partial products for all lanes in one matrix.

    p = sum_{i,j<7} a_i b_j 2^(i+j) + a7 b7 2^14
        + sum_{j<7} ~(a7 b_j) 2^(7+j) + sum_{i<7} ~(a_i b7) 2^(7+i) + (2^8 - 2^15)
    Eight lanes share one constant: 8*(2^8 - 2^15) = 2^11 + 2^18 (mod 2^19).
    """
    cols: list[list[str]] = [[] for _ in range(W)]
    for k in range(LANES):
        for i in range(EW):
            for j in range(EW):
                a = f"io_vs1[{8*k+i}]"
                b = f"io_vs2[{8*k+j}]"
                inverted = (i == EW - 1) != (j == EW - 1)
                expr = f"~({a} & {b})" if inverted else f"({a} & {b})"
                cols[i + j].append(net.wire(expr))
    cols[11].append("1'b1")
    cols[18].append("1'b1")
    return cols


def dadda_targets(max_height: int) -> list[int]:
    seq = [2]
    while seq[-1] < max_height:
        seq.append(seq[-1] * 3 // 2)
    return [d for d in reversed(seq) if d < max_height]


def fa(net: Netlist, a: str, b: str, c: str) -> tuple[str, str]:
    x = net.wire(f"{a} ^ {b}")
    s = net.wire(f"{x} ^ {c}")
    co = net.wire(f"({a} & {b}) | ({c} & {x})")
    return s, co


def ha(net: Netlist, a: str, b: str) -> tuple[str, str]:
    return net.wire(f"{a} ^ {b}"), net.wire(f"{a} & {b}")


def dadda_step(net: Netlist, cols: list[list[str]], target: int) -> list[list[str]]:
    """One Dadda level: reduce every column to <= target bits (mod 2^W)."""
    new: list[list[str]] = [[] for _ in range(W)]
    for c in range(W):
        bits = list(cols[c])
        while len(bits) + len(new[c]) > target:
            excess = len(bits) + len(new[c]) - target
            if excess >= 2 and len(bits) >= 3:
                s, co = fa(net, bits.pop(), bits.pop(), bits.pop())
            elif len(bits) >= 2:
                s, co = ha(net, bits.pop(), bits.pop())
            else:
                break
            new[c].append(s)
            if c + 1 < W:
                new[c + 1].append(co)
        new[c].extend(bits)
        assert len(new[c]) <= target, f"column {c} has {len(new[c])} > {target} bits"
    return new


def dadda_levels(cols: list[list[str]]) -> list[int]:
    return dadda_targets(max(len(c) for c in cols))


def v3_build(cut_after: int) -> tuple[list[str], list[str], int, int]:
    """Return (stage1 module body, stage2 module body, cut bits, levels)."""
    net1 = Netlist()
    cols = bw_matrix(net1)
    targets = dadda_levels(cols)
    for t in targets[:cut_after]:
        cols = dadda_step(net1, cols, t)
    flat = [(c, b) for c in range(W) for b in cols[c]]
    s1 = list(net1.lines)
    s1.append(f"  assign cut = {{{', '.join(b for _, b in reversed(flat))}}};")

    net2 = Netlist()
    net2.n = 10 ** 6  # disjoint names
    cols2: list[list[str]] = [[] for _ in range(W)]
    for idx, (c, _) in enumerate(flat):
        cols2[c].append(f"cut[{idx}]")
    for t in targets[cut_after:]:
        cols2 = dadda_step(net2, cols2, t)
    rows = [["1'b0"] * W, ["1'b0"] * W]
    for c in range(W):
        assert len(cols2[c]) <= 2, (c, len(cols2[c]))
        for r, b in enumerate(cols2[c]):
            rows[r][c] = b
    s2 = list(net2.lines)
    s2.append(f"  wire [18:0] r0 = {{{', '.join(reversed(rows[0]))}}};")
    s2.append(f"  wire [18:0] r1 = {{{', '.join(reversed(rows[1]))}}};")
    s2.append("  assign sum = r0 + r1;")
    return s1, s2, len(flat), len(targets)


# --------------------------------------------------------------------------


def top(name: str, cut_w: int) -> list[str]:
    return header(name, TOP_PORTS) + [
        f"  wire [{cut_w-1}:0] cut_d;",
        "  wire [18:0] sum_d;",
        f"  reg  [{cut_w-1}:0] cut_q;",
        "  reg  [18:0] sum_q;",
        "  reg         v1;",
        f"  {name}_s1 u_s1 (.io_vs1(io_vs1), .io_vs2(io_vs2), {'.q0(cut_d[17:0]), .q1(cut_d[35:18])' if name == 'v1_cpa' else '.cut(cut_d)'});",
        f"  {name}_s2 u_s2 ({'.q0(cut_q[17:0]), .q1(cut_q[35:18])' if name == 'v1_cpa' else '.cut(cut_q)'}, .sum(sum_d));",
        "  always @(posedge clock) begin",
        "    if (reset) v1 <= 1'b0; else v1 <= io_en;",
        "    if (io_en) cut_q <= cut_d;",
        "    if (v1) sum_q <= sum_d;",
        "  end",
        "  assign io_result = {96'd0, {13{sum_q[18]}}, sum_q};",
        "endmodule",
    ]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--outdir", default=str(Path(__file__).parent / "gen"))
    args = ap.parse_args()
    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    designs: dict[str, list[str]] = {}
    designs["v1_cpa"] = v1_stage1("v1_cpa_s1") + v1_stage2("v1_cpa_s2") + top("v1_cpa", 36)
    designs["v2_csa"] = v2_stage1("v2_csa_s1") + v2_stage2("v2_csa_s2") + top("v2_csa", 76)

    probe_targets = dadda_levels(bw_matrix(Netlist()))
    info = []
    for cut in range(3, len(probe_targets)):
        s1, s2, cut_w, levels = v3_build(cut)
        name = f"v3_dadda_c{cut}"
        body = header(f"{name}_s1", f"  input [127:0] io_vs1,\n  input [127:0] io_vs2,\n  output [{cut_w-1}:0] cut")
        body += s1 + ["endmodule"]
        body += header(f"{name}_s2", f"  input [{cut_w-1}:0] cut,\n  output [18:0] sum") + s2 + ["endmodule"]
        body += top(name, cut_w)
        designs[name] = body
        info.append((name, cut, levels, cut_w))

    for name, lines in designs.items():
        (out / f"{name}.v").write_text("\n".join(lines) + "\n", encoding="ascii")
    print("dadda targets:", probe_targets)
    for name, cut, levels, cut_w in info:
        print(f"{name}: cut after {cut}/{levels} Dadda levels, {cut_w} pipeline bits")
    print("wrote", ", ".join(designs))


if __name__ == "__main__":
    main()
