# The reference and fitted PLL are the same as the production clock path.
# Template.sdc derives the generated clock and its uncertainty.
create_clock -name FPGA_CLK2_50 -period 20.000 [get_ports FPGA_CLK2_50]

# Only the fixture's asynchronous switch inputs and visual readouts.
# Switches enter two synchronization registers before use.
set_false_path -from [get_ports {SW[*]}]
set_false_path -to [get_ports {LED_USER LED_POWER}]
