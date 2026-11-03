set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir finalA.gprj]
set_option -top_module finalA_top
set_option -output_base_name finalA
set_option -verilog_std v2001
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_mspi_as_gpio 0
set_option -route_option 0
set_option -co-place_io_registers 1
set_option -correct_hold_violation 1
run syn
run pnr
exit
