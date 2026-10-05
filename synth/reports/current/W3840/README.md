# 4K (3840 x 2160) out-of-context builds, LUTRAM line buffers

Both cores at W = 3840, H = 2160, CW = 12 (line buffers 4096 x 8), default
directives, `synth/ooc_synth_param.tcl`, Vivado 2026.1, XC7Z020-1,
148.5 MHz (6.734 ns) constraint. Run from the repository root:

    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 3840 2160 12
    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs sobel_fixed    3840 2160 12

Reports: `<core>_W3840_{util_synth,util_impl,tim_impl,power}.rpt` (host name
and absolute paths redacted).

## Results (post-route)

| Core | LUT total | LUT logic | LUTRAM | FF | BRAM | DSP | WNS (ns) | TNS (ns) / failing endpoints | Power (W) total / dynamic |
|---|---|---|---|---|---|---|---|---|---|
| conv3x3_engine | 3,160 | 1,112 | 2,048 | 953 | 0 | 18 | **-0.273** (fails) | -5.045 / 71 | 0.170 / 0.066 |
| sobel_fixed | 2,742 | 694 | 2,048 | 420 | 0 | 0 | **-0.150** (fails) | -1.957 / 25 | 0.131 / 0.028 |

For comparison the W = 1920 (CW = 11) baselines in `../W1920/` are
1,916 LUT (892 + 1,024) / 816 FF / +0.076 ns (engine) and
1,532 LUT (508 + 1,024) / 322 FF / +0.367 ns (sobel_fixed).

Neither core closes 148.5 MHz at 4K with LUTRAM line buffers. The worst
path in both is the column counter to the 4096-deep distributed-RAM read
decode (`col_in_reg -> ... -> lb2_reg_*/DP.HIGH`, 5 logic levels
LUT6 x2 + MUXF7 x2 + RAMD64E, ~73 % routing): the line buffers double to
4096 x 8 and the read multiplexer grows by one level. The block-RAM
variant of the engine (`LB_BRAM = 1`, `../W3840_bram/`) removes this path.

## Line-buffer mapping (synthesis log, both cores)

    Distributed RAM: Final Mapping Report
    |conv3x3_engine | lb2_reg    | Implied   | 4 K x 8              | RAM128X1D x 256  |
    |conv3x3_engine | lb1_reg    | Implied   | 4 K x 8              | RAM128X1D x 256  |
    RAM128X1D => RAM128X1D (MUXF7(x2), RAMD64E(x4)): 512 instances

(`sobel_fixed` maps identically: 2 x RAM128X1D x 256 = 2,048 LUTRAM.)
