package yunsuan.vectortest.alu

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import yunsuan.vector.alu.VIntFixpAlu

/** Minimal upstream YunSuan vector-add test used to generate the stage-1 VCD. */
class VAddWaveformSpec extends AnyFlatSpec with ChiselScalatestTester {
  behavior of "VIAlu vector addition waveform"

  private def packBytes(values: Seq[Int]): BigInt =
    values.zipWithIndex.foldLeft(BigInt(0)) { case (acc, (value, index)) =>
      acc | (BigInt(value & 0xff) << (8 * index))
    }

  it should "add sixteen e8 lanes" in {
    test(new VIntFixpAlu).withAnnotations(Seq(WriteVcdAnnotation)) { dut =>
      val lhs = 1 to 16
      val rhs = 16 to 1 by -1

      dut.io.fire.poke(true.B)
      dut.io.in.opcode.op.poke(0.U) // vadd
      dut.io.in.info.vm.poke(true.B)
      dut.io.in.info.ma.poke(false.B)
      dut.io.in.info.ta.poke(true.B)
      dut.io.in.info.vlmul.poke(0.U)
      dut.io.in.info.vl.poke(16.U)
      dut.io.in.info.vstart.poke(0.U)
      dut.io.in.info.uopIdx.poke(0.U)
      dut.io.in.info.vxrm.poke(0.U)
      dut.io.in.srcType(0).poke(4.U) // signed e8
      dut.io.in.srcType(1).poke(4.U)
      dut.io.in.vdType.poke(4.U)
      dut.io.in.vs1.poke(packBytes(lhs).U)
      dut.io.in.vs2.poke(packBytes(rhs).U)
      dut.io.in.old_vd.poke(0.U)
      dut.io.in.mask16b.poke("hffff".U)
      dut.io.ctrl.narrow.poke(false.B)
      dut.io.ctrl.vstart_gte_vl.poke(false.B)

      dut.clock.step()
      dut.io.fire.poke(false.B)
      dut.io.out.vd.expect(packBytes(Seq.fill(16)(17)).U)
      dut.clock.step()
    }
  }
}
