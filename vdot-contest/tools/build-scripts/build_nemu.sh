#!/bin/bash
set -e
cd /root/codex-work/vdot-build/NEMU
export NEMU_HOME=$PWD
echo "== [$(date)] building NEMU ref .so (riscv64-xs-ref_defconfig)"
make riscv64-xs-ref_defconfig
make -j12
cp build/riscv64-nemu-interpreter-so /root/codex-work/vdot-build/riscv64-nemu-interpreter-vdot-so
echo "== [$(date)] building NEMU standalone interpreter (riscv64-xs_defconfig)"
make clean-all >/dev/null 2>&1 || true
make riscv64-xs_defconfig
make -j12
cp build/riscv64-nemu-interpreter /root/codex-work/vdot-build/riscv64-nemu-interpreter-vdot
echo "== [$(date)] done"
nm /root/codex-work/vdot-build/riscv64-nemu-interpreter-vdot-so | grep -c exec_vdot
