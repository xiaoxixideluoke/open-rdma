`timescale 1ps / 1ps
`ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC

`define ENABLE_CMAC_RS_FEC

module bluerdma_top#(
   parameter          PL_LINK_CAP_MAX_LINK_WIDTH     = 16,            // 1- X1; 2 - X2; 4 - X4; 8 - X8
   parameter          C_DATA_WIDTH                   = 512,
   parameter          CMAC_GT_LANE_WIDTH             = 4,
   parameter          AXISTEN_IF_MC_RX_STRADDLE      = 1,
   parameter          PL_LINK_CAP_MAX_LINK_SPEED     = 4,  // 1- GEN1, 2 - GEN2, 4 - GEN3, 8 - GEN4
   parameter          KEEP_WIDTH                     = C_DATA_WIDTH / 32,
   parameter          EXT_PIPE_SIM                   = "FALSE",  // This Parameter has effect on selecting Enable External PIPE Interface in GUI.
   parameter          AXISTEN_IF_CC_ALIGNMENT_MODE   = "FALSE",
   parameter          AXISTEN_IF_CQ_ALIGNMENT_MODE   = "FALSE",
   parameter          AXISTEN_IF_RQ_ALIGNMENT_MODE   = "FALSE",
   parameter          AXISTEN_IF_RC_ALIGNMENT_MODE   = "FALSE",
   parameter          AXI4_CQ_TUSER_WIDTH            = 183,
   parameter          AXI4_CC_TUSER_WIDTH            = 81,
   parameter          AXI4_RQ_TUSER_WIDTH            = 137,
   parameter          AXI4_RC_TUSER_WIDTH            = 161,
   parameter          AXISTEN_IF_ENABLE_CLIENT_TAG   = 0,
   parameter          RQ_AVAIL_TAG_IDX               = 8,
   parameter          RQ_AVAIL_TAG                   = 256,
   parameter          AXISTEN_IF_RQ_PARITY_CHECK     = 0,
   parameter          AXISTEN_IF_CC_PARITY_CHECK     = 0,
   parameter          AXISTEN_IF_RC_PARITY_CHECK     = 0,
   parameter          AXISTEN_IF_CQ_PARITY_CHECK     = 0,
   parameter          AXISTEN_IF_ENABLE_RX_MSG_INTFC = "FALSE",
   parameter   [17:0] AXISTEN_IF_ENABLE_MSG_ROUTE    = 18'h2FFFF

)(
    // PCIe and XDMA
    output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_txp,
    output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_txn,
    input [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0]  pci_exp_rxp,
    input [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0]  pci_exp_rxn,

    input 					 sys_clk_p,
    input 					 sys_clk_n,
    input 					 sys_rst_n,

    input            board_sys_clk_n,
    input            board_sys_clk_p,


    // CMAC
    input qsfp1_ref_clk_p,
    input qsfp1_ref_clk_n,

    // input qsfp2_ref_clk_p,
    // input qsfp2_ref_clk_n,

    input  [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp1_rxn_in,
    input  [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp1_rxp_in,
    output [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp1_txn_out,
    output [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp1_txp_out,

    // input  [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp2_rxn_in,
    // input  [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp2_rxp_in,
    // output [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp2_txn_out,
    // output [CMAC_GT_LANE_WIDTH - 1 : 0] qsfp2_txp_out,

    input qsfp1_fault_in,
    output qsfp1_lpmode_out,
    output qsfp1_resetl_out

    // input qsfp2_fault_in,
    // output qsfp2_lpmode_out,
    // output qsfp2_resetl_out
);

  localparam AXIL_ADDR_WIDTH = 20;

  localparam CMAC_AXIS_TDATA_WIDTH = 512;
  localparam CMAC_AXIS_TKEEP_WIDTH = 64;
  localparam CMAC_AXIS_TUSER_WIDTH = 1;
   
   wire 					   user_lnk_up;
   wire              user_resetn;
   
   //----------------------------------------------------------------------------------------------------------------//
   //  AXI Interface                                                                                                 //
   //----------------------------------------------------------------------------------------------------------------//
   
   
   wire 					   user_lnk_up;
   
   //----------------------------------------------------------------------------------------------------------------//
   //  AXI Interface                                                                                                 //
   //----------------------------------------------------------------------------------------------------------------//
 
   wire                                       user_clk_250;
   wire                                       user_reset;
 
   wire                                       s_axis_rq_tlast;
   (*mark_debug, mark_debug_clock="user_clk_250" *)wire                 [C_DATA_WIDTH-1:0]    s_axis_rq_tdata;
   wire          [AXI4_RQ_TUSER_WIDTH-1:0]    s_axis_rq_tuser;
   wire                   [KEEP_WIDTH-1:0]    s_axis_rq_tkeep;
   (*mark_debug, mark_debug_clock="user_clk_250" *)wire                              [3:0]    s_axis_rq_tready;
   (*mark_debug, mark_debug_clock="user_clk_250" *)wire                                       s_axis_rq_tvalid;
 
   (*mark_debug, mark_debug_clock="user_clk_250" *)wire                 [C_DATA_WIDTH-1:0]    m_axis_rc_tdata;
   wire          [AXI4_RC_TUSER_WIDTH-1:0]    m_axis_rc_tuser;
   wire                                       m_axis_rc_tlast;
   wire                   [KEEP_WIDTH-1:0]    m_axis_rc_tkeep;
   (*mark_debug, mark_debug_clock="user_clk_250" *)wire                                       m_axis_rc_tvalid;
   (*mark_debug, mark_debug_clock="user_clk_250" *)wire                                       m_axis_rc_tready;
 
   wire                 [C_DATA_WIDTH-1:0]    m_axis_cq_tdata;
   wire          [AXI4_CQ_TUSER_WIDTH-1:0]    m_axis_cq_tuser;
   wire                                       m_axis_cq_tlast;
   wire                   [KEEP_WIDTH-1:0]    m_axis_cq_tkeep;
   wire                                       m_axis_cq_tvalid;
   wire                                       m_axis_cq_tready;
 
   wire                 [C_DATA_WIDTH-1:0]    s_axis_cc_tdata;
   wire          [AXI4_CC_TUSER_WIDTH-1:0]    s_axis_cc_tuser;
   wire                                       s_axis_cc_tlast;
   wire                   [KEEP_WIDTH-1:0]    s_axis_cc_tkeep;
   wire                                       s_axis_cc_tvalid;
   wire                              [3:0]    s_axis_cc_tready;
 
   wire                              [3:0]    pcie_tfc_nph_av;
   wire                              [3:0]    pcie_tfc_npd_av;
   //----------------------------------------------------------------------------------------------------------------//
   //  Configuration (CFG) Interface                                                                                 //
   //----------------------------------------------------------------------------------------------------------------//
 
   wire                                       pcie_cq_np_req;
   wire                              [5:0]    pcie_cq_np_req_count;
   wire                              [5:0]    pcie_rq_seq_num0;
   wire                                       pcie_rq_seq_num_vld0;
   wire                              [5:0]    pcie_rq_seq_num1;
   wire                                       pcie_rq_seq_num_vld1;
 
   //----------------------------------------------------------------------------------------------------------------//
   // EP and RP                                                                                                      //
   //----------------------------------------------------------------------------------------------------------------//
 
   wire                                       cfg_phy_link_down;
   wire                              [2:0]    cfg_negotiated_width;
   wire                              [1:0]    cfg_current_speed;
   wire                              [1:0]    cfg_max_payload;
   wire                              [2:0]    cfg_max_read_req;
   wire                              [15:0]    cfg_function_status;
   wire                              [11:0]    cfg_function_power_state;
   wire                             [503:0]    cfg_vf_status;
   wire                              [1:0]    cfg_link_power_state;
 
   // Error Reporting Interface
   wire                                       cfg_err_cor_out;
   wire                                       cfg_err_nonfatal_out;
   wire                                       cfg_err_fatal_out;
   wire                              [4:0]    cfg_local_error_out;
   wire                                       cfg_local_error_valid;
 
   wire                              [5:0]    cfg_ltssm_state;
   wire                              [3:0]    cfg_rcb_status;
   wire                              [1:0]    cfg_obff_enable;
   wire                                       cfg_pl_status_change;
 
   // Management Interface
   wire                             [9:0]    cfg_mgmt_addr;
   wire                                       cfg_mgmt_write;
   wire                             [31:0]    cfg_mgmt_write_data;
   wire                              [3:0]    cfg_mgmt_byte_enable;
   wire                                       cfg_mgmt_read;
   wire                             [31:0]    cfg_mgmt_read_data;
   wire                                       cfg_mgmt_read_write_done;
   wire                                       cfg_mgmt_type1_cfg_reg_access;
   wire                                       cfg_msg_received;
   wire                              [7:0]    cfg_msg_received_data;
   wire                              [4:0]    cfg_msg_received_type;
   wire                                       cfg_msg_transmit;
   wire                              [2:0]    cfg_msg_transmit_type;
   wire                             [31:0]    cfg_msg_transmit_data;
   wire                                       cfg_msg_transmit_done;
   wire                              [7:0]    cfg_fc_ph;
   wire                             [11:0]    cfg_fc_pd;
   wire                              [7:0]    cfg_fc_nph;
   wire                             [11:0]    cfg_fc_npd;
   wire                              [7:0]    cfg_fc_cplh;
   wire                             [11:0]    cfg_fc_cpld;
   wire                              [2:0]    cfg_fc_sel;
   wire                              [2:0]    cfg_per_func_status_control;
   wire                              [3:0]    cfg_per_function_number;
   wire                                       cfg_per_function_output_request;
 
   wire                             [63:0]    cfg_dsn;
   wire                                       cfg_power_state_change_interrupt;
   wire                                       cfg_power_state_change_ack;
   wire                                       cfg_err_cor_in;
   wire                                       cfg_err_uncor_in;
 
   wire                              [3:0]    cfg_flr_in_process;
   wire                              [1:0]    cfg_flr_done;
   wire                              [251:0]  cfg_vf_flr_in_process;
   wire                                       cfg_vf_flr_done;
   wire                              [7:0]    cfg_vf_flr_func_num;
 
   wire                                       cfg_link_training_enable;
 
   //----------------------------------------------------------------------------------------------------------------//
   // EP Only                                                                                                        //
   //----------------------------------------------------------------------------------------------------------------//
 
   // Interrupt Interface Signals
   wire                              [3:0]    cfg_interrupt_int;
   wire                              [1:0]    cfg_interrupt_pending;
   wire                                       cfg_interrupt_sent;
 
   wire                              [3:0]    cfg_interrupt_msi_enable;
   wire                              [11:0]   cfg_interrupt_msi_mmenable;
   wire                                       cfg_interrupt_msi_mask_update;
   wire                             [31:0]    cfg_interrupt_msi_data;
   wire                              [1:0]    cfg_interrupt_msi_select;
   wire                             [31:0]    cfg_interrupt_msi_int;
   wire                             [63:0]    cfg_interrupt_msi_pending_status;
   wire                                       cfg_interrupt_msi_sent;
   wire                                       cfg_interrupt_msi_fail;
   wire                              [2:0]    cfg_interrupt_msi_attr;
   wire                                       cfg_interrupt_msi_tph_present;
   wire                              [1:0]    cfg_interrupt_msi_tph_type;
   wire                              [7:0]    cfg_interrupt_msi_tph_st_tag;
   wire                              [7:0]    cfg_interrupt_msi_function_number;
 
 // EP only
   wire                                       cfg_hot_reset_out;
   wire                                       cfg_config_space_enable;
   wire                                       cfg_req_pm_transition_l23_ready;
 
 // RP only
   wire                                       cfg_hot_reset_in;
 
   wire                              [7:0]    cfg_ds_port_number;
   wire                              [7:0]    cfg_ds_bus_number;
   wire                              [4:0]    cfg_ds_device_number;
 
   //----------------------------------------------------------------------------------------------------------------//
   //    System(SYS) Interface                                                                                       //
   //----------------------------------------------------------------------------------------------------------------//
 
     wire                                    sys_clk;
     wire                                    sys_clk_gt;
     wire                                    global_reset_100mhz_clk;
     wire                                    sys_rst_n_c;
 
 
     wire [33 : 0] tlpSizeDebugPort;
     wire RDY_tlpSizeDebugPort;
 
 

  // Ref clock buffer
  IBUFDS_GTE4 # (.REFCLK_HROW_CK_SEL(2'b00)) refclk_ibuf (.O(sys_clk_gt), .ODIV2(sys_clk), .I(sys_clk_p), .CEB(1'b0), .IB(sys_clk_n));
  // Reset buffer
  IBUF   sys_reset_n_ibuf (.O(sys_rst_n_c), .I(sys_rst_n));
  

  IBUFDS IBUFDS_inst (
      .O(global_reset_100mhz_clk),    // 1-bit output: Buffer output
      .I(board_sys_clk_p),            // 1-bit input: Diff_p buffer input (connect directly to top-level port)
      .IB(board_sys_clk_n)            // 1-bit input: Diff_n buffer input (connect directly to top-level port)
  );



// GT Signals
    wire            gt_txusrclk2;
    wire            gt_usr_tx_reset;
    wire            gt_usr_rx_reset;

    wire            gt_rx_axis_tvalid;
    wire            gt_rx_axis_tready;
    wire            gt_rx_axis_tlast;
    wire [CMAC_AXIS_TDATA_WIDTH - 1 : 0] gt_rx_axis_tdata;
    wire [CMAC_AXIS_TKEEP_WIDTH - 1 : 0] gt_rx_axis_tkeep;
    wire [CMAC_AXIS_TUSER_WIDTH - 1 : 0] gt_rx_axis_tuser;

    wire            gt_stat_rx_aligned;
    wire [8:0]      gt_stat_rx_pause_req;
    wire [2:0]      gt_stat_rx_bad_fcs;
    wire [2:0]      gt_stat_rx_stomped_fcs;
    wire            gt_ctl_rx_enable;
    wire            gt_ctl_rx_force_resync;
    wire            gt_ctl_rx_test_pattern;
    wire            gt_ctl_rx_check_etype_gcp;
    wire            gt_ctl_rx_check_etype_gpp;
    wire            gt_ctl_rx_check_etype_pcp;
    wire            gt_ctl_rx_check_etype_ppp;
    wire            gt_ctl_rx_check_mcast_gcp;
    wire            gt_ctl_rx_check_mcast_gpp;
    wire            gt_ctl_rx_check_mcast_pcp;
    wire            gt_ctl_rx_check_mcast_ppp;
    wire            gt_ctl_rx_check_opcode_gcp;
    wire            gt_ctl_rx_check_opcode_gpp;
    wire            gt_ctl_rx_check_opcode_pcp;
    wire            gt_ctl_rx_check_opcode_ppp;
    wire            gt_ctl_rx_check_sa_gcp;
    wire            gt_ctl_rx_check_sa_gpp;
    wire            gt_ctl_rx_check_sa_pcp;
    wire            gt_ctl_rx_check_sa_ppp;
    wire            gt_ctl_rx_check_ucast_gcp;
    wire            gt_ctl_rx_check_ucast_gpp;
    wire            gt_ctl_rx_check_ucast_pcp;
    wire            gt_ctl_rx_check_ucast_ppp;
    wire            gt_ctl_rx_enable_gcp;
    wire            gt_ctl_rx_enable_gpp;
    wire            gt_ctl_rx_enable_pcp;
    wire            gt_ctl_rx_enable_ppp;
    wire [8:0]      gt_ctl_rx_pause_ack;
    wire [8:0]      gt_ctl_rx_pause_enable;

     wire            gt_tx_axis_tready;
     wire            gt_tx_axis_tvalid;
    wire            gt_tx_axis_tlast;
     wire [CMAC_AXIS_TDATA_WIDTH - 1 : 0] gt_tx_axis_tdata;
    wire [CMAC_AXIS_TKEEP_WIDTH - 1 : 0] gt_tx_axis_tkeep;
    wire [CMAC_AXIS_TUSER_WIDTH - 1 : 0] gt_tx_axis_tuser;

    wire            gt_tx_ovfout;
    wire            gt_tx_unfout;
    wire            gt_ctl_tx_enable;
    wire            gt_ctl_tx_test_pattern;
    wire            gt_ctl_tx_send_idle;
    wire            gt_ctl_tx_send_rfi;
    wire            gt_ctl_tx_send_lfi;
    wire [8:0]      gt_ctl_tx_pause_enable;
    wire [15:0]     gt_ctl_tx_pause_quanta0;
    wire [15:0]     gt_ctl_tx_pause_quanta1;
    wire [15:0]     gt_ctl_tx_pause_quanta2;
    wire [15:0]     gt_ctl_tx_pause_quanta3;
    wire [15:0]     gt_ctl_tx_pause_quanta4;
    wire [15:0]     gt_ctl_tx_pause_quanta5;
    wire [15:0]     gt_ctl_tx_pause_quanta6;
    wire [15:0]     gt_ctl_tx_pause_quanta7;
    wire [15:0]     gt_ctl_tx_pause_quanta8;
    wire [8:0]      gt_ctl_tx_pause_req;
    wire            gt_ctl_tx_resend_pause;


    // CMAC RS-FEC Signals
    wire            gt_ctl_rsfec_ieee_error_indication_mode;
    wire            gt_ctl_tx_rsfec_enable;
    wire            gt_ctl_rx_rsfec_enable;
    wire            gt_ctl_rx_rsfec_enable_correction;
    wire            gt_ctl_rx_rsfec_enable_indication;

    // CMAC CTRL STATE
    wire [3:0]      cmac_ctrl_tx_state;
    wire [3:0]      cmac_ctrl_rx_state;
    wire            is_cmac_rx_aligned;


    reg qsfp_reset_flag_reg;

    always @ (negedge user_resetn) begin
      qsfp_reset_flag_reg <= !qsfp_reset_flag_reg;
    end

    assign qsfp1_lpmode_out = 1'b0;
    assign qsfp1_resetl_out = 1'b1;

    // assign qsfp2_lpmode_out = 1'b0;
    // assign qsfp2_resetl_out = 1'b1;



    always @ (negedge user_resetn) begin
      qsfp_reset_flag_reg <= !qsfp_reset_flag_reg;
    end


    reg user_resetn_buffer_reg;
    always @ (posedge user_clk_250) begin
      user_resetn_buffer_reg <= ~user_reset;
    end
    assign user_resetn = user_resetn_buffer_reg;

    pcie4_uscale_plus_0  pcie4_uscale_plus_0_i (
    //---------------------------------------------------------------------------------------//
    //  PCI Express (pci_exp) Interface                                                      //
    //---------------------------------------------------------------------------------------//

      // Tx
      .pci_exp_txn                                    ( pci_exp_txn ),
      .pci_exp_txp                                    ( pci_exp_txp ),

      // Rx
      .pci_exp_rxn                                    ( pci_exp_rxn ),
      .pci_exp_rxp                                    ( pci_exp_rxp ),
      
      //---------------------------------------------------------------------------------------//
      //  AXI Interface                                                                        //
      //---------------------------------------------------------------------------------------//

      .user_clk                                       ( user_clk_250 ),
      .user_reset                                     ( user_reset ),
      .user_lnk_up                                    ( user_lnk_up ),
      // .phy_rdy_out                                    ( phy_rdy_out ),
    
      .s_axis_rq_tlast                                ( s_axis_rq_tlast ),
      .s_axis_rq_tdata                                ( s_axis_rq_tdata ),
      .s_axis_rq_tuser                                ( s_axis_rq_tuser ),
      .s_axis_rq_tkeep                                ( s_axis_rq_tkeep ),
      .s_axis_rq_tready                               ( s_axis_rq_tready ),
      .s_axis_rq_tvalid                               ( s_axis_rq_tvalid ),

      .m_axis_rc_tdata                                ( m_axis_rc_tdata ),
      .m_axis_rc_tuser                                ( m_axis_rc_tuser ),
      .m_axis_rc_tlast                                ( m_axis_rc_tlast ),
      .m_axis_rc_tkeep                                ( m_axis_rc_tkeep ),
      .m_axis_rc_tvalid                               ( m_axis_rc_tvalid ),
      .m_axis_rc_tready                               ( m_axis_rc_tready ),

      .m_axis_cq_tdata                                ( m_axis_cq_tdata ),
      .m_axis_cq_tuser                                ( m_axis_cq_tuser ),
      .m_axis_cq_tlast                                ( m_axis_cq_tlast ),
      .m_axis_cq_tkeep                                ( m_axis_cq_tkeep ),
      .m_axis_cq_tvalid                               ( m_axis_cq_tvalid ),
      .m_axis_cq_tready                               ( m_axis_cq_tready ),

      .s_axis_cc_tdata                                ( s_axis_cc_tdata ),
      .s_axis_cc_tuser                                ( s_axis_cc_tuser ),
      .s_axis_cc_tlast                                ( s_axis_cc_tlast ),
      .s_axis_cc_tkeep                                ( s_axis_cc_tkeep ),
      .s_axis_cc_tvalid                               ( s_axis_cc_tvalid ),
      .s_axis_cc_tready                               ( s_axis_cc_tready ),



      //---------------------------------------------------------------------------------------//
      //  Configuration (CFG) Interface                                                        //
      //---------------------------------------------------------------------------------------//
      .pcie_tfc_nph_av                                ( pcie_tfc_nph_av ),
      .pcie_tfc_npd_av                                ( pcie_tfc_npd_av ),

      .pcie_rq_seq_num0                               ( pcie_rq_seq_num0     ) ,
      .pcie_rq_seq_num_vld0                           ( pcie_rq_seq_num_vld0 ) ,
      .pcie_rq_seq_num1                               ( pcie_rq_seq_num1     ) ,
      .pcie_rq_seq_num_vld1                           ( pcie_rq_seq_num_vld1 ) ,
      .pcie_rq_tag0                                   ( ) ,
      .pcie_rq_tag1                                   ( ) ,
      .pcie_rq_tag_av                                 ( ) ,
      .pcie_rq_tag_vld0                               ( ) ,
      .pcie_rq_tag_vld1                               ( ) ,
      .pcie_cq_np_req                                 ( {1'b1,pcie_cq_np_req} ),
      .pcie_cq_np_req_count                           ( pcie_cq_np_req_count ),
      .cfg_phy_link_down                              ( cfg_phy_link_down ),
      .cfg_phy_link_status                            ( ),
      .cfg_negotiated_width                           ( cfg_negotiated_width ),
      .cfg_current_speed                              ( cfg_current_speed ),
      .cfg_max_payload                                ( cfg_max_payload ),
      .cfg_max_read_req                               ( cfg_max_read_req ),
      .cfg_function_status                            ( cfg_function_status ),
      .cfg_function_power_state                       ( cfg_function_power_state ),
      .cfg_vf_status                                  ( cfg_vf_status ),
      .cfg_vf_power_state                             ( ),
      .cfg_link_power_state                           ( cfg_link_power_state ),
      // Error Reporting Interface
      .cfg_err_cor_out                                ( cfg_err_cor_out ),
      .cfg_err_nonfatal_out                           ( cfg_err_nonfatal_out ),
      .cfg_err_fatal_out                              ( cfg_err_fatal_out ),

      .cfg_local_error_out                            (cfg_local_error_out ),
      .cfg_local_error_valid                          (cfg_local_error_valid ),

      .cfg_ltssm_state                                ( cfg_ltssm_state ),
      .cfg_rx_pm_state                                ( ),
      .cfg_tx_pm_state                                ( ), 
      .cfg_rcb_status                                 ( cfg_rcb_status ),
    
      .cfg_obff_enable                                ( cfg_obff_enable ),
      .cfg_pl_status_change                           ( cfg_pl_status_change ),

      .cfg_tph_requester_enable                       ( ),
      .cfg_tph_st_mode                                ( ),
      .cfg_vf_tph_requester_enable                    ( ),
      .cfg_vf_tph_st_mode                             ( ),
      // Management Interface
      .cfg_mgmt_addr                                  ( cfg_mgmt_addr ),
      .cfg_mgmt_write                                 ( cfg_mgmt_write ),
      .cfg_mgmt_write_data                            ( cfg_mgmt_write_data ),
      .cfg_mgmt_byte_enable                           ( cfg_mgmt_byte_enable ),
      .cfg_mgmt_read                                  ( cfg_mgmt_read ),
      .cfg_mgmt_read_data                             ( cfg_mgmt_read_data ),
      .cfg_mgmt_read_write_done                       ( cfg_mgmt_read_write_done ),
      .cfg_mgmt_debug_access                          (1'b0),
      .cfg_mgmt_function_number                       (8'b0),
      .cfg_pm_aspm_l1_entry_reject                    (1'b0),
      .cfg_pm_aspm_tx_l0s_entry_disable               (1'b1),

      .cfg_msg_received                               ( cfg_msg_received ),
      .cfg_msg_received_data                          ( cfg_msg_received_data ),
      .cfg_msg_received_type                          ( cfg_msg_received_type ),

      .cfg_msg_transmit                               ( cfg_msg_transmit ),
      .cfg_msg_transmit_type                          ( cfg_msg_transmit_type ),
      .cfg_msg_transmit_data                          ( cfg_msg_transmit_data ),
      .cfg_msg_transmit_done                          ( cfg_msg_transmit_done ),

      .cfg_fc_ph                                      ( cfg_fc_ph ),
      .cfg_fc_pd                                      ( cfg_fc_pd ),
      .cfg_fc_nph                                     ( cfg_fc_nph ),
      .cfg_fc_npd                                     ( cfg_fc_npd ),
      .cfg_fc_cplh                                    ( cfg_fc_cplh ),
      .cfg_fc_cpld                                    ( cfg_fc_cpld ),
      .cfg_fc_sel                                     ( cfg_fc_sel ),

      //-------------------------------------------------------------------------------//
      // EP and RP                                                                     //
      //-------------------------------------------------------------------------------//
      .cfg_bus_number                                 ( ), 
      .cfg_dsn                                        ( cfg_dsn ),
      .cfg_power_state_change_ack                     ( cfg_power_state_change_ack ),
      .cfg_power_state_change_interrupt               ( cfg_power_state_change_interrupt ),
      .cfg_err_cor_in                                 ( cfg_err_cor_in ),
      .cfg_err_uncor_in                               ( cfg_err_uncor_in ),

      .cfg_flr_in_process                             ( cfg_flr_in_process ),
      .cfg_flr_done                                   ( {2'b0,cfg_flr_done} ),
      .cfg_vf_flr_in_process                          ( cfg_vf_flr_in_process ),
      .cfg_vf_flr_done                                ( cfg_vf_flr_done ),
      .cfg_link_training_enable                       ( cfg_link_training_enable ),
    // EP only
      .cfg_hot_reset_out                              ( cfg_hot_reset_out ),
      .cfg_config_space_enable                        ( cfg_config_space_enable ),
      .cfg_req_pm_transition_l23_ready                ( cfg_req_pm_transition_l23_ready ),

    // RP only
      .cfg_hot_reset_in                               ( cfg_hot_reset_in ),

      .cfg_ds_bus_number                              ( cfg_ds_bus_number ),
      .cfg_ds_device_number                           ( cfg_ds_device_number ),
      .cfg_ds_port_number                             ( cfg_ds_port_number ),
      .cfg_vf_flr_func_num                            (cfg_vf_flr_func_num),

      //-------------------------------------------------------------------------------//
      // EP Only                                                                       //
      //-------------------------------------------------------------------------------//

      // Interrupt Interface Signals
      .cfg_interrupt_int                              ( cfg_interrupt_int ),
      .cfg_interrupt_pending                          ( {2'b0,cfg_interrupt_pending} ),
      .cfg_interrupt_sent                             ( cfg_interrupt_sent ),



      // MSI Interface
      .cfg_interrupt_msi_enable                       ( cfg_interrupt_msi_enable ),
      .cfg_interrupt_msi_mmenable                     ( cfg_interrupt_msi_mmenable ),
      .cfg_interrupt_msi_mask_update                  ( cfg_interrupt_msi_mask_update ),
      .cfg_interrupt_msi_data                         ( cfg_interrupt_msi_data ),
      .cfg_interrupt_msi_select                       ( cfg_interrupt_msi_select ),
      .cfg_interrupt_msi_int                          ( cfg_interrupt_msi_int ),
      .cfg_interrupt_msi_pending_status               ( cfg_interrupt_msi_pending_status [31:0]),
      .cfg_interrupt_msi_sent                         ( cfg_interrupt_msi_sent ),
      .cfg_interrupt_msi_fail                         ( cfg_interrupt_msi_fail ),
      .cfg_interrupt_msi_attr                         ( cfg_interrupt_msi_attr ),
      .cfg_interrupt_msi_tph_present                  ( cfg_interrupt_msi_tph_present ),
      .cfg_interrupt_msi_tph_type                     ( cfg_interrupt_msi_tph_type ),
      .cfg_interrupt_msi_tph_st_tag                   ( cfg_interrupt_msi_tph_st_tag ),
      .cfg_interrupt_msi_pending_status_function_num  ( 2'b0),
      .cfg_interrupt_msi_pending_status_data_enable   ( 1'b0),
      
      .cfg_interrupt_msi_function_number              ( cfg_interrupt_msi_function_number ),


      //--------------------------------------------------------------------------------------//
      //  System(SYS) Interface                                                               //
      //--------------------------------------------------------------------------------------//

      .sys_clk                                        ( sys_clk ),
      .sys_clk_gt                                     ( sys_clk_gt ),
      .sys_reset                                      ( sys_rst_n_c )
    );


    mkBsvTop bsv_top(
      .cmac_rxtx_clk(gt_txusrclk2),
      .cmac_rx_resetn(~gt_usr_rx_reset),
      .cmac_tx_resetn(~gt_usr_tx_reset),
      .CLK(user_clk_250),
      .RST_N(user_resetn),

      // PCIe

      .m_axis_rq_tvalid( s_axis_rq_tvalid ),
      .m_axis_rq_tdata( s_axis_rq_tdata ),
      .m_axis_rq_tkeep( s_axis_rq_tkeep ),
      .m_axis_rq_tlast( s_axis_rq_tlast ),
      .m_axis_rq_tuser( s_axis_rq_tuser ),
      .m_axis_rq_tready( s_axis_rq_tready ),
      
      .pcie_rq_tag_vld0( ),
      .pcie_rq_tag_vld1( ),
      .pcie_rq_tag0( ),
      .pcie_rq_tag1( ),
      .pcie_rq_seq_num_vld0( pcie_rq_seq_num_vld0 ),
      .pcie_rq_seq_num_vld1( pcie_rq_seq_num_vld1 ),
      .pcie_rq_seq_num0( pcie_rq_seq_num0     ),
      .pcie_rq_seq_num1( pcie_rq_seq_num1     ),
  
      .s_axis_rc_tvalid( m_axis_rc_tvalid ),
      .s_axis_rc_tdata( m_axis_rc_tdata ),
      .s_axis_rc_tkeep( m_axis_rc_tkeep ),
      .s_axis_rc_tlast( m_axis_rc_tlast ),
      .s_axis_rc_tuser( m_axis_rc_tuser ),
      .s_axis_rc_tready( m_axis_rc_tready ),
  
      .s_axis_cq_tvalid( m_axis_cq_tvalid ),
      .s_axis_cq_tdata( m_axis_cq_tdata ),
      .s_axis_cq_tkeep( m_axis_cq_tkeep ),
      .s_axis_cq_tlast( m_axis_cq_tlast ),
      .s_axis_cq_tuser( m_axis_cq_tuser ),
      .s_axis_cq_tready( m_axis_cq_tready ),
  
      .pcie_cq_np_req( pcie_cq_np_req ),
      .pcie_cq_np_req_count(pcie_cq_np_req_count),
  
      .m_axis_cc_tvalid( s_axis_cc_tvalid ),
      .m_axis_cc_tdata( s_axis_cc_tdata ),
      .m_axis_cc_tkeep( s_axis_cc_tkeep ),
      .m_axis_cc_tlast( s_axis_cc_tlast ),
      .m_axis_cc_tuser( s_axis_cc_tuser ),
      .m_axis_cc_tready( s_axis_cc_tready[0] ),
  
      .cfg_mgmt_addr( cfg_mgmt_addr ),
      .cfg_mgmt_byte_enable( cfg_mgmt_byte_enable ),
      // .cfg_mgmt_debug_access,
      // .cfg_mgmt_function_number,
      .cfg_mgmt_read( cfg_mgmt_read ),
      .cfg_mgmt_write_data( cfg_mgmt_write_data ),
      .cfg_mgmt_write( cfg_mgmt_write ),
      .cfg_mgmt_read_data( cfg_mgmt_read_data ),
      .cfg_mgmt_read_write_done( cfg_mgmt_read_write_done ),

      // cfg_pm_aspm_l1_entry_reject,
      // cfg_pm_aspm_tx_l0s_entry_disable,
  
      .cfg_interrupt_msi_int( cfg_interrupt_msi_int ),
      .cfg_interrupt_msi_function_number( cfg_interrupt_msi_function_number ),
      .cfg_interrupt_msi_pending_status( cfg_interrupt_msi_pending_status ),
      // .cfg_interrupt_msi_pending_status_function_num,
      // .cfg_interrupt_msi_pending_status_data_enable,
      .cfg_interrupt_msi_select( cfg_interrupt_msi_select ),
      .cfg_interrupt_msi_attr( cfg_interrupt_msi_attr ),
      .cfg_interrupt_msi_tph_present( cfg_interrupt_msi_tph_present ),
      .cfg_interrupt_msi_tph_type( cfg_interrupt_msi_tph_type ),
      .cfg_interrupt_msi_tph_st_tag( cfg_interrupt_msi_tph_st_tag ),
      .cfg_interrupt_msi_enable( cfg_interrupt_msi_enable[0] ),
      .cfg_interrupt_msi_sent( cfg_interrupt_msi_sent ),
      .cfg_interrupt_msi_fail( cfg_interrupt_msi_fail ),
      .cfg_interrupt_msi_mmenable( cfg_interrupt_msi_mmenable[5:0] ),
      .cfg_interrupt_msi_mask_update( cfg_interrupt_msi_mask_update ),
      .cfg_interrupt_msi_data( cfg_interrupt_msi_data ),
  
      .cfg_interrupt_int( cfg_interrupt_int ),
      .cfg_interrupt_pending( cfg_interrupt_pending ),
      .cfg_interrupt_sent( cfg_interrupt_sent ),

      .cfg_hot_reset_out( cfg_hot_reset_in ),
      .cfg_hot_reset_in( cfg_hot_reset_out ),
  
      .cfg_config_space_enable( cfg_config_space_enable ),
  
      .cfg_dsn( cfg_dsn ),
      .cfg_ds_bus_number( cfg_ds_bus_number ),
      .cfg_ds_device_number( cfg_ds_device_number ),
      .cfg_ds_function_number( ),

      .cfg_power_state_change_ack( cfg_power_state_change_ack ),
      .cfg_power_state_change_interrupt( cfg_power_state_change_interrupt ),
  
      .cfg_ds_port_number( cfg_ds_port_number ),
      .cfg_err_cor_in( cfg_err_cor_in ),
      .cfg_err_cor_out( cfg_err_cor_out ),
      .cfg_err_fatal_out( cfg_err_fatal_out ),
      .cfg_err_nonfatal_out( cfg_err_nonfatal_out ),
      .cfg_err_uncor_in( cfg_err_uncor_in ),
  
      .cfg_flr_done( cfg_flr_done ),
      .cfg_vf_flr_done( cfg_vf_flr_done ),
  
      .cfg_vf_flr_func_num( cfg_vf_flr_func_num ),
  
      .cfg_flr_in_process( cfg_flr_in_process [1:0] ),
      .cfg_vf_flr_in_process( cfg_vf_flr_in_process ),
  
      .cfg_req_pm_transition_l23_ready( cfg_req_pm_transition_l23_ready ),
      .cfg_link_training_enable( cfg_link_training_enable ),
      // cfg_bus_number,
      // cfg_vend_id,
      // cfg_subsys_vend_id,
  
      // cfg_dev_id_pf0,
      // cfg_dev_id_pf1,
      // cfg_dev_id_pf2,
      // cfg_dev_id_pf3,
  
      // cfg_rev_id_pf0,
      // cfg_rev_id_pf1,
      // cfg_rev_id_pf2,
      // cfg_rev_id_pf3,
  
      // cfg_subsys_id_pf0,
      // cfg_subsys_id_pf1,
      // cfg_subsys_id_pf2,
      // cfg_subsys_id_pf3,
  
      .cfg_fc_ph( cfg_fc_ph ),
      .cfg_fc_nph( cfg_fc_nph ),
      .cfg_fc_cplh( cfg_fc_cplh ),
      .cfg_fc_pd( cfg_fc_pd ),
      .cfg_fc_npd( cfg_fc_npd ),
      .cfg_fc_cpld( cfg_fc_cpld ),
      .cfg_fc_sel( cfg_fc_sel ),

      .cfg_msg_transmit( cfg_msg_transmit ),
      .cfg_msg_transmit_type( cfg_msg_transmit_type ),
      .cfg_msg_transmit_data( cfg_msg_transmit_data ),
      .cfg_msg_transmit_done( cfg_msg_transmit_done ),
      .cfg_msg_received( cfg_msg_received ),
      .cfg_msg_received_data( cfg_msg_received_data ),
      .cfg_msg_received_type( cfg_msg_received_type ),
  
      .cfg_phy_link_down( cfg_phy_link_down ),
      // cfg_phy_link_status,
      .cfg_negotiated_width( cfg_negotiated_width ),
      .cfg_current_speed( cfg_current_speed ),
      .cfg_max_payload( cfg_max_payload ),
      .cfg_max_read_req( cfg_max_read_req ),
      .cfg_function_status( cfg_function_status [7:0] ),
      .cfg_vf_status( cfg_vf_status ),
      .cfg_function_power_state( cfg_function_power_state [5:0] ),
      // cfg_vf_power_state,
      .cfg_link_power_state( cfg_link_power_state ),
      // cfg_local_error_out,
      // cfg_local_error_valid,
      // cfg_rx_pm_state,
      // cfg_tx_pm_state,
      .cfg_ltssm_state( cfg_ltssm_state ),
      .cfg_rcb_status( cfg_rcb_status [1:0]),
      // cfg_dpa_substage_change,
      .cfg_obff_enable( cfg_obff_enable ),
  
      .pcie_tfc_nph_av( pcie_tfc_nph_av[1:0]),
      .pcie_tfc_npd_av( pcie_tfc_npd_av[1:0]),
  
      .user_lnk_up( user_lnk_up ),
  
      .tlpSizeDebugPort(tlpSizeDebugPort),
      .RDY_tlpSizeDebugPort(RDY_tlpSizeDebugPort),
  
      // sys_reset,
      // RDY_sys_reset

      // CMAC Interface

      .cmac_tx_axis_tvalid    (gt_tx_axis_tvalid),
      .cmac_tx_axis_tdata     (gt_tx_axis_tdata ),
      .cmac_tx_axis_tkeep     (gt_tx_axis_tkeep ),
      .cmac_tx_axis_tlast     (gt_tx_axis_tlast ),
      .cmac_tx_axis_tuser     (gt_tx_axis_tuser ),
      .cmac_tx_axis_tready    (gt_tx_axis_tready),

      .tx_stat_ovfout         (gt_tx_ovfout),
      .tx_stat_unfout         (gt_tx_unfout),
      .tx_stat_rx_aligned     (gt_stat_rx_aligned),

      .tx_ctl_enable          (gt_ctl_tx_enable      ),
      .tx_ctl_test_pattern    (gt_ctl_tx_test_pattern),
      .tx_ctl_send_idle       (gt_ctl_tx_send_idle   ),
      .tx_ctl_send_lfi        (gt_ctl_tx_send_lfi    ),
      .tx_ctl_send_rfi        (gt_ctl_tx_send_rfi    ),
      .tx_ctl_reset           (),

      .tx_ctl_pause_enable    (gt_ctl_tx_pause_enable ),
      .tx_ctl_pause_req       (gt_ctl_tx_pause_req    ),
      .tx_ctl_pause_quanta0   (gt_ctl_tx_pause_quanta0),
      .tx_ctl_pause_quanta1   (gt_ctl_tx_pause_quanta1),
      .tx_ctl_pause_quanta2   (gt_ctl_tx_pause_quanta2),
      .tx_ctl_pause_quanta3   (gt_ctl_tx_pause_quanta3),
      .tx_ctl_pause_quanta4   (gt_ctl_tx_pause_quanta4),
      .tx_ctl_pause_quanta5   (gt_ctl_tx_pause_quanta5),
      .tx_ctl_pause_quanta6   (gt_ctl_tx_pause_quanta6),
      .tx_ctl_pause_quanta7   (gt_ctl_tx_pause_quanta7),
      .tx_ctl_pause_quanta8   (gt_ctl_tx_pause_quanta8),

      .cmac_rx_axis_tvalid    (gt_rx_axis_tvalid),
      .cmac_rx_axis_tdata     (gt_rx_axis_tdata ),
      .cmac_rx_axis_tkeep     (gt_rx_axis_tkeep ),
      .cmac_rx_axis_tlast     (gt_rx_axis_tlast ),
      .cmac_rx_axis_tuser     (gt_rx_axis_tuser ),
      .cmac_rx_axis_tready    (gt_rx_axis_tready),

      .rx_stat_aligned        (gt_stat_rx_aligned    ),
      .rx_stat_pause_req      (gt_stat_rx_pause_req  ),
      .rx_ctl_enable          (gt_ctl_rx_enable      ),
      .rx_ctl_force_resync    (gt_ctl_rx_force_resync),
      .rx_ctl_test_pattern    (gt_ctl_rx_test_pattern),
      .rx_ctl_reset           (),
      .rx_ctl_pause_enable    (gt_ctl_rx_pause_enable),
      .rx_ctl_pause_ack       (gt_ctl_rx_pause_ack   ),

      .rx_ctl_enable_gcp      (gt_ctl_rx_enable_gcp),
      .rx_ctl_check_mcast_gcp (gt_ctl_rx_check_mcast_gcp),
      .rx_ctl_check_ucast_gcp (gt_ctl_rx_check_ucast_gcp),
      .rx_ctl_check_sa_gcp    (gt_ctl_rx_check_sa_gcp),
      .rx_ctl_check_etype_gcp (gt_ctl_rx_check_etype_gcp),
      .rx_ctl_check_opcode_gcp(gt_ctl_rx_check_opcode_gcp),

      .rx_ctl_enable_pcp      (gt_ctl_rx_enable_pcp),
      .rx_ctl_check_mcast_pcp (gt_ctl_rx_check_mcast_pcp),
      .rx_ctl_check_ucast_pcp (gt_ctl_rx_check_ucast_pcp),
      .rx_ctl_check_sa_pcp    (gt_ctl_rx_check_sa_pcp),
      .rx_ctl_check_etype_pcp (gt_ctl_rx_check_etype_pcp),
      .rx_ctl_check_opcode_pcp(gt_ctl_rx_check_opcode_pcp),

      .rx_ctl_enable_gpp      (gt_ctl_rx_enable_gpp),
      .rx_ctl_check_mcast_gpp (gt_ctl_rx_check_mcast_gpp),
      .rx_ctl_check_ucast_gpp (gt_ctl_rx_check_ucast_gpp),
      .rx_ctl_check_sa_gpp    (gt_ctl_rx_check_sa_gpp),
      .rx_ctl_check_etype_gpp (gt_ctl_rx_check_etype_gpp),
      .rx_ctl_check_opcode_gpp(gt_ctl_rx_check_opcode_gpp),

      .rx_ctl_enable_ppp      (gt_ctl_rx_enable_ppp),
      .rx_ctl_check_mcast_ppp (gt_ctl_rx_check_mcast_ppp),
      .rx_ctl_check_ucast_ppp (gt_ctl_rx_check_ucast_ppp),
      .rx_ctl_check_sa_ppp    (gt_ctl_rx_check_sa_ppp),
      .rx_ctl_check_etype_ppp (gt_ctl_rx_check_etype_ppp),
      .rx_ctl_check_opcode_ppp(gt_ctl_rx_check_opcode_ppp),

      .tx_ctl_rsfec_enable    (gt_ctl_tx_rsfec_enable),
      .rx_ctl_rsfec_enable    (gt_ctl_rx_rsfec_enable),
      .rx_ctl_rsfec_enable_correction(gt_ctl_rx_rsfec_enable_correction),
      .rx_ctl_rsfec_enable_indication(gt_ctl_rx_rsfec_enable_indication),
      .ctl_rsfec_ieee_error_indication_mode(gt_ctl_rsfec_ieee_error_indication_mode),

      // Controller State
      .cmac_ctrl_tx_state     (cmac_ctrl_tx_state ),
      .cmac_ctrl_rx_state     (cmac_ctrl_rx_state ),
      .cmac_rx_aligned_indication(is_cmac_rx_aligned)
  );

  wire [(CMAC_GT_LANE_WIDTH * 3)-1 :0]    gt_loopback_in;
  //// For other GT loopback options please change the value appropriately
  //// For example, for Near End PMA loopback for 4 Lanes update the gt_loopback_in = {4{3'b010}};
  //// For more information and settings on loopback, refer GT Transceivers user guide
  assign gt_loopback_in  = {CMAC_GT_LANE_WIDTH{3'b000}};

  wire            gtwiz_reset_tx_datapath;
  wire            gtwiz_reset_rx_datapath;
  assign gtwiz_reset_tx_datapath    = 1'b0;
  assign gtwiz_reset_rx_datapath    = 1'b0;

  assign udp_reset = user_resetn;
  assign cmac_sys_reset = ~ user_resetn;


  cmac_usplus_0 cmac_inst(
        .gt_rxp_in                            (qsfp1_rxp_in  ),
        .gt_rxn_in                            (qsfp1_rxn_in  ),
        .gt_txp_out                           (qsfp1_txp_out ),
        .gt_txn_out                           (qsfp1_txn_out ),

        // .gt_rxp_in                            (qsfp2_rxp_in  ),
        // .gt_rxn_in                            (qsfp2_rxn_in  ),
        // .gt_txp_out                           (qsfp2_txp_out ),
        // .gt_txn_out                           (qsfp2_txn_out ),

        .gt_loopback_in                       (gt_loopback_in),
        
        .gtwiz_reset_tx_datapath              (gtwiz_reset_tx_datapath),
        .gtwiz_reset_rx_datapath              (gtwiz_reset_rx_datapath),
        .sys_reset                            (cmac_sys_reset),
        .gt_ref_clk_p                         (qsfp1_ref_clk_p),
        .gt_ref_clk_n                         (qsfp1_ref_clk_n),
        // .gt_ref_clk_p                         (qsfp2_ref_clk_p),
        // .gt_ref_clk_n                         (qsfp2_ref_clk_n),
        .init_clk                             (user_clk_250),

        .gt_txusrclk2                         (gt_txusrclk2),
        .usr_rx_reset                         (gt_usr_rx_reset),
        .usr_tx_reset                         (gt_usr_tx_reset),

        // RX
        .rx_axis_tvalid                       (gt_rx_axis_tvalid),
        .rx_axis_tdata                        (gt_rx_axis_tdata ),
        .rx_axis_tkeep                        (gt_rx_axis_tkeep ),
        .rx_axis_tlast                        (gt_rx_axis_tlast ),
        .rx_axis_tuser                        (gt_rx_axis_tuser ),
        
        .stat_rx_bad_fcs                      (gt_stat_rx_bad_fcs),
        .stat_rx_stomped_fcs                  (gt_stat_rx_stomped_fcs),
        .stat_rx_aligned                      (gt_stat_rx_aligned),
        .stat_rx_pause_req                    (gt_stat_rx_pause_req),
        .ctl_rx_enable                        (gt_ctl_rx_enable),
        .ctl_rx_force_resync                  (gt_ctl_rx_force_resync),
        .ctl_rx_test_pattern                  (gt_ctl_rx_test_pattern),
        .ctl_rx_check_etype_gcp               (gt_ctl_rx_check_etype_gcp),
        .ctl_rx_check_etype_gpp               (gt_ctl_rx_check_etype_gpp),
        .ctl_rx_check_etype_pcp               (gt_ctl_rx_check_etype_pcp),
        .ctl_rx_check_etype_ppp               (gt_ctl_rx_check_etype_ppp),
        .ctl_rx_check_mcast_gcp               (gt_ctl_rx_check_mcast_gcp),
        .ctl_rx_check_mcast_gpp               (gt_ctl_rx_check_mcast_gpp),
        .ctl_rx_check_mcast_pcp               (gt_ctl_rx_check_mcast_pcp),
        .ctl_rx_check_mcast_ppp               (gt_ctl_rx_check_mcast_ppp),
        .ctl_rx_check_opcode_gcp              (gt_ctl_rx_check_opcode_gcp),
        .ctl_rx_check_opcode_gpp              (gt_ctl_rx_check_opcode_gpp),
        .ctl_rx_check_opcode_pcp              (gt_ctl_rx_check_opcode_pcp),
        .ctl_rx_check_opcode_ppp              (gt_ctl_rx_check_opcode_ppp),
        .ctl_rx_check_sa_gcp                  (gt_ctl_rx_check_sa_gcp),
        .ctl_rx_check_sa_gpp                  (gt_ctl_rx_check_sa_gpp),
        .ctl_rx_check_sa_pcp                  (gt_ctl_rx_check_sa_pcp),
        .ctl_rx_check_sa_ppp                  (gt_ctl_rx_check_sa_ppp),
        .ctl_rx_check_ucast_gcp               (gt_ctl_rx_check_ucast_gcp),
        .ctl_rx_check_ucast_gpp               (gt_ctl_rx_check_ucast_gpp),
        .ctl_rx_check_ucast_pcp               (gt_ctl_rx_check_ucast_pcp),
        .ctl_rx_check_ucast_ppp               (gt_ctl_rx_check_ucast_ppp),
        .ctl_rx_enable_gcp                    (gt_ctl_rx_enable_gcp),
        .ctl_rx_enable_gpp                    (gt_ctl_rx_enable_gpp),
        .ctl_rx_enable_pcp                    (gt_ctl_rx_enable_pcp),
        .ctl_rx_enable_ppp                    (gt_ctl_rx_enable_ppp),
        .ctl_rx_pause_ack                     (gt_ctl_rx_pause_ack),
        .ctl_rx_pause_enable                  (gt_ctl_rx_pause_enable),
    

        // TX
        .tx_axis_tready                       (gt_tx_axis_tready),
        .tx_axis_tvalid                       (gt_tx_axis_tvalid),
        .tx_axis_tdata                        (gt_tx_axis_tdata),
        .tx_axis_tkeep                        (gt_tx_axis_tkeep),
        .tx_axis_tlast                        (gt_tx_axis_tlast),
        .tx_axis_tuser                        (gt_tx_axis_tuser),
        
        .tx_ovfout                            (gt_tx_ovfout),
        .tx_unfout                            (gt_tx_unfout),
        .ctl_tx_enable                        (gt_ctl_tx_enable),
        .ctl_tx_test_pattern                  (gt_ctl_tx_test_pattern),
        .ctl_tx_send_idle                     (gt_ctl_tx_send_idle),
        .ctl_tx_send_rfi                      (gt_ctl_tx_send_rfi),
        .ctl_tx_send_lfi                      (gt_ctl_tx_send_lfi),
        .ctl_tx_pause_enable                  (gt_ctl_tx_pause_enable),
        .ctl_tx_pause_req                     (gt_ctl_tx_pause_req),
        .ctl_tx_pause_quanta0                 (gt_ctl_tx_pause_quanta0),
        .ctl_tx_pause_quanta1                 (gt_ctl_tx_pause_quanta1),
        .ctl_tx_pause_quanta2                 (gt_ctl_tx_pause_quanta2),
        .ctl_tx_pause_quanta3                 (gt_ctl_tx_pause_quanta3),
        .ctl_tx_pause_quanta4                 (gt_ctl_tx_pause_quanta4),
        .ctl_tx_pause_quanta5                 (gt_ctl_tx_pause_quanta5),
        .ctl_tx_pause_quanta6                 (gt_ctl_tx_pause_quanta6),
        .ctl_tx_pause_quanta7                 (gt_ctl_tx_pause_quanta7),
        .ctl_tx_pause_quanta8                 (gt_ctl_tx_pause_quanta8),

        .ctl_tx_pause_refresh_timer0          (16'd0),
        .ctl_tx_pause_refresh_timer1          (16'd0),
        .ctl_tx_pause_refresh_timer2          (16'd0),
        .ctl_tx_pause_refresh_timer3          (16'd0),
        .ctl_tx_pause_refresh_timer4          (16'd0),
        .ctl_tx_pause_refresh_timer5          (16'd0),
        .ctl_tx_pause_refresh_timer6          (16'd0),
        .ctl_tx_pause_refresh_timer7          (16'd0),
        .ctl_tx_pause_refresh_timer8          (16'd0),
        .ctl_tx_resend_pause                  (1'b0 ),
        .tx_preamblein                        (56'd0),

        // RS-FEC
`ifdef ENABLE_CMAC_RS_FEC
        .ctl_rsfec_ieee_error_indication_mode (gt_ctl_rsfec_ieee_error_indication_mode),
        .ctl_tx_rsfec_enable                  (gt_ctl_tx_rsfec_enable),
        .ctl_rx_rsfec_enable                  (gt_ctl_rx_rsfec_enable),
        .ctl_rx_rsfec_enable_correction       (gt_ctl_rx_rsfec_enable_correction),
        .ctl_rx_rsfec_enable_indication       (gt_ctl_rx_rsfec_enable_indication),
`endif    

        .core_rx_reset                        (1'b0 ),
        .core_tx_reset                        (1'b0 ),
        .rx_clk                               (gt_txusrclk2),
        .core_drp_reset                       (1'b0 ),
        .drp_clk                              (1'b0 ),
        .drp_addr                             (10'b0),
        .drp_di                               (16'b0),
        .drp_en                               (1'b0 ),
        .drp_do                               (),
        .drp_rdy                              (),
        .drp_we                               (1'b0 )
    );
endmodule
`endif  // BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC