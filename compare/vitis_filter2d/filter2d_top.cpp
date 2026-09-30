// Vitis Vision xf::cv::filter2D baseline for the brief's comparison.
// Same external interface class as conv3x3_engine: 8-bit AXI4-Stream video
// in/out, runtime 3x3 coefficients and shift over AXI4-Lite, 1 pixel/clock,
// 1920x1080 maximum frame.
#include "hls_stream.h"
#include "ap_axi_sdata.h"
#include "common/xf_common.hpp"
#include "common/xf_infra.hpp"
#include "imgproc/xf_custom_convolution.hpp"

#define MAXR 1080
#define MAXC 1920
typedef hls::stream<ap_axiu<8, 1, 1, 1> > axis8_t;

void filter2d_top(axis8_t& s_axis, axis8_t& m_axis, short int coef[9],
                  unsigned char shift, int rows, int cols) {
#pragma HLS INTERFACE axis port=s_axis
#pragma HLS INTERFACE axis port=m_axis
#pragma HLS INTERFACE s_axilite port=coef
#pragma HLS INTERFACE s_axilite port=shift
#pragma HLS INTERFACE s_axilite port=rows
#pragma HLS INTERFACE s_axilite port=cols
#pragma HLS INTERFACE s_axilite port=return
    short int lcoef[9];
    for (int i = 0; i < 9; i++) {
#pragma HLS PIPELINE II=1
        lcoef[i] = coef[i];
    }
    xf::cv::Mat<XF_8UC1, MAXR, MAXC, XF_NPPC1> src(rows, cols);
    xf::cv::Mat<XF_8UC1, MAXR, MAXC, XF_NPPC1> dst(rows, cols);
#pragma HLS DATAFLOW
    xf::cv::AXIvideo2xfMat(s_axis, src);
    xf::cv::filter2D<XF_BORDER_CONSTANT, 3, 3, XF_8UC1, XF_8UC1, MAXR, MAXC, XF_NPPC1>(src, dst, lcoef, shift);
    xf::cv::xfMat2AXIvideo(dst, m_axis);
}
