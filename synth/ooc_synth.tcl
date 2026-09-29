# Out-of-context implementation for the reconstructed cores.
# Usage:
#   vivado -mode batch -source synth/ooc_synth.tcl -tclargs conv3x3_engine
#   vivado -mode batch -source synth/ooc_synth.tcl -tclargs sobel_fixed
# Produces <top>_util_impl.rpt, <top>_tim_impl.rpt, <top>_power.rpt.
set top [lindex $argv 0]
if {$top eq ""} { set top conv3x3_engine }
create_project -in_memory -part xc7z020clg400-1
read_verilog [glob rtl/*.v]
read_xdc synth/ooc.xdc
synth_design -top $top -mode out_of_context -flatten_hierarchy rebuilt
report_utilization -file ${top}_util_synth.rpt
opt_design
place_design
phys_opt_design
route_design
report_utilization -hierarchical -file ${top}_util_impl.rpt
report_timing_summary -delay_type min_max -max_paths 25 -file ${top}_tim_impl.rpt
report_power -file ${top}_power.rpt
puts "== $top implemented; see ${top}_util_impl.rpt / ${top}_tim_impl.rpt =="
