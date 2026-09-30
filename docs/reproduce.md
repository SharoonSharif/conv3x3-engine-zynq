# Reproduction guide

Everything runs from the repository root. Tested on Windows 11 with
Vivado 2026.1 (build 6511674) and Python 3.14 + NumPy 2.4.

## 0. Prerequisites

* Vivado ML 2026.1, free Standard edition, with Zynq-7000 device support.
  Put `<install>\Vivado\bin` on PATH, or run inside the "Vivado Tcl Shell".
  (On Windows, `settings64.bat` changes the working directory, so `cd` back
  to the repository root after calling it.)
* Python 3 with NumPy, for step 1 only.
* Optional: Icarus Verilog >= 11 instead of xsim.

## 1. Golden model

    python golden/rtl_model.py

Expected: `PASS` for sobel, scharr, gaussian and laplacian, then
`random x24 + degenerate H (all PASS)`.

    python golden/gen_vectors.py

Expected: `checksums: sobel=156112, scharr=158612, gaussian=2491069,
laplacian=349497`. `git status` shows no change under `tb/vectors/`.

## 2. RTL simulation

    tb\run_xsim.bat

Expected, for each of the four engine runs:

    frame1 (reset Sobel): 0 mismatches / 19200 px
    coefficient-swap programming: 76 clock cycles (19 AXI4-Lite writes)
    frame2 (swapped kernel): 0 mismatches / 19200 px
    TB PASS: both frames bit-exact; tlast count = 240 (exp 240)

and for the fixed core:

    TB PASS: sobel_fixed bit-exact over 19200 px; tlast count = 120 (exp 120)

## 3. Implementation at W = 160 (RTL default width)

    vivado -mode batch -source synth/ooc_synth.tcl -tclargs sobel_fixed
    vivado -mode batch -source synth/ooc_synth.tcl -tclargs conv3x3_engine

Compare with `synth/reports/W160_july2026/`:

| Report / field | sobel_fixed | conv3x3_engine |
|---|---|---|
| `*_util_impl.rpt` Total LUTs / Logic LUTs / LUTRAMs | 575 / 319 / 256 | 931 / 675 / 256 |
| `*_util_impl.rpt` FFs / RAMB36 / RAMB18 / DSP | 237 / 0 / 0 / 0 | 622 / 0 / 0 / 18 |
| `*_tim_impl.rpt` WNS / TNS | 0.629 / 0.000 | 0.025 / 0.000 |
| `*_power.rpt` Total / Dynamic / Static (W) | 0.114 / 0.012 / 0.103 | 0.164 / 0.061 / 0.103 |

`vivado.log` should show `lb1_reg` / `lb2_reg` as `512 x 8` distributed RAM
(`RAM128X1D x 32`) and `Parameter W bound to: 160`.

## 4. Implementation at W = 1920

    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs sobel_fixed    1920 1080 11
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11

Arguments are `<top> <W> <H> <CW>`, where `2**CW` must exceed `W + 1`.
Compare with `synth/reports/W1920/`:

| Report / field | sobel_fixed | conv3x3_engine |
|---|---|---|
| Total LUTs / Logic LUTs / LUTRAMs | 1,532 / 508 / 1,024 | 1,930 / 906 / 1,024 |
| FFs / BRAM / DSP | 322 / 0 / 0 | 845 / 0 / 18 |
| WNS / TNS (ns) | 0.367 / 0.000 | **−0.086 / −0.230 (3 failing endpoints)** |
| Total / Dynamic power (W) | 0.118 / 0.015 | 0.157 / 0.054 |

The log should show the line buffers as `2 K x 8` (`RAM128X1D x 128`) and
`Parameter W bound to: 1920`.

## Determinism note

Vivado place and route is deterministic for a fixed tool build, part, source
and constraint set on the same host. On 2026-09-29 the W = 160 runs
reproduced the July 2026 reports exactly. Another OS, tool build or host CPU
count can shift placement, and with it WNS and the LUT counts, by small
amounts.

## 5. Implementation at W = 1920 with the ExtraTimingOpt strategy (brief, Table IV)

    vivado -mode batch -source synth/ooc_synth_strategy.tcl -tclargs sobel_fixed    1920 1080 11 extratiming
    vivado -mode batch -source synth/ooc_synth_strategy.tcl -tclargs conv3x3_engine 1920 1080 11 extratiming

Directives: `opt_design -directive Explore`, `place_design -directive
ExtraTimingOpt`, `phys_opt_design -directive AggressiveExplore`,
`route_design -directive AggressiveExplore`, then a post-route
`phys_opt_design -directive AggressiveExplore`. Compare with
`synth/reports/W1920_extratiming/`:

| Report / field | sobel_fixed | conv3x3_engine |
|---|---|---|
| Total LUTs / Logic LUTs / LUTRAMs | 1,531 / 507 / 1,024 | 1,917 / 893 / 1,024 |
| FFs / BRAM / DSP | 322 / 0 / 0 | 814 / 0 / 18 |
| WNS / TNS (ns) | 0.290 / 0.000 | 0.066 / 0.000 |
| Total / Dynamic power (W) | 0.118 / 0.015 | 0.156 / 0.052 |

Other strategy names accepted by the script: `default_flow`, `explore`,
`netdelay`, `retime` (see the README for their W = 1920 engine results).

## 6. Extended simulation (mid-frame reprogramming, full rate, 1920 wide)

    python golden/gen_vectors_wide.py 1920 16
    tb\run_xsim_ext.bat
    python golden/gen_vectors_wide.py 1920 1080
    tb\run_xsim_1080p.bat

Every log in `tb/logs_ext/` must end in `TB PASS`. Expected throughput lines:

| Run | cycles first-in to last-out per frame |
|---|---|
| 160x120, full rate | 19,484 (1.0148 cycles/px) |
| 1920x16, full rate | 32,660 (1.0632 cycles/px) |
| 1920x1080, full rate | 2,076,604 (1.0014 cycles/px) |

With random gaps and backpressure the cycle counts are larger and depend on
the LFSR seeds in the testbench.
