# conv3x3-engine-zynq

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23047577.svg)](https://doi.org/10.5281/zenodo.23047577)

A runtime-programmable 3x3 convolution engine and a fixed Sobel reference
core for AMD/Xilinx Zynq-7020, with their testbenches, fixed-point reference
model, Vivado scripts and the implementation reports behind the TCAS-II
brief's resource/timing/power table.

> **Read before citing any number from this repository.**
>
> 1. **This RTL is a reconstruction.** The original design sources and Vivado
>    projects were lost. The files in `rtl/` were written in July 2026 from
>    the manuscript's own design description (engine microarchitecture,
>    register map, fixed Sobel core). They are not recovered original code.
> 2. **1920-pixel timing closure depends on the implementation directives.**
>    With default directives the engine misses 148.5 MHz by 86 ps at a line
>    width of 1920; with the ExtraTimingOpt / AggressiveExplore directives in
>    `synth/ooc_synth_strategy.tcl` both cores close (engine +0.066 ns). The
>    brief reports that flow.
> 3. **The BSDS500 evaluation code is not included** and could not be
>    located; those numbers cannot be reproduced from here (see `eval/`).
> 4. **No board-level runtime campaigns were executed.** Every hardware
>    number here is post-route, out-of-context, from Vivado. Nothing was run
>    on a Zynq board.

## Target and tools

| | |
|---|---|
| Device | XC7Z020-1 (`xc7z020clg400-1`) |
| Tool | Vivado 2026.1 (build 6511674), free Standard edition |
| Flow | Out-of-context: `synth_design -mode out_of_context`, `opt_design`, `place_design`, `phys_opt_design`, `route_design`. Default directives (`ooc_synth.tcl`, `ooc_synth_param.tcl`) or a named strategy (`ooc_synth_strategy.tcl`) |
| Clock | `aclk`, 6.734 ns period (148.5 MHz); 2.0 ns input/output delays (`synth/ooc.xdc`) |
| Line width | Parameter `W`. RTL default 160 (H = 120, CW = 9). The 1920 builds use W = 1920, H = 1080, CW = 11 (line buffers are `2**CW` deep, so 2048 x 8 each) |
| Simulator | Vivado xsim 2026.1 (Icarus Verilog also supported) |

## Layout

    rtl/conv3x3_engine.v    programmable engine: AXI4-Stream in/out + AXI4-Lite
                            (CTRL, STATUS, 18 signed 8-bit coefficients),
                            18 DSP48E1, two distributed-RAM line buffers
    rtl/sobel_fixed.v       hardwired Sobel (|Gx|+|Gy|)>>3, same streaming
                            front end, no AXI4-Lite
    tb/                     self-checking testbenches (random backpressure,
                            full-rate input, mid-frame reprogramming, any W/H),
                            vectors, run scripts, logs          -> tb/README.md
    golden/                 fixed-point (integer) reference model -> golden/README.md
    eval/                   BSDS500 evaluation: NOT INCLUDED      -> eval/README.md
    synth/                  Vivado Tcl + XDC + reports (evidence, not regenerated)
    docs/register_map.md    AXI4-Lite register map and known limitations
    docs/reproduce.md       step-by-step reproduction with expected values

There are no separate `line_buffer.v` or `axi_lite_regs.v` modules. The line
buffers (`lb1`, `lb2`) and the AXI4-Lite register file are inside
`conv3x3_engine.v`, and the line buffers are inside `sobel_fixed.v`.

## Results

All values are post-route, out-of-context, from the reports under
`synth/reports/`. Power figures are Vivado vectorless estimates (default
switching activity, confidence level "Medium").

**Reported in the brief (Table IV): W = 1920, ExtraTimingOpt strategy**
(`synth/reports/W1920_extratiming/`)

| | Sobel (fixed) | Engine |
|---|---|---|
| Total LUTs (logic + distributed RAM) | 1,531 (507 + 1,024) | 1,917 (893 + 1,024) |
| Flip-flops | 322 | 814 |
| Block RAM tiles / DSP48E1 | 0 / 0 | 0 / 18 |
| WNS @ 6.734 ns | +0.290 ns | +0.066 ns |
| Total / dynamic power | 0.118 / 0.015 W | 0.156 / 0.052 W |

**All builds**

| Build | Sobel LUT (logic + mem) | Sobel FF | Sobel WNS | Engine LUT (logic + mem) | Engine FF | Engine WNS |
|---|---|---|---|---|---|---|
| W = 160, default (`W160_july2026/`) | 575 (319 + 256) | 237 | +0.629 | 931 (675 + 256) | 622 | +0.025 |
| W = 1920, default (`W1920_default/`) | 1,532 (508 + 1,024) | 322 | +0.367 | 1,930 (906 + 1,024) | 845 | **−0.086 (fails)** |
| W = 1920, ExtraTimingOpt (`W1920_extratiming/`) | 1,531 (507 + 1,024) | 322 | +0.290 | 1,917 (893 + 1,024) | 814 | +0.066 |

Other strategies tried for the W = 1920 engine (same RTL; script
`ooc_synth_strategy.tcl`; reports not archived): `explore` +0.002 ns,
`netdelay` (ExtraNetDelay_high) +0.015 ns, `retime` (synthesis retiming +
AlternateFlowWithRetiming) −0.575 ns. With default directives the failing
paths run from a line-buffer read (`RAMD64E` → `MUXF7`/`MUXF8`) into the
multiply stage.

### Provenance of the reports

* `synth/reports/W160_july2026/` — the original July 2026 builds at the RTL default width (W = 160): `sobel_fixed_*`
  (2026-07-09 10:23) and `conv3x3_engine_*` (2026-07-09 10:44). `rtl/` is
  byte-identical to the sources of both runs.
* `synth/reports/W1920_default/` — 2026-09-29, `ooc_synth_param.tcl`.
* `synth/reports/W1920_extratiming/` — 2026-09-30, `ooc_synth_strategy.tcl
  ... extratiming`, same `rtl/`.
* A W = 160 rerun on 2026-09-29 with `ooc_synth_param.tcl` produced reports
  identical to `W160_july2026/` apart from the date and file name.
* The build host name is redacted (`<redacted>`) in every report header and
  log. Nothing else has been edited.

## Verification

| Test | Frames | Result |
|---|---|---|
| `tb_engine.v`, 4 kernels (Sobel, Scharr k=5, Gaussian single k=4, Laplacian single k=0), random gaps + backpressure, swap between frames | 2 x 160x120 | bit-exact, TB PASS (`tb/logs/`) |
| `tb_sobel_fixed.v` | 1 x 160x120 | bit-exact, TB PASS |
| `tb_engine_ext.v`, same 4 kernels, kernel written **mid-frame** | 2 x 160x120 and 2 x 1920x16 | bit-exact; the frame in flight is unaffected (`tb/logs_ext/`) |
| `tb_engine_ext.v`, **full-rate** input (TVALID back-to-back, TREADY high) | 2 x 160x120, 2 x 1920x16 | bit-exact; W pixels per W+1 cycles within a frame, plus a (W+1)-cycle bottom-border flush |
| `tb_engine_ext.v`, full-rate + mid-frame, Scharr | 2 x **1920x1080** | bit-exact; 2,076,604 cycles per frame (1080p60 frame period: 2,475,000 cycles at 148.5 MHz) |

Kernel swap (19 AXI4-Lite writes) takes 76 clock cycles in every run.

## Reproducing

Full details and expected values: `docs/reproduce.md`. From the repository
root, with Vivado 2026.1's `bin` directory on PATH:

    # 1. Reference model self-check and vector regeneration (Python 3 + NumPy)
    python golden/rtl_model.py
    python golden/gen_vectors.py                 # tb/vectors/ regenerates byte-identically
    python golden/gen_vectors_wide.py 1920 16    # tb/vectors_w1920_h16/
    python golden/gen_vectors_wide.py 1920 1080  # tb/vectors_w1920_h1080/ (not archived, ~30 MB)

    # 2. RTL simulation — every run must print "TB PASS"
    tb\run_xsim.bat          # original testbenches, 160x120
    tb\run_xsim_ext.bat      # mid-frame + full-rate, 160x120 and 1920x16
    tb\run_xsim_1080p.bat    # one 1920x1080 frame pair

    # 3. Implementation, W = 1920, strategy used in the brief
    vivado -mode batch -source synth/ooc_synth_strategy.tcl -tclargs sobel_fixed    1920 1080 11 extratiming
    vivado -mode batch -source synth/ooc_synth_strategy.tcl -tclargs conv3x3_engine 1920 1080 11 extratiming

    # 4. Other builds: W = 160 default, W = 1920 default
    vivado -mode batch -source synth/ooc_synth.tcl       -tclargs conv3x3_engine
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11

Each default implementation run takes a few minutes; the strategy runs take longer.
Compare against `synth/reports/`.

## BSDS500 evaluation protocol

**The code for this evaluation is not in this repository** (see `eval/`).
The brief describes the protocol as follows:

* Data: a **20-image subset** of the BSDS500 test set, with the dataset's
  human ground truth.
* The fixed-point pipeline (`>> 3` normalization) is compared with a
  float64 reference.
* Edges are thinned by non-maximum suppression and swept over **99
  thresholds**. ODS and OIS F-measures and Pratt's figure of merit are
  reported.
* **Relaxed matching:** a detected edge pixel counts as correct if it lies
  within **0.0075 of the image diagonal** of any ground-truth edge pixel,
  **without a one-to-one correspondence constraint**. This is more lenient
  than the standard BSDS benchmark, which enforces one-to-one matching.

**These are internal-comparison numbers (fixed point vs. float64 under one
protocol), not BSDS500 leaderboard results, and they are not comparable
with published benchmark scores.** The values reported are ODS F = 0.619
(P = 0.508, R = 0.793), OIS F = 0.646, Pratt 0.310 ± 0.111 for fixed point,
and 0.618 / 0.648 / 0.309 ± 0.110 for float64. They cannot be regenerated
from this repository.

## Scope and limitations

* **No hardware execution.** No bitstream, board design or runtime software
  is included, and none of the runtime board-level campaigns were executed.
  Throughput, latency on hardware, DDR bandwidth and real power are not
  measured anywhere here.
* **The DDR bandwidth-feasibility model is not included.**
* **Power is a vectorless estimate**, not a measurement.
* **The W = 1920 engine needs non-default implementation directives** to
  meet 148.5 MHz.
* **Single-kernel mode outputs a magnitude**, `clamp(|acc1| >> k)`, so
  kernels whose response changes sign (Laplacian, sharpening) are rectified.
* **EN = 0 is sticky until reset** (see `docs/register_map.md`).

## Citation

Cite the archive as doi:[10.5281/zenodo.23047577](https://doi.org/10.5281/zenodo.23047577)
(concept DOI; resolves to the latest version). See `CITATION.cff`.

## License

MIT, see `LICENSE`.
