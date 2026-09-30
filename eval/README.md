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
