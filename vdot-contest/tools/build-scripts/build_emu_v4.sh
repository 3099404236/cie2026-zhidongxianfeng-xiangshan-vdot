#!/bin/bash
# Full rebuild with vdota.vv: regenerate RTL (decode changed), verilate, compile.
set -e
VB=/root/codex-work/vdot-build
LOG=$VB/logs/build_emu_v4.log
CG=/sys/fs/cgroup/memory/xsbuild
mkdir -p $CG; echo $((7680*1024*1024)) > $CG/memory.limit_in_bytes; echo $$ > $CG/cgroup.procs
swapon /swapfile-build 2>/dev/null || true
export NOOP_HOME=/root/codex-work/xiangshan-vdot-2026/XiangShan NEMU_HOME=$VB/NEMU
cd $NOOP_HOME
COMMON="CONFIG=MinimalConfig NUM_CORES=1 WITH_CHISELDB=0 WITH_CONSTANTIN=0 DISABLE_PERF=1"
ARGS="NUM_CORES=1 RTL_SUFFIX=sv WITH_CHISELDB=0 WITH_CONSTANTIN=0 EMU_THREADS=0 EMU_TRACE=fst"
echo "[$(date)] sim-verilog" > $LOG
rm -rf build/rtl
/usr/bin/time -v make sim-verilog $COMMON JVM_XMX=6G >> $LOG 2>&1
grep -c "io_acc" build/rtl/VDot128.sv >> $LOG
rm -f build/verilator-compile/VSimTop.mk
echo "[$(date)] verilate" >> $LOG
/usr/bin/time -v make -C ./difftest emu-mk $ARGS >> $LOG 2>&1
for f in build/verilator-compile/*.cpp; do
  if [ $(stat -c %s "$f") -gt 5000000 ]; then
    echo "$(basename ${f%.cpp}).o: override OPT_FAST := -O1" >> build/verilator-compile/VSimTop.mk
  fi
done
echo "[$(date)] compile (ccache), $(grep -c override build/verilator-compile/VSimTop.mk) files at -O1" >> $LOG
/usr/bin/time -v make -C ./difftest emu $ARGS OBJCACHE=ccache -j6 >> $LOG 2>&1
cp -L build/emu $VB/emu-v4-vdota
echo "[$(date)] done: $(ls -la $VB/emu-v4-vdota)" >> $LOG
tail -3 $LOG
