# Bare-metal vdot.vv tests and benchmarks (run inside WSL2 / Linux).
#
#   make            build every image into ../build
#   make run-nemu   run every image on the vdot-enabled NEMU interpreter
#   make run-emu    run every image on the XiangShan emu with difftest (NEMU REF)
#
# Override tool locations on the command line, e.g. make run-emu EMU=/path/emu

CROSS   ?= riscv64-linux-gnu-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
PYTHON  ?= python3

NEMU    ?= /root/codex-work/vdot-build/riscv64-nemu-interpreter-vdot
NEMU_SO ?= /root/codex-work/vdot-build/riscv64-nemu-interpreter-vdot-so
EMU     ?= /root/codex-work/xiangshan-vdot-2026/XiangShan/build/emu

B := ../build
ARCH := -march=rv64gcv -mabi=lp64d -mcmodel=medany
# The linux-gnu toolchain defaults to PIE and emits a .note.gnu.build-id
# section; both must be disabled so the raw image starts with _start.
LDFLAGS := -nostdlib -nostartfiles -static -no-pie -fno-pic -Wl,--build-id=none
ASFLAGS := $(ARCH) $(LDFLAGS) -T link.ld
CFLAGS := $(ARCH) -O2 -ffreestanding -fno-builtin -fno-tree-vectorize -fno-tree-slp-vectorize \
          $(LDFLAGS) -Wall -Wextra -T bench/link.ld

TESTS := vdot_nemu_test vdot_full_test vdota_test vdot_illegal_test vadd_trace
PROGS := hello_xiangshan $(TESTS) vdot_demo vdot_bench
IMAGES := $(addprefix $(B)/,$(addsuffix .bin,$(PROGS)))

# Stage 1.1 identity line; the IP is the source address of the default route.
HELLO_NAME   ?= 曾俊翔
HELLO_SCHOOL ?= 电子科技大学
HELLO_IP     ?= $(shell ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($$i=="src") print $$(i+1)}')

all: $(IMAGES) $(B)/vdot_baseline.o

vdot_cases.inc: gen_vdot_cases.py ../reference/vdot_model.py
	$(PYTHON) gen_vdot_cases.py -o $@

vdota_cases.inc: gen_vdota_cases.py gen_vdot_cases.py ../reference/vdot_model.py
	$(PYTHON) gen_vdota_cases.py -o $@

$(B)/vdot_full_test.elf: vdot_cases.inc
$(B)/vdota_test.elf: vdota_cases.inc
$(B)/%.elf: %.S vdot_macros.h link.ld | $(B)
	$(CC) $(ASFLAGS) $< -o $@

$(B)/vdot_bench.elf: bench/crt0.S bench/bench_kernels.S bench/bench.c bench/link.ld vdot_macros.h | $(B)
	$(CC) $(CFLAGS) bench/crt0.S bench/bench_kernels.S bench/bench.c -o $@

$(B)/vdot_demo.elf: bench/crt0.S bench/vdot_demo.c bench/link.ld | $(B)
	$(CC) $(CFLAGS) bench/crt0.S bench/vdot_demo.c -o $@

$(B)/hello_xiangshan.elf: bench/crt0.S bench/hello_xiangshan.c bench/link.ld FORCE | $(B)
	$(CC) $(CFLAGS) -DHELLO_NAME='"$(HELLO_NAME)"' -DHELLO_SCHOOL='"$(HELLO_SCHOOL)"' -DHELLO_IP='"$(HELLO_IP)"' \
	  bench/crt0.S bench/hello_xiangshan.c -o $@

FORCE:

$(B)/vdot_baseline.o: vdot_baseline.S | $(B)
	$(CC) $(ARCH) -c $< -o $@

$(B)/%.bin: $(B)/%.elf
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > $(B)/$*.dis

$(B):
	mkdir -p $@

run-nemu: all
	@for t in $(PROGS); do \
	  echo "=== NEMU: $$t"; \
	  $(NEMU) -b $(B)/$$t.bin 2>&1 | grep -v "^\[src/.*Log\]" | tail -n 30; \
	done

run-emu: all
	@for t in $(PROGS); do \
	  echo "=== XiangShan emu + difftest(NEMU): $$t"; \
	  $(EMU) -i $(B)/$$t.bin --diff $(NEMU_SO) 2>&1 | tail -n 40; \
	done

clean:
	rm -f $(B)/*.elf $(B)/*.bin $(B)/*.dis $(B)/*.o

.PHONY: all run-nemu run-emu clean FORCE
