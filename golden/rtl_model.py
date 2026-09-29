#!/usr/bin/env python3
"""Transaction-level replica of conv3x3_engine.v's streaming microarchitecture.

Models the exact push pipeline the RTL implements (per push event; AXI
stalls are orthogonal since the whole datapath shares one clock-enable):

  * every accepted pixel (row r >= 1) forms a vertical triple
      bot = pix(r, c)
      mid = lb1[c]            (row r-1)
      top = lb1[c] if r == 1 else lb2[c]     (top-border replication)
    and AFTER the memory read, lb2[c] <- lb1[c], lb1[c] <- pix.
  * after each row's EOL, one extra push repeats the last triple
    (right-border replication).
  * after the last input row, a synthetic row is pushed reading
    top = lb2[c], mid = bot = lb1[c] (bottom-border replication),
    followed by its own right-edge repeat push.
  * per output row, pushes are numbered p = 1..W+1; after push p >= 2 the
    MAC stage consumes the post-push taps (t0, t1, t2) = triples from pushes
    (p-2, p-1, p) and emits center column p-2, substituting t1 for t0 when
    p == 2 (left-border replication).
  * y = clamp(((|acc1| + |acc2|) if dual else |acc1|) >> k, 0, 255).

If this model matches golden/gen_vectors.py's numpy golden on every case,
the algorithm the RTL transcribes is correct; the shipped testbench then
checks the transcription itself bit-for-bit.
"""
import numpy as np
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_vectors import engine_golden, SOBEL_GX, SOBEL_GY, CASES  # noqa: E402


def engine_push_model(img, K1, K2, mode, k):
    H, W = img.shape
    K1 = [int(v) for r in K1 for v in r]
    K2 = [int(v) for r in K2 for v in r]
    lb1 = np.zeros(W, dtype=np.int64)   # previous row
    lb2 = np.zeros(W, dtype=np.int64)   # two rows back
    out = np.zeros((H, W), dtype=np.uint8)

    def mac_emit(t0, t1, t2, p, row_out):
        if p < 2:
            return
        left = t1 if p == 2 else t0
        taps = [left[0], t1[0], t2[0],
                left[1], t1[1], t2[1],
                left[2], t1[2], t2[2]]
        a1 = abs(sum(c * x for c, x in zip(K1, taps)))
        a2 = abs(sum(c * x for c, x in zip(K2, taps)))
        s = a1 if mode == 1 else a1 + a2
        out[row_out, p - 2] = min(s >> k, 255)

    for r in range(H):
        t0 = t1 = t2 = (0, 0, 0)
        p = 0
        for c in range(W):
            pix = int(img[r, c])
            if r >= 1:
                top = lb1[c] if r == 1 else lb2[c]
                trip = (int(top), int(lb1[c]), pix)      # (top, mid, bot)
                t0, t1, t2 = t1, t2, trip
                p += 1
                mac_emit(t0, t1, t2, p, r - 1)
            lb2[c] = lb1[c]
            lb1[c] = pix
        if r >= 1:                                        # right-edge repeat
            t0, t1, t2 = t1, t2, t2
            p += 1
            mac_emit(t0, t1, t2, p, r - 1)
    # synthetic bottom row
    t0 = t1 = t2 = (0, 0, 0)
    p = 0
    for c in range(W):
        top = int(lb2[c]) if H >= 2 else int(lb1[c])
        trip = (top, int(lb1[c]), int(lb1[c]))
        t0, t1, t2 = t1, t2, trip
        p += 1
        mac_emit(t0, t1, t2, p, H - 1)
    t0, t1, t2 = t1, t2, t2
    p += 1
    mac_emit(t0, t1, t2, p, H - 1)
    return out


def main():
    rng = np.random.default_rng(7)
    fails = 0
    # 1. the four manuscript kernel families on the shipped test scene
    from gen_vectors import img as scene
    for name, c in CASES.items():
        got = engine_push_model(scene, c["K1"], c["K2"], c["mode"], c["k"])
        ref = engine_golden(scene, np.array(c["K1"]), np.array(c["K2"]), c["mode"], c["k"])
        ok = np.array_equal(got, ref)
        print(f"scene/{name:9s}: {'PASS' if ok else 'FAIL'}")
        fails += (not ok)
    # 2. randomized images, sizes, and kernels (including tiny H)
    for t in range(24):
        H = int(rng.integers(2, 40))
        W = int(rng.integers(3, 64))
        im = rng.integers(0, 256, size=(H, W)).astype(np.uint8)
        K1 = rng.integers(-16, 17, size=(3, 3))
        K2 = rng.integers(-16, 17, size=(3, 3))
        mode = int(rng.integers(0, 2))
        k = int(rng.integers(0, 8))
        got = engine_push_model(im, K1, K2, mode, k)
        ref = engine_golden(im, K1, K2, mode, k)
        ok = np.array_equal(got, ref)
        if not ok:
            print(f"random #{t}: FAIL (H={H} W={W} mode={mode} k={k}, "
                  f"{int((got != ref).sum())} mismatches)")
            fails += 1
    # 3. forced degenerate heights
    for H in (1, 2, 3):
        for t in range(6):
            W = int(rng.integers(3, 40))
            im = rng.integers(0, 256, size=(H, W)).astype(np.uint8)
            K1 = rng.integers(-16, 17, size=(3, 3)); K2 = rng.integers(-16, 17, size=(3, 3))
            mode = int(rng.integers(0, 2)); k = int(rng.integers(0, 8))
            got = engine_push_model(im, K1, K2, mode, k)
            ref = engine_golden(im, K1, K2, mode, k)
            if not np.array_equal(got, ref):
                print(f"H={H} case FAIL (W={W})"); fails += 1
    print(f"random x24 + degenerate H ({'all PASS' if fails == 0 else str(fails) + ' FAILURES'})")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
