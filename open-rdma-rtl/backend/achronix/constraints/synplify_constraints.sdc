# -------------------------------------------------------------------------
# Synplify timing constaint file
# All clocks and clock relationships should be defined in this file for synthesis
# Note : There are small differences between Synplify Pro and ACE SDC syntax
# therefore it is not recommended to use the same file for both, instead to
# have two separate files.
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Primary clock timing constraints
# -------------------------------------------------------------------------
# Set main clocks to 507MHz.
create_clock -name rdma_clk  [get_ports CLK]  -period 1.971

# JTAG CLK_IPIN pass-through:
# When using ACX_SNAPSHOT
create_clock [get_pins x_snapshot.x_jtap_interface.x_acx_jtap.clk_ipin_tck/dout] -period 40 -name tck_core
set_clock_groups -asynchronous -group {tck_core}

# -------------------------------------------------------------------------
# Example of defining a generated clock
# -------------------------------------------------------------------------
# create_generated_clock -name clk_gate [ get_pins {i_clkgate/clk_out} ] -source  [get_ports {i_clk} ] -divide_by 1

# -------------------------------------------------------------------------
# Example of setting asynchronous clock groups if more than one clock
# -------------------------------------------------------------------------
# Create a new async clock
# create_clock -name clk_dummy [get_ports i_clk_dummy] -period 1.33

# From example above, the clk_gate is related to clk, 
# but clk_dummy is asynchronous to both
# set_clock_groups -asynchronous -group {clk clk_gate} \
#                                -group {clk_dummy}

# -------------------------------------------------------------------------
# Set three clocks in design to be asynchronous to one another
# -------------------------------------------------------------------------
# Setting asynchronous clock groups for send_clk, chk_clk, cc_clk and reg_clk
#  set_clock_groups -asynchronous -group {send_clk} \
#                                 -group {chk_clk}  \
#                                 -group {cc_clk}   \
#                                 -group {reg_clk}
