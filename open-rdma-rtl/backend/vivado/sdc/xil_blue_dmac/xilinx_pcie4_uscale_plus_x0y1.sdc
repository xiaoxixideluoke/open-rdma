
# sys_clk vs TXOUTCLK
set_clock_groups -name async18 -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[31].*gen_gtye4_channel_inst[3].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]]
#
#
#
#
#
#
# ASYNC CLOCK GROUPINGS
# sys_clk vs user_clk
set_clock_groups -name async5 -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_userclk/O]]
# sys_clk vs pclk
set_clock_groups -name async1 -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O]]
#
#
#
# Add/Edit Pblock slice constraints for 512b soft logic to improve timing
create_pblock soft_512b; add_cells_to_pblock [get_pblocks soft_512b] [get_cells {pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_pcie_4_0_pipe_inst/pcie_4_0_init_ctrl_inst pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_pcie_4_0_pipe_inst/pcie4_0_512b_intfc_mod}]
# Keep This Logic Left/Right Side Of The PCIe Block (Whichever is near to the FPGA Boundary)
resize_pblock [get_pblocks soft_512b] -add {SLICE_X200Y240:SLICE_X231Y300}
set_property EXCLUDE_PLACEMENT 1 [get_pblocks soft_512b]
#
set_clock_groups -name async24 -asynchronous -group [get_clocks -of_objects [get_pins pcie4_uscale_plus_0_i/inst/pcie4_uscale_plus_0_gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_intclk/O]] -group [get_clocks {sys_clk}]
#
#create_waiver -type METHODOLOGY -id {LUTAR-1} -user "pcie4_uscale_plus" -desc "user link up is synchroized in the user clk so it is safe to ignore"  -internal -scoped -tags 1024539  -objects [get_cells { pcie_app_uscale_i/PIO_i/len_i[5]_i_4 }] -objects [get_pins { pcie4_uscale_plus_0_i/inst/user_lnk_up_cdc/arststages_ff_reg[0]/CLR pcie4_uscale_plus_0_i/inst/user_lnk_up_cdc/arststages_ff_reg[1]/CLR }] 

#--------------------- Adding waiver --------------------#

create_waiver -type DRC -id {REQP-1839} -tags "1167240" -scope -internal -user "pcie4_uscale_plus" -desc "DRC expects synchronous pins to be provided to BRAM inputs. Since synchronization is present one stage before, it is safe to ignore" -objects [get_cells -hierarchical -filter {NAME =~ {pcie_app_uscale_i/PIO_i/pio_ep/ep_mem/ep_xpm_sdpram/*mem_reg_bram_0}}]
create_waiver -type DRC -id {REQP-1840} -tags "1167240" -scope -internal -user "pcie4_uscale_plus" -desc "DRC expects synchronous pins to be provided to BRAM inputs. Since synchronization is present one stage before, it is safe to ignore" -objects [get_cells -hierarchical -filter {NAME =~ {pcie_app_uscale_i/PIO_i/pio_ep/ep_mem/ep_xpm_sdpram/*mem_reg_bram_0}}]

create_waiver -type CDC -id {CDC-1} -tags "1165868" -scope -internal -user "pcie4_uscale_plus" -desc "PCIe reset path -Safe to waive" -from [get_ports sys_rst_n] -to [get_pins -hier -filter {NAME =~ {*/user_clk_heartbeat_reg[*]/R}}]



create_pblock pblock_xilBdmaController
resize_pblock pblock_xilBdmaController -add {SLICE_X140Y236:SLICE_X232Y482 BUFG_GT_X1Y96:BUFG_GT_X1Y191 BUFG_GT_SYNC_X1Y60:BUFG_GT_SYNC_X1Y119 DSP48E2_X17Y96:DSP48E2_X31Y191 LAGUNA_X16Y232:LAGUNA_X31Y485 RAMB18_X9Y96:RAMB18_X13Y191 RAMB36_X9Y48:RAMB36_X13Y95 URAM288_X2Y64:URAM288_X4Y127}
add_cells_to_pblock pblock_xilBdmaController [get_cells [list bsv_top/bsvTopOnlyHardIp/xilBdmaController]]


create_pblock pblock_bsvTpWthtHrdIpInstnc
resize_pblock pblock_bsvTpWthtHrdIpInstnc -add {SLICE_X0Y238:SLICE_X180Y479 BUFG_GT_X0Y96:BUFG_GT_X0Y191 BUFG_GT_SYNC_X0Y60:BUFG_GT_SYNC_X0Y119 CMACE4_X0Y3:CMACE4_X0Y5 DSP48E2_X0Y96:DSP48E2_X17Y191 RAMB18_X0Y96:RAMB18_X8Y191 RAMB36_X0Y48:RAMB36_X8Y95 URAM288_X0Y64:URAM288_X2Y127}
add_cells_to_pblock pblock_bsvTpWthtHrdIpInstnc [get_cells [list bsv_top/bsvTopWithoutHardIpInstance]]
