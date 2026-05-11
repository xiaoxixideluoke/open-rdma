create_clock -name rdma_main_clk -period 4 [get_ports {CLK}]
set_clock_groups -asynchronous -group user_clk_250 -group txoutclk_out[0]