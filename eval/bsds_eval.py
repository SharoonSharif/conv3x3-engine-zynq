#!/usr/bin/env python3
"""BSDS500 boundary-quality evaluation: fixed-point gradient magnitude vs
float64 reference, for a selectable kernel family and normalization shift k.

Protocol (as described in the TCAS-II brief, Sec. IV-D):
  * Rec. 601 luminance, Y = round(0.299 R + 0.587 G + 0.114 B), uint8.
  * Gx/Gy of the selected kernel (--kernel sobel|prewitt|scharr, default
    sobel; Gy is the transpose of Gx) on an edge-replicated 3x3 window
    (golden/gen_vectors.conv3x3_int, int64 arithmetic).
      fixed : E = clamp((|Gx| + |Gy|) >> k, 0, 255)   (bit-exact to the RTL)
      float : E = (|Gx| + |Gy|) / 2**k                (float64, no truncation,
                                                        no saturation)
    k is the engine's normalization shift (--k, default 3 = the Sobel
    natural scale: max |Gx| + |Gy| = 2040 -> 255, so k = 3 never saturates).
  * Gradient-direction non-maximum suppression (4 directions, from Gx/Gy).
  * Per-image max normalization, then a 99-threshold sweep t = 0.01 .. 0.99.
  * Matching tolerance 0.0075 x image diagonal, RELAXED: a detected pixel is
    correct if it lies within tolerance of any ground-truth boundary pixel
    (union of annotators); a ground-truth pixel is recalled if any detected
    pixel lies within tolerance. No one-to-one correspondence is enforced, so
    scores are optimistic relative to the official benchmark.
  * ODS: counts summed over images per threshold, best F.
    OIS: counts summed at each image's own best threshold.
  * Pratt figure of merit at the ODS threshold, ideal edges = union of
    annotators, alpha = 1/9, mean +/- sample std over images.
  * Saturation: fraction of pixels (before NMS) whose fixed-point magnitude
    was clipped, i.e. (|Gx| + |Gy|) >> k > 255. Reported pooled over all
    pixels of the run and as the per-image mean / max. (frac_at_255 counts
    output pixels equal to 255, clipped or not.)

Because the float64 path is max-normalized per image, dividing by 2**k is
exactly scale-invariant: float64 scores do not depend on k. Only the fixed
path (truncation + saturation) changes with k.

These are internal-comparison scores (fixed vs float64 under one protocol),
not BSDS500 benchmark results.

Usage:
  python eval/bsds_eval.py <BSDS500 data dir> [--subset all|20] [--out eval/results]
                           [--kernel sobel|prewitt|scharr] [--k N]
  <data dir> contains images/test/*.jpg and groundTruth/test/*.mat

Outputs (in --out): bsds500_test_<subset>_<kernel>_k<k>.json and
  _per_image.csv. For the default setting (sobel, k = 3) the original file
  names bsds500_test_<subset>.json / _per_image.csv are ALSO written, in the
  original schema (no kernel/k/saturation fields), byte-identical to the
  files produced before the --kernel/--k options existed.
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy.io import loadmat
from scipy.ndimage import distance_transform_edt

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "golden"))
import contextlib, io  # noqa: E402
with contextlib.redirect_stdout(io.StringIO()):          # gen_vectors writes vectors on import
    from gen_vectors import conv3x3_int, SOBEL_GX, SOBEL_GY, CASES  # noqa: E402

THRESH = np.linspace(0.01, 0.99, 99)
TOL_FRAC = 0.0075
ALPHA = 1.0 / 9.0

# Kernel families: Gx and Gy = Gx^T. The matrices are the ones used for the
# RTL test vectors (golden/gen_vectors.CASES), so the eval and the RTL
# testbench see identical coefficients.
KERNELS = {
    "sobel":   (SOBEL_GX, SOBEL_GY),
    "prewitt": (CASES["prewitt"]["K1"], CASES["prewitt"]["K2"]),
    "scharr":  (CASES["scharr"]["K1"], CASES["scharr"]["K2"]),
}
for _name, (_gx, _gy) in KERNELS.items():
    assert np.array_equal(np.array(_gx).T, np.array(_gy)), _name + ": Gy must be Gx^T"
DEFAULT_KERNEL, DEFAULT_K = "sobel", 3


def luminance(path):
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    y = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    return np.clip(np.floor(y + 0.5), 0, 255).astype(np.uint8)


def gradients(y8, kernel=DEFAULT_KERNEL):
    gx, gy = KERNELS[kernel]
    return conv3x3_int(y8, np.array(gx)), conv3x3_int(y8, np.array(gy))


def magnitude(gx, gy, precision, k=DEFAULT_K):
    s = np.abs(gx) + np.abs(gy)                       # int64
    if precision == "fixed":
        return np.clip(s >> k, 0, 255).astype(np.float64)
    return s.astype(np.float64) / float(2 ** k)


def saturation(gx, gy, k=DEFAULT_K):
    """(clipped pixels, pixels equal to 255 after clamp, total pixels), before NMS."""
    q = (np.abs(gx) + np.abs(gy)) >> k
    return int((q > 255).sum()), int((q >= 255).sum()), int(q.size)


def nms(mag, gx, gy):
    """Keep pixels that are >= both neighbours along the gradient direction."""
    ang = (np.degrees(np.arctan2(gy, gx)) + 180.0) % 180.0
    p = np.pad(mag, 1, mode="edge")
    H, W = mag.shape
    c = lambda dy, dx: p[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]  # noqa: E731
    d0 = (ang < 22.5) | (ang >= 157.5)          # gradient ~ horizontal
    d45 = (ang >= 22.5) & (ang < 67.5)
    d90 = (ang >= 67.5) & (ang < 112.5)
    d135 = (ang >= 112.5) & (ang < 157.5)
    keep = np.zeros_like(mag, dtype=bool)
    keep |= d0 & (mag >= c(0, -1)) & (mag >= c(0, 1))
    keep |= d90 & (mag >= c(-1, 0)) & (mag >= c(1, 0))
    keep |= d45 & (mag >= c(-1, 1)) & (mag >= c(1, -1))
    keep |= d135 & (mag >= c(-1, -1)) & (mag >= c(1, 1))
    return np.where(keep & (mag > 0), mag, 0.0)


def load_gt(path):
    gt = loadmat(path)["groundTruth"]
    return [gt[0, i]["Boundaries"][0, 0].astype(bool) for i in range(gt.shape[1])]


def image_counts(E, gts):
    """Per-threshold (cntR, sumR, cntP, sumP) plus the distance map to the GT union."""
    H, W = E.shape
    tol = TOL_FRAC * np.hypot(H, W)
    union = np.logical_or.reduce(gts)
    dt_union = distance_transform_edt(~union)
    sumR_img = sum(int(b.sum()) for b in gts)
    out = np.zeros((len(THRESH), 4), dtype=np.int64)
    for i, t in enumerate(THRESH):
        D = E >= t
        nD = int(D.sum())
        cntP = int((D & (dt_union <= tol)).sum())
        if nD:
            dt_det = distance_transform_edt(~D)
            cntR = sum(int((b & (dt_det <= tol)).sum()) for b in gts)
        else:
            cntR = 0
        out[i] = (cntR, sumR_img, cntP, nD)
    return out, union, dt_union


def prf(cntR, sumR, cntP, sumP):
    R = cntR / sumR if sumR else 0.0
    P = cntP / sumP if sumP else 0.0
    F = 2 * P * R / (P + R) if (P + R) else 0.0
    return P, R, F


def pratt(D, union, dt_union):
    nI, nD = int(union.sum()), int(D.sum())
    if max(nI, nD) == 0:
        return 0.0
    d = dt_union[D]
    return float(np.sum(1.0 / (1.0 + ALPHA * d * d)) / max(nI, nD))


def write_outputs(out_dir, tag, results, rows, extended):
    with open(os.path.join(out_dir, tag + ".json"), "w", newline="\n") as f:
        json.dump(results, f, indent=1)
    with open(os.path.join(out_dir, tag + "_per_image.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["precision", "image", "P_at_ODS", "R_at_ODS", "F_at_ODS", "Pratt_at_ODS"]
                   + (["sat_frac"] if extended else []))
        w.writerows(rows if extended else [r[:6] for r in rows])
    print("wrote", os.path.join(out_dir, tag + ".json"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data")
    ap.add_argument("--subset", default="all", choices=["all", "20"])
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "results"))
    ap.add_argument("--kernel", default=DEFAULT_KERNEL, choices=sorted(KERNELS))
    ap.add_argument("--k", default=DEFAULT_K, type=int,
                    help="normalization shift: fixed = clamp(s >> k), float = s / 2**k (default 3)")
    a = ap.parse_args()
    if a.k < 0:
        ap.error("--k must be >= 0")

    ids = sorted((f[:-4] for f in os.listdir(os.path.join(a.data, "images", "test"))
                  if f.endswith(".jpg")), key=int)
    if a.subset == "20":
        ids = ids[::10][:20]          # every 10th test image in numeric-ID order
    os.makedirs(a.out, exist_ok=True)

    results = {"protocol": {"thresholds": 99, "tolerance_frac_diag": TOL_FRAC,
                            "matching": "relaxed (no one-to-one correspondence)",
                            "pratt_alpha": ALPHA, "subset": a.subset, "n_images": len(ids),
                            "image_ids": ids}}
    per_image_rows = []
    sat_frac_img = []
    sat_clip = sat_255 = sat_total = 0
    for prec in ("fixed", "float64"):
        counts, cache = [], []
        for iid in ids:
            y = luminance(os.path.join(a.data, "images", "test", iid + ".jpg"))
            gx, gy = gradients(y, a.kernel)
            if prec == "fixed":
                nclip, n255, npix = saturation(gx, gy, a.k)
                sat_clip, sat_255, sat_total = sat_clip + nclip, sat_255 + n255, sat_total + npix
                sat_frac_img.append(nclip / npix)
            m = nms(magnitude(gx, gy, "fixed" if prec == "fixed" else "float", a.k), gx, gy)
            E = m / m.max() if m.max() > 0 else m
            gts = load_gt(os.path.join(a.data, "groundTruth", "test", iid + ".mat"))
            c, union, dtu = image_counts(E, gts)
            counts.append(c)
            cache.append((E, union, dtu))
        C = np.stack(counts)                       # images x thresholds x 4
        tot = C.sum(axis=0)
        f_ods = [prf(*row)[2] for row in tot]
        k = int(np.argmax(f_ods))
        P, R, F = prf(*tot[k])
        best = [int(np.argmax([prf(*row)[2] for row in c])) for c in counts]
        ois = np.sum([counts[i][best[i]] for i in range(len(ids))], axis=0)
        _, _, F_ois = prf(*ois)
        pr = [pratt(E >= THRESH[k], u, d) for (E, u, d) in cache]
        results[prec] = {"ODS_F": F, "ODS_P": P, "ODS_R": R, "ODS_threshold": float(THRESH[k]),
                         "OIS_F": F_ois, "Pratt_mean": float(np.mean(pr)),
                         "Pratt_std": float(np.std(pr, ddof=1))}
        for i, iid in enumerate(ids):
            per_image_rows.append([prec, iid, *prf(*counts[i][k]), pr[i],
                                   sat_frac_img[i] if prec == "fixed" else ""])
        print(f"{prec:8s} ODS F={F:.3f} (P={P:.3f}, R={R:.3f}, t={THRESH[k]:.2f})  "
              f"OIS F={F_ois:.3f}  Pratt={np.mean(pr):.3f} +/- {np.std(pr, ddof=1):.3f}  "
              f"[{len(ids)} images, {a.kernel} k={a.k}]")
    print(f"fixed    saturation (clipped before NMS): {sat_clip}/{sat_total} = "
          f"{sat_clip / sat_total:.6f}  (per-image mean {np.mean(sat_frac_img):.6f}, "
          f"max {np.max(sat_frac_img):.6f}; at 255: {sat_255 / sat_total:.6f})")

    # Original file names / schema for the default setting (byte-identical to
    # the output produced before --kernel/--k existed).
    if a.kernel == DEFAULT_KERNEL and a.k == DEFAULT_K:
        write_outputs(a.out, f"bsds500_test_{a.subset}", results, per_image_rows, False)

    # Extended schema, file name tagged with kernel and k.
    gx_m, gy_m = KERNELS[a.kernel]
    results["protocol"].update({"kernel": a.kernel, "k": a.k, "Gx": gx_m, "Gy": gy_m,
                                "fixed": f"clamp((|Gx|+|Gy|) >> {a.k}, 0, 255)",
                                "float64": f"(|Gx|+|Gy|) / {2 ** a.k}"})
    results["fixed"].update({"saturation_frac": sat_clip / sat_total,
                             "saturation_frac_image_mean": float(np.mean(sat_frac_img)),
                             "saturation_frac_image_max": float(np.max(sat_frac_img)),
                             "saturated_pixels": sat_clip, "total_pixels": sat_total,
                             "frac_at_255": sat_255 / sat_total})
    results["fixed_minus_float64"] = {m: results["fixed"][m] - results["float64"][m]
                                      for m in ("ODS_F", "OIS_F", "Pratt_mean")}
    write_outputs(a.out, f"bsds500_test_{a.subset}_{a.kernel}_k{a.k}", results, per_image_rows, True)


if __name__ == "__main__":
    main()
