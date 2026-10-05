# Out-of-context implementation with explicit frame geometry.
# Usage:
#   vivado -mode batch -source synth/ooc_synth_param.tcl -tclargs <top> <W> <H> <CW> [LB_BRAM]
#   e.g. -tclargs conv3x3_engine 1920 1080 11   (CW: 2**CW > W+1)
#        -tclargs conv3x3_engine 1920 1080 11 1 (block-RAM line buffers)
# The optional 5th argument sets the conv3x3_engine generic LB_BRAM (default
# 0); it is only passed to synth_design when given, so the 4-argument form is
# unchanged. Produces <top>_W<W>[_bram]_{util_synth,util_impl,tim_impl,power}.rpt.
set top [lindex $argv 0]
set W   [lindex $argv 1]
set H   [lindex $argv 2]
set CW  [lindex $argv 3]
set LB  [lindex $argv 4]
if {$top eq ""} { set top conv3x3_engine }
if {$W  eq ""} { set W 160 }
if {$H  eq ""} { set H 120 }
if {$CW eq ""} { set CW 9 }
if {(1 << $CW) <= ($W + 1)} { error "CW=$CW too small for W=$W (need 2**CW > W+1)" }
set tag ${top}_W${W}
set gen_extra {}
if {$LB ne ""} {
    set gen_extra [list -generic LB_BRAM=$LB]
    if {$LB != 0} { append tag _bram }
}
create_project -in_memory -part xc7z020clg400-1
read_verilog [glob rtl/*.v]
read_xdc synth/ooc.xdc
synth_design -top $top -mode out_of_context -flatten_hierarchy rebuilt \
    -generic W=$W -generic H=$H -generic CW=$CW {*}$gen_extra
report_utilization -file ${tag}_util_synth.rpt
opt_design
place_design
phys_opt_design
route_design
report_utilization -hierarchical -file ${tag}_util_impl.rpt
report_timing_summary -delay_type min_max -max_paths 25 -file ${tag}_tim_impl.rpt
report_power -file ${tag}_power.rpt
puts "== $tag implemented (W=$W H=$H CW=$CW LB_BRAM=[expr {$LB eq "" ? 0 : $LB}]) =="
