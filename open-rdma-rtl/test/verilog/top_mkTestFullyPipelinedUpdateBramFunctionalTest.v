`include "speedster7t/common/speedster7t_snapshot_v3.sv"
`timescale 1ps/1ps
module top_mkTestFullyPipelinedUpdateBramFunctionalTest (
    // pll lock
    input pll_1_lock,
    // jtap ports:
    input t_JTAG_INPUT i_jtag_in,
    output t_JTAG_OUTPUT o_jtag_out,
    // user design ports:
    input wire CLK
);
    /********** clock ************************************************************/
    wire clk = CLK;
    
    /********** reset ************************************************************/
    // No reset input to VectorPath card, so generate a self-starting reset from power up
    // Once the circuit is running, the various blocks have their individual resets controlled from
    // the reg_control_block
    logic [32 -1:0] reset_pipe = 16'h0;

    always @(posedge clk)
        reset_pipe <= {reset_pipe[$bits(reset_pipe)-2 : 0], 1'b1};

    // Create an main reset, based on reg_clk
    reset_processor_v2 #(
        .NUM_INPUT_RESETS       (2),    // One reset sources
        .IN_RST_PIPE_LENGTH     (8),    // Length of input flop pipeline, minimum of 2
                                        // Ignored if SYNC_INPUT_RESETS = 0
        .SYNC_INPUT_RESETS      (1),    // Synchronize input resets
        .OUT_RST_PIPE_LENGTH    (4),    // Length of reset flop pipeline, minimum of 2
                                        // Ignored if RESET_OVER_CLOCK = 1
        .RESET_OVER_CLOCK       (1)     // Set to route the output reset over the clock network
    ) i_reset_processor_main (
        .i_rstn_array       ({reset_pipe[$bits(reset_pipe)-1], pll_1_lock}),
        .i_clk              (clk),
        .o_rstn             (rstn)
    );  

    /********** user circuit *****************************************************/


    wire getSuccess;
    wire getFinished;

    mkTestFullyPipelinedUpdateBramFunctionalTest dutInst(
        .CLK(clk),
        .RST_N(rstn),
        .getSuccess(getSuccess),
        .getFinished(getFinished)
    ) /* synthesis syn_preserve=1 */;
    
    
    /********** snapshot *********************************************************/
    localparam integer MONITOR_WIDTH = 2;
    localparam integer MONITOR_DEPTH = 2000; // will be rounded up
    localparam TRIGGER_WIDTH = MONITOR_WIDTH < 40? MONITOR_WIDTH : 40;
    wire [MONITOR_WIDTH-1 : 0] monitor;



    assign monitor = {
        getSuccess,
        getFinished
    };
    localparam STIMULI_WIDTH = 0;
    ACX_SNAPSHOT #(
    .DUT_NAME("snapshot_example"),
    .MONITOR_WIDTH(MONITOR_WIDTH), // 1..4080
    .MONITOR_DEPTH(MONITOR_DEPTH), // 1..16384

    .TRIGGER_WIDTH(TRIGGER_WIDTH), // 1..40
    .STANDARD_TRIGGERS(2), // use i_monitor[39:0] as trigger input
    .STIMULI_WIDTH(STIMULI_WIDTH), // 0..512
    .INPUT_PIPELINING(3), // for i_monitor and i_trigger
    .OUTPUT_PIPELINING(0), // for o_stimuli(_valid) and o_arm
    .ARM_DELAY(2) // between o_stimuli_valid and o_arm
    ) x_snapshot (
    .i_jtag_in(i_jtag_in),
    .o_jtag_out(o_jtag_out),
    .i_user_clk(clk),
    .i_monitor(monitor),
    .i_trigger({getSuccess, getFinished}), // not used if STANDARD_TRIGGERS = 1
    .o_stimuli(),
    .o_stimuli_valid(),
    .o_arm(),
    .o_trigger()
    );
endmodule