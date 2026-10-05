// Vitis Vision xf::cv::Sobel baseline for the brief's fixed-Sobel comparison.
// Same external interface class as rtl/sobel_fixed.v: 8-bit AXI4-Stream video
// in/out, 1 pixel/clock, 1920x1080 maximum frame; rows/cols on AXI4-Lite.
// Pipeline: AXIvideo2xfMat -> xf::cv::Sobel (3x3, XF_8UC1 -> XF_16SC1, raw
// signed gradients, zero-padded borders) -> combine stage computing
// y = clamp((|gx| + |gy|) >> 3, 0, 255) exactly as sobel_fixed.v -> xfMat2AXIvideo.
#include "hls_stream.h"
#include "ap_axi_sdata.h"
#include "common/xf_common.hpp"
#include "common/xf_infra.hpp"
#include "imgproc/xf_sobel.hpp"

#define MAXR 1080
#define MAXC 1920
typedef hls::stream<ap_axiu<8, 1, 1, 1> > axis8_t;

// Bit-exact copy of the sobel_fixed.v magnitude stage:
//   ax = |gx|, ay = |gy| (12-bit magnitudes), mag = ax + ay (13 bit),
//   y  = (mag >> 3) > 255 ? 255 : (mag >> 3)
// LOOP_FLATTEN off mirrors the library's own per-row kernels
// (e.g. xFMagnitudeKernel): a flattened loop made HLS build an 11x11-bit
// rows*cols multiplier for the trip count, which cost one DSP48 that has
// nothing to do with the filter arithmetic.
static void sobel_combine(xf::cv::Mat<XF_16SC1, MAXR, MAXC, XF_NPPC1>& gx,
                          xf::cv::Mat<XF_16SC1, MAXR, MAXC, XF_NPPC1>& gy,
                          xf::cv::Mat<XF_8UC1, MAXR, MAXC, XF_NPPC1>& dst,
                          int rows, int cols) {
#pragma HLS INLINE off
    int idx = 0;
ROW_LOOP:
    for (int r = 0; r < rows; r++) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=MAXR
#pragma HLS LOOP_FLATTEN off
    COL_LOOP:
        for (int c = 0; c < cols; c++) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=MAXC
#pragma HLS PIPELINE II=1
            ap_int<16> x = gx.read(idx);
            ap_int<16> y = gy.read(idx);
            idx++;
            ap_uint<16> ax = (x < 0) ? (ap_uint<16>)(-x) : (ap_uint<16>)x;
            ap_uint<16> ay = (y < 0) ? (ap_uint<16>)(-y) : (ap_uint<16>)y;
            ap_uint<17> mag = ax + ay;
            ap_uint<14> sh = mag >> 3;
            ap_uint<8> out = (sh > 255) ? (ap_uint<8>)255 : (ap_uint<8>)sh;
            dst.write(idx - 1, out);
        }
    }
}

void sobel_top(axis8_t& s_axis, axis8_t& m_axis, int rows, int cols) {
#pragma HLS INTERFACE axis port=s_axis
#pragma HLS INTERFACE axis port=m_axis
#pragma HLS INTERFACE s_axilite port=rows
#pragma HLS INTERFACE s_axilite port=cols
#pragma HLS INTERFACE s_axilite port=return
    xf::cv::Mat<XF_8UC1, MAXR, MAXC, XF_NPPC1> src(rows, cols);
    xf::cv::Mat<XF_16SC1, MAXR, MAXC, XF_NPPC1> gx(rows, cols);
    xf::cv::Mat<XF_16SC1, MAXR, MAXC, XF_NPPC1> gy(rows, cols);
    xf::cv::Mat<XF_8UC1, MAXR, MAXC, XF_NPPC1> dst(rows, cols);
#pragma HLS DATAFLOW
    xf::cv::AXIvideo2xfMat(s_axis, src);
    xf::cv::Sobel<XF_BORDER_CONSTANT, XF_FILTER_3X3, XF_8UC1, XF_16SC1, MAXR, MAXC, XF_NPPC1, false>(src, gx, gy);
    sobel_combine(gx, gy, dst, rows, cols);
    xf::cv::xfMat2AXIvideo(dst, m_axis);
}
