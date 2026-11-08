#!/bin/bash
# PPA of the accumulating (vdota) VDot128 vs the plain one, from Chisel output.
VB=/root/codex-work/vdot-build; OUT=$VB/ppa_acc; mkdir -p $OUT
CG=/sys/fs/cgroup/memory/millrun; mkdir -p $CG; echo $((6144*1024*1024)) > $CG/memory.limit_in_bytes; echo $$ > $CG/cgroup.procs
export JAVA_OPTS="-Xmx3g -Xss64m"
cd /root/codex-work/xiangshan-vdot-2026/XiangShan
gen() { mill -i xiangshan.test.runMain xiangshan.backend.fu.vector.VDotVerilog $OUT/$1 $2 $3 > $OUT/$1.gen.log 2>&1; }
gen plain_c7 7 noacc
for c in 6 7 8 9; do gen acc_c$c $c acc; done
D="-script +strash;dch;map,-D,1;topo"
printf "%-10s %8s %12s %6s %10s %10s\n" variant cells transistors FFs depth_g depth_c
for v in plain_c7 acc_c6 acc_c7 acc_c8 acc_c9; do
  f=$OUT/$v/VDot128.sv
  a=$(yosys -q -p "read_verilog -sv -DSYNTHESIS $f; synth -flatten -noabc -top VDot128; abc -g AND,NAND,OR,NOR,XOR,XNOR; opt_clean; stat" -l /dev/stdout 2>&1)
  cells=$(echo "$a" | grep -E "Number of cells" | tail -1 | awk '{print $NF}')
  ffs=$(echo "$a" | grep -E "DFF" | awk '{s+=$NF} END {print s}')
  t=$(yosys -q -p "read_verilog -sv -DSYNTHESIS $f; synth -flatten -noabc -top VDot128; abc -g cmos3; opt_clean; stat -tech cmos" -l /dev/stdout 2>&1 | grep -E "transistors" | tail -1 | awk '{print $NF}')
  dg=$(yosys -q -p "read_verilog -sv -DSYNTHESIS $f; synth -flatten -noabc -top VDot128; abc -g AND,NAND,OR,NOR,XOR,XNOR $D; opt_clean; ltp -noff" -l /dev/stdout 2>&1 | grep -oE "length=[0-9]+" | tail -1 | cut -d= -f2)
  dc=$(yosys -q -p "read_verilog -sv -DSYNTHESIS $f; synth -flatten -noabc -top VDot128; abc -g cmos3 $D; opt_clean; ltp -noff" -l /dev/stdout 2>&1 | grep -oE "length=[0-9]+" | tail -1 | cut -d= -f2)
  printf "%-10s %8s %12s %6s %10s %10s\n" $v "$cells" "$t" "$ffs" "$dg" "$dc"
done
