#!/usr/bin/env python3
"""Synthesis-level timing and area of VDot128 in real standard-cell libraries.

Every design is synthesised with Yosys and mapped with ABC onto a real Liberty
library (NanGate 45 nm Open Cell Library, ASAP7 7 nm predictive PDK), then
timed with ABC's static timing (`stime`, NLDM tables, fanout loads, no wires).

Pipeline segments are timed one at a time: all flip-flops are turned into
ports (`expose -evert-dff`), the outputs that do not belong to the segment are
dropped and only the logic cone of the segment's register D pins is mapped.
  S1  : module inputs      -> stage-1 registers
  S2  : stage-1 registers  -> stage-2 registers
  out : stage-2 registers  -> module outputs (continues into the FU's result mux)
Area is taken from a separate mapping of the whole module, flip-flops included.

The XiangShan multiplier VIMac64b (two of them sit next to VDot128 inside
VIMacU and already meet the core's timing) is put through the same flow; it is
the budget VDot128 has to stay within.

  python3 pdk_ppa.py [--pdk DIR] [--rtl DIR] [--out results_pdk.md] [--jobs N]
"""
import argparse
import concurrent.futures as cf
import fnmatch
import gzip
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

VB = Path("/root/codex-work/vdot-build")
XS = Path(os.environ.get("XS", "/root/codex-work/xiangshan-vdot-2026/XiangShan"))

LIBS = {
    "nangate45": dict(
        title="NanGate 45 nm (FreePDK45, typical)",
        files=["NangateOpenCellLibrary_typical.lib"],
        dont_use=["TAPCELL_X1", "FILLCELL_X*", "AOI211_X1", "OAI211_X1"],  # ORFS nangate45 list
        driver="BUF_X2", dff="DFF_X1", clk="CK", q="Q", d="D"),
    "asap7": dict(
        title="ASAP7 7 nm predictive (RVT, TT)",
        files=["asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib.gz",
               "asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib.gz",
               "asap7sc7p5t_AO_RVT_TT_nldm_211120.lib.gz",
               "asap7sc7p5t_OA_RVT_TT_nldm_211120.lib.gz",
               "asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib"],
        dont_use=["*x1p*_ASAP7*", "*xp*_ASAP7*", "SDF*", "ICG*"],          # ORFS asap7 list
        driver="BUFx2_ASAP7_75t_R", dff="DFFHQNx1_ASAP7_75t_R", clk="CLK", q="QN", d="D"),
}

def designs(rtl):
    ppa, eq = VB / "ppa_acc", VB / "equiv"
    out = [dict(key="v2_plain", name="v2: 4 CSA trees + 4 CPAs (old)", files=[eq / "v2_chisel.sv"], top="VDot128")]
    for c in (6, 7, 8, 9, 10):
        out.append(dict(key=f"v3_plain_c{c}", name=f"v3: fused Dadda, vdot only, cut {c}",
                        files=[ppa / f"plain_c{c}/VDot128.sv"], top="VDot128"))
    for c in (6, 7, 8, 9, 10):
        out.append(dict(key=f"v3_acc_c{c}", name=f"v3: fused Dadda + acc, cut {c}" + (" (shipped)" if c == 8 else ""),
                        files=[ppa / f"acc_c{c}/VDot128.sv"], top="VDot128"))
    out.append(dict(key="vimac64b", name="XiangShan VIMac64b (existing multiplier)", files=[rtl / "VIMac64b.sv"],
                    top="VIMac64b"))
    return out


# ---------------------------------------------------------------- liberty ----

def read_text(p):
    p = Path(p)
    return gzip.open(p, "rt").read() if p.suffix == ".gz" else p.read_text()


def strip_comments(t):
    return re.sub(r"/\*.*?\*/", "", t, flags=re.S)


STMT = re.compile(r"\s*([A-Za-z_][\w.]*)\s*(\(([^)]*)\))?\s*([{;:])")
BRACE = re.compile(r'[{}"]')
SEMI = re.compile(r'[;"]')


def close_brace(body, j):
    """Index just after the '}' matching the '{' that ends at j."""
    depth = 1
    while depth:
        m = BRACE.search(body, j)
        j = m.end()
        if m.group() == "{":
            depth += 1
        elif m.group() == "}":
            depth -= 1
        else:
            j = body.index('"', j) + 1
    return j


def groups(body):
    """Split the inside of a liberty group into top-level statements:
    yields (kind, name, text); kind is the group keyword, or None for an attribute."""
    i, n = 0, len(body)
    while i < n:
        m = STMT.match(body, i)
        if not m:
            break
        if m.group(4) == "{":
            j = close_brace(body, m.end())
            yield m.group(1), (m.group(3) or "").strip().strip('"'), body[m.start():j]
            i = j
        elif m.group(4) == ";":                 # complex attribute: name(args);
            yield None, m.group(1), body[m.start():m.end()]
            i = m.end()
        else:                                   # simple attribute: name : value;
            j = m.end()
            while True:
                s = SEMI.search(body, j)
                if s.group() == '"':
                    j = body.index('"', s.end()) + 1
                    continue
                break
            yield None, m.group(1), body[m.start():s.end()]
            i = s.end()


def inner(group_txt):
    """(header up to and including '{', body) of one group's text."""
    i = group_txt.index("{")
    return group_txt[:i + 1], group_txt[i + 1:group_txt.rstrip().rfind("}")]


def library_body(text):
    m = re.search(r"library\s*\([^)]*\)\s*{", text)
    return text[:m.end()], text[m.end():text.rstrip().rfind("}")]


def find_cell(text, name):
    m = re.search(r"\bcell\s*\(\s*\"?%s\"?\s*\)\s*{" % re.escape(name), text)
    return text[m.start():close_brace(text, m.end())]


def sub(group_txt, kind):
    return [(n, t) for k, n, t in groups(inner(group_txt)[1]) if k == kind]


def build_lib(lib, pdk, out):
    """Merge the library files into one and remove the dont_use cells."""
    head, seen, attrs, cells = None, set(), [], []
    for f in lib["files"]:
        h, body = library_body(strip_comments(read_text(pdk / f)))
        head = head or h
        for kind, name, txt in groups(body):
            if kind == "cell":
                if not any(fnmatch.fnmatch(name, p) for p in lib["dont_use"]):
                    cells.append(txt)
            elif (kind, name) not in seen:
                seen.add((kind, name))
                attrs.append(txt)
    out.write_text(head + "\n" + "\n".join(attrs) + "\n" + "\n".join(cells) + "\n}\n")
    return len(cells)


def table_mid(table_txt):
    """Value of an NLDM table at the middle index of both axes."""
    rows = re.search(r"values\s*\((.*?)\)\s*;", table_txt, re.S).group(1)
    rows = [[float(x) for x in r.split(",")] for r in re.findall(r'"([^"]*)"', rows)]
    r = rows[len(rows) // 2]
    return r[len(r) // 2]


def ff_timing(libfile, lib):
    """clk->q delay and setup time (ps, middle of the NLDM tables) and D pin
    capacitance (fF) of the library DFF."""
    text = libfile.read_text()
    unit = re.search(r'time_unit\s*:\s*"1(\w+)"', text).group(1)
    scale = {"ps": 1.0, "ns": 1000.0}[unit]
    pins = dict(sub(find_cell(text, lib["dff"]), "pin"))

    def arcs(pin, ttype, tables):
        vals = [table_mid(g) for _, t in sub(pins[pin], "timing")
                if re.search(r'timing_type\s*:\s*"?%s"?\s*;' % ttype, t)
                for tab in tables for _, g in sub(t, tab)]
        return max(vals)

    clk2q = arcs(lib["q"], "rising_edge", ("cell_rise", "cell_fall"))
    setup = arcs(lib["d"], "setup_rising", ("rise_constraint", "fall_constraint"))
    cap = float(re.search(r"\bcapacitance\s*:\s*([\d.]+)", pins[lib["d"]]).group(1))
    return clk2q * scale, setup * scale, cap


def last_stat(text):
    """(area, cell counts) of the last `stat -liberty` in a yosys log."""
    s = text[text.rfind("Printing statistics"):]
    area = re.findall(r"Chip area for module .*?:\s*([\d.]+)", s)
    counts = dict((c, int(n)) for c, n in re.findall(r"^\s+(\S+)\s+(\d+)\s*$", s, re.M))
    return (float(area[-1]) if area else 0.0), counts


# ------------------------------------------------------------------ yosys ----

READ = """read_verilog -sv -DSYNTHESIS {files}
hierarchy -check -top {top}
proc
flatten
opt_clean
async2sync
"""

# No opt before expose: opt_dff would drop constant register bits, and a register
# whose Q then drives only a slice of its wire is not everted by `expose`.
EVERT = READ + """dffunmap
expose -evert-dff t:$dff
opt_clean
"""


def yosys(script, log):
    with tempfile.NamedTemporaryFile("w", suffix=".ys", delete=False) as f:
        f.write(script)
    r = subprocess.run(["yosys", "-l", str(log), "-s", f.name], stdout=subprocess.DEVNULL,
                       stderr=subprocess.STDOUT)
    os.unlink(f.name)
    text = Path(log).read_text(errors="replace")
    if r.returncode:
        raise RuntimeError(f"yosys failed, see {log}")
    return text


def segments(d, work):
    """Group the everted outputs into pipeline segments from the netlist itself:
    a register D pin is in segment k if the deepest register feeding it (its own
    hold path excluded) is in segment k-1; module inputs are segment 0.
    Module outputs form the segment `out`."""
    js = work / f"{d['key']}.evert.json"
    yosys(EVERT.format(files=" ".join(map(str, d["files"])), top=d["top"]) + f"write_json {js}\n",
          work / f"{d['key']}.evert.log")
    m = json.loads(js.read_text())["modules"][d["top"]]
    driver = {}                                   # net bit -> input bits of its driving cell
    for c in m["cells"].values():
        dirs = c["port_directions"]
        ins = [b for p, bs in c["connections"].items() if dirs[p] == "input" for b in bs if isinstance(b, int)]
        for p, bs in c["connections"].items():
            if dirs[p] == "output":
                for b in bs:
                    if isinstance(b, int):
                        driver[b] = ins
    src = {}                                      # input port bit -> register name, or None for a module input
    for name, p in m["ports"].items():
        if p["direction"] == "input":
            for b in p["bits"]:
                if isinstance(b, int):
                    src[b] = name[:-2] if name.endswith(".q") else None
    outs = {n: p["bits"] for n, p in m["ports"].items() if p["direction"] == "output" and not n.endswith(".c")}

    def feeders(name):
        own = name[:-2] if name.endswith(".d") else None
        seen, stack, regs = set(), [b for b in outs[name] if isinstance(b, int)], set()
        while stack:
            b = stack.pop()
            if b in seen:
                continue
            seen.add(b)
            if b in src:
                if src[b] is not None and src[b] != own:
                    regs.add(src[b])
                continue
            stack.extend(driver.get(b, []))
        return regs

    feed = {n: feeders(n) for n in outs}
    level = {}

    def lev(n, path=()):
        if n not in level:
            ups = [lev(r + ".d", path + (n,)) for r in feed[n] if r + ".d" in outs and r + ".d" not in path]
            level[n] = 1 + max(ups, default=0)
        return level[n]

    seg = {}
    for n in outs:
        seg.setdefault("out" if not n.endswith(".d") else f"S{lev(n)}", []).append(n)
    with open(work / f"{d['key']}.segments.txt", "w") as f:
        for s, ns in sorted(seg.items()):
            f.write(f"{s}: {len(ns)} ports: {' '.join(sorted(ns))}\n")
    return seg


# ABC scripts for the timing runs (both delay-driven, target 1 ps, then sizing):
#  restructure: Yosys' default liberty script with -constr/-D (AIG rewriting and
#               choice computation before mapping; can re-serialise prefix adders)
#  struct:      map the structure Yosys built (Dadda tree, Brent-Kung adders) as is
ABC_SCRIPTS = {
    "restructure": "",
    "struct": " -script +strash;&get,-n;&nf,-D,1;&put;buffer;upsize,-D,1;dnsize,-D,1;stime,-p",
}


def time_segment(d, seg, keep, libname, libfile, constr, work, abc):
    log = work / f"{d['key']}.{seg}.{libname}.{abc}.log"
    sel = " ".join(f"o:{n}" for n in keep)
    text = yosys(EVERT.format(files=" ".join(map(str, d["files"])), top=d["top"]) + f"""select -set keep {sel}
delete -port o:* @keep %d
opt_clean -purge
synth -noabc -top {d['top']}
abc -liberty {libfile} -constr {constr} -D 1{ABC_SCRIPTS[abc]}
opt_clean
stat -liberty {libfile}
""", log)
    delay = [float(x) for x in re.findall(r"Delay\s*=\s*([\d.]+)\s*ps", text)]
    area, counts = last_stat(text)
    return dict(delay=delay[-1] if delay else 0.0, area=area, cells=sum(counts.values()))


def area_full(d, libname, libfile, constr, lib, work):
    log = work / f"{d['key']}.area.{libname}.log"
    text = yosys(READ.format(files=" ".join(map(str, d["files"])), top=d["top"]) + f"""synth -noabc -top {d['top']}
dfflegalize -cell $_DFF_P_ x
dfflibmap -liberty {libfile}
abc -liberty {libfile} -constr {constr}
opt_clean
stat -liberty {libfile}
""", log)
    area, counts = last_stat(text)
    return dict(area=area, ffs=sum(n for c, n in counts.items() if c.upper().startswith("DFF")))


# ------------------------------------------------------------------- main ----

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pdk", type=Path, default=VB / "pdk")
    ap.add_argument("--rtl", type=Path, default=XS / "build-minimal-v4/rtl")
    ap.add_argument("--libs", default="nangate45,asap7")
    ap.add_argument("--out", type=Path, default=Path(__file__).with_name("results_pdk.md"))
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--work", type=Path, default=VB / "pdk_runs", help="yosys scripts' logs")
    ap.add_argument("--abc", default="struct,restructure", help="ABC scripts for the timing runs")
    a = ap.parse_args()
    work = a.work
    work.mkdir(parents=True, exist_ok=True)
    ds = designs(a.rtl)
    segs = {d["key"]: segments(d, work) for d in ds}
    res = {"libs": {}, "designs": [{k: d[k] for k in ("key", "name", "top")} for d in ds]}
    for libname in a.libs.split(","):
        lib = LIBS[libname]
        libfile = work / f"{libname}.merged.lib"
        ncell = build_lib(lib, a.pdk, libfile)
        clk2q, setup, dcap = ff_timing(libfile, lib)
        constr = work / f"{libname}.constr"
        constr.write_text(f"set_driving_cell {lib['driver']}\nset_load {dcap:.4f}\n")
        info = dict(title=lib["title"], cells=ncell, dff=lib["dff"], clk2q_ps=clk2q, setup_ps=setup,
                    dff_d_cap=dcap, area={}, timing={})
        jobs = {}
        with cf.ThreadPoolExecutor(a.jobs) as ex:
            for d in ds:
                for abc in a.abc.split(","):
                    for s, keep in segs[d["key"]].items():
                        jobs[("timing", abc, d["key"], s)] = ex.submit(time_segment, d, s, keep, libname, libfile,
                                                                       constr, work, abc)
                jobs[("area", None, d["key"], None)] = ex.submit(area_full, d, libname, libfile, constr, lib, work)
            for (kind, abc, k, s), f in jobs.items():
                if kind == "area":
                    info["area"][k] = f.result()
                else:
                    info["timing"].setdefault(abc, {}).setdefault(k, {})[s] = f.result()
        res["libs"][libname] = info
        print(f"[{libname}] done", file=sys.stderr)
    (a.out.with_suffix(".json")).write_text(json.dumps(res, indent=1))
    a.out.write_text(report(res))
    print(a.out.read_text())


def report(res):
    names = {d["key"]: d["name"] for d in res["designs"]}
    out = ["# VDot128 in real standard-cell libraries (Yosys 0.33 + ABC, synthesis-level STA)", "",
           "Combinational delay per pipeline segment in ps (ABC `stime`: NLDM tables, fanout loads, no wire "
           "load, inputs driven by a X2 buffer, D-pin load), for two ABC scripts: `struct` maps the structure "
           "Yosys built (Dadda tree, Brent-Kung adders) as is, `restructure` is Yosys' default liberty script "
           "(AIG rewriting first). `cycle` = clk->q + worst register-to-register segment + setup of the library "
           "DFF. Area: whole module incl. flip-flops (default area-recovering mapping), um^2.", ""]
    for libname, info in res["libs"].items():
        out += [f"## {info['title']}", "",
                f"{info['cells']} cells after dont_use; DFF {info['dff']}: clk->q {info['clk2q_ps']:.1f} ps, "
                f"setup {info['setup_ps']:.1f} ps, D cap {info['dff_d_cap']:.3f} fF.", ""]
        for abc, rows in info["timing"].items():
            regsegs = sorted({s for r in rows.values() for s in r if s.startswith("S")})
            out += [f"### ABC script: {abc}", "",
                    "| design | " + " | ".join(regsegs) + " | out | worst reg-to-reg | cycle | area | FFs |",
                    "|---|" + "---|" * (len(regsegs) + 6)]
            for k, r in rows.items():
                seg = [r.get(s, {}).get("delay", 0.0) for s in regsegs]
                w = max(seg)
                a = info["area"][k]
                out.append(f"| {names[k]} | " + " | ".join(f"{x:.0f}" for x in seg) +
                           f" | {r.get('out', {}).get('delay', 0.0):.0f} | {w:.0f} | "
                           f"{w + info['clk2q_ps'] + info['setup_ps']:.0f} | {a['area']:.0f} | {a['ffs']} |")
            out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    main()
