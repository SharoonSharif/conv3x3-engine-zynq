// C-simulation: Vitis Vision Sobel baseline vs sobel_fixed's expected output
// (tb/vectors/exp_sobel.hex) on interior pixels; borders differ by design
// (Vitis pads with zeros, sobel_fixed replicates edges). Border mismatches
// are counted separately for information only.
#include <cstdio>
#include <cstdlib>
#include "hls_stream.h"
#include "ap_axi_sdata.h"
typedef hls::stream<ap_axiu<8, 1, 1, 1> > axis8_t;
void sobel_top(axis8_t&, axis8_t&, int, int);

static int readhex(const char* fn, int* v, int n) {
    FILE* f = fopen(fn, "r"); if (!f) { printf("cannot open %s\n", fn); exit(2); }
    int i = 0; unsigned x; while (i < n && fscanf(f, "%x", &x) == 1) v[i++] = x; fclose(f); return i;
}
int main(int argc, char** argv) {
    const char* dir = argc > 1 ? argv[1] : "../../tb/vectors";
    const int W = 160, H = 120, N = W * H;
    static int img[N], exp[N]; char fn[256];
    snprintf(fn, sizeof fn, "%s/image.hex", dir); if (readhex(fn, img, N) != N) { printf("short image.hex\n"); return 2; }
    snprintf(fn, sizeof fn, "%s/exp_sobel.hex", dir); if (readhex(fn, exp, N) != N) { printf("short exp_sobel.hex\n"); return 2; }
    axis8_t in, out;
    for (int i = 0; i < N; i++) { ap_axiu<8,1,1,1> p; p.data = img[i]; p.user = (i == 0); p.last = (i % W == W - 1); p.keep = -1; p.strb = -1; in.write(p); }
    sobel_top(in, out, H, W);
    int mism = 0, cnt = 0, bmism = 0, bcnt = 0, maxd = 0, nout = 0;
    for (int i = 0; i < N; i++) {
        if (out.empty()) { printf("output stream short: %d of %d pixels\n", nout, N); return 1; }
        int y = out.read().data; nout++; int r = i / W, c = i % W;
        int d = y > exp[i] ? y - exp[i] : exp[i] - y;
        if (r > 0 && r < H - 1 && c > 0 && c < W - 1) {
            cnt++; if (y != exp[i]) { if (mism < 5) printf("mismatch r%d c%d: %d vs %d\n", r, c, y, exp[i]); mism++; if (d > maxd) maxd = d; }
        } else { bcnt++; if (y != exp[i]) bmism++; }
    }
    if (!out.empty()) { printf("output stream has extra pixels\n"); return 1; }
    printf("Vitis Sobel vs sobel_fixed: %d mismatches / %d interior px (max |diff| %d); borders: %d / %d differ (zero-pad vs replicate, by design)\n",
           mism, cnt, maxd, bmism, bcnt);
    return mism ? 1 : 0;
}
