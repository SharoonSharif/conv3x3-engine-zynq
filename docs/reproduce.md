# Reproduction guide

Everything runs from the repository root. Tested on Windows 11 with
Vivado / Vitis HLS 2026.1 (build 6511674) and Python 3.14 + NumPy 2.4.

## 0. Prerequisites

* Vivado ML 2026.1, free Standard edition, with Zynq-7000 device support.
  Put `<install>\Vivado\bin` on PATH, or run inside the "Vivado Tcl Shell".
  (On Windows, `settings64.bat` changes the working directory, so `cd` back
  to the repository root after calling it.)
* Python 3 with NumPy (steps 1 and 6), plus SciPy, Pillow and matplotlib
  (step 6).
* Optional: Icarus Verilog >= 11 instead of xsim. Vitis HLS and the Vitis
  Vision headers are needed for step 5 only.

## 1. Reference model

    python golden/rtl_model.py

Expected: `PASS` for sobel, scharr, gaussian, laplacian, prewitt and
sharpen, then `random x24 + degenerate H + signed x12 (all PASS)`.

    python golden/gen_vectors.py

Expected checksums: `sobel=156112, scharr=158612, gaussian=2491069,
laplacian=349497, prewitt=113197, sharpen=2475743`; `git status` shows no
change under `tb/vectors/`.

## 2. RTL simulation

    python golden/gen_vectors_wide.py 1920 16
    python golden/gen_vectors_wide.py 1920 1080
    tb\run_xsim.bat
    tb\run_xsim_ext.bat
    tb\run_xsim_1080p.bat

All 25 logs (`tb/logs/`, `tb/logs_ext/`) must end in `TB PASS`. Every
kernel swap reports `coefficient-swap programming: 76 clock cycles`. The
EN-pause runs report `EN pause: input held for 300 cycles`. Full-rate
throughput lines:

| Run | cycles, first input to last output, frame 1 |
|---|---|
| 160x120 | 19,484 (1.0148 cycles/px) |
| 1920x16 | 32,660 (1.0632 cycles/px) |
| 1920x1080 | 2,076,604 (1.0014 cycles/px) |

## 3. Implementation at W = 1920 (brief, Table IV)

    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs sobel_fixed    1920 1080 11
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11

Arguments are `<top> <W> <H> <CW>`, where `2**CW` must exceed `W + 1`.
Default directives. Compare with `synth/reports/current/W1920/`:

| Report / field | sobel_fixed | conv3x3_engine |
|---|---|---|
| `*_util_impl.rpt` Total / Logic / LUTRAM | 1,532 / 508 / 1,024 | 1,916 / 892 / 1,024 |
| `*_util_impl.rpt` FF / RAMB36 / RAMB18 / DSP | 322 / 0 / 0 / 0 | 816 / 0 / 0 / 18 |
| `*_tim_impl.rpt` WNS / TNS (ns) | 0.367 / 0.000 | 0.076 / 0.000 |
| `*_power.rpt` Total / Dynamic (W) | 0.118 / 0.015 | 0.156 / 0.053 |

`vivado.log` should show `Parameter W bound to: 1920` and the line buffers
as `2 K x 8` distributed RAM (`RAM128X1D x 128`).

## 4. Implementation at W = 160

    vivado -mode batch -source synth/ooc_synth.tcl -tclargs sobel_fixed
    vivado -mode batch -source synth/ooc_synth.tcl -tclargs conv3x3_engine

Compare with `synth/reports/current/W160/`: Sobel 575 / 319 / 256 LUT,
237 FF, WNS 0.629; engine 953 / 697 / 256 LUT, 636 FF, 18 DSP, WNS 0.064.

## 5. Vitis Vision `filter2D` baseline

See `compare/vitis_filter2d/README.md`. Expected with default directives:
956 LUT (874 logic + 82 memory), 1,392 FF, 3 RAMB18, 9 DSP, WNS 0.427 ns.
C simulation: 0 mismatches on interior pixels versus the engine's signed
single-kernel output.

## 6. Other scripts

    python model/ddr_model.py                          # brief Tables I and II
    python eval/bsds_eval.py <BSR/BSDS500/data> --subset all
    python eval/make_fig10.py <BSR/BSDS500/data>

## Determinism note

Vivado place and route is deterministic for a fixed tool build, part, source
and constraint set on the same host; a W = 160 rerun on 2026-09-29
reproduced the July 2026 fixed-core reports exactly. Another OS, tool build
or host CPU count can shift placement, and with it WNS and the LUT counts,
by small amounts.
