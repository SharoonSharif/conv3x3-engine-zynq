# Logs of the BSDS500 sensitivity runs (task E4)

One log per setting, written by `eval/run_sensitivity.py`, which invoked

    python eval/bsds_eval.py <BSR/BSDS500/data> --subset all --out eval/results --kernel <kernel> --k <k>

for sobel k = 0..5, prewitt k = 2, 3 and scharr k = 4, 5 (10 runs, 4 at a
time, Python 3.14.3 / NumPy 2.4.2 / SciPy 1.17.1 / Pillow 12.2.0). Each log
holds the command line, the fixed / float64 summary lines, the saturation
line and the exit code with the wall time. `run_sensitivity.log` is the
driver's own output (per-run exit codes, total time, and the aggregated
table that it also wrote to `../sensitivity.md` / `../sensitivity.json`).

Absolute paths were redacted to `<repo>` before committing; the BSDS500 data
directory (`<repo>/data/BSDS500/...` in the logs) was outside the repository
(see `eval/README.md` for the download).

| Log | Setting | Result file |
|---|---|---|
| `sobel_k0.log` .. `sobel_k5.log` | Sobel, k = 0 .. 5 | `../bsds500_test_all_sobel_k<k>.json` |
| `prewitt_k2.log`, `prewitt_k3.log` | Prewitt, k = 2, 3 | `../bsds500_test_all_prewitt_k<k>.json` |
| `scharr_k4.log`, `scharr_k5.log` | Scharr, k = 4, 5 | `../bsds500_test_all_scharr_k<k>.json` |

The results table is in `../sensitivity.md`.
