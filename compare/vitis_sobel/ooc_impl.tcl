# Out-of-context implementation of the HLS-generated Sobel RTL with the same
# part, clock and directive sets as ../../synth/ooc_synth_strategy.tcl.
# Usage: vivado -mode batch -source ooc_impl.tcl -tclargs <default_flow|extratiming>
set strat [lindex $argv 0]
if {$strat eq "extratiming"} { set o Explore; set p ExtraTimingOpt; set ph AggressiveExplore; set r AggressiveExplore; set post 1 } \
else { set o Default; set p Default; set ph Default; set r Default; set post 0 }
set tag sobel_top_${strat}
create_project -in_memory -part xc7z020clg400-1
read_verilog [glob hls_prj/sol/syn/verilog/*.v]
foreach f [glob -nocomplain hls_prj/sol/syn/verilog/*.dat] { file copy -force $f . }
read_xdc ooc.xdc
synth_design -top sobel_top -mode out_of_context -flatten_hierarchy rebuilt
opt_design -directive $o
place_design -directive $p
phys_opt_design -directive $ph
route_design -directive $r
if {$post} { phys_opt_design -directive AggressiveExplore }
report_utilization -hierarchical -file ${tag}_util_impl.rpt
report_utilization -file ${tag}_util_flat.rpt
report_timing_summary -delay_type min_max -max_paths 10 -file ${tag}_tim_impl.rpt
report_power -file ${tag}_power.rpt
