# BSDS500 sensitivity to the normalization shift k and the kernel family

200-image test split, protocol of `bsds_eval.py` (relaxed matching, internal
comparison only). Fixed: `clamp((|Gx|+|Gy|) >> k, 0, 255)`; float64:
`(|Gx|+|Gy|) / 2^k`. `Delta ODS` = fixed minus float64. `Sat.` = fraction of
pixels (before NMS) whose fixed-point magnitude was clipped at 255, pooled over
all pixels of the split. `k*` marks each kernel's natural scale (smallest k
that can never clip: Sobel 3, Prewitt 3, Scharr 5).

| Kernel | k | Fixed ODS F (P, R) | Fixed OIS F | Fixed Pratt | Float64 ODS F (P, R) | Float64 OIS F | Float64 Pratt | Delta ODS | Sat. |
|---|---|---|---|---|---|---|---|---|---|
| sobel | 0 | 0.617 (0.495, 0.817) | 0.624 | 0.424 +/- 0.152 | 0.589 (0.480, 0.761) | 0.600 | 0.291 +/- 0.106 | +0.0279 | 0.0906 |
| sobel | 1 | 0.604 (0.493, 0.780) | 0.615 | 0.331 +/- 0.129 | 0.589 (0.480, 0.761) | 0.600 | 0.291 +/- 0.106 | +0.0149 | 0.0205 |
| sobel | 2 | 0.590 (0.476, 0.776) | 0.600 | 0.300 +/- 0.112 | 0.589 (0.480, 0.761) | 0.600 | 0.291 +/- 0.106 | +0.0017 | 0.0005 |
| sobel | 3* | 0.589 (0.476, 0.775) | 0.599 | 0.304 +/- 0.108 | 0.589 (0.480, 0.761) | 0.600 | 0.291 +/- 0.106 | +0.0005 | 0.0000 |
| sobel | 4 | 0.590 (0.484, 0.755) | 0.594 | 0.294 +/- 0.107 | 0.589 (0.480, 0.761) | 0.600 | 0.291 +/- 0.106 | +0.0010 | 0.0000 |
| sobel | 5 | 0.592 (0.472, 0.793) | 0.593 | 0.330 +/- 0.112 | 0.589 (0.480, 0.761) | 0.600 | 0.291 +/- 0.106 | +0.0034 | 0.0000 |
| prewitt | 2 | 0.592 (0.476, 0.783) | 0.601 | 0.316 +/- 0.111 | 0.592 (0.481, 0.769) | 0.602 | 0.305 +/- 0.110 | +0.0003 | 0.0000 |
| prewitt | 3* | 0.592 (0.478, 0.779) | 0.601 | 0.318 +/- 0.112 | 0.592 (0.481, 0.769) | 0.602 | 0.305 +/- 0.110 | +0.0004 | 0.0000 |
| scharr | 4 | 0.588 (0.474, 0.774) | 0.597 | 0.292 +/- 0.111 | 0.586 (0.469, 0.780) | 0.597 | 0.295 +/- 0.105 | +0.0021 | 0.0009 |
| scharr | 5* | 0.586 (0.470, 0.778) | 0.595 | 0.297 +/- 0.105 | 0.586 (0.469, 0.780) | 0.597 | 0.295 +/- 0.105 | +0.0003 | 0.0000 |

ODS thresholds (fixed / float64): sobel k=0: 0.84 / 0.22, sobel k=1: 0.47 / 0.22, sobel k=2: 0.24 / 0.22, sobel k=3: 0.21 / 0.22, sobel k=4: 0.22 / 0.22, sobel k=5: 0.19 / 0.22, prewitt k=2: 0.22 / 0.23, prewitt k=3: 0.22 / 0.23, scharr k=4: 0.25 / 0.20, scharr k=5: 0.20 / 0.20

Float64 scores are exactly k-invariant per kernel (per-image max normalization cancels the 2^k scale): sobel: yes, prewitt: yes, scharr: yes.
