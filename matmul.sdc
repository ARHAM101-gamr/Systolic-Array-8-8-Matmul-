# 50 MHz board clock (20 ns). The Timing Analyzer reports the real Fmax in its
# "Fmax Summary"; 50 MHz is only the target it checks against.
create_clock -name clk -period 20.000 [get_ports clk]
derive_clock_uncertainty
# rst_n comes from a push button: asynchronous, no timing relationship to clk.
set_false_path -from [get_ports rst_n]
