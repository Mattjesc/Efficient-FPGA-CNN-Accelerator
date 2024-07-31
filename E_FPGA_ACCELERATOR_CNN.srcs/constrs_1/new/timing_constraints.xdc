# Define the primary clock with a 100 MHz frequency (10 ns period)
# This line sets a timing constraint on the 'clk' input port, specifying the timing period for the design.
# 'clk' is the identifier for the clock domain used throughout the design.
create_clock -name clk -period 10 [get_ports clk]

# Set the maximum and minimum input delay for input signals relative to the primary clock 'clk'
# Assuming that 'activation_in' is the input port for the design, replace 'input_signal' with 'activation_in'.
# These constraints specify the valid arrival time window for external signals.
set_input_delay -clock clk -max 2.5 [get_ports activation_in]
set_input_delay -clock clk -min 0 [get_ports activation_in]

# Set the maximum and minimum output delay for output signals relative to the primary clock 'clk'
# Assuming that 'data_out' is the output port of the design, replace 'output_signal' with 'data_out'.
# These constraints specify the valid timing window for signals to become stable and be read by external components.
set_output_delay -clock clk -max 2.5 [get_ports data_out]
set_output_delay -clock clk -min 0 [get_ports data_out]

# Define a generated clock if there is a need to create a derived clock signal from 'clk'.
# Since no specific generated clocks were indicated in the design, this line can be left out
# unless there's a particular instance or requirement. If needed, replace 'some_instance/clk_out'
# with the actual instance and pin names that produce the generated clock.
# Example: create_generated_clock -name gen_clk -source [get_ports clk] -divide_by 2 [get_pins actual_instance/actual_clk_out]

# Additional constraints, if there are specific timing requirements for other signals or constraints
# for input/output delays for other ports, you can add them here. These are crucial for multi-clock domain designs
# or when interfacing with external high-speed components.
