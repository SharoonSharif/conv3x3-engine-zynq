#!/usr/bin/env python3
"""Two-condition DDR feasibility model of the TCAS-II brief (Sec. II).

  (1) B_v   = W * H * f * b                  bytes/s per direction
  (2) sum B_v <= eta * B_peak                 average capacity
  (3) t_tol = D_FIFO / B_read >= t_stall,max  stall tolerance

Conventions: MB = 1e6 B; FIFO sizes in KiB (4 KB = 4096 B, illustrative).
Reproduces Table I (observed / predicted configurations) and Table II
(design-space projection). The screening threshold is the tolerance of the
verified 720p60 RGB888 configuration; at equal FIFO storage it is equivalent
to B_read <= 165.9 MB/s for any FIFO depth.

    python model/ddr_model.py
"""
PEAK = {"32-bit DDR3-1066": 4266.0, "64-bit DDR4-2400": 19200.0}   # MB/s
FIFO = 4096                                                         # bytes


def rate(w, h, f, b):
    return w * h * f * b / 1e6                                      # MB/s


def ttol_us(read_mbs, fifo=FIFO):
    return fifo / (read_mbs * 1e6) * 1e6


REF_READ = rate(1280, 720, 60, 3)          # verified 720p60 RGB888 display read
REF_TTOL = ttol_us(REF_READ)


def status(read):
    t = ttol_us(read)
    return "feasible" if t >= REF_TTOL else ("marginal" if t > ttol_us(rate(1920, 1080, 60, 3)) else "fails")


print(f"Screening threshold: t_tol >= {REF_TTOL:.1f} us (4-KB FIFO), i.e. B_read <= {REF_READ:.1f} MB/s at equal storage\n")

print("TABLE I  (camera write + display read)")
print(f"{'Configuration':34s} {'MB/s':>7s} {'share':>6s} {'t_tol us':>8s}")
table1 = [
    ("720p60 RGB888 (verified)",               (1280, 720, 60, 3), (1280, 720, 60, 3)),
    ("1080p RGB888, cam 30 / disp 60 (fails)", (1920, 1080, 30, 3), (1920, 1080, 60, 3)),
    ("1080p60 YUV 4:2:0",                      (1920, 1080, 60, 1.5), (1920, 1080, 60, 1.5)),
    ("1080p60 Y8",                             (1920, 1080, 60, 1), (1920, 1080, 60, 1)),
]
for name, wr, rd in table1:
    w, r = rate(*wr), rate(*rd)
    print(f"{name:34s} {w + r:7.1f} {100 * (w + r) / PEAK['32-bit DDR3-1066']:5.1f}% {ttol_us(r):8.1f}")
w30 = rate(1920, 1080, 30, 3)
print(f"  (if the failing test's display also ran at 30 Hz: t_tol = {ttol_us(w30):.1f} us)\n")

print("TABLE II  (projection; FIFO = 4 KB x read-rate ratio to 720p60)")
print(f"{'Configuration':16s} {'MB/s':>7s} {'t_tol':>6s} {'FIFO KB':>7s} " + " ".join(f"{k:>17s}" for k in PEAK))
for name, (w, h, f, b) in [("1080p60 RGB888", (1920, 1080, 60, 3)), ("1080p60 Y8", (1920, 1080, 60, 1)),
                           ("4K30 RGB888", (3840, 2160, 30, 3)), ("4K30 Y8", (3840, 2160, 30, 1)),
                           ("4K60 RGB888", (3840, 2160, 60, 3)), ("4K60 Y8", (3840, 2160, 60, 1))]:
    r = rate(w, h, f, b)
    tot = 2 * r
    fifo_kb = FIFO * r / REF_READ / 1024
    shares = " ".join(f"{100 * tot / p:16.1f}%" for p in PEAK.values())
    print(f"{name:16s} {tot:7.1f} {ttol_us(r):6.1f} {fifo_kb:7.1f} {shares}")
