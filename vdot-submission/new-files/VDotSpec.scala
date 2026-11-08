package xiangshan.backend.fu.vector

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

import scala.util.Random

class VDotSpec extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "VDot128"

  private def pack(values: Seq[Int], high: BigInt = 0, lanes: Int = 8): BigInt = {
    require(values.length == lanes)
    values.zipWithIndex.foldLeft(high << (8 * lanes)) { case (acc, (value, index)) =>
      acc | (BigInt(value & 0xff) << (8 * index))
    }
  }

  /** vd[31:0] = (acc + signed dot) mod 2^32, vd[127:32] = 0. */
  private def expected(lhs: Seq[Int], rhs: Seq[Int], acc: Long = 0): BigInt = {
    val sum = lhs.zip(rhs).map { case (a, b) => a * b }.sum
    BigInt((acc + sum) & 0xffffffffL)
  }

  /** One isolated operation: en for a single cycle, result after 2 cycles. */
  private def check(dut: VDot128, lhs: Seq[Int], rhs: Seq[Int], hi1: BigInt = 0, hi2: BigInt = 0,
                    acc: Long = 0): Unit = {
    dut.io.vs1.poke(pack(lhs, hi1).U)
    dut.io.vs2.poke(pack(rhs, hi2).U)
    dut.io.acc.poke(acc.U(32.W))
    dut.io.en.poke(true.B)
    dut.clock.step()
    dut.io.en.poke(false.B)
    dut.clock.step()
    dut.io.result.expect(expected(lhs, rhs, acc).U)
  }

  /** Back-to-back stream: a new operand pair every cycle; operation j is
    * visible right after the clock edge that follows its stage-1 edge.
    * `accs` (optional) gives the accumulator of each operation. */
  private def stream(dut: VDot128, ops: Seq[(Seq[Int], Seq[Int])], lanes: Int = 8, accs: Seq[Long] = Nil): Unit = {
    val rnd = new Random(7)
    def acc(j: Int): Long = if (accs.isEmpty) 0L else accs(j)
    for (j <- 0 to ops.length) {
      if (j < ops.length) {
        dut.io.vs1.poke(pack(ops(j)._1, BigInt(64, rnd), lanes).U)
        dut.io.vs2.poke(pack(ops(j)._2, BigInt(64, rnd), lanes).U)
        dut.io.acc.poke(acc(j).U(32.W))
        dut.io.en.poke(true.B)
      } else dut.io.en.poke(false.B)
      dut.clock.step()
      if (j > 0) dut.io.result.expect(expected(ops(j - 1)._1, ops(j - 1)._2, acc(j - 1)).U)
    }
  }

  private def randomOps(n: Int, seed: Int, lanes: Int = 8): Seq[(Seq[Int], Seq[Int])] = {
    val r = new Random(seed)
    Seq.fill(n)((Seq.fill(lanes)(r.nextInt(256) - 128), Seq.fill(lanes)(r.nextInt(256) - 128)))
  }

  it should "compute positive signed INT8 products" in {
    test(new VDot128).withAnnotations(Seq(WriteVcdAnnotation)) { dut =>
      check(dut, Seq(1, 2, 3, 4, 5, 6, 7, 8), Seq(8, 7, 6, 5, 4, 3, 2, 1)) // 120
    }
  }

  it should "preserve a negative sum in the low signed 32-bit result" in {
    test(new VDot128) { dut =>
      check(dut, Seq(-1, -2, -3, -4, -5, -6, -7, -8), Seq(1, 2, 3, 4, 5, 6, 7, 8)) // -204
    }
  }

  it should "cover zero and signed INT8 boundaries" in {
    test(new VDot128) { dut =>
      check(dut, Seq.fill(8)(-128), Seq.fill(8)(-128)) // +131072 (maximum)
      check(dut, Seq.fill(8)(-128), Seq.fill(8)(127))  // -130048 (minimum)
      check(dut, Seq.fill(8)(127), Seq.fill(8)(127))   // +129032
      check(dut, Seq.fill(8)(0), Seq.fill(8)(-128))    // 0
      check(dut, Seq(-128, 127, 0, 1, -1, 64, -64, 0), Seq(127, -128, 5, -1, 1, -64, 64, 0))
    }
  }

  it should "ignore the upper 64 bits of both sources" in {
    test(new VDot128) { dut =>
      val ones = (BigInt(1) << 64) - 1
      check(dut, Seq(1, 2, 3, 4, 5, 6, 7, 8), Seq(8, 7, 6, 5, 4, 3, 2, 1), ones, BigInt("0123456789abcdef", 16))
      check(dut, Seq.fill(8)(-128), Seq.fill(8)(-128), ones, ones)
    }
  }

  it should "sweep every byte value on the lowest and the sign-critical highest lane" in {
    test(new VDot128) { dut =>
      val r = new Random(1)
      val ops = for (lane <- Seq(0, 7); a <- -128 to 127 by 1; b <- Seq(-128, -1, 0, 1, 127, r.nextInt(256) - 128))
        yield {
          val lhs = Seq.tabulate(8)(i => if (i == lane) a else r.nextInt(256) - 128)
          val rhs = Seq.tabulate(8)(i => if (i == lane) b else r.nextInt(256) - 128)
          (lhs, rhs)
        }
      stream(dut, ops)
    }
  }

  it should "match a software reference for back-to-back random vectors" in {
    test(new VDot128) { dut =>
      stream(dut, randomOps(2000, 0x2026))
    }
  }

  it should "be correct for every pipeline cut position of the Dadda tree" in {
    for (cut <- 0 to 10) {
      test(new VDot128(cutLevel = cut)) { dut =>
        stream(dut, randomOps(64, cut) ++ Seq((Seq.fill(8)(-128), Seq.fill(8)(-128)), (Seq.fill(8)(-128), Seq.fill(8)(127))))
      }
    }
  }

  it should "scale to VLEN = 256 with 16 lanes (20-bit exact sum)" in {
    test(new VDot128(vlen = 256, lanes = 16)) { dut =>
      val ops = randomOps(200, 16, lanes = 16) ++
        Seq((Seq.fill(16)(-128), Seq.fill(16)(-128)), (Seq.fill(16)(-128), Seq.fill(16)(127)))
      stream(dut, ops, lanes = 16)
    }
  }

  // ---- accumulating tree (vdota.vv; the instance used inside XiangShan) ----

  behavior of "VDot128(accumulate = true)"

  it should "give exactly the vdot.vv results when acc = 0" in {
    test(new VDot128(accumulate = true)) { dut =>
      check(dut, Seq(1, 2, 3, 4, 5, 6, 7, 8), Seq(8, 7, 6, 5, 4, 3, 2, 1))       // 120
      check(dut, Seq(-1, -2, -3, -4, -5, -6, -7, -8), Seq(1, 2, 3, 4, 5, 6, 7, 8)) // -204
      check(dut, Seq.fill(8)(-128), Seq.fill(8)(-128))                           // 131072
      check(dut, Seq.fill(8)(-128), Seq.fill(8)(127))                            // -130048
      stream(dut, randomOps(500, 3))
    }
  }

  it should "add the 32-bit accumulator with int32 wrap-around" in {
    test(new VDot128(accumulate = true)) { dut =>
      check(dut, Seq(1, 2, 3, 4, 5, 6, 7, 8), Seq(8, 7, 6, 5, 4, 3, 2, 1), acc = 1000L)        // 1120
      check(dut, Seq(1, 2, 3, 4, 5, 6, 7, 8), Seq(8, 7, 6, 5, 4, 3, 2, 1), acc = 0x7fffffffL)  // wraps
      check(dut, Seq.fill(8)(-128), Seq.fill(8)(127), acc = 0x80000000L)                     // wraps
      check(dut, Seq.fill(8)(-128), Seq.fill(8)(-128), acc = 0xffffffffL)                    // -1 + 131072
      val r = new Random(11)
      val ops = randomOps(1000, 12)
      stream(dut, ops, accs = Seq.fill(ops.length)(r.nextLong() & 0xffffffffL))
    }
  }

  it should "be correct for every pipeline cut position of the 32-bit tree" in {
    for (cut <- 0 to 10) {
      test(new VDot128(cutLevel = cut, accumulate = true)) { dut =>
        val r = new Random(100 + cut)
        val ops = randomOps(48, cut) ++ Seq((Seq.fill(8)(-128), Seq.fill(8)(-128)), (Seq.fill(8)(-128), Seq.fill(8)(127)))
        stream(dut, ops, accs = Seq.fill(ops.length)(r.nextLong() & 0xffffffffL))
      }
    }
  }
}
