set jtag_id [jtag::get_connected_devices]
jtag::open ${jtag_id}
jtag::initialize_scan_chain $jtag_id 0 0 0
# ac7t1500::noc_read 080c0000008
# ac7t1500::get_dict_spaces CSR_SPACE ETHERNET_0 400G_PCS
ac7t1500::csr_read_named CSR_SPACE ETHERNET_0 400G_PCS CONTROL1_0
jtag::close