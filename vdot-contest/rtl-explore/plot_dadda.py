#!/usr/bin/env python3
"""Draw the column heights of the fused vdot bit matrix after every Dadda level.

Output: dadda_levels.svg (pure SVG, no plotting library needed). The data comes
from the same generator that produced the verified netlists.
"""

from __future__ import annotations

from pathlib import Path

import gen_vdot_variants as g

CUT = 7


def heights() -> list[tuple[str, list[int]]]:
    net = g.Netlist()
    cols = g.bw_matrix(net)
    rows = [("partial products", [len(c) for c in cols])]
    for i, t in enumerate(g.dadda_levels(cols), 1):
        cols = g.dadda_step(net, cols, t)
        rows.append((f"level {i} (≤{t})", [len(c) for c in cols]))
    return rows


def main() -> None:
    rows = heights()
    cw, rh, left, top = 34, 46, 150, 40
    width = left + cw * g.W + 20
    height = top + rh * len(rows) + 50
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
           f'font-family="Helvetica, Arial, sans-serif" font-size="12">',
           f'<rect width="{width}" height="{height}" fill="#ffffff"/>',
           f'<text x="{left}" y="22" font-size="14" font-weight="bold">'
           f'Fused 8-lane Baugh-Wooley matrix: bits per column after each Dadda level</text>']
    for r, (label, hs) in enumerate(rows):
        y = top + r * rh
        stage = "stage 1" if r <= CUT else "stage 2"
        out.append(f'<text x="8" y="{y + rh / 2 + 4}" fill="#333">{label}</text>')
        for c, h in enumerate(hs):
            x = left + (g.W - 1 - c) * cw          # MSB on the left, like a number
            bar = (rh - 14) * h / 64
            color = "#3b6fb6" if stage == "stage 1" else "#d9822b"
            if h:
                out.append(f'<rect x="{x + 3}" y="{y + rh - 8 - bar:.1f}" width="{cw - 6}" height="{bar:.1f}" fill="{color}"/>')
            out.append(f'<text x="{x + cw / 2}" y="{y + rh - 10 - bar:.1f}" text-anchor="middle" fill="#222" font-size="10">{h if h else ""}</text>')
        if r == CUT:
            out.append(f'<line x1="{left - 140}" x2="{width - 10}" y1="{y + rh}" y2="{y + rh}" stroke="#c0392b" stroke-width="2" stroke-dasharray="6 4"/>')
            out.append(f'<text x="{width - 12}" y="{y + rh + 14}" text-anchor="end" fill="#c0392b">'
                       f'pipeline register (99 bits): stage 1 above, stage 2 below</text>')
    yb = top + rh * len(rows) + 16
    for c in range(g.W):
        x = left + (g.W - 1 - c) * cw + cw / 2
        out.append(f'<text x="{x}" y="{yb}" text-anchor="middle" fill="#555" font-size="10">{c}</text>')
    out.append(f'<text x="{left + cw * g.W / 2}" y="{yb + 18}" text-anchor="middle" fill="#555">column (bit weight 2^c)</text>')
    out.append("</svg>")
    path = Path(__file__).with_name("dadda_levels.svg")
    path.write_text("\n".join(out), encoding="utf-8")
    print("wrote", path)


if __name__ == "__main__":
    main()
