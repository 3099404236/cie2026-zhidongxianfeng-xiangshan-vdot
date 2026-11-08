#!/bin/bash
# Assemble vdot-submission/logs/emu.log from the run directories written by
# run_emu_suite.sh: the full output of the final run, the two negative
# controls, the vdot waveform timeline and a one-line summary per program of
# the earlier emus.
#   bash collect_emu_log.sh <final-run-dir> "<emu description>" [<earlier-dir> "<description>"]... > emu.log
set -u
R="$1"; DESC="$2"; shift 2
EMU_NAME=$(basename "$(grep -m1 -oE '^emu[^ ]* compiled at .*' "$R/vdot_nemu_test.log" | cut -d' ' -f1)")
PROGS="hello_xiangshan vdot_nemu_test vdot_full_test vdota_test vdot_illegal_test vadd_trace vdot_demo vdot_bench"
summary() {   # $1 = log file
  printf '%s | %s\n' "$(grep -m1 -E 'HIT GOOD TRAP|HIT BAD TRAP|ABORT' "$1")" "$(grep -m1 -oE 'instrCnt = .*' "$1")"
}

echo "XiangShan emu + DiffTest: $DESC"
echo "REF = vdot NEMU (riscv64-xs-ref_defconfig, nemu-vdot.patch: vdot.vv + vdota.vv)"
echo "emu binary: $(grep -m1 -oE '^emu[^ ]* compiled at .*' "$R/vdot_nemu_test.log")"
echo "Command per program: emu -i <program>.bin --diff riscv64-nemu-interpreter-vdot-so   (tools/run_emu_suite.sh)"
for p in $PROGS; do
  [ -f "$R/$p.log" ] || continue
  echo; echo "==================================================================== $p"
  cat "$R/$p.log"
done

echo; echo "==================================================================== NEGATIVE CONTROL 1: REF = upstream NEMU without vdot"
echo "(DiffTest must abort at the first vdot.vv: REF raises an illegal-instruction trap, the RTL executes vdot)"
grep -E 'Commit Group Trace|<--|different|ABORT|instrCnt|Guest cycle' "$R/negative_control_novdot.log"
echo; echo "==================================================================== NEGATIVE CONTROL 2: REF = NEMU with a deliberately wrong vdot (vs1 bytes unsigned)"
echo "(the positive case agrees; DiffTest must abort at the negative case: REF 9012, RTL -204)"
grep -E 'Commit Group Trace|<--|different|ABORT|instrCnt|Guest cycle' "$R/negative_control_buggy.log"

echo; echo "==================================================================== WAVEFORM: first vdot.vv in VIMacU (trace_timeline.py on vdot_nemu_test.fst)"
cat "$R/vdot_timeline.md"

while [ $# -ge 2 ]; do
  echo; echo "==================================================================== EARLIER EMU: $2"
  for p in $PROGS; do
    [ -f "$1/$p.log" ] && echo "  $p: $(summary "$1/$p.log")"
  done
  for c in novdot buggy; do
    [ -f "$1/negative_control_$c.log" ] && echo "  negative control ($c REF): $(summary "$1/negative_control_$c.log")"
  done
  shift 2
done
