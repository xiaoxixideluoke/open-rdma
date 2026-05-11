# -------------------------------------------------------------------------
# ACE timing constaint file
# All clocks, clock relationships, and IO timing constraints should be set
# in this file
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Example Timing constraints NoC reference design
# -------------------------------------------------------------------------
# Not needed here, using generated clock constraints from I/O Designer Toolkit
# Set 507MHz target
# create_clock -name rdma_clk  [get_ports CLK]  -period 1.971

# Snapshot JTAG clock: 25MHz
create_clock -period 40 [get_ports {i_jtag_in[0]}] -name tck
set_clock_groups -asynchronous -group {tck}

set_clock_groups -asynchronous -group [get_clocks i_eth_clk]
set_clock_groups -asynchronous -group [get_clocks pll_logic_clk]