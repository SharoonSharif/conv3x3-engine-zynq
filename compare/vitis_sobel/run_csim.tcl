# HLS-managed C simulation (csim_design). Fails on hosts with a stray C:\dev\null
# file ("/dev/null:1: *** missing separator"); see README.md for the direct g++ route.
set vl $::env(VITIS_VISION_INC)
open_project hls_prj
set_top sobel_top
add_files sobel_top.cpp -cflags "-I$vl -std=c++14"
add_files -tb tb_sobel.cpp -cflags "-std=c++14"
open_solution sol -flow_target vivado
csim_design
exit
