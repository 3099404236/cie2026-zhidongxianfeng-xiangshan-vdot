#!/bin/bash
# Resume the DefaultConfig build at the C++ compile step (sim-verilog and
# verilate already done by build_emu_default.sh).
#
# The files compiled with `override OPT_FAST := -O1` cannot use the precompiled
# header VSimTop__pch.h.fast.gch (built with the global -O3 flags); GCC then
# falls back to a real header named VSimTop__pch.h.fast, which Verilator does
# not create. Provide it as a copy of VSimTop__pch.h with an old timestamp so
# that make does not treat it as newer than the objects.
set -e
VB=/root/codex-work/vdot-build
LOG=$VB/logs/build_emu_default.log
CG=/sys/fs/cgroup/memory/xsbuild
mkdir -p $CG; echo $((10752*1024*1024)) > $CG/memory.limit_in_bytes; echo $$ > $CG/cgroup.procs
swapon /swapfile-build 2>/dev/null || true
export NOOP_HOME=/root/codex-work/xiangshan-vdot-2026/XiangShan NEMU_HOME=$VB/NEMU
cd $NOOP_HOME
VC=build/verilator-compile
cp $VC/VSimTop__pch.h $VC/VSimTop__pch.h.fast
touch -d '2000-01-01 00:00' $VC/VSimTop__pch.h.fast
ARGS="NUM_CORES=1 RTL_SUFFIX=sv WITH_CHISELDB=0 WITH_CONSTANTIN=0 EMU_THREADS=0 EMU_TRACE=fst"
echo "[$(date)] compile resumed after adding the VSimTop__pch.h.fast fallback header" >> $LOG
/usr/bin/time -v make -C ./difftest emu $ARGS OBJCACHE=ccache -j4 >> $LOG 2>&1
cp -L build/emu $VB/emu-default-vdota
echo "[$(date)] done: $(ls -la $VB/emu-default-vdota)" >> $LOG
tail -3 $LOG
