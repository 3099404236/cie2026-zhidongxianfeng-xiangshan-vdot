#!/usr/bin/env python3
"""Follow one instruction through the XiangShan pipeline in an emu FST dump.

  trace_timeline.py wave.fst --instr 0x36942557 [--fu Vimac] [--fstdump PATH]

The emu dumps once per cycle (right after the rising edge), so FST time equals
the cycle number. The script locates, by instruction encoding and robIdx:

  decode   DecodeStage io_out_<k>_valid && io_out_<k>_bits_instr == INSTR
  rename   Rename      io_out_<k>_valid && io_out_<k>_bits_instr == INSTR
  fu in    <fu>.io_in_valid (first cycle after rename with the expected fuOpType)
  fu out   <fu>.io_out_valid (first cycle after fu in), with res_data
  commit   DummyDPICWrapper_InstrCommit io_valid && io_bits_instr == INSTR

and prints a markdown table, plus the raw per-cycle values of every signal
whose name contains one of the --show substrings around the FU window.
"""

from __future__ import annotations

import argparse
import collections
import re
import subprocess

DEFAULT_FSTDUMP = "/root/codex-work/vdot-build/bin/fstdump"


def dump(fstdump: str, wave: str, patterns: list[str]) -> dict[str, list[tuple[int, str]]]:
    out = subprocess.run([fstdump, wave, *patterns], capture_output=True, text=True, check=True).stdout
    changes: dict[str, list[tuple[int, str]]] = collections.defaultdict(list)
    for line in out.splitlines():
        parts = line.split(" ")
        # "<time> <name>[ [hi:lo]] <value>" -- vector names carry a bit range
        t, val = parts[0], parts[-1]
        name = re.sub(r" \[\d+:\d+\]$", "", " ".join(parts[1:-1]))
        changes[name].append((int(t), val))
    return changes


def value_at(ch: list[tuple[int, str]], t: int) -> int | None:
    v = None
    for tt, vv in ch:
        if tt > t:
            break
        v = vv
    if v is None or any(c in v for c in "xzXZ"):
        return None
    return int(v, 2)


def times(ch_all: dict[str, list[tuple[int, str]]]) -> list[int]:
    return sorted({t for ch in ch_all.values() for t, _ in ch})


def find_stage(ch: dict, prefix_re: str, instr: int, t_min: int = 0) -> tuple[int, str] | None:
    """First cycle >= t_min where some <prefix>_<k>_valid is 1 and its instr matches."""
    slots = collections.defaultdict(dict)
    for name in ch:
        m = re.search(prefix_re + r"_(\d+)_(valid|bits_instr)$", name)
        if m:
            slots[(name[: m.start()], m.group(1))][m.group(2)] = name
    hits = []
    for (scope, k), sig in slots.items():
        if "valid" not in sig or "bits_instr" not in sig:
            continue
        hit = first_match(ch[sig["valid"]], ch[sig["bits_instr"]], instr, t_min)
        if hit is not None:
            hits.append((hit, f"{scope}{k}"))
    return min(hits) if hits else None


def first_match(valid: list[tuple[int, str]], data: list[tuple[int, str]], want: int, t_min: int = 0) -> int | None:
    """First time >= t_min at which valid == 1 and data == want (either may change)."""
    for t in sorted({t for t, _ in valid} | {t for t, _ in data}):
        if t >= t_min and value_at(valid, t) == 1 and value_at(data, t) == want:
            return t
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("wave")
    ap.add_argument("--instr", required=True, type=lambda s: int(s, 0))
    ap.add_argument("--fu", default="Vimac", help="FU instance name substring (Vimac, VialuFix)")
    ap.add_argument("--fstdump", default=DEFAULT_FSTDUMP)
    ap.add_argument("--show", nargs="*", default=[])
    a = ap.parse_args()

    pats = [".decode.io_out_", ".rename.io_out_", "endpoint.commit", f".{a.fu}.io_in_", f".{a.fu}.io_out_"] + a.show
    ch = dump(a.fstdump, a.wave, pats)

    dec = find_stage(ch, r"\.decode\.io_out", a.instr)
    ren = find_stage(ch, r"\.rename\.io_out", a.instr, dec[0] if dec else 0)
    com = find_stage_commit(ch, a.instr)
    fu_in = fu_out = None
    fu_valid_in = [n for n in ch if n.endswith(f".{a.fu}.io_in_valid")]
    fu_valid_out = [n for n in ch if n.endswith(f".{a.fu}.io_out_valid")]
    t0 = ren[0] if ren else (dec[0] if dec else 0)
    for n in fu_valid_in:
        for t, v in ch[n]:
            if t > t0 and v == "1" and (com is None or t < com[0]):
                if fu_in is None or t < fu_in[0]:
                    fu_in = (t, n.rsplit(".io_in_valid", 1)[0])
                break
    if fu_in:
        for n in fu_valid_out:
            if not n.startswith(fu_in[1]):
                continue
            for t, v in ch[n]:
                if t >= fu_in[0] and v == "1":
                    fu_out = (t, n.rsplit(".io_out_valid", 1)[0])
                    break

    print(f"| stage | cycle | where |\n|---|---:|---|")
    for label, hit in (("decode out", dec), ("rename out", ren), ("FU in (issue)", fu_in),
                       ("FU out (write-back)", fu_out), ("commit", com)):
        print(f"| {label} | {hit[0] if hit else '-'} | `{hit[1].split('.')[-1] if hit else '-'}` |")

    if fu_in:
        base = fu_in[1]
        lo, hi = fu_in[0] - 1, (fu_out[0] if fu_out else fu_in[0] + 3) + 1
        sigs = [n for n in sorted(ch) if n.startswith(base + ".") and
                re.search(r"io_in_valid$|fuOpType$|src_0$|src_1$|io_out_valid$|res_data$", n)]
        sigs += [n for n in sorted(ch) if any(s in n for s in a.show)]
        print("\n| signal | " + " | ".join(f"cycle {t}" for t in range(lo, hi + 1)) + " |")
        print("|---|" + "---:|" * (hi - lo + 1))
        for n in sigs:
            vals = []
            for t in range(lo, hi + 1):
                v = value_at(ch[n], t)
                vals.append("x" if v is None else (hex(v) if v > 1 else str(v)))
            print(f"| `{n.split(base + '.')[-1] if n.startswith(base) else n.split('.')[-1]}` | " + " | ".join(vals) + " |")


def find_stage_commit(ch: dict, instr: int) -> tuple[int, str] | None:
    hits = []
    valids = [n for n in ch if re.search(r"commit(_\d+)?\.io_bits_valid$", n)]
    for vn in valids:
        inn = vn.replace(".io_bits_valid", ".io_bits_instr")
        if inn not in ch:
            continue
        hit = first_match(ch[vn], ch[inn], instr)
        if hit is not None:
            hits.append((hit, vn.rsplit(".io_bits_valid", 1)[0]))
    return min(hits) if hits else None


if __name__ == "__main__":
    main()
