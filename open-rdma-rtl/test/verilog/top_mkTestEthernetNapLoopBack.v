`include "speedster7t/common/speedster7t_snapshot_v3.sv"
`timescale 1ps/1ps
module top_mkTestEthernetNapLoopBack (

    // jtap ports:
    input t_JTAG_INPUT i_jtag_in,
    output t_JTAG_OUTPUT o_jtag_out,

    // ===========================================================
    // | Begin ports imported from IORing generated header files
    // ===========================================================

    // Ports for clock_io_bank_1
    // Ports for ethernet_1
    // 400G MAC 0 Flow Control
    input wire  [7:0] ethernet_1_m0_pause_on,
    output wire       ethernet_1_m0_tx_smhold,
    output wire [7:0] ethernet_1_m0_xoff_gen,
    // 400G MAC 0 Status
    input wire        ethernet_1_m0_tx_ovr_err,
    input wire        ethernet_1_m0_tx_underflow,
    // Buffer Levels
    input wire  [3:0] ethernet_1_m0_rx_buffer0_at_threshold,
    input wire  [3:0] ethernet_1_m0_rx_buffer1_at_threshold,
    input wire  [3:0] ethernet_1_m0_rx_buffer2_at_threshold,
    input wire  [3:0] ethernet_1_m0_rx_buffer3_at_threshold,
    input wire  [3:0] ethernet_1_m0_tx_buffer0_at_threshold,
    input wire  [3:0] ethernet_1_m0_tx_buffer1_at_threshold,
    input wire  [3:0] ethernet_1_m0_tx_buffer2_at_threshold,
    input wire  [3:0] ethernet_1_m0_tx_buffer3_at_threshold,
    // Clocks and Resets
    input wire        ethernet_1_m0_ff_clk_divby2,
    input wire        ethernet_1_m1_ff_clk_divby2,
    input wire        ethernet_1_ref_clk_divby2,
    // Ports for noc_1
    // Ports for pll_eth_507M
    input wire        i_eth_clk,
    input wire        pll_eth_507M_lock,
    // Ports for pll_eth_ff_800M
    input wire        pll_eth_ff_800M_lock,
    // Ports for pll_eth_ref_900M
    input wire        eth_ref_clk,
    input wire        pll_eth_ref_900M_lock,
    // Ports for pll_noc
    input wire        pll_noc_clk,
    input wire        pll_noc_lock

    // ===========================================================
    // | End ports imported from IORing generated header files
    // ===========================================================


    
    
);
    /********** clock ************************************************************/
    wire clk = i_eth_clk;
    
    /********** reset ************************************************************/
    // No reset input to VectorPath card, so generate a self-starting reset from power up
    // Once the circuit is running, the various blocks have their individual resets controlled from
    // the reg_control_block
    logic [32 -1:0] reset_pipe = 16'h0;

    // Use syn_keep to retain name, so it can assigned to reset over clock
    logic rstn /* synthesis syn_keep=1 */;

    always @(posedge clk)
        reset_pipe <= {reset_pipe[$bits(reset_pipe)-2 : 0], 1'b1};

    // Create an main reset, based on reg_clk
    reset_processor_v2 #(
        .NUM_INPUT_RESETS       (5),    // One reset sources
        .IN_RST_PIPE_LENGTH     (8),    // Length of input flop pipeline, minimum of 2
                                        // Ignored if SYNC_INPUT_RESETS = 0
        .SYNC_INPUT_RESETS      (1),    // Synchronize input resets
        .OUT_RST_PIPE_LENGTH    (4),    // Length of reset flop pipeline, minimum of 2
                                        // Ignored if RESET_OVER_CLOCK = 1
        .RESET_OVER_CLOCK       (0)     // Set to route the output reset over the clock network
    ) i_reset_processor_main (
        .i_rstn_array       ({reset_pipe[$bits(reset_pipe)-1], pll_eth_507M_lock, pll_eth_ff_800M_lock, pll_eth_ref_900M_lock, pll_noc_lock}),
        .i_clk              (clk),
        .o_rstn             (rstn)
    );  


    /********** user circuit *****************************************************/

    wire [15 : 0] recvPacketCnt;
    wire [4:0] getStateReg;
    wire EN_run;

    mkTestEthernetNapLoopBack dutInst(
        .CLK(clk),
        .RST_N(rstn),
        .recvPacketCnt(recvPacketCnt),
        .getStateReg(getStateReg),
        .EN_run(EN_run)
    ) /* synthesis syn_preserve=1 */;
    
    
    /********** snapshot *********************************************************/
    localparam integer MONITOR_WIDTH = 2 + 16 + 5 + 10;
    localparam integer MONITOR_DEPTH = 2000; // will be rounded up
    localparam TRIGGER_WIDTH = MONITOR_WIDTH < 40? MONITOR_WIDTH : 40;
    wire [MONITOR_WIDTH-1 : 0] monitor;


    // ACX_PROBE_POINT #(
    //     .width(10),
    //     .tag("axi_slave1")
    // ) probe_axi_slave1 (
    //     .din({
    //         napSlave_axiSlaveNap_inst$arready,
    //         napSlave_axiSlaveNap_inst$arvalid,
    //         napSlave_axiSlaveNap_inst$awready,
    //         napSlave_axiSlaveNap_inst$awvalid,
    //         napSlave_axiSlaveNap_inst$bready,
    //         napSlave_axiSlaveNap_inst$bvalid,
    //         napSlave_axiSlaveNap_inst$rready,
    //         napSlave_axiSlaveNap_inst$rvalid,
    //         napSlave_axiSlaveNap_inst$wready,
    //         napSlave_axiSlaveNap_inst$wvalid
    //     })
    // );


    wire    napSlave_axiSlaveNap_inst$arready,
            napSlave_axiSlaveNap_inst$arvalid,
            napSlave_axiSlaveNap_inst$awready,
            napSlave_axiSlaveNap_inst$awvalid,
            napSlave_axiSlaveNap_inst$bready,
            napSlave_axiSlaveNap_inst$bvalid,
            napSlave_axiSlaveNap_inst$rready,
            napSlave_axiSlaveNap_inst$rvalid,
            napSlave_axiSlaveNap_inst$wready,
            napSlave_axiSlaveNap_inst$wvalid;


    wire [9:0] axi_slave1_probe_siginals;
    ACX_PROBE_CONNECT #(
        .width(10),
        .tag("axi_slave1")
    ) probe_counter_a1 (
        .dout({
            napSlave_axiSlaveNap_inst$arready,
            napSlave_axiSlaveNap_inst$arvalid,
            napSlave_axiSlaveNap_inst$awready,
            napSlave_axiSlaveNap_inst$awvalid,
            napSlave_axiSlaveNap_inst$bready,
            napSlave_axiSlaveNap_inst$bvalid,
            napSlave_axiSlaveNap_inst$rready,
            napSlave_axiSlaveNap_inst$rvalid,
            napSlave_axiSlaveNap_inst$wready,
            napSlave_axiSlaveNap_inst$wvalid
        })
    );

    wire stimuli_valid;

    assign monitor = {
        stimuli_valid,
        EN_run,
        recvPacketCnt,
        getStateReg,
        napSlave_axiSlaveNap_inst$arready,
        napSlave_axiSlaveNap_inst$arvalid,
        napSlave_axiSlaveNap_inst$awready,
        napSlave_axiSlaveNap_inst$awvalid,
        napSlave_axiSlaveNap_inst$bready,
        napSlave_axiSlaveNap_inst$bvalid,
        napSlave_axiSlaveNap_inst$rready,
        napSlave_axiSlaveNap_inst$rvalid,
        napSlave_axiSlaveNap_inst$wready,
        napSlave_axiSlaveNap_inst$wvalid
    };
    localparam STIMULI_WIDTH = 1;
    ACX_SNAPSHOT #(
    .DUT_NAME("snapshot_example"),
    .MONITOR_WIDTH(MONITOR_WIDTH), // 1..4080
    .MONITOR_DEPTH(MONITOR_DEPTH), // 1..16384

    .TRIGGER_WIDTH(TRIGGER_WIDTH), // 1..40
    .STANDARD_TRIGGERS(1), // use i_monitor[39:0] as trigger input
    .STIMULI_WIDTH(STIMULI_WIDTH), // 0..512
    .INPUT_PIPELINING(6), // for i_monitor and i_trigger
    .OUTPUT_PIPELINING(2), // for o_stimuli(_valid) and o_arm
    .ARM_DELAY(2) // between o_stimuli_valid and o_arm
    ) x_snapshot (
    .i_jtag_in(i_jtag_in),
    .o_jtag_out(o_jtag_out),
    .i_user_clk(clk),
    .i_monitor(monitor),
    .i_trigger(), // not used if STANDARD_TRIGGERS = 1
    .o_stimuli(EN_run),
    .o_stimuli_valid(stimuli_valid),
    .o_arm(),
    .o_trigger()
    );
endmodule