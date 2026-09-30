# Vitis HLS 2026.1: synthesize the filter2D baseline for xc7z020clg400-1 @ 6.734 ns.
# Usage (from this directory): vitis-run --mode hls --tcl run_hls.tcl
set vl $::env(VITIS_VISION_INC)
open_project -reset hls_prj
set_top filter2d_top
add_files filter2d_top.cpp -cflags "-I$vl -std=c++14"
open_solution -reset sol -flow_target vivado
set_part xc7z020clg400-1
create_clock -period 6.734 -name default
csynth_design
exit
