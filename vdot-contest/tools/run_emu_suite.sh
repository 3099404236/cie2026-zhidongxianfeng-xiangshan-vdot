#!/bin/bash
# Run every bare-metal program on the XiangShan emu with DiffTest (NEMU REF),
# the two negative controls (deliberately wrong REFs) and the waveform dumps.
#   bash run_emu_suite.sh <tag>          (tag names the run directory, e.g. v3-dadda)
#   PAR=1 bash run_emu_suite.sh <tag>    (start all emu runs at once; each emu is
#                                         single-threaded, so this only needs cores)
# The REFs for the negative controls are built by vdot-build/build_negctl_refs.sh.
set -u
TAG="${1:-run}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"       # vdot-contest
VB=/root/codex-work/vdot-build
XS="${XS:-/root/codex-work/xiangshan-vdot-2026/XiangShan}"
EMU="${EMU:-$XS/build/emu}"
REF="${REF:-$VB/riscv64-nemu-interpreter-vdot-so}"
NOVDOT_REF="${NOVDOT_REF:-$VB/riscv64-nemu-ref-novdot-so}"
BUGGY_REF="${BUGGY_REF:-$VB/riscv64-nemu-ref-buggy-so}"
OUT="${OUT:-$VB/emu-runs/$TAG}"
PAR="${PAR:-0}"
B="$HERE/build"
PROGS="hello_xiangshan vdot_nemu_test vdot_full_test vdota_test vdot_illegal_test vadd_trace vdot_demo vdot_bench"
mkdir -p "$OUT"
strip() { sed -u 's/\x1b\[[0-9;]*m//g'; }

# one job per emu run; in PAR mode they all run in the background
job() { if [ "$PAR" = 1 ]; then "$@" & else "$@"; fi; }
run_prog() {
  /usr/bin/time -f "[host] %e s, max RSS %M KB" "$EMU" -i "$B/$1.bin" --diff "$REF" 2>&1 | strip > "$OUT/$1.log"
}
run_ctl() {   # $1 = novdot | buggy
  local ref=$NOVDOT_REF; [ "$1" = buggy ] && ref=$BUGGY_REF
  "$EMU" -i "$B/vdot_nemu_test.bin" --diff "$ref" 2>&1 | strip > "$OUT/negative_control_$1.log"
}
run_wave() {  # $1 = program, $2 = log name
  "$EMU" -i "$B/$1.bin" --diff "$REF" --dump-wave --wave-path "$OUT/$1.fst" 2>&1 | strip > "$OUT/$2.log"
}

echo "[$(date '+%F %T')] emu=$EMU par=$PAR"
for p in $PROGS; do
  [ "$PAR" = 1 ] || echo "=== $p (difftest REF = vdot NEMU)"
  job run_prog "$p"
  [ "$PAR" = 1 ] || grep -E "HIT GOOD TRAP|HIT BAD TRAP|ABORT|different|instrCnt|\[vdot-|cycles=|PASS|FAIL" "$OUT/$p.log" | tail -n 40
done
job run_ctl novdot
job run_ctl buggy
job run_wave vadd_trace vadd_trace_wave
job run_wave vdot_nemu_test vdot_wave
wait

if [ "$PAR" = 1 ]; then
  for p in $PROGS; do
    echo "=== $p (difftest REF = vdot NEMU)"
    grep -E "HIT GOOD TRAP|HIT BAD TRAP|ABORT|different|instrCnt|\[vdot-|cycles=|PASS|FAIL" "$OUT/$p.log" | tail -n 40
  done
fi
for ctl in novdot buggy; do
  echo "=== negative control ($ctl REF): DiffTest must ABORT at a vdot.vv"
  grep -E "<--|different|ABORT|instrCnt" "$OUT/negative_control_$ctl.log"
done

echo "=== waveforms"
python3 "$HERE/tools/trace_timeline.py" "$OUT/vadd_trace.fst" --instr 0x022081d7 --fu VialuFix > "$OUT/vadd_timeline.md"
python3 "$HERE/tools/trace_timeline.py" "$OUT/vdot_nemu_test.fst" --instr 0x36942557 --fu Vimac \
  --show Vimac.inIsVDot Vimac.vdot.io_en Vimac.vdot.stage1Valid Vimac.vdot.stage2 > "$OUT/vdot_timeline.md"
cat "$OUT/vdot_timeline.md"
echo "[$(date '+%F %T')] done"
ls -la "$OUT"
