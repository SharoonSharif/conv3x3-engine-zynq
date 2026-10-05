#!/usr/bin/env python3
"""Sensitivity of the BSDS500 fixed-vs-float64 comparison to the normalization
shift k and to the kernel family.

Runs eval/bsds_eval.py on the full 200-image test split for every setting in
SETTINGS (up to --jobs processes at once, logs in results/sensitivity_logs/),
then aggregates results/bsds500_test_all_<kernel>_k<k>.json into
results/sensitivity.json and results/sensitivity.md.

Usage:
  python eval/run_sensitivity.py <BSDS500 data dir> [--jobs 4] [--out eval/results]
  python eval/run_sensitivity.py --aggregate-only [--out eval/results]
"""
import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
SETTINGS = [("sobel", 0), ("sobel", 1), ("sobel", 2), ("sobel", 3), ("sobel", 4), ("sobel", 5),
            ("prewitt", 2), ("prewitt", 3), ("scharr", 4), ("scharr", 5)]
# natural scale: smallest k with max(|Gx|+|Gy|) >> k <= 255 (sum of |weights| x 255 x 2)
NATURAL_K = {"sobel": 3, "prewitt": 3, "scharr": 5}


def run_one(data, out, kernel, k, log_dir):
    log = os.path.join(log_dir, f"{kernel}_k{k}.log")
    cmd = [sys.executable, os.path.join(HERE, "bsds_eval.py"), data, "--subset", "all",
           "--out", out, "--kernel", kernel, "--k", str(k)]
    env = dict(os.environ, OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1")
    t0 = time.time()
    with open(log, "w") as f:
        f.write("$ " + " ".join(cmd[1:]) + "\n")
        f.flush()
        rc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=env).returncode
        f.write(f"exit {rc} after {time.time() - t0:.0f} s\n")
    print(f"{kernel:8s} k={k}  exit {rc}  {time.time() - t0:.0f} s", flush=True)
    return rc


def aggregate(out):
    rows = []
    for kernel, k in SETTINGS:
        path = os.path.join(out, f"bsds500_test_all_{kernel}_k{k}.json")
        if not os.path.exists(path):
            print("missing", path)
            continue
        with open(path) as f:
            r = json.load(f)
        fx, fl = r["fixed"], r["float64"]
        rows.append({
            "kernel": kernel, "k": k, "natural_k": NATURAL_K[kernel], "n_images": r["protocol"]["n_images"],
            "fixed_ODS_F": fx["ODS_F"], "fixed_ODS_P": fx["ODS_P"], "fixed_ODS_R": fx["ODS_R"],
            "fixed_ODS_threshold": fx["ODS_threshold"], "fixed_OIS_F": fx["OIS_F"],
            "fixed_Pratt_mean": fx["Pratt_mean"], "fixed_Pratt_std": fx["Pratt_std"],
            "float64_ODS_F": fl["ODS_F"], "float64_ODS_P": fl["ODS_P"], "float64_ODS_R": fl["ODS_R"],
            "float64_ODS_threshold": fl["ODS_threshold"], "float64_OIS_F": fl["OIS_F"],
            "float64_Pratt_mean": fl["Pratt_mean"], "float64_Pratt_std": fl["Pratt_std"],
            "ODS_F_fixed_minus_float64": fx["ODS_F"] - fl["ODS_F"],
            "OIS_F_fixed_minus_float64": fx["OIS_F"] - fl["OIS_F"],
            "Pratt_fixed_minus_float64": fx["Pratt_mean"] - fl["Pratt_mean"],
            "saturation_frac": fx["saturation_frac"],
            "saturation_frac_image_mean": fx["saturation_frac_image_mean"],
            "saturation_frac_image_max": fx["saturation_frac_image_max"],
            "saturated_pixels": fx["saturated_pixels"], "total_pixels": fx["total_pixels"],
            "frac_at_255": fx["frac_at_255"],
        })

    # float64 is max-normalized per image, so it must be exactly k-invariant per kernel
    invariant = {}
    for kernel in dict.fromkeys(r["kernel"] for r in rows):
        vals = {(r["float64_ODS_F"], r["float64_OIS_F"], r["float64_Pratt_mean"])
                for r in rows if r["kernel"] == kernel}
        invariant[kernel] = len(vals) == 1

    res = {"description": "BSDS500 test split (200 images), fixed = clamp((|Gx|+|Gy|) >> k, 0, 255) "
                          "vs float64 = (|Gx|+|Gy|) / 2**k, same relaxed-matching protocol as "
                          "bsds_eval.py; saturation_frac = fraction of pixels (before NMS) with "
                          "(|Gx|+|Gy|) >> k > 255, pooled over all pixels of the split.",
           "float64_k_invariant_per_kernel": invariant,
           "settings": rows}
    with open(os.path.join(out, "sensitivity.json"), "w", newline="\n") as f:
        json.dump(res, f, indent=1)

    L = ["# BSDS500 sensitivity to the normalization shift k and the kernel family", "",
         "200-image test split, protocol of `bsds_eval.py` (relaxed matching, internal",
         "comparison only). Fixed: `clamp((|Gx|+|Gy|) >> k, 0, 255)`; float64:",
         "`(|Gx|+|Gy|) / 2^k`. `Delta ODS` = fixed minus float64. `Sat.` = fraction of",
         "pixels (before NMS) whose fixed-point magnitude was clipped at 255, pooled over",
         "all pixels of the split. `k*` marks each kernel's natural scale (smallest k",
         "that can never clip: Sobel 3, Prewitt 3, Scharr 5).", "",
         "| Kernel | k | Fixed ODS F (P, R) | Fixed OIS F | Fixed Pratt | Float64 ODS F (P, R) | Float64 OIS F | Float64 Pratt | Delta ODS | Sat. |",
         "|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        kk = f"{r['k']}*" if r["k"] == r["natural_k"] else str(r["k"])
        L.append(f"| {r['kernel']} | {kk} | {r['fixed_ODS_F']:.3f} ({r['fixed_ODS_P']:.3f}, {r['fixed_ODS_R']:.3f}) "
                 f"| {r['fixed_OIS_F']:.3f} | {r['fixed_Pratt_mean']:.3f} +/- {r['fixed_Pratt_std']:.3f} "
                 f"| {r['float64_ODS_F']:.3f} ({r['float64_ODS_P']:.3f}, {r['float64_ODS_R']:.3f}) "
                 f"| {r['float64_OIS_F']:.3f} | {r['float64_Pratt_mean']:.3f} +/- {r['float64_Pratt_std']:.3f} "
                 f"| {r['ODS_F_fixed_minus_float64']:+.4f} | {r['saturation_frac']:.4f} |")
    L += ["", "ODS thresholds (fixed / float64): " +
          ", ".join(f"{r['kernel']} k={r['k']}: {r['fixed_ODS_threshold']:.2f} / {r['float64_ODS_threshold']:.2f}"
                    for r in rows), "",
          "Float64 scores are exactly k-invariant per kernel (per-image max normalization "
          "cancels the 2^k scale): " +
          ", ".join(f"{k}: {'yes' if v else 'NO'}" for k, v in invariant.items()) + ".", ""]
    with open(os.path.join(out, "sensitivity.md"), "w", newline="\n") as f:
        f.write("\n".join(L))
    print("\n".join(L))
    print("wrote", os.path.join(out, "sensitivity.json"), "and sensitivity.md")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data", nargs="?")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--out", default=os.path.join(HERE, "results"))
    ap.add_argument("--aggregate-only", action="store_true")
    a = ap.parse_args()
    if not a.aggregate_only:
        if not a.data:
            ap.error("data dir required unless --aggregate-only")
        log_dir = os.path.join(a.out, "sensitivity_logs")
        os.makedirs(log_dir, exist_ok=True)
        t0 = time.time()
        with ThreadPoolExecutor(max_workers=a.jobs) as ex:
            rcs = list(ex.map(lambda s: run_one(a.data, a.out, s[0], s[1], log_dir), SETTINGS))
        print(f"all {len(SETTINGS)} runs finished in {time.time() - t0:.0f} s, exit codes {rcs}", flush=True)
        if any(rcs):
            sys.exit(1)
    aggregate(a.out)


if __name__ == "__main__":
    main()
