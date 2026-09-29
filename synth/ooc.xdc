# out-of-context constraints — 148.5 MHz pixel/AXI clock (manuscript target)
create_clock -name aclk -period 6.734 [get_ports aclk]
set_input_delay  -clock aclk 2.000 [get_ports -filter {DIRECTION == IN && NAME != aclk}]
set_output_delay -clock aclk 2.000 [get_ports -filter {DIRECTION == OUT}]
