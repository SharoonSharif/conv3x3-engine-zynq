# LB_BRAM = 0 gate: W = 1920 rebuild after adding the LB_BRAM parameter

Purpose: prove that the `LB_BRAM` parameter (default 0) added to
`rtl/conv3x3_engine.v` leaves the LUTRAM engine unchanged. Same command as
the baseline in `../W1920/` (default directives, 4-argument form, so the
generic is not even passed to `synth_design`):

    vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs conv3x3_engine 1920 1080 11

## Result

| Build | LUT total | LUT logic | LUTRAM | FF | BRAM | DSP | WNS (ns) | Power (W) total / dynamic |
|---|---|---|---|---|---|---|---|---|
| baseline `../W1920/` (commit 6758070) | 1,916 | 892 | 1,024 | 816 | 0 | 18 | +0.076 | 0.156 / 0.053 |
| this rebuild (LB_BRAM parameter present, = 0) | 1,916 | 892 | 1,024 | 816 | 0 | 18 | +0.076 | 0.156 / 0.053 |

All four report files are line-identical to the baseline's apart from the
`Date` line (checked with `diff` after redaction), i.e. the post-synthesis
cell list, the placed/routed utilization, every timing path and the power
estimate are the same. The LB_BRAM = 0 code path is today's code at module
scope; the LB_BRAM = 1 differences are behind constant `if (LB_BRAM == 0)`
tests that Vivado folds at elaboration and a `generate if (LB_BRAM != 0)`
block.

Note: a first attempt that moved the LUTRAM arrays and the streaming
process into a named generate block (`g_lb_lut`) was *not* identical:
1,921 LUT (897 + 1,024) / 816 FF / 18 DSP / WNS +0.222 ns, with the
post-synthesis netlist already differing by 2 LUTs. That variant was
discarded in favour of the module-scope form above.
