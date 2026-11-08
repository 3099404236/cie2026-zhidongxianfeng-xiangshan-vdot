#!/usr/bin/env python3
"""Design-space exploration for the VDot128 datapath (run inside WSL/Linux).

1. gen_vdot_variants.py emits every variant (top + per-stage modules).
2. One Verilator testbench streams >1.1M vectors through all variants at once.
3. Yosys 0.33 + ABC synthesizes every pipeline stage separately with two
   generic gate libraries and reports cells and the longest combinational
   path (ltp -noff), i.e. the real per-stage logic depth.

Results are written to results.md (and printed).
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GEN = HERE / "gen"
BUILD = HERE / "build"
# NOTE: Yosys' default ABC script (dc2/&dch/&nf + area recovery) re-ripples
# carry-lookahead adders: a plain 19-bit a+b maps to depth 36 instead of the
# depth-14 Brent-Kung structure Yosys emits. Depth is therefore measured with
# a delay-oriented script; area with the default (area-recovering) script.
DELAY = "-script +strash;dch;map,-D,1;topo"
LIBS = {
    # 2-input gates incl. XOR, unit delay per gate
    "gates": "abc -g AND,NAND,OR,NOR,XOR,XNOR",
    "gates_delay": f"abc -g AND,NAND,OR,NOR,XOR,XNOR {DELAY}",
    # NAND/NOR/AOI3/OAI3 only: an XOR costs 2-3 levels, closer to CMOS delay
    "cmos": "abc -g cmos3",
    "cmos_delay": f"abc -g cmos3 {DELAY}",
}


def sh(cmd: str, cwd: Path = HERE) -> str:
    res = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    if res.returncode != 0:
        sys.stderr.write(res.stdout[-4000:] + res.stderr[-4000:])
        raise SystemExit(f"command failed: {cmd}")
    return res.stdout


def variants() -> list[str]:
    return sorted(p.stem for p in GEN.glob("*.v") if p.stem not in ("tb_top",))


def write_tb(names: list[str]) -> None:
    lines = [
        "module tb_top (",
        "  input clock, input reset, input io_en,",
        "  input [127:0] io_vs1, input [127:0] io_vs2,",
    ]
    lines += [f"  output [127:0] r_{n}{',' if i + 1 < len(names) else ''}" for i, n in enumerate(names)]
    lines.append(");")
    for n in names:
        lines.append(f"  {n} u_{n} (.clock(clock), .reset(reset), .io_en(io_en), .io_vs1(io_vs1), "
                     f".io_vs2(io_vs2), .io_result(r_{n}));")
    lines.append("endmodule")
    (GEN / "tb_top.v").write_text("\n".join(lines) + "\n")

    hdr = ["#pragma once", f"#define NUM_VARIANTS {len(names)}",
           "static const char *VARIANT_NAMES[] = {" + ", ".join(f'"{n}"' for n in names) + "};",
           "static void read_variant(Vtb_top *t, int k, uint32_t &lo, bool &hi) {", "  switch (k) {"]
    for i, n in enumerate(names):
        hdr.append(f"  case {i}: lo = t->r_{n}[0]; hi = t->r_{n}[1] | t->r_{n}[2] | t->r_{n}[3]; break;")
    hdr += ["  default: lo = 0; hi = true;", "  }", "}"]
    (BUILD / "tb_ports.h").write_text("\n".join(hdr) + "\n")


def yosys_stats(vfile: Path, top: str, lib: str) -> tuple[int, int, int]:
    script = (f"read_verilog {vfile}; synth -flatten -noabc -top {top}; {LIBS[lib]}; opt_clean; "
              f"stat{' -tech cmos' if lib.startswith('cmos') else ''}; ltp -noff")
    out = sh(f"yosys -q -p '{script.replace(chr(39), '')}' -l /dev/stdout 2>&1 || true")
    cells = int(re.findall(r"Number of cells:\s+(\d+)", out)[-1])
    depth = int(re.findall(r"Longest topological path.*length=(\d+)", out)[-1])
    trans = re.findall(r"Estimated number of transistors:\s+(\d+)", out)
    return cells, depth, int(trans[-1]) if trans else 0


def main() -> None:
    BUILD.mkdir(exist_ok=True)
    print(sh(f"python3 {HERE / 'gen_vdot_variants.py'} -o {GEN}"))
    names = variants()
    write_tb(names)

    print("== Verilator equivalence run")
    srcs = " ".join(str(GEN / f"{n}.v") for n in names)
    sh(f"verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED --top-module tb_top "
       f"-CFLAGS -I{BUILD} -Mdir {BUILD}/obj {GEN / 'tb_top.v'} {srcs} {HERE / 'tb_variants.cpp'} -j 4")
    sim = sh(f"{BUILD}/obj/Vtb_top 1000000")
    print(sim)
    if "mismatches" not in sim or re.search(r" [1-9]\d* mismatches", sim):
        raise SystemExit("equivalence check FAILED")

    rows = []
    for n in names:
        vf = GEN / f"{n}.v"
        r = {"name": n}
        # area: whole module incl. flip-flops, area-recovering ABC script
        r["cells_g"], _, _ = yosys_stats(vf, n, "gates")
        r["cells_c"], _, r["trans"] = yosys_stats(vf, n, "cmos")
        # delay: each pipeline stage separately, delay-oriented ABC script
        for st in ("s1", "s2"):
            _, r[f"{st}_d_g"], _ = yosys_stats(vf, f"{n}_{st}", "gates_delay")
            _, r[f"{st}_d_c"], _ = yosys_stats(vf, f"{n}_{st}", "cmos_delay")
        cut = re.findall(r"output \[(\d+):0\] cut", vf.read_text())
        r["cutbits"] = int(cut[0]) + 1 if cut else 36  # v1_cpa: two 18-bit sums
        r["crit_c"] = max(r["s1_d_c"], r["s2_d_c"])
        r["crit_g"] = max(r["s1_d_g"], r["s2_d_g"])
        rows.append(r)
        print(r)

    md = ["| variant | stage-1 FFs | cells (gates) | transistors (cmos3) | S1 depth gates | S2 depth gates |"
          " S1 depth cmos3 | S2 depth cmos3 | critical stage cmos3 |",
          "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for r in rows:
        md.append(f"| {r['name']} | {r['cutbits']} | {r['cells_g']} | {r['trans']} | {r['s1_d_g']} | "
                  f"{r['s2_d_g']} | {r['s1_d_c']} | {r['s2_d_c']} | **{r['crit_c']}** |")
    text = "\n".join(md)
    (HERE / "results.md").write_text(
        "# VDot128 datapath exploration (Yosys 0.33 + ABC, generic gates)\n\n"
        "* Area: whole module (incl. flip-flops), `synth -noabc` + `abc -g <lib>` default script;\n"
        "  transistors from `stat -tech cmos` (flip-flops are not counted by -tech cmos).\n"
        "* Depth: each pipeline stage synthesized alone with a delay-oriented ABC script\n"
        "  (`strash; dch; map -D 1; topo`), longest combinational path from `ltp -noff`.\n"
        "  The default ABC script is NOT used for depth: it re-ripples carry-lookahead adders\n"
        "  (a 19-bit a+b becomes depth 36 instead of 14).\n"
        "* Equivalence: every variant matched the C++ reference on all streamed vectors:\n\n"
        f"```\n{sim.strip()}\n```\n\n{text}\n")
    print(text)


if __name__ == "__main__":
    main()
