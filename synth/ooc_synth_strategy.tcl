# OOC implementation with a named directive strategy.
# vivado -mode batch -source synth/ooc_synth_strategy.tcl -tclargs <top> <W> <H> <CW> <strategy>
# Reports: <top>_W<W>_<strategy>_{util_synth,util_impl,tim_impl,power}.rpt
lassign $argv top W H CW strat
set tag ${top}_W${W}_${strat}
set sopt {}
switch $strat {
  default_flow { set o Default;  set p Default;            set ph Default;           set r Default;           set post 0 }
  explore      { set o Explore;  set p Explore;            set ph Explore;           set r Explore;           set post 1 }
  extratiming  { set o Explore;  set p ExtraTimingOpt;     set ph AggressiveExplore; set r AggressiveExplore; set post 1 }
  netdelay     { set o Explore;  set p ExtraNetDelay_high; set ph AggressiveExplore; set r AggressiveExplore; set post 1 }
  retime       { set o Explore;  set p Explore;            set ph AlternateFlowWithRetiming; set r Explore;   set post 1; set sopt {-retiming} }
  default { error "unknown strategy $strat" }
}
create_project -in_memory -part xc7z020clg400-1
read_verilog [glob rtl/*.v]
read_xdc synth/ooc.xdc
synth_design -top $top -mode out_of_context -flatten_hierarchy rebuilt \
    -generic W=$W -generic H=$H -generic CW=$CW {*}$sopt
report_utilization -file ${tag}_util_synth.rpt
opt_design -directive $o
place_design -directive $p
phys_opt_design -directive $ph
route_design -directive $r
if {$post} { phys_opt_design -directive AggressiveExplore }
report_utilization -hierarchical -file ${tag}_util_impl.rpt
report_timing_summary -delay_type min_max -max_paths 25 -file ${tag}_tim_impl.rpt
report_power -file ${tag}_power.rpt
puts "== $tag done =="
