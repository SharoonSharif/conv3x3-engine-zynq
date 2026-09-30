#!/usr/bin/env python3
"""BSDS500 boundary-quality evaluation: fixed-point Sobel vs float64 reference.

Protocol (as described in the TCAS-II brief, Sec. IV-D):
  * Rec. 601 luminance, Y = round(0.299 R + 0.587 G + 0.114 B), uint8.
  * Sobel Gx/Gy on an edge-replicated 3x3 window (golden/gen_vectors.conv3x3_int).
      fixed : E = clamp((|Gx| + |Gy|) >> 3, 0, 255)   (bit-exact to the RTL)
      float : E = (|Gx| + |Gy|) / 8                   (float64, no truncation,
                                                        no saturation)
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

These are internal-comparison scores (fixed vs float64 under one protocol),
not BSDS500 benchmark results.

Usage:
  python eval/bsds_eval.py <BSDS500 data dir> [--subset all|20] [--out eval/results]
  <data dir> contains images/test/*.jpg and groundTruth/test/*.mat
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
    from gen_vectors import conv3x3_int, SOBEL_GX, SOBEL_GY  # noqa: E402

THRESH = np.linspace(0.01, 0.99, 99)
TOL_FRAC = 0.0075
ALPHA = 1.0 / 9.0


def luminance(path):
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    y = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    return np.clip(np.floor(y + 0.5), 0, 255).astype(np.uint8)


def gradients(y8):
    return conv3x3_int(y8, np.array(SOBEL_GX)), conv3x3_int(y8, np.array(SOBEL_GY))


def magnitude(gx, gy, precision):
    s = np.abs(gx) + np.abs(gy)
    if precision == "fixed":
        return np.clip(s >> 3, 0, 255).astype(np.float64)
    return s.astype(np.float64) / 8.0


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("data")
    ap.add_argument("--subset", default="all", choices=["all", "20"])
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "results"))
    a = ap.parse_args()

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
    for prec in ("fixed", "float64"):
        counts, cache = [], []
        for iid in ids:
            y = luminance(os.path.join(a.data, "images", "test", iid + ".jpg"))
            gx, gy = gradients(y)
            m = nms(magnitude(gx, gy, "fixed" if prec == "fixed" else "float"), gx, gy)
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
            per_image_rows.append([prec, iid, *prf(*counts[i][k]), pr[i]])
        print(f"{prec:8s} ODS F={F:.3f} (P={P:.3f}, R={R:.3f}, t={THRESH[k]:.2f})  "
              f"OIS F={F_ois:.3f}  Pratt={np.mean(pr):.3f} +/- {np.std(pr, ddof=1):.3f}  "
              f"[{len(ids)} images]")

    tag = f"bsds500_test_{a.subset}"
    with open(os.path.join(a.out, tag + ".json"), "w", newline="\n") as f:
        json.dump(results, f, indent=1)
    with open(os.path.join(a.out, tag + "_per_image.csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["precision", "image", "P_at_ODS", "R_at_ODS", "F_at_ODS", "Pratt_at_ODS"])
        w.writerows(per_image_rows)
    print("wrote", os.path.join(a.out, tag + ".json"))


if __name__ == "__main__":
    main()
