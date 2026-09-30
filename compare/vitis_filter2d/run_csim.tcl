set vl $::env(VITIS_VISION_INC)
open_project hls_prj
set_top filter2d_top
add_files filter2d_top.cpp -cflags "-I$vl -std=c++14"
add_files -tb tb_filter2d.cpp -cflags "-std=c++14"
open_solution sol -flow_target vivado
csim_design -argv "sharpen"
exit
