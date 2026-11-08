#!/usr/bin/env python3
"""Build the two submission archives with correct UTF-8 (Chinese) file names.

  python3 vdot-contest/tools/make_packages.py

  vdot-submission/packages/tech-doc.zip                  documents + logs
  vdot-submission/packages/other-code-and-waveforms.zip  patches, new files,
                                                          tests, tools, waveforms

Python's zipfile sets the UTF-8 flag for non-ASCII names, so the Chinese
document names display correctly on every OS (the previous archives did not).
"""

from __future__ import annotations

import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]          # .../香山
SUB = ROOT / "vdot-submission"
CON = ROOT / "vdot-contest"
OUT = SUB / "packages"

SKIP_DIRS = {"__pycache__", "build", "gen", "obj"}
SKIP_SUFFIX = {".pyc", ".o", ".elf"}


def walk(base: Path, rel_to: Path, exts: set[str] | None = None):
    for p in sorted(base.rglob("*")):
        if not p.is_file() or any(part in SKIP_DIRS for part in p.relative_to(base).parts):
            continue
        if p.suffix in SKIP_SUFFIX or (exts is not None and p.suffix not in exts):
            continue
        yield p, p.relative_to(rel_to)


def add(z: zipfile.ZipFile, path: Path, arcname: Path) -> None:
    z.write(path, arcname.as_posix())


def main() -> None:
    OUT.mkdir(exist_ok=True)

    with zipfile.ZipFile(OUT / "tech-doc.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for name in ("README.md", "PROGRESS_REPORT.md", "AI_HANDOVER_VDOT.md"):
            if (SUB / name).exists():
                add(z, SUB / name, Path(name))
        for p, rel in walk(SUB / "docs", SUB):
            add(z, p, rel)
        for p, rel in walk(SUB / "logs", SUB):
            add(z, p, rel)

    with zipfile.ZipFile(OUT / "other-code-and-waveforms.zip", "w", zipfile.ZIP_DEFLATED) as z:
        for name in ("xs-vdot-rtl.patch", "xs-vdot-rtl-stat.txt", "nemu-vdot.patch", "README.md"):
            add(z, SUB / name, Path("vdot-submission") / name)
        for p, rel in walk(SUB / "new-files", ROOT):
            add(z, p, rel)
        for sub in ("reference", "tests", "software", "rtl-explore", "tools", "artifacts"):
            for p, rel in walk(CON / sub, ROOT):
                add(z, p, rel)
        add(z, CON / "run_all_checks.sh", Path("vdot-contest/run_all_checks.sh"))
        for p in sorted((CON / "build").glob("*.bin")):     # ready-to-run images
            add(z, p, p.relative_to(ROOT))

    for f in sorted(OUT.glob("*.zip")):
        with zipfile.ZipFile(f) as z:
            print(f"{f.name}: {len(z.namelist())} files, {f.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
