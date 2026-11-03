create_clock -name clk50 -period 20.000 -waveform {0.000 10.000} [get_ports {clk}]
set_clock_uncertainty -setup -from [get_clocks {clk50}] -to [get_clocks {clk50}] 0.500
set_clock_uncertainty -hold -from [get_clocks {clk50}] -to [get_clocks {clk50}] 0.200
# A owns audio cadence; all A logic remains in50MHz.
create_generated_clock -name audio_bclk -source [get_ports {clk}] -edges {9 17 25} [get_ports {i2s_bclk}]
set_output_delay -clock [get_clocks {audio_bclk}] -max 10.000 [get_ports {i2s_dout i2s_lrck}]
set_output_delay -clock [get_clocks {audio_bclk}] -min 0.000 [get_ports {i2s_dout i2s_lrck}]
# Raw asynchronous inputs enter dedicated synchronizers; their interstage paths stay timed.
set_false_path -from [get_ports {reset_n touch_sdo kb_col[*] mcp_miso encoder_s1 encoder_s2 link_miso}]
set_output_delay -clock [get_clocks {clk50}] -max 10.000 [get_ports {mcp_cs_n mcp_sclk mcp_mosi link_cs_n link_sclk link_mosi}]
set_output_delay -clock [get_clocks {clk50}] -min 0.000 [get_ports {mcp_cs_n mcp_sclk mcp_mosi link_cs_n link_sclk link_mosi}]
