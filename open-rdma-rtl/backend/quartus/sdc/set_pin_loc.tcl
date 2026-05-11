########################################################################
# PCIE GEN5 x16
set_location_assignment PIN_DR68 -to pcie_ep_refclk0
set_location_assignment PIN_CU68 -to pcie_ep_refclk1
set_location_assignment PIN_CD58 -to pcie_ep_perstn
set_location_assignment PIN_DE82 -to rtile_pcie_rx_p_in[0]
set_location_assignment PIN_DB83 -to rtile_pcie_rx_n_in[0]
set_location_assignment PIN_CW80 -to rtile_pcie_rx_p_in[1]
set_location_assignment PIN_CT79 -to rtile_pcie_rx_n_in[1]
set_location_assignment PIN_CM82 -to rtile_pcie_rx_p_in[2]
set_location_assignment PIN_CJ83 -to rtile_pcie_rx_n_in[2]
set_location_assignment PIN_CF80 -to rtile_pcie_rx_p_in[3]
set_location_assignment PIN_CC79 -to rtile_pcie_rx_n_in[3]
set_location_assignment PIN_BY82 -to rtile_pcie_rx_p_in[4]
set_location_assignment PIN_BU83 -to rtile_pcie_rx_n_in[4]
set_location_assignment PIN_BP80 -to rtile_pcie_rx_p_in[5]
set_location_assignment PIN_BL79 -to rtile_pcie_rx_n_in[5]
set_location_assignment PIN_BH82 -to rtile_pcie_rx_p_in[6]
set_location_assignment PIN_BE83 -to rtile_pcie_rx_n_in[6]
set_location_assignment PIN_BB80 -to rtile_pcie_rx_p_in[7]
set_location_assignment PIN_AW79 -to rtile_pcie_rx_n_in[7]
set_location_assignment PIN_AR82 -to rtile_pcie_rx_p_in[8]
set_location_assignment PIN_AM83 -to rtile_pcie_rx_n_in[8]
set_location_assignment PIN_AJ80 -to rtile_pcie_rx_p_in[9]
set_location_assignment PIN_AF79 -to rtile_pcie_rx_n_in[9]
set_location_assignment PIN_AC82 -to rtile_pcie_rx_p_in[10]
set_location_assignment PIN_Y83  -to rtile_pcie_rx_n_in[10]
set_location_assignment PIN_V80  -to rtile_pcie_rx_p_in[11]
set_location_assignment PIN_T79  -to rtile_pcie_rx_n_in[11]
set_location_assignment PIN_P82  -to rtile_pcie_rx_p_in[12]
set_location_assignment PIN_M83  -to rtile_pcie_rx_n_in[12]
set_location_assignment PIN_K80  -to rtile_pcie_rx_p_in[13]
set_location_assignment PIN_G79  -to rtile_pcie_rx_n_in[13]
set_location_assignment PIN_M77  -to rtile_pcie_rx_p_in[14]
set_location_assignment PIN_P76  -to rtile_pcie_rx_n_in[14]
set_location_assignment PIN_C77  -to rtile_pcie_rx_p_in[15]
set_location_assignment PIN_E76  -to rtile_pcie_rx_n_in[15]
set_location_assignment PIN_DL74 -to rtile_pcie_tx_p_out[0]
set_location_assignment PIN_DH73 -to rtile_pcie_tx_n_out[0]
set_location_assignment PIN_DB77 -to rtile_pcie_tx_p_out[1]
set_location_assignment PIN_DE76 -to rtile_pcie_tx_n_out[1]
set_location_assignment PIN_CW74 -to rtile_pcie_tx_p_out[2]
set_location_assignment PIN_CT73 -to rtile_pcie_tx_n_out[2]
set_location_assignment PIN_CJ77 -to rtile_pcie_tx_p_out[3]
set_location_assignment PIN_CM76 -to rtile_pcie_tx_n_out[3]
set_location_assignment PIN_CF74 -to rtile_pcie_tx_p_out[4]
set_location_assignment PIN_CC73 -to rtile_pcie_tx_n_out[4]
set_location_assignment PIN_BU77 -to rtile_pcie_tx_p_out[5]
set_location_assignment PIN_BY76 -to rtile_pcie_tx_n_out[5]
set_location_assignment PIN_BP74 -to rtile_pcie_tx_p_out[6]
set_location_assignment PIN_BL73 -to rtile_pcie_tx_n_out[6]
set_location_assignment PIN_BE77 -to rtile_pcie_tx_p_out[7]
set_location_assignment PIN_BH76 -to rtile_pcie_tx_n_out[7]
set_location_assignment PIN_BB74 -to rtile_pcie_tx_p_out[8]
set_location_assignment PIN_AW73 -to rtile_pcie_tx_n_out[8]
set_location_assignment PIN_AM77 -to rtile_pcie_tx_p_out[9]
set_location_assignment PIN_AR76 -to rtile_pcie_tx_n_out[9]
set_location_assignment PIN_AJ74 -to rtile_pcie_tx_p_out[10]
set_location_assignment PIN_AF73 -to rtile_pcie_tx_n_out[10]
set_location_assignment PIN_Y77  -to rtile_pcie_tx_p_out[11]
set_location_assignment PIN_AC76 -to rtile_pcie_tx_n_out[11]
set_location_assignment PIN_V74  -to rtile_pcie_tx_p_out[12]
set_location_assignment PIN_T73  -to rtile_pcie_tx_n_out[12]
set_location_assignment PIN_K74  -to rtile_pcie_tx_p_out[13]
set_location_assignment PIN_G73  -to rtile_pcie_tx_n_out[13]
set_location_assignment PIN_C71  -to rtile_pcie_tx_p_out[14]
set_location_assignment PIN_E69  -to rtile_pcie_tx_n_out[14]
set_location_assignment PIN_M71  -to rtile_pcie_tx_p_out[15]
set_location_assignment PIN_P69  -to rtile_pcie_tx_n_out[15]

set_instance_assignment -name IO_STANDARD "1.0 V" -to pcie_ep_perstn -entity $top_module
set_instance_assignment -name IO_STANDARD HCSL -to pcie_ep_refclk1 -entity $top_module
set_instance_assignment -name IO_STANDARD HCSL -to pcie_ep_refclk0 -entity $top_module

set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[0] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[0] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[1] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[1] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[2] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[2] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[3] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[3] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[4] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[4] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[5] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[5] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[6] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[6] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[7] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[7] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[8] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[8] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[9] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[9] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[10] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[10] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[11] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[11] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[12] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[12] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[13] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[13] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[14] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[14] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_p_in[15] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_rx_n_in[15] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[0] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[0] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[1] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[1] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[2] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[2] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[3] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[3] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[4] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[4] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[5] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[5] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[6] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[6] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[7] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[7] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[8] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[8] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[9] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[9] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[10] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[10] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[11] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[11] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[12] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[12] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[13] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[13] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[14] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[14] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_p_out[15] -entity $top_module
set_instance_assignment -name IO_STANDARD "HIGH SPEED DIFFERENTIAL I/O" -to rtile_pcie_tx_n_out[15] -entity $top_module


########################################################################
# qsfpdd
# set_location_assignment PIN_N45 -to clk_sys_100m_p
# set_location_assignment PIN_EW75 -to qsfpdd_refclk_fht
# set_location_assignment PIN_HJ68 -to qsfpdd_refclk_fgt

# set_location_assignment PIN_DL78 -to qsfpdd0_rx_p[0]
# set_location_assignment PIN_EC78 -to qsfpdd0_rx_p[1]
# set_location_assignment PIN_ET78 -to qsfpdd0_rx_p[2]
# set_location_assignment PIN_FH78 -to qsfpdd0_rx_p[3]
# set_location_assignment PIN_DP79 -to qsfpdd0_rx_n[0]
# set_location_assignment PIN_EF79 -to qsfpdd0_rx_n[1]
# set_location_assignment PIN_EW79 -to qsfpdd0_rx_n[2]
# set_location_assignment PIN_FL79 -to qsfpdd0_rx_n[3]
# set_location_assignment PIN_DU82 -to qsfpdd0_tx_p[0]
# set_location_assignment PIN_EK82 -to qsfpdd0_tx_p[1]
# set_location_assignment PIN_FB82 -to qsfpdd0_tx_p[2]
# set_location_assignment PIN_FP82 -to qsfpdd0_tx_p[3]
# set_location_assignment PIN_DY81 -to qsfpdd0_tx_n[0]
# set_location_assignment PIN_EN81 -to qsfpdd0_tx_n[1]
# set_location_assignment PIN_FE81 -to qsfpdd0_tx_n[2]
# set_location_assignment PIN_FU81 -to qsfpdd0_tx_n[3]