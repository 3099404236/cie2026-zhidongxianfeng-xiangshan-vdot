package xiangshan.backend.fu.vector

import chisel3.RequireAsyncReset
import circt.stage.ChiselStage

/** Emit standalone SystemVerilog of [[VDot128]] (used for the Yosys PPA study
  * and for the formal equivalence check against the previous version).
  *
  *   mill -i xiangshan.test.runMain xiangshan.backend.fu.vector.VDotVerilog <outDir> [cutLevel|-1] [acc]
  *
  * `acc` selects the accumulating 32-bit tree (vdota.vv), which is the
  * configuration instantiated in VIMacU; -1 picks the default cut.
  * The firtool options are the ones XiangShan's Makefile passes for `sim-verilog`
  * (MFC_ARGS), and the reset is asynchronous as everywhere inside the XiangShan
  * core, so the module matches what the full SoC flow emits for VDot128.
  */
object VDotVerilog extends App {
  val outDir = if (args.nonEmpty) args(0) else "build/vdot128"
  val cut = if (args.length > 1) args(1).toInt else -1
  val acc = args.length > 2 && args(2) == "acc"
  ChiselStage.emitSystemVerilogFile(
    new VDot128(cutLevel = cut, accumulate = acc) with RequireAsyncReset { override def desiredName = "VDot128" },
    Array("--target-dir", outDir),
    Array(
      "-O=release",
      "--disable-annotation-unknown",
      "--lowering-options=explicitBitcast,disallowLocalVariables,disallowPortDeclSharing,locationInfoStyle=none"
    )
  )
}
