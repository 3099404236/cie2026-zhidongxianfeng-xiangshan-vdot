#!/bin/bash
# Two deliberately wrong DiffTest REFs for the negative-control experiment:
#   ref-novdot : upstream NEMU without the vdot patch (vdot -> illegal instruction in REF)
#   ref-buggy  : vdot treats vs1 bytes as UNSIGNED (wrong result only for negative lanes)
set -e
VB=/root/codex-work/vdot-build
C=$VB/NEMU-ctl
rm -rf $C && rsync -a --exclude /build $VB/NEMU/ $C/
cd $C && export NEMU_HOME=$C
build() { make riscv64-xs-ref_defconfig >/dev/null && make -j12 >/dev/null 2>&1 && cp build/riscv64-nemu-interpreter-so $VB/$1; echo "built $1"; }
git checkout -- src/isa/riscv64/include/isa-all-instr.h src/isa/riscv64/instr/rvv/decode.h src/isa/riscv64/instr/rvv/vcompute.h
build riscv64-nemu-ref-novdot-so
git apply "/mnt/d/大四上学期/risc/香山/vdot-submission/nemu-vdot.patch"
sed -i 's/const int8_t lhs = (int8_t)vreg_b(id_src->reg, i);/const int32_t lhs = (uint8_t)vreg_b(id_src->reg, i); \/\/ BUG on purpose/' src/isa/riscv64/instr/rvv/vcompute.h
grep -n "BUG on purpose" src/isa/riscv64/instr/rvv/vcompute.h
make clean-all >/dev/null 2>&1 || true
build riscv64-nemu-ref-buggy-so
nm $VB/riscv64-nemu-ref-novdot-so | grep -c exec_vdot || true
nm $VB/riscv64-nemu-ref-buggy-so | grep -c exec_vdot
