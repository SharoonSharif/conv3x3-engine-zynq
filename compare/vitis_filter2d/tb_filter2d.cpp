// C-simulation: filter2D baseline vs the engine's expected output
// (tb/vectors/exp_<case>.hex) on interior pixels; borders differ by design
// (Vitis pads with zeros, the engine replicates edges).
#include <cstdio>
#include <cstdlib>
#include "hls_stream.h"
#include "ap_axi_sdata.h"
typedef hls::stream<ap_axiu<8, 1, 1, 1> > axis8_t;
void filter2d_top(axis8_t&, axis8_t&, short int[9], unsigned char, int, int);

static int readhex(const char* fn, int* v, int n) {
    FILE* f = fopen(fn, "r"); if (!f) { printf("cannot open %s\n", fn); exit(2); }
    int i = 0; unsigned x; while (i < n && fscanf(f, "%x", &x) == 1) v[i++] = x; fclose(f); return i;
}
int main(int argc, char** argv) {
    const char* dir = "../../tb/vectors"; const char* cs = argc > 1 ? argv[1] : "sharpen";
    const int W = 160, H = 120, N = W * H;
    static int img[N], exp[N], cfg[20]; char fn[256];
    snprintf(fn, sizeof fn, "%s/image.hex", dir); readhex(fn, img, N);
    snprintf(fn, sizeof fn, "%s/exp_%s.hex", dir, cs); readhex(fn, exp, N);
    snprintf(fn, sizeof fn, "%s/cfg_%s.hex", dir, cs); readhex(fn, cfg, 20);
    short int coef[9]; for (int i = 0; i < 9; i++) coef[i] = (signed char)cfg[2 + i];
    axis8_t in, out;
    for (int i = 0; i < N; i++) { ap_axiu<8,1,1,1> p; p.data = img[i]; p.user = (i == 0); p.last = (i % W == W - 1); p.keep = -1; p.strb = -1; in.write(p); }
    filter2d_top(in, out, coef, (unsigned char)cfg[1], H, W);
    int mism = 0, cnt = 0;
    for (int i = 0; i < N; i++) {
        int y = out.read().data; int r = i / W, c = i % W;
        if (r > 0 && r < H - 1 && c > 0 && c < W - 1) { cnt++; if (y != exp[i]) { if (mism < 5) printf("mismatch r%d c%d: %d vs %d\n", r, c, y, exp[i]); mism++; } }
    }
    printf("filter2D vs engine (%s, signed single-kernel): %d mismatches / %d interior px\n", cs, mism, cnt);
    return mism ? 1 : 0;
}
