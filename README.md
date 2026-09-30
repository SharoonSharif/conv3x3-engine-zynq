# conv3x3-engine-zynq

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23047577.svg)](https://doi.org/10.5281/zenodo.23047577)

A runtime-programmable 3x3 convolution engine and a fixed Sobel reference
core for AMD/Xilinx Zynq-7020, with testbenches, a fixed-point reference
model, Vivado scripts and reports, a Vitis Vision `filter2D` baseline, the
BSDS500 evaluation, and the DDR feasibility-model script behind the TCAS-II
brief.

> **Read before citing any number from this repository.**
>
> 1. **This RTL is a reconstruction.** The original design sources and Vivado
>    projects were lost. The files in `rtl/` were written in July 2026 from
>    the manuscript's own design description and revised on 2026-09-30
>    (signed single-kernel mode, immediate EN, one timing register). They are
>    not recovered original code.
> 2. **No board-level runtime campaigns were executed.** Every hardware
>    number here is post-route, out-of-context, from Vivado; power is a
>    vectorless estimate. Nothing was run on a Zynq board.
> 3. **The BSDS500 evaluation was re-implemented** on 2026-09-30 (`eval/`);
>    the original scripts were lost, and the numbers from earlier drafts are
>    superseded.

## Target and tools

| | |
|---|---|
| Device | XC7Z020-1 (`xc7z020clg400-1`) |
| Tools | Vivado 2026.1 (build 6511674), Vitis HLS 2026.1; free Standard edition |
| Flow | Out-of-context: `synth_design -mode out_of_context`, `opt_design`, `place_design`, `phys_opt_design`, `route_design`, **default directives** (`synth/ooc_synth.tcl`, `synth/ooc_synth_param.tcl`). `synth/ooc_synth_strategy.tcl` runs named directive sets |
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
                            full-rate input, mid-frame reprogramming, EN pause,
                            any W/H), vectors, run scripts, logs  -> tb/README.md
    golden/                 fixed-point (integer) reference model -> golden/README.md
    compare/vitis_filter2d/ Vitis Vision filter2D baseline (HLS)  -> its README.md
    model/ddr_model.py      DDR feasibility model: reproduces Tables I and II
    eval/                   BSDS500 evaluation script + results   -> eval/README.md
    synth/                  Vivado Tcl + XDC + reports (evidence, not regenerated)
    docs/register_map.md    AXI4-Lite register map
    docs/reproduce.md       step-by-step reproduction with expected values

There are no separate `line_buffer.v` or `axi_lite_regs.v` modules. The line
buffers (`lb1`, `lb2`) and the AXI4-Lite register file are inside
`conv3x3_engine.v`, and the line buffers are inside `sobel_fixed.v`.

## Results

Post-route, out-of-context, default directives, from
`synth/reports/current/` and `compare/vitis_filter2d/reports/`. Power
figures are Vivado vectorless estimates (confidence level "Medium").

**Brief, Table IV: W = 1920**

| | LUT (logic + mem) | FF | BRAM tiles | DSP | WNS @ 6.734 ns | Power total / dyn |
|---|---|---|---|---|---|---|
| Sobel (fixed) | 1,532 (508 + 1,024) | 322 | 0 | 0 | +0.367 ns | 0.118 / 0.015 W |
| Programmable engine | 1,916 (892 + 1,024) | 816 | 0 | 18 | +0.076 ns | 0.156 / 0.053 W |
| Vitis Vision `filter2D`, 1 kernel | 956 (874 + 82) | 1,392 | 1.5 | 9 | +0.427 ns | 0.131 / 0.028 W |

**W = 160 (RTL default width)**: Sobel 575 LUT (319 + 256), 237 FF, +0.629 ns;
engine 953 LUT (697 + 256), 636 FF, 18 DSP, +0.064 ns.

### Provenance of the reports

* `synth/reports/current/` — reports for the RTL in this commit.
  `conv3x3_engine_W*` from 2026-09-30; `sobel_fixed_W1920_*` from
  2026-09-29; `sobel_fixed_*` (W = 160) from 2026-07-09. `sobel_fixed.v` has
  not changed since July, so the older fixed-core reports still apply.
* `synth/reports/history/` — engine reports for the RTL of release v1.1.0
  and earlier (before the SIGNED/EN/`lrep` change). At W = 1920 that RTL
  failed timing with default directives (−0.086 ns) and closed only with
  the ExtraTimingOpt directive set (+0.066 ns). Registering the left-border
  flag `lrep` removed the critical compare from the window-mux → DSP path,
  so the current RTL closes with default directives.
* `compare/vitis_filter2d/reports/` — Vitis HLS csynth report and Vivado
  implementation reports for the baseline, both flows.
* The build host name is redacted (`<redacted>`) in every report header and
  log. Nothing else has been edited.

## Verification (`tb/logs/`, `tb/logs_ext/`; 25 runs, all TB PASS)

| Test | Frames | Result |
|---|---|---|
| `tb_engine.v`, 6 kernels: Sobel, Scharr (k=5), Prewitt (k=3), Gaussian (single, k=4), Laplacian (single, k=0), sharpen (single **signed**, k=0); random gaps + backpressure | 2 x 160x120 | bit-exact |
| `tb_sobel_fixed.v` | 1 x 160x120 | bit-exact |
| `tb_engine_ext.v`, same 6 kernels, kernel written **mid-frame** | 2 x 160x120 and 2 x 1920x16 | bit-exact; the frame in flight is unaffected |
| `tb_engine_ext.v`, **full-rate** input (TVALID back-to-back, TREADY high) | 2 x 160x120, 2 x 1920x16 | bit-exact; W pixels per W+1 cycles within a frame, plus a (W+1)-cycle bottom-border flush |
| `tb_engine_ext.v`, full rate + mid-frame, Scharr | 2 x **1920x1080** | bit-exact; 2,076,604 cycles per frame (1080p60 frame period: 2,475,000 cycles at 148.5 MHz) |
| `tb_engine_ext.v`, **EN pause**: CTRL.EN = 0 mid-frame for 300 cycles, then 1 | 160x120; 1920x16 at full rate | no input accepted while paused; both frames bit-exact |
| `compare/vitis_filter2d` C simulation vs the engine's signed single-kernel output | 160x120 | 0 mismatches on all interior pixels (borders differ by design) |

A kernel swap (19 AXI4-Lite writes) takes 76 clock cycles in every run.

## Reproducing

Full details and expected values: `docs/reproduce.md`. From the repository
root, with Vivado 2026.1's `bin` directory on PATH:

    # 1. Reference model self-check and vector regeneration (Python 3 + NumPy)
    python golden/rtl_model.py
    python golden/gen_vectors.py                 # tb/vectors/
    python golden/gen_vectors_wide.py 1920 16    # tb/vectors_w1920_h16/
    python golden/gen_vectors_wide.py 1920 1080  # tb/vectors_w1920_h1080/ (not archived, ~30 MB)

    # 2. RTL simulation — every run must print "TB PASS"
    tb\run_xsim.bat          # original testbenches, 160x120, 6 kernels
    tb\run_xsim_ext.bat      # mid-frame, full rate, EN pause; 160x120 and 1920x16
    tb\run_xsim_1080p.bat    # one 1920x1080 frame pair

    # 3. Implementation, W = 1920 (Table IV), default directives
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs sobel_fixed    1920 1080 11
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11

    # 4. W = 160
    vivado -mode batch -source synth/ooc_synth.tcl -tclargs conv3x3_engine

    # 5. Vitis Vision baseline: see compare/vitis_filter2d/README.md

Each implementation run takes a few minutes. Compare against `synth/reports/current/`.

## BSDS500 evaluation protocol

Script and results: `eval/` (see `eval/README.md`; BSDS500 itself is
downloaded separately).

* Data: all **200 images of the BSDS500 test split**, with the dataset's
  human ground truth (a 20-image subset option is also provided).
* The fixed-point pipeline (`>> 3` normalization, bit-exact to the RTL) is
  compared with a float64 reference without truncation or saturation.
* Edges are thinned by four-direction non-maximum suppression, normalized
  per image, and swept over **99 thresholds**. ODS and OIS F-measures and
  Pratt's figure of merit are reported.
* **Relaxed matching:** a detected edge pixel counts as correct if it lies
  within **0.0075 of the image diagonal** of any ground-truth edge pixel,
  **without a one-to-one correspondence constraint**. This is more lenient
  than the standard BSDS benchmark, which enforces one-to-one matching.

**These are internal-comparison numbers (fixed point vs. float64 under one
protocol), not BSDS500 leaderboard results, and they are not comparable
with published benchmark scores.**

| 200 test images | ODS F (P, R) | OIS F | Pratt FOM |
|---|---|---|---|
| Fixed point | 0.589 (0.476, 0.775) | 0.599 | 0.304 ± 0.108 |
| Float64 | 0.589 (0.480, 0.761) | 0.600 | 0.291 ± 0.106 |

## Scope and limitations

* **No hardware execution.** No bitstream, board design or runtime software
  is included, and none of the runtime board-level campaigns were executed.
  Throughput, latency on hardware, DDR bandwidth and real power are not
  measured anywhere here.
* **The DDR bandwidth-feasibility model** is included as equations only
  (`model/ddr_model.py` reproduces the brief's Tables I and II); its inputs
  from the conference system are not re-measured.
* **Power is a vectorless estimate**, not a measurement.
* The `filter2D` baseline implements one kernel with zero-padded borders; the
  engine implements two kernels with edge replication. See
  `compare/vitis_filter2d/README.md`.

## Citation

Cite the archive as doi:[10.5281/zenodo.23047577](https://doi.org/10.5281/zenodo.23047577)
(concept DOI; resolves to the latest version). See `CITATION.cff`.

## License

MIT, see `LICENSE`.
