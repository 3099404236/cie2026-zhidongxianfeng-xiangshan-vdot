#!/bin/bash
# Export the vdot.vv patches and new files from the WSL working trees into
# vdot-submission/. Run inside WSL:  bash vdot-contest/tools/export_patch.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../../vdot-submission"
XS="${XS:-/root/codex-work/xiangshan-vdot-2026/XiangShan}"
NEMU="${NEMU_SRC:-/root/codex-work/vdot-build/NEMU}"

mkdir -p "$OUT/new-files"
cd "$XS"
# Tracked-file changes only (the two new files are shipped separately).
git diff -- src/main/scala/xiangshan/backend/decode/Instructions.scala \
            src/main/scala/xiangshan/backend/decode/DecodeUnit.scala \
            src/main/scala/xiangshan/backend/decode/VecDecoder.scala \
            src/main/scala/xiangshan/backend/decode/VecExceptionGen.scala \
            src/main/scala/xiangshan/backend/fu/wrapper/VIMacU.scala > "$OUT/xs-vdot-rtl.patch"
{
  echo "XiangShan base commit: $(git rev-parse HEAD)"
  git diff --stat -- src/main/scala
  echo "new files:"
  wc -l src/main/scala/xiangshan/backend/fu/vector/VDot.scala \
        src/test/scala/xiangshan/backend/fu/vector/VDotSpec.scala \
        src/test/scala/xiangshan/backend/fu/vector/VDotVerilog.scala
} > "$OUT/xs-vdot-rtl-stat.txt"
cp src/main/scala/xiangshan/backend/fu/vector/VDot.scala "$OUT/new-files/"
cp src/test/scala/xiangshan/backend/fu/vector/VDotSpec.scala "$OUT/new-files/"
cp src/test/scala/xiangshan/backend/fu/vector/VDotVerilog.scala "$OUT/new-files/"

cd "$NEMU"
git diff -- src/isa/riscv64/include/isa-all-instr.h src/isa/riscv64/instr/rvv/decode.h \
            src/isa/riscv64/instr/rvv/vcompute.h > "$OUT/nemu-vdot.patch"
echo "NEMU base commit: $(git rev-parse HEAD)" >> "$OUT/xs-vdot-rtl-stat.txt"

wc -l "$OUT/xs-vdot-rtl.patch" "$OUT/nemu-vdot.patch"
