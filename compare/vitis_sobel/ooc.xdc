# same constraint as synth/ooc.xdc, for the HLS clock/port names
create_clock -name ap_clk -period 6.734 [get_ports ap_clk]
set_input_delay  -clock ap_clk 2.000 [get_ports -filter {DIRECTION == IN && NAME != ap_clk}]
set_output_delay -clock ap_clk 2.000 [get_ports -filter {DIRECTION == OUT}]
