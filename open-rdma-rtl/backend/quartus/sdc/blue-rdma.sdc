create_clock -name rdma_main_clk -period 2.222 [get_ports {CLK}]
set_clock_groups -asynchronous -group {ftile_eth_hip_inst|eth_f_*|tx_clkout|ch*}