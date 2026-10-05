# BSDS500 boundary-quality evaluation

`bsds_eval.py` compares the engine's fixed-point Sobel specification with a
float64 reference on the BSDS500 test split. The fixed-point path is
bit-exact to the RTL (it calls `golden/gen_vectors.conv3x3_int`). The
float64 path computes the same gradients without truncation or saturation.

This evaluation was re-implemented on 2026-09-30 from the protocol described
in the brief; the scripts behind the numbers in earlier drafts were lost.

## Data

BSDS500 is not redistributed here. Download it from the Berkeley site:

    https://www2.eecs.berkeley.edu/Research/Projects/CS/vision/grouping/BSR/BSR_bsds500.tgz
    (70,763,455 bytes; SHA-256 97e49d31764f3912f0c4122707d53062ac9e783ba0f095e447a4d53c1a41af8e)

and unpack it; the data directory is `BSR/BSDS500/data`.

## Run

    python eval/bsds_eval.py <BSR/BSDS500/data> --subset all   # 200 test images (reported)
    python eval/bsds_eval.py <BSR/BSDS500/data> --subset 20    # every 10th image, 20 total
    python eval/make_fig10.py <BSR/BSDS500/data>               # the brief's image-3063 figure

Python 3 with NumPy, SciPy, Pillow and matplotlib. The full run takes a few
minutes. Results go to `eval/results/` (JSON summary plus per-image CSV).

## Protocol

* Rec. 601 luminance, `Y = round(0.299 R + 0.587 G + 0.114 B)`.
* Sobel Gx/Gy on an edge-replicated 3×3 window.
  Fixed: `clamp((|Gx| + |Gy|) >> 3, 0, 255)`. Float64: `(|Gx| + |Gy|) / 8`.
* Four-direction gradient non-maximum suppression, per-image max
  normalization, 99 thresholds (0.01–0.99).
* **Relaxed matching**: tolerance 0.0075 × image diagonal (4.3 px at
  481×321). A detection is correct if it lies within tolerance of any
  annotator's boundary; a ground-truth pixel (per annotator, summed) is
  recalled if any detection lies within tolerance. **There is no
  one-to-one correspondence**, so scores are optimistic relative to the
  official benchmark.
* ODS: counts summed over images, best common threshold. OIS: counts summed
  at each image's own best threshold (BSDS definition).
* Pratt FOM at the ODS threshold, ideal edges = union of annotators,
  α = 1/9, mean ± sample standard deviation over images.

**These are internal-comparison numbers (fixed point vs float64 under one
protocol), not BSDS500 leaderboard results.**

## Results (`results/bsds500_test_all.json`, 200 test images)

| | ODS F (P, R) | OIS F | Pratt FOM |
|---|---|---|---|
| Fixed point | 0.589 (0.476, 0.775) | 0.599 | 0.304 ± 0.108 |
| Float64 | 0.589 (0.480, 0.761) | 0.600 | 0.291 ± 0.106 |

20-image subset (`--subset 20`): fixed ODS 0.619 / OIS 0.608 / Pratt
0.301 ± 0.113; float64 0.618 / 0.608 / 0.262 ± 0.105.

Earlier drafts of the brief reported, for an unrecorded 20-image subset,
ODS 0.619 / 0.618, OIS 0.646 / 0.648 and Pratt 0.310 / 0.309. Those numbers
could not be reproduced exactly and are superseded by the table above.

## Sensitivity to the normalization shift k and the kernel family

`bsds_eval.py` takes two further options (the CLI above is unchanged):

    --kernel {sobel,prewitt,scharr}   gradient kernel, Gy = Gx^T (default sobel)
    --k N                             normalization shift (default 3)

Prewitt `Gx = [[-1,0,1],[-1,0,1],[-1,0,1]]`, Scharr
`Gx = [[-3,0,3],[-10,0,10],[-3,0,3]]`; the matrices are taken from
`golden/gen_vectors.CASES`, i.e. they are the ones the RTL test vectors use.
Fixed: `clamp((|Gx| + |Gy|) >> k, 0, 255)` in int64; float64:
`(|Gx| + |Gy|) / 2^k` (no truncation, no saturation). Each run also records
the fraction of pixels (before NMS) whose fixed-point magnitude was clipped
at 255, `(|Gx| + |Gy|) >> k > 255`, pooled over all pixels of the split
(plus per-image mean / max and `frac_at_255`).

Output files are `results/bsds500_test_<subset>_<kernel>_k<k>.json` and
`_per_image.csv` (extended schema: `kernel`, `k`, `Gx`, `Gy`, saturation
fields, `fixed_minus_float64`, a `sat_frac` CSV column). For the default
setting (sobel, k = 3) the original `bsds500_test_<subset>.json` /
`_per_image.csv` are written as well, in the original schema; they are
byte-identical to the files produced before these options existed (checked
with `--subset 20`, SHA-256 `196dc1c7…` for the JSON, and on the full split,
where git reports both files unchanged).

The ten settings of the sensitivity study are run and aggregated by

    python eval/run_sensitivity.py <BSR/BSDS500/data> --jobs 4   # ~24 min with 4 processes
    python eval/run_sensitivity.py --aggregate-only              # rebuild the table only

which writes `results/sensitivity.json`, `results/sensitivity.md` and one
log per run in `results/sensitivity_logs/`.

### Finding (`results/sensitivity.md`, 200 test images)

| Kernel | k | Fixed ODS F (P, R) | Fixed OIS | Fixed Pratt | Float64 ODS F | Float64 OIS | Float64 Pratt | ΔODS | Clipped |
|---|---|---|---|---|---|---|---|---|---|
| Sobel | 0 | 0.617 (0.495, 0.817) | 0.624 | 0.424 ± 0.152 | 0.589 | 0.600 | 0.291 ± 0.106 | +0.028 | 9.06 % |
| Sobel | 1 | 0.604 (0.493, 0.780) | 0.615 | 0.331 ± 0.129 | 0.589 | 0.600 | 0.291 ± 0.106 | +0.015 | 2.05 % |
| Sobel | 2 | 0.590 (0.476, 0.776) | 0.600 | 0.300 ± 0.112 | 0.589 | 0.600 | 0.291 ± 0.106 | +0.002 | 0.05 % |
| Sobel | 3 (natural) | 0.589 (0.476, 0.775) | 0.599 | 0.304 ± 0.108 | 0.589 | 0.600 | 0.291 ± 0.106 | +0.0005 | 0 |
| Sobel | 4 | 0.590 (0.484, 0.755) | 0.594 | 0.294 ± 0.107 | 0.589 | 0.600 | 0.291 ± 0.106 | +0.001 | 0 |
| Sobel | 5 | 0.592 (0.472, 0.793) | 0.593 | 0.330 ± 0.112 | 0.589 | 0.600 | 0.291 ± 0.106 | +0.003 | 0 |
| Prewitt | 2 | 0.592 (0.476, 0.783) | 0.601 | 0.316 ± 0.111 | 0.592 | 0.602 | 0.305 ± 0.110 | +0.0003 | 0 |
| Prewitt | 3 (natural) | 0.592 (0.478, 0.779) | 0.601 | 0.318 ± 0.112 | 0.592 | 0.602 | 0.305 ± 0.110 | +0.0004 | 0 |
| Scharr | 4 | 0.588 (0.474, 0.774) | 0.597 | 0.292 ± 0.111 | 0.586 | 0.597 | 0.295 ± 0.105 | +0.002 | 0.09 % |
| Scharr | 5 (natural) | 0.586 (0.470, 0.778) | 0.595 | 0.297 ± 0.105 | 0.586 | 0.597 | 0.295 ± 0.105 | +0.0003 | 0 |

"Natural" k is the smallest shift that can never clip (max `|Gx| + |Gy|` is
2040 for Sobel, 1530 for Prewitt, 8160 for Scharr). ΔODS = fixed minus
float64. The float64 column is exactly independent of k (the per-image max
normalization cancels the 2^k scale), so k only acts on the fixed path.

* **At the natural scale the fixed/float64 ODS gap is ≤ 0.0006 for all three
  kernels** (OIS −0.001 … −0.002, Pratt +0.002 … +0.013). The kernel family
  moves ODS by at most 0.006 (Prewitt 0.592, Sobel 0.589, Scharr 0.586).
* **k above the natural scale** (Sobel k = 4, 5: 7- and 6-bit magnitudes, no
  clipping) leaves ODS within +0.003 but lowers OIS by 0.006–0.007 and raises
  Pratt by up to +0.04: coarser levels produce more ties, which the `>=`
  non-maximum suppression keeps as thicker responses.
* **k below the natural scale** clips 0.05 % (Sobel k = 2), 2.1 % (k = 1) and
  9.1 % (k = 0) of the pixels (up to 33 % in single images), and the fixed
  scores go *up* (ODS 0.604 / 0.617, Pratt 0.33 / 0.42, with the ODS
  threshold moving from 0.21 to 0.47 / 0.84). This is an artifact of the
  relaxed protocol: saturated plateaus pass the `>=` NMS as thick bands, and
  without one-to-one matching every pixel of a band near a boundary counts as
  correct. It must not be read as a benefit of saturation; Scharr k = 4
  (0.09 % clipped, +0.002 ODS) and Prewitt k = 2 (no pixel reaches the
  possible 382) show the same direction at a small scale.

In short, k = 3 for Sobel is the right engine setting (no clipping, 8-bit
range used fully), the fixed-point loss against float64 is negligible for
every kernel at its natural scale, and the comparison is insensitive to the
kernel choice; the only large effects come from saturation, and those are
inflated by the relaxed matching rather than real quality gains.
