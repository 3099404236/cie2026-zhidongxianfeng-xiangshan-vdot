#!/bin/bash
# Re-run every vdot.vv check and capture the REAL tool output in logs/.
#
#   ./run_all_checks.sh [all|env|patch|python|nemu|explore|chisel|emu|pdk]
#   (pdk is not part of `all`: it needs the downloaded liberty files, see step_pdk)
#
# Paths below match the WSL2 machine used for the submission; override them
# with environment variables on another machine.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SUB="$HERE/../vdot-submission"
LOGS="$SUB/logs"
XS="${XS:-/root/codex-work/xiangshan-vdot-2026/XiangShan}"
NEMU_SRC="${NEMU_SRC:-/root/codex-work/vdot-build/NEMU}"
NEMU="${NEMU:-/root/codex-work/vdot-build/riscv64-nemu-interpreter-vdot}"
NEMU_SO="${NEMU_SO:-/root/codex-work/vdot-build/riscv64-nemu-interpreter-vdot-so}"
EMU="${EMU:-$XS/build/emu}"
PROGRAMS="hello_xiangshan vdot_nemu_test vdot_full_test vdota_test vdot_illegal_test vadd_trace vdot_demo vdot_bench"
mkdir -p "$LOGS"

banner() { printf '\n================================================================\n%s\n[%s]\n================================================================\n' "$1" "$(date '+%F %T %z')"; }
run() { echo "\$ $*"; "$@" 2>&1; echo "[exit status: $?]"; }

step_env() {
  banner "Environment"
  run uname -a
  run riscv64-linux-gnu-gcc --version
  run verilator --version
  run yosys -V
  run java -version
  run mill --version
  run python3 --version
  (cd "$XS" && run git log -1 --format='XiangShan %H %cd')
  (cd "$NEMU_SRC" && run git log -1 --format='NEMU %H %cd')
}

step_patch() {
  banner "Patches apply cleanly to pristine upstream trees"
  local tmp; tmp=$(mktemp -d)
  (cd "$XS" && git worktree add -f --detach "$tmp/xs" HEAD >/dev/null 2>&1)
  (cd "$tmp/xs" && run git apply --check -v "$SUB/xs-vdot-rtl.patch")
  (cd "$XS" && git worktree remove --force "$tmp/xs")
  (cd "$NEMU_SRC" && git worktree add -f --detach "$tmp/nemu" HEAD >/dev/null 2>&1)
  (cd "$tmp/nemu" && run git apply --check -v "$SUB/nemu-vdot.patch")
  (cd "$NEMU_SRC" && git worktree remove --force "$tmp/nemu")
  rm -rf "$tmp"
}

step_python() {
  banner "Python golden model unit tests"
  (cd "$HERE" && run python3 -m unittest -v tests/test_vdot_model.py)
}

step_nemu() {
  banner "Bare-metal programs on the vdot-enabled NEMU interpreter"
  (cd "$HERE/software" && run make all)
  for p in $PROGRAMS; do
    echo "--- $p"
    run "$NEMU" -b "$HERE/build/$p.bin"
  done
}

step_explore() {
  banner "VDot128 datapath exploration (Verilator equivalence + Yosys)"
  (cd "$HERE/rtl-explore" && run python3 run_explore.py)
}

step_pdk() {
  # needs the NanGate45 / ASAP7 liberty files in $PDK (see vdot-submission/logs/pdk.log for the source)
  local pdk="${PDK:-/root/codex-work/vdot-build/pdk}"
  banner "Real standard-cell libraries: per-stage synthesis-level timing (Yosys + ABC)"
  run cat "$pdk/PROVENANCE.txt"
  run yosys -V
  (cd "$HERE/rtl-explore" && run python3 -I pdk_ppa.py --pdk "$pdk")
  for f in /root/codex-work/vdot-build/pdk_runs/*.segments.txt; do echo "[$(basename "$f" .segments.txt)]"; cut -c1-160 "$f"; done
}

step_chisel() {
  banner "ChiselTest: VDotSpec"
  (cd "$XS" && run mill -i xiangshan.test.testOnly xiangshan.backend.fu.vector.VDotSpec)
}

step_emu() {
  banner "XiangShan emu + difftest (NEMU as REF): co-simulation, negative controls, waveforms"
  run ls -la "$EMU" "$NEMU_SO"
  EMU="$EMU" REF="$NEMU_SO" run bash "$HERE/tools/run_emu_suite.sh" "check-$(date +%m%d-%H%M)"
}

what="${1:-all}"
if [ "$what" = all ]; then
  for s in env patch python nemu explore chisel emu; do "$0" "$s"; done
  exit 0
fi
# strip ANSI colour codes so the logs read cleanly in any viewer
"step_$what" 2>&1 | sed -u 's/\x1b\[[0-9;]*m//g' | tee "$LOGS/$what.log"
