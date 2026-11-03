create_clock -name clk50 -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
set_clock_uncertainty -setup -from [get_clocks {clk50}] -to [get_clocks {clk50}] 0.500
set_clock_uncertainty -hold -from [get_clocks {clk50}] -to [get_clocks {clk50}] 0.200
# Source-synchronous I2S input from A. Data/WS launch on its falling edge.
create_clock -name audio_bclk -period 160.000 -waveform {0.000 80.000} [get_ports {audio_bclk}]
create_generated_clock -name dac_bclk -source [get_ports {audio_bclk}] -divide_by 1 [get_ports {i2s_bclk}]
set_input_delay -clock [get_clocks {audio_bclk}] -clock_fall -max 15.000 [get_ports {audio_din audio_lrck}]
set_input_delay -clock [get_clocks {audio_bclk}] -clock_fall -min 0.000 [get_ports {audio_din audio_lrck}]
set_output_delay -clock [get_clocks {dac_bclk}] -max 10.000 [get_ports {i2s_dout i2s_lrck}]
set_output_delay -clock [get_clocks {dac_bclk}] -min 0.000 [get_ports {i2s_dout i2s_lrck}]
# The only multi-bit CDC is dual-clock audio RAM with Gray-pointer synchronizers.
# Other crossings are reset synchronizers and single-bit link/primed indications.
set_clock_groups -asynchronous -group [get_clocks {clk50}] -group [get_clocks {audio_bclk dac_bclk}]
set_false_path -from [get_ports {reset_n link_cs_n link_sclk link_mosi uart_rx bt_rx ultrasonic_echo}]
# SPI MISO is sampled only every 25 system clocks after the module changes
# it on SCLK's falling edge. A one-cycle input delay constraint is invalid.
set_false_path -from [get_ports {flash_miso}]
# BCLK is also sampled as data only by the first clock-loss-monitor synchronizer.
set_false_path -from [get_ports {audio_bclk}] -to [get_cells {clock_meta_s0}]
set_output_delay -clock [get_clocks {clk50}] -max 10.000 [get_ports {uart_tx bt_tx link_miso ultrasonic_trig dac_xsmt}]
set_output_delay -clock [get_clocks {clk50}] -min 0.000 [get_ports {uart_tx bt_tx link_miso ultrasonic_trig dac_xsmt}]
