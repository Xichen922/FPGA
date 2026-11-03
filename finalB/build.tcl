set project_dir [file dirname [file normalize [info script]]]
open_project [file join $project_dir finalB.gprj]
set_option -top_module finalB_top
set_option -output_base_name finalB
set_option -verilog_std v2001
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -use_mspi_as_gpio 0
set_option -place_option 1
set_option -route_option 2
run syn
run pnr
exit






