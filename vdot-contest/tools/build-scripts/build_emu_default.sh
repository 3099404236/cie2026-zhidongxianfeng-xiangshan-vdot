#!/bin/bash
# XiangShan DefaultConfig (the Makefile default: ROB 160, IQ 24, 64 KB L1D,
# 1 MB L2, 16 MB L3, prefetchers on) with vdot.vv + vdota.vv.
# Same flags as the MinimalConfig builds (build_emu_v4.sh) except CONFIG.
# Memory-capped for the 12 GB WSL VM: the September DefaultConfig sim-verilog
# run on this machine peaked at 10.4 GB with a 9 GB JVM heap.
set -e
VB=/root/codex-work/vdot-build
LOG=$VB/logs/build_emu_default.log
CG=/sys/fs/cgroup/memory/xsbuild
mkdir -p $CG; echo $((10752*1024*1024)) > $CG/memory.limit_in_bytes; echo $$ > $CG/cgroup.procs
swapon /swapfile-build 2>/dev/null || true
export NOOP_HOME=/root/codex-work/xiangshan-vdot-2026/XiangShan NEMU_HOME=$VB/NEMU
cd $NOOP_HOME
# keep the MinimalConfig v4 tree (its RTL is the reference for the PPA study)
if [ -d build ] && [ ! -e build-minimal-v4 ]; then mv build build-minimal-v4; fi
COMMON="CONFIG=DefaultConfig NUM_CORES=1 WITH_CHISELDB=0 WITH_CONSTANTIN=0 DISABLE_PERF=1"
ARGS="NUM_CORES=1 RTL_SUFFIX=sv WITH_CHISELDB=0 WITH_CONSTANTIN=0 EMU_THREADS=0 EMU_TRACE=fst"
echo "[$(date)] sim-verilog CONFIG=DefaultConfig" > $LOG
free -m >> $LOG; swapon --show >> $LOG
/usr/bin/time -v make sim-verilog $COMMON JVM_XMX=9G >> $LOG 2>&1
echo "VDot128 io_acc refs: $(grep -c io_acc build/rtl/VDot128.sv); rtl size: $(du -sh build/rtl | cut -f1)" >> $LOG
echo "[$(date)] verilate" >> $LOG
/usr/bin/time -v make -C ./difftest emu-mk $ARGS >> $LOG 2>&1
for f in build/verilator-compile/*.cpp; do
  if [ $(stat -c %s "$f") -gt 5000000 ]; then
    echo "$(basename ${f%.cpp}).o: override OPT_FAST := -O1" >> build/verilator-compile/VSimTop.mk
  fi
done
# The -O1 files cannot use the -O3 precompiled header; give GCC the real header
# it falls back to (old timestamp so make does not rebuild objects because of it).
cp build/verilator-compile/VSimTop__pch.h build/verilator-compile/VSimTop__pch.h.fast
touch -d '2000-01-01 00:00' build/verilator-compile/VSimTop__pch.h.fast
echo "[$(date)] compile (ccache), $(grep -c override build/verilator-compile/VSimTop.mk) files at -O1" >> $LOG
/usr/bin/time -v make -C ./difftest emu $ARGS OBJCACHE=ccache -j4 >> $LOG 2>&1
cp -L build/emu $VB/emu-default-vdota
echo "[$(date)] done: $(ls -la $VB/emu-default-vdota)" >> $LOG
tail -3 $LOG
