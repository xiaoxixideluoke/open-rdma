import GetPut :: *;
import ClientServer :: *;
import FIFOF :: *;
import Vector :: *;
import Reserved :: *;
import BRAM :: *;
import PAClib :: *;

import BasicDataTypes :: *;
import PrimUtils :: *;
import ConnectableF :: *;
import MockHost :: *;




typedef 4 VERTICAL_NAP_NODE_ID_WIDTH;
typedef 293 VERTICAL_NAP_DATA_WIDTH;

typedef 256 NOC_DATA_BUS_BIT_WIDTH;
typedef TDiv#(NOC_DATA_BUS_BIT_WIDTH, BYTE_WIDTH) NOC_DATA_BUS_BYTE_WIDTH;   // 32
typedef Bit#(NOC_DATA_BUS_BIT_WIDTH) NocData;

typedef Bit#(VERTICAL_NAP_NODE_ID_WIDTH) VerticalNapsrcOrDstNodeId;
typedef Bit#(VERTICAL_NAP_DATA_WIDTH) VerticalNapData;

typedef VERTICAL_NAP_DATA_WIDTH ETHERNET_NAP_DATA_WIDTH;
typedef Bit#(ETHERNET_NAP_DATA_WIDTH) EthernetNapData;

typedef TSub#(ETHERNET_NAP_DATA_WIDTH, NOC_DATA_BUS_BIT_WIDTH) ETHERNET_NAP_EXTRA_INFO_WIDTH;
typedef Bit#(ETHERNET_NAP_EXTRA_INFO_WIDTH) EthernetExtraInfo;

typedef 15 ETHERNET_NAP_NODE_ID; // according to UG086, the node ID of EIU is 4'hf

typedef 5 ETH_NAP_MOD_WIDTH;
typedef Bit#(ETH_NAP_MOD_WIDTH) EthernetNapMod;

typedef 30 ETH_NAP_TIMESTAMP_WIDTH;
typedef Bit#(ETH_NAP_TIMESTAMP_WIDTH) EthernetNapTimestamp;

typedef 5 ETH_NAP_SEQ_ID_WIDTH;
typedef Bit#(ETH_NAP_SEQ_ID_WIDTH) EthernetNapSeqID;


typedef struct {
    ReservedZero#(16) revd1;
    EthernetNapSeqID sequenceID;
    Bool vlan;
    Bool transmitError;
    Bool invertedCRC;
    Bool shortFrame;
    Bool fifoOverflow;
    Bool decodeError;
    Bool crcError;
    Bool lengthError;
    Bool error;
} EthernetNapRecvFlags deriving(Bits, FShow, Eq);

typedef struct {
    ReservedZero#(2) rsvd2;
    EthernetNapTimestamp timestamp;
    ReservedZero#(ETH_NAP_MOD_WIDTH) rsvd1;
} EthernetNapRecvFirstBeatExtraInfo deriving(Bits, FShow, Eq);

typedef struct {
    EthernetNapRecvFirstBeatExtraInfo   extraInfo;
    NocData                             data;
} EthernetNapRecvFirstBeat deriving(Bits, FShow, Eq);

typedef struct {
    ReservedZero#(2) rsvd1;
    EthernetNapRecvFlags flags;
    EthernetNapMod mod;
} EthernetNapRecvOtherBeatExtraInfo deriving(Bits, FShow, Eq);

typedef struct {
    EthernetNapRecvOtherBeatExtraInfo   extraInfo;
    NocData                             data;
} EthernetNapRecvOtherBeat deriving(Bits, FShow, Eq);

typedef 17 ETH_NAP_TRANSMIT_ID_FLAG_WIDTH;
typedef Bit#(ETH_NAP_TRANSMIT_ID_FLAG_WIDTH) EthernetNapTransmitID;

typedef struct {
    ReservedZero#(6) revd1;
    Bool classB;
    Bool classA;
    Bool crcOverride;
    Bool crcInvert;
    Bool crcInsert;
    Bool txError;
    Bool frame;
    EthernetNapTransmitID id;
} EthernetNapSendFlags deriving(Bits, FShow, Eq);

typedef struct {
    ReservedZero#(2) rsvd2;
    EthernetNapTimestamp timestamp;
    ReservedZero#(ETH_NAP_MOD_WIDTH) rsvd1;
} EthernetNapSendFirstBeatExtraInfo deriving(Bits, FShow, Eq);

typedef struct {
    EthernetNapSendFirstBeatExtraInfo   extraInfo;
    NocData                             data;
} EthernetNapSendFirstBeat deriving(Bits, FShow, Eq);


typedef struct {
    ReservedZero#(2) rsvd1;
    EthernetNapSendFlags flags;
    EthernetNapMod mod;
} EthernetNapSendOtherBeatExtraInfo deriving(Bits, FShow, Eq);

typedef struct {
    EthernetNapSendOtherBeatExtraInfo   extraInfo;
    NocData                             data;
} EthernetNapSendOtherBeat deriving(Bits, FShow, Eq);


(* always_ready, always_enabled*)
interface ACX_NAP_ETHERNET_BVI_WRAPPER;
    
    // input port
    method Action tx_valid(Bool val);
    method Action tx_data(VerticalNapData val);
    method Action tx_sop(Bool val);
    method Action tx_eop(Bool val);
    method Action rx_ready(Bool val);

    // output port
    method Bool rx_valid;
    method VerticalNapsrcOrDstNodeId rx_src;
    method VerticalNapData rx_data;
    method Bool rx_sop;
    method Bool rx_eop;
    method Bool tx_ready;  
endinterface


import "BVI" ACX_NAP_ETHERNET =
module mkAcxNapEthernetWrapperInner#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(ACX_NAP_ETHERNET_BVI_WRAPPER);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    parameter tx_mode = 4'b0111;  // 400G_PKT, From UG086 Table 233
    parameter rx_mode = 4'b0111;  // 400G_PKT, From UG086 Table 233
    parameter tx_mac_id = 2'b00;  // 400G_MAC0, From UG086 Table 233
    parameter rx_mac_id = 2'b00;  // 400G_MAC0, From UG086 Table 233
    parameter tx_eiu_channel = tx_eiu_channel;
    parameter rx_eiu_channel = rx_eiu_channel;

    input_clock (clk) = clk;
    input_reset rstN(rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    port tx_dest = 4'hF;  // 400G_MAC0, From UG086 Table 233, means to EIU

    
    // input port
    method tx_valid(tx_valid) enable((*inhigh*) EN_NO_USE_1) clocked_by(clk) reset_by(no_reset);
    method tx_data(tx_data) enable((*inhigh*) EN_NO_USE_2) clocked_by(clk) reset_by(no_reset);
    method tx_sop(tx_sop) enable((*inhigh*) EN_NO_USE_3) clocked_by(clk) reset_by(no_reset);
    method tx_eop(tx_eop) enable((*inhigh*) EN_NO_USE_4) clocked_by(clk) reset_by(no_reset);
    method rx_ready(rx_ready) enable((*inhigh*) EN_NO_USE_5) clocked_by(clk) reset_by(no_reset);

    // output port
    method rx_valid rx_valid clocked_by(clk) reset_by(no_reset);
    method rx_src rx_src clocked_by(clk) reset_by(no_reset);
    method rx_data rx_data clocked_by(clk) reset_by(no_reset);
    method rx_sop rx_sop clocked_by(clk) reset_by(no_reset);
    method rx_eop rx_eop clocked_by(clk) reset_by(no_reset);
    method tx_ready tx_ready clocked_by(clk) reset_by(no_reset);  

    schedule (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready) CF (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready);
    schedule (tx_valid, tx_data, tx_sop, tx_eop) CF (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);

    schedule (rx_ready) C (rx_ready);
    schedule (rx_valid, rx_src, rx_data, rx_sop, rx_eop, tx_ready) CF (tx_valid, tx_data, tx_sop, tx_eop, rx_ready);


endmodule



module mkAcxNapEthernetWrapperInnerBluesim#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(ACX_NAP_ETHERNET_BVI_WRAPPER);

    FIFOF#(Tuple3#(Bool, Bool, VerticalNapData)) txRelayQ <- mkUGFIFOF;
    FIFOF#(Tuple3#(Bool, Bool, VerticalNapData)) rxRelayQ <- mkUGFIFOF;

    Wire#(Bool)                         txValidWire     <- mkBypassWire;
    Wire#(VerticalNapData)              txDataWire      <- mkBypassWire;
    Wire#(Bool)                         txSopWire       <- mkBypassWire;
    Wire#(Bool)                         txEopWire       <- mkBypassWire;
    Wire#(Bool)                         rxReadyWire     <- mkBypassWire;



`ifdef USE_MOCK_HOST 
    let mockHostNetworkConnector <- mkMockHostNetworkConnector;

    rule forwardTxPacket;
        if (txRelayQ.notEmpty) begin
            let {isSop, isEop, beat} = txRelayQ.first;
            txRelayQ.deq;
            let mod = 0;
            DATA data = ?;
            if (isSop) begin
                EthernetNapSendFirstBeat decodedPayload = unpack(beat);
                data = decodedPayload.data;
            end
            else begin
                EthernetNapSendOtherBeat decodedPayload = unpack(beat);
                data = decodedPayload.data;
                mod = decodedPayload.extraInfo.mod;
            end

            mockHostNetworkConnector.txPut.put(NetIfcAccessAction {
                isValid : 1,
                isLast  : zeroExtend(pack(isEop)),
                isFirst : zeroExtend(pack(isSop)),
                mod     : zeroExtend(pack(mod)),
                data    : data
            });
        end
    endrule

    rule forwardRxPacket;
        if (rxRelayQ.notFull) begin
            let netIfcAccessAction <- mockHostNetworkConnector.rxGet.get;
            let isSop = (netIfcAccessAction.isFirst != 0);
            let isEop = (netIfcAccessAction.isLast != 0);

            if (isSop) begin
                let outBeat = EthernetNapRecvFirstBeat {
                    data: netIfcAccessAction.data,
                    extraInfo: EthernetNapRecvFirstBeatExtraInfo {
                        rsvd2: unpack(0),
                        rsvd1: unpack(0),
                        timestamp: 0
                    }
                };
                rxRelayQ.enq(tuple3(isSop, isEop, unpack(pack(outBeat))));
            end
            else begin
                let outBeat = EthernetNapSendOtherBeat {
                    data: netIfcAccessAction.data,
                    extraInfo: EthernetNapSendOtherBeatExtraInfo {
                        rsvd1: unpack(0),
                        flags: unpack(0),
                        mod: truncate(pack(netIfcAccessAction.mod))
                    }
                };
                rxRelayQ.enq(tuple3(isSop, isEop, unpack(pack(outBeat))));
            end
        end
    endrule

`else
    rule forwardPacket;
        if (txRelayQ.notEmpty && rxRelayQ.notFull) begin
            let {isSop, isEop, beat} = txRelayQ.first;
            txRelayQ.deq;

            if (isSop) begin
                EthernetNapSendFirstBeat decodedPayload = unpack(beat);
                let outBeat = EthernetNapRecvFirstBeat {
                    data: decodedPayload.data,
                    extraInfo: EthernetNapRecvFirstBeatExtraInfo {
                        rsvd2: unpack(0),
                        rsvd1: unpack(0),
                        timestamp: unpack(0)
                    }
                };
                rxRelayQ.enq(tuple3(isSop, isEop, pack(outBeat)));
            end
            else begin
                EthernetNapSendOtherBeat decodedPayload = unpack(beat);
                let outBeat = EthernetNapSendOtherBeat {
                    data: decodedPayload.data,
                    extraInfo: EthernetNapSendOtherBeatExtraInfo {
                        rsvd1: unpack(0),
                        flags: unpack(0),
                        mod: decodedPayload.extraInfo.mod
                    }
                };
                rxRelayQ.enq(tuple3(isSop, isEop, pack(outBeat)));
            end
            $display("time=%0t: ", $time, "net ifc forward data, isSop=", fshow(isSop), ", isEop=", fshow(isEop));
        end
        else if (!rxRelayQ.notFull) begin
            $display("time=%0t: ", $time, "net ifc recv data BUT DISCARD SINCE QUEUE FULL");
            $finish(1);
        end
    endrule
`endif

    rule handleTxInput;
        if (txValidWire && txRelayQ.notFull) begin
            txRelayQ.enq(tuple3(txSopWire, txEopWire, txDataWire));
            // $display("txBeat recv=", fshow(txDataWire), ", txSopWire=", fshow(txSopWire), ", txEopWire=", fshow(txEopWire));
        end
    endrule

    rule handleRxInput;
        if (rxReadyWire && rxRelayQ.notEmpty) begin
            rxRelayQ.deq;
        end
    endrule

    // input port
    method tx_valid           = txValidWire._write;
    method tx_data            = txDataWire._write;
    method tx_sop             = txSopWire._write;
    method tx_eop             = txEopWire._write;
    method rx_ready           = rxReadyWire._write;

    // output port
    method rx_valid                     = rxRelayQ.notEmpty;
    method rx_src                       = 4'hf;
    method rx_data                      = tpl_3(rxRelayQ.first);
    method rx_sop                       = tpl_1(rxRelayQ.first);
    method rx_eop                       = tpl_2(rxRelayQ.first);
    method tx_ready                     = txRelayQ.notFull;


endmodule



module mkAcxNapEthernetPrimitiveWrapper#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(ACX_NAP_ETHERNET_BVI_WRAPPER);

    ACX_NAP_ETHERNET_BVI_WRAPPER inst;

    if (genVerilog) begin
        inst <- mkAcxNapEthernetWrapperInner(tx_eiu_channel, rx_eiu_channel);
    end
    else begin
        inst <- mkAcxNapEthernetWrapperInnerBluesim(tx_eiu_channel, rx_eiu_channel);
    end

    return inst;
endmodule

typedef struct {
    VerticalNapsrcOrDstNodeId srcOrDstNodeId;
    VerticalNapData data;
    Bool sop;
    Bool eop;
} VerticalNapBeatEntry deriving(Bits, FShow);

typedef VerticalNapBeatEntry EthernetNapBeatEntry;


interface AcxNapEthernetWrapper;
    method Action send(VerticalNapBeatEntry beat);
    method ActionValue#(VerticalNapBeatEntry) recv;
endinterface


module mkAcxNapEthernetWrapper#(
    Bit#(5) tx_eiu_channel,
    Bit#(5) rx_eiu_channel
)(AcxNapEthernetWrapper);

    let inner <- mkAcxNapEthernetWrapperPipe(tx_eiu_channel, rx_eiu_channel);

    method Action send(VerticalNapBeatEntry beat) if (inner.sendPipeIn.notFull);
        inner.sendPipeIn.enq(beat);
    endmethod

    method ActionValue#(VerticalNapBeatEntry) recv if (inner.recvPipeOut.notEmpty);
        inner.recvPipeOut.deq;
        return inner.recvPipeOut.first;
    endmethod

endmodule

interface AcxNapEthernetWrapperPipe;
    interface PipeIn#(VerticalNapBeatEntry) sendPipeIn;
    interface PipeOut#(VerticalNapBeatEntry) recvPipeOut;
endinterface

module mkAcxNapEthernetWrapperPipe#(
        Bit#(5) tx_eiu_channel,
        Bit#(5) rx_eiu_channel
    )(AcxNapEthernetWrapperPipe);

    FIFOF#(VerticalNapBeatEntry) txQ <- mkUGFIFOF;
    FIFOF#(VerticalNapBeatEntry) rxQ <- mkUGFIFOF;
    
    let ethNap <- mkAcxNapEthernetPrimitiveWrapper(tx_eiu_channel, rx_eiu_channel);

    rule forwardTxAxiSignal;
        let txBeat = txQ.first;
        ethNap.tx_valid(txQ.notEmpty);
        ethNap.tx_data(txBeat.data);
        ethNap.tx_sop(txBeat.sop);
        ethNap.tx_eop(txBeat.eop);

        if (txQ.notEmpty) begin
            if (ethNap.tx_ready) begin
                txQ.deq;
                // $display("txBeat send=", fshow(txBeat));
            end
        end
    endrule

    rule forwardRxAxiSignal;
        if (rxQ.notFull) begin
            ethNap.rx_ready(True);
            if (ethNap.rx_valid) begin
                let recvBeat = VerticalNapBeatEntry{
                    srcOrDstNodeId: fromInteger(valueOf(ETHERNET_NAP_NODE_ID)),
                    data: ethNap.rx_data,
                    sop: ethNap.rx_sop,
                    eop: ethNap.rx_eop
                };
                rxQ.enq(recvBeat);
            end
        end
        else begin
            ethNap.rx_ready(False);
        end
    endrule

    interface sendPipeIn  = ugToPipeIn(txQ);
    interface recvPipeOut = ugToPipeOut(rxQ);
endmodule


// Common ==================
typedef 8 AXI_AXLEN_WIDTH;
typedef Bit#(AXI_AXLEN_WIDTH) AxiAxlen;


// AW channel ==============
typedef 8 NAP_AXI_AWID_WIDTH;
typedef Bit#(NAP_AXI_AWID_WIDTH) NapAxiAwid;

typedef 42 NAP_AXI_AWADDR_WIDTH;
typedef Bit#(NAP_AXI_AWADDR_WIDTH) NapAxiAwaddr;

typedef AXI_AXLEN_WIDTH NAP_AXI_AWLEN_WIDTH;
typedef Bit#(NAP_AXI_AWLEN_WIDTH) NapAxiAwlen;

typedef 3 NAP_AXI_AWSIZE_WIDTH;
typedef Bit#(NAP_AXI_AWSIZE_WIDTH) NapAxiAwsize;

typedef 2 NAP_AXI_AWBURST_WIDTH;
typedef Bit#(NAP_AXI_AWBURST_WIDTH) NapAxiAwburst;

typedef 4 NAP_AXI_AWQOS_WIDTH;
typedef Bit#(NAP_AXI_AWQOS_WIDTH) NapAxiAwqos;

// W channel ==============
typedef 256 NAP_AXI_WDATA_WIDTH;
typedef Bit#(NAP_AXI_WDATA_WIDTH) NapAxiWdata;

typedef 32 NAP_AXI_WSTRB_WIDTH;
typedef Bit#(NAP_AXI_WSTRB_WIDTH) NapAxiWstrb;

// B channel ==============
typedef 8 NAP_AXI_BID_WIDTH;
typedef Bit#(NAP_AXI_BID_WIDTH) NapAxiBid;

typedef 2 NAP_AXI_BRESP_WIDTH;
typedef Bit#(NAP_AXI_BRESP_WIDTH) NapAxiBresp;

// AR channel ==============
typedef 8 NAP_AXI_ARID_WIDTH;
typedef Bit#(NAP_AXI_ARID_WIDTH) NapAxiArid;

typedef 42 NAP_AXI_ARADDR_WIDTH;
typedef Bit#(NAP_AXI_ARADDR_WIDTH) NapAxiAraddr;

typedef AXI_AXLEN_WIDTH NAP_AXI_ARLEN_WIDTH;
typedef Bit#(NAP_AXI_ARLEN_WIDTH) NapAxiArlen;

typedef 3 NAP_AXI_ARSIZE_WIDTH;
typedef Bit#(NAP_AXI_ARSIZE_WIDTH) NapAxiArsize;

typedef 2 NAP_AXI_ARBURST_WIDTH;
typedef Bit#(NAP_AXI_ARBURST_WIDTH) NapAxiArburst;

typedef 4 NAP_AXI_ARQOS_WIDTH;
typedef Bit#(NAP_AXI_ARQOS_WIDTH) NapAxiArqos;

// R channel ==============
typedef 8 NAP_AXI_RID_WIDTH;
typedef Bit#(NAP_AXI_RID_WIDTH) NapAxiRid;

typedef 256 NAP_AXI_RDATA_WIDTH;
typedef Bit#(NAP_AXI_RDATA_WIDTH) NapAxiRdata;

typedef 2 NAP_AXI_RRESP_WIDTH;
typedef Bit#(NAP_AXI_RRESP_WIDTH) NapAxiRresp;

typedef enum {
    NapAxiSize1B   = 0,
    NapAxiSize2B   = 1,
    NapAxiSize4B   = 2,
    NapAxiSize8B   = 3,
    NapAxiSize16B  = 4,
    NapAxiSize32B  = 5,
    NapAxiSize64B  = 6,
    NapAxiSize128B = 7
} NapAxiSize deriving(Bits, FShow, Eq);

typedef enum {
    NapAxiBurstFixed  = 0,
    NapAxiBurstIncr   = 1,
    NapAxiBurstWrap   = 2
} NapAxiBurst deriving(Bits, FShow, Eq);

typedef struct {
    NapAxiAwid awid;
    NapAxiAwaddr awaddr;
    NapAxiAwlen awlen;
    NapAxiAwsize awsize;
    NapAxiAwburst awburst;
    Bool awlock;  
    NapAxiAwqos awqos;
} AxiMmNapBeatAw deriving(Bits, FShow);

typedef struct {
    NapAxiWdata wdata;
    NapAxiWstrb wstrb;
    Bool wlast;
} AxiMmNapBeatW deriving(Bits, FShow);

typedef struct {
    NapAxiBid bid;
    NapAxiBresp bresp;
} AxiMmNapBeatB deriving(Bits, FShow);

typedef struct {
    NapAxiArid arid;
    NapAxiAraddr araddr;
    NapAxiArlen arlen;
    NapAxiArsize arsize;
    NapAxiArburst arburst;
    Bool arlock;
    NapAxiArqos arqos;
} AxiMmNapBeatAr deriving(Bits, FShow);

typedef struct {
    NapAxiRid rid;
    NapAxiRdata rdata;
    NapAxiRresp rresp;
    Bool rlast;
} AxiMmNapBeatR deriving(Bits, FShow);


(* always_ready, always_enabled*)
interface ACX_NAP_AXI_MASTER_BVI_WRAPPER;
    
    // aw channel ===========
    // output port
    method NapAxiAwid awid;
    method NapAxiAwaddr awaddr;
    method NapAxiAwlen awlen;
    method NapAxiAwsize awsize;
    method NapAxiAwburst awburst;
    method Bool awlock;
    method NapAxiAwqos awqos;
    method Bool awvalid;
    // input port
    method Action awready(Bool val);

    // w channel ===========
    // output port
    method NapAxiWdata wdata;
    method NapAxiWstrb wstrb;
    method Bool wlast;
    method Bool wvalid;
    // input port
    method Action wready(Bool val);

    // b channel ===========
    // output port 
    method Bool bready;
    // input port
    method Action bid(NapAxiBid val);
    method Action bresp(NapAxiBresp val);
    method Action bvalid(Bool val);

    // ar channel ===========
    // output port 
    method NapAxiArid arid;
    method NapAxiAraddr araddr;
    method NapAxiArlen arlen;
    method NapAxiArsize arsize;
    method NapAxiArburst arburst;
    method Bool arlock;
    method NapAxiArqos arqos;
    method Bool arvalid;
    // input port
    method Action arready(Bool val);

    // r channel ===========
    // output port
    method Bool rready;
    // input port
    method Action rid(NapAxiRid val);
    method Action rdata(NapAxiRdata val);
    method Action rresp(NapAxiRresp val);
    method Action rlast(Bool val);
    method Action rvalid(Bool val);
endinterface


import "BVI" ACX_NAP_AXI_MASTER =
module mkAcxNapAxiMasterWrapperInner(ACX_NAP_AXI_MASTER_BVI_WRAPPER);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    input_clock (clk) = clk;
    input_reset rstN(rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    // aw channel ===========
    // output port 
    method awid awid clocked_by(clk) reset_by(no_reset);
    method awaddr awaddr clocked_by(clk) reset_by(no_reset);
    method awlen awlen clocked_by(clk) reset_by(no_reset);
    method awsize awsize clocked_by(clk) reset_by(no_reset);
    method awburst awburst clocked_by(clk) reset_by(no_reset);
    method awlock awlock clocked_by(clk) reset_by(no_reset);  
    method awqos awqos clocked_by(clk) reset_by(no_reset);
    method awvalid awvalid clocked_by(clk) reset_by(no_reset);
    // input port
    method awready(awready) enable((*inhigh*) EN_NO_USE_1) clocked_by(clk) reset_by(no_reset);

    // w channel ===========
    // output port
    method wdata wdata clocked_by(clk) reset_by(no_reset);
    method wstrb wstrb clocked_by(clk) reset_by(no_reset);
    method wlast wlast clocked_by(clk) reset_by(no_reset);
    method wvalid wvalid clocked_by(clk) reset_by(no_reset);
    // input port
    method wready(wready) enable((*inhigh*) EN_NO_USE_2) clocked_by(clk) reset_by(no_reset);

    // b channel ===========
    // output port 
    method bready bready clocked_by(clk) reset_by(no_reset);
    // input port
    method bid(bid) enable((*inhigh*) EN_NO_USE_3) clocked_by(clk) reset_by(no_reset);
    method bresp(bresp) enable((*inhigh*) EN_NO_USE_4) clocked_by(clk) reset_by(no_reset);
    method bvalid(bvalid) enable((*inhigh*) EN_NO_USE_5) clocked_by(clk) reset_by(no_reset);

    // ar channel ===========
    // output port 
    method arid arid clocked_by(clk) reset_by(no_reset);
    method araddr araddr clocked_by(clk) reset_by(no_reset);
    method arlen arlen clocked_by(clk) reset_by(no_reset);
    method arsize arsize clocked_by(clk) reset_by(no_reset);
    method arburst arburst clocked_by(clk) reset_by(no_reset);
    method arlock arlock clocked_by(clk) reset_by(no_reset);
    method arqos arqos clocked_by(clk) reset_by(no_reset);
    method arvalid arvalid clocked_by(clk) reset_by(no_reset);
    // input port
    method arready(arready) enable((*inhigh*) EN_NO_USE_6) clocked_by(clk) reset_by(no_reset);

    // r channel ===========
    // output port
    method rready rready clocked_by(clk) reset_by(no_reset);
    // input port
    method rid(rid) enable((*inhigh*) EN_NO_USE_7) clocked_by(clk) reset_by(no_reset);
    method rdata(rdata) enable((*inhigh*) EN_NO_USE_8) clocked_by(clk) reset_by(no_reset);
    method rresp(rresp) enable((*inhigh*) EN_NO_USE_9) clocked_by(clk) reset_by(no_reset);
    method rlast(rlast) enable((*inhigh*) EN_NO_USE_10) clocked_by(clk) reset_by(no_reset);
    method rvalid(rvalid) enable((*inhigh*) EN_NO_USE_11) clocked_by(clk) reset_by(no_reset);

    schedule (awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready
            ) CF (
                awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready);
    
    schedule (awready, wready, bid, bresp, bvalid, arready, 
                rid, rdata, rresp, rlast, rvalid
            ) CF (
                awready, wready, bid, bresp, bvalid, arready,
                rid, rdata, rresp, rlast, rvalid);

    schedule (awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready
            ) CF (
                awready, wready, bid, bresp, bvalid, arready,
                rid, rdata, rresp, rlast, rvalid);
endmodule







module mkAcxNapAxiMasterWrapperInnerBluesim(ACX_NAP_AXI_MASTER_BVI_WRAPPER);

    MockHostBarAccess mockHostBarAccess <- mkMockHostBarAccess;


    FIFOF#(AxiMmNapBeatAw) awQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatW)   wQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatB)   bQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatAr) arQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatR)   rQ   <- mkUGFIFOF;

    Wire#(Bool)       awreadyWire <- mkBypassWire;
    Wire#(Bool)        wreadyWire <- mkBypassWire;
    Wire#(NapAxiBid)       bidWire <- mkBypassWire;
    Wire#(NapAxiBresp)       brespWire <- mkBypassWire;
    Wire#(Bool)       bvalidWire <- mkBypassWire;
    Wire#(Bool)       arreadyWire <- mkBypassWire;
    Wire#(NapAxiRid)       ridWire <- mkBypassWire;
    Wire#(NapAxiRdata)       rdataWire <- mkBypassWire;
    Wire#(NapAxiRresp)       rrespWire <- mkBypassWire;
    Wire#(Bool)       rlastWire <- mkBypassWire;
    Wire#(Bool)       rvalidWire <- mkBypassWire;



    rule forwardWriteReq;
        if (awQ.notFull && wQ.notFull) begin
            let {addr, data} <- mockHostBarAccess.barWriteClt.request.get;
            let awReq = AxiMmNapBeatAw {
                awid: 0,
                awaddr: zeroExtend(addr),
                awlen: unpack(0),
                awsize: unpack(pack(NapAxiSize32B)),
                awburst: unpack(pack(NapAxiBurstIncr)),
                awlock: False,
                awqos: 0
            };
            awQ.enq(awReq);

            let wReq = AxiMmNapBeatW {
                wdata: zeroExtend(data),
                wstrb: 'hF,
                wlast: True
            };
            wQ.enq(wReq);
            // $display("time=%0t,  mkAcxNapAxiMasterWrapperInnerBluesim, forwardWriteReq", $time, "addr=", fshow(addr));
        end
    endrule

    rule forwardWriteResp;
        if (bQ.notEmpty) begin
            let resp = bQ.first;
            bQ.deq;
            mockHostBarAccess.barWriteClt.response.put(True);
        end
    endrule


    rule forwardReadReq;
        if (arQ.notFull) begin
            let addr <- mockHostBarAccess.barReadClt.request.get;
            let arReq = AxiMmNapBeatAr {
                arid: 0,
                araddr: zeroExtend(addr),
                arlen: unpack(0),
                arsize: unpack(pack(NapAxiSize32B)),
                arburst: unpack(pack(NapAxiBurstIncr)),
                arlock: False,
                arqos: 0
            };
            arQ.enq(arReq);
        end
    endrule

    rule forwardReadResp;
        if (rQ.notEmpty) begin
            let resp = rQ.first;
            rQ.deq;
            mockHostBarAccess.barReadClt.response.put(truncate(resp.rdata));
        end
    endrule

    rule handleHandshake;
        if (awQ.notEmpty && awreadyWire) begin
            awQ.deq;
        end
        if (wQ.notEmpty && wreadyWire) begin
            wQ.deq;
        end
        if (bQ.notFull && bvalidWire) begin
            let bresp = AxiMmNapBeatB {
                bid: bidWire,
                bresp: brespWire
            };
            bQ.enq(bresp);
        end
        if (arQ.notEmpty && arreadyWire) begin
            arQ.deq;
        end
        if (rQ.notFull && rvalidWire) begin
            let rresp = AxiMmNapBeatR {
                rid  : ridWire,
                rdata: rdataWire,
                rresp: rrespWire,
                rlast: rlastWire
            };
            rQ.enq(rresp);
        end
    endrule




    // aw channel ===========
    // output port
    method awid = awQ.first.awid;
    method awaddr = awQ.first.awaddr;
    method awlen = awQ.first.awlen;
    method awsize = awQ.first.awsize;
    method awburst = awQ.first.awburst;
    method awlock = awQ.first.awlock;
    method awqos = awQ.first.awqos;
    method awvalid = awQ.notEmpty;
    // input port
    method awready = awreadyWire._write;

    // w channel ===========
    // output port
    method wdata = wQ.first.wdata;
    method wstrb = wQ.first.wstrb;
    method wlast = wQ.first.wlast;
    method wvalid = wQ.notEmpty;
    // input port
    method wready = wreadyWire._write;

    // b channel ===========
    // output port 
    method bready = bQ.notFull;
    // input port
    method bid = bidWire._write;
    method bresp = brespWire._write;
    method bvalid = bvalidWire._write;

    // ar channel ===========
    // output port 
    method arid = arQ.first.arid;
    method araddr = arQ.first.araddr;
    method arlen = arQ.first.arlen;
    method arsize = arQ.first.arsize;
    method arburst = arQ.first.arburst;
    method arlock = arQ.first.arlock;
    method arqos = arQ.first.arqos;
    method arvalid = arQ.notEmpty;
    // input port
    method arready = arreadyWire._write;

    // r channel ===========
    // output port
    method rready = rQ.notFull;
    // input port
    method rid = ridWire._write;
    method rdata = rdataWire._write;
    method rresp = rrespWire._write;
    method rlast = rlastWire._write;
    method rvalid = rvalidWire._write;
endmodule


module mkAcxNapAxiMasterPrimitiveWrapper(ACX_NAP_AXI_MASTER_BVI_WRAPPER);
    ACX_NAP_AXI_MASTER_BVI_WRAPPER inst;

    if (genVerilog) begin
        inst <- mkAcxNapAxiMasterWrapperInner;
    end
    else begin
        inst <- mkAcxNapAxiMasterWrapperInnerBluesim;
    end

    return inst;
endmodule



interface AcxNapMasterWrapper;
    method ActionValue#(AxiMmNapBeatAw) recvWriteAddr;
    method ActionValue#(AxiMmNapBeatW) recvWriteData;
    method Action sendWriteResp(AxiMmNapBeatB beat);

    method ActionValue#(AxiMmNapBeatAr) recvReadAddr;
    method Action sendReadResp(AxiMmNapBeatR beat);
endinterface


module mkAcxNapMasterWrapper(AcxNapMasterWrapper);
    let inner <- mkAcxNapMasterWrapperPipe;

    method ActionValue#(AxiMmNapBeatAw) recvWriteAddr if (inner.writePipeIfc.writeAddrPipeOut.notEmpty);
        inner.writePipeIfc.writeAddrPipeOut.deq;
        return inner.writePipeIfc.writeAddrPipeOut.first;
    endmethod

    method ActionValue#(AxiMmNapBeatW) recvWriteData if (inner.writePipeIfc.writeDataPipeOut.notEmpty);
        inner.writePipeIfc.writeDataPipeOut.deq;
        return inner.writePipeIfc.writeDataPipeOut.first;
    endmethod

    method Action sendWriteResp(AxiMmNapBeatB beat) if (inner.writePipeIfc.writeRespPipeIn.notFull);
        inner.writePipeIfc.writeRespPipeIn.enq(beat);
    endmethod

    method ActionValue#(AxiMmNapBeatAr) recvReadAddr if (inner.readPipeIfc.readAddrPipeOut.notEmpty);
        inner.readPipeIfc.readAddrPipeOut.deq;
        return inner.readPipeIfc.readAddrPipeOut.first;
    endmethod

    method Action sendReadResp(AxiMmNapBeatR beat) if (inner.readPipeIfc.readRespPipeIn.notFull);
        inner.readPipeIfc.readRespPipeIn.enq(beat);
    endmethod

endmodule



interface AcxNapMasterWrapperWritePipe;
    interface PipeOut#(AxiMmNapBeatAw)  writeAddrPipeOut;
    interface PipeOut#(AxiMmNapBeatW)   writeDataPipeOut;
    interface PipeIn#(AxiMmNapBeatB)    writeRespPipeIn;
endinterface

interface AcxNapMasterWrapperReadPipe;
    interface PipeOut#(AxiMmNapBeatAr)  readAddrPipeOut;
    interface PipeIn#(AxiMmNapBeatR)    readRespPipeIn;
endinterface


interface AcxNapMasterWrapperPipe;
    interface AcxNapMasterWrapperWritePipe  writePipeIfc;
    interface AcxNapMasterWrapperReadPipe   readPipeIfc;
endinterface


(* synthesize *)
module mkAcxNapMasterWrapperPipe(AcxNapMasterWrapperPipe);

    FIFOF#(AxiMmNapBeatAw) awQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatW)   wQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatB)   bQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatAr) arQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatR)   rQ   <- mkUGFIFOF;
    
    let axiMasterNap <- mkAcxNapAxiMasterPrimitiveWrapper;

    rule forwardAxiSignalAw;
        if (awQ.notFull) begin
            axiMasterNap.awready(True);
            if (axiMasterNap.awvalid) begin
                let recvBeat = AxiMmNapBeatAw{
                    awid: axiMasterNap.awid,
                    awaddr: zeroExtend(axiMasterNap.awaddr),
                    awlen: axiMasterNap.awlen,
                    awsize: axiMasterNap.awsize,
                    awburst: axiMasterNap.awburst,
                    awlock: axiMasterNap.awlock,
                    awqos: axiMasterNap.awqos
                };
                awQ.enq(recvBeat);
            end
        end
        else begin
            axiMasterNap.awready(False);
        end
    endrule

    rule forwardAxiSignalW;
        if (wQ.notFull) begin
            axiMasterNap.wready(True);
            if (axiMasterNap.wvalid) begin
                let recvBeat = AxiMmNapBeatW{
                    wdata: axiMasterNap.wdata,
                    wstrb: axiMasterNap.wstrb,
                    wlast: axiMasterNap.wlast
                };
                wQ.enq(recvBeat);
            end
        end
        else begin
            axiMasterNap.wready(False);
        end
    endrule


    rule forwardAxiSignalB;
        let bBeat = bQ.first;
        axiMasterNap.bvalid(bQ.notEmpty);
        axiMasterNap.bid(bBeat.bid);
        axiMasterNap.bresp(bBeat.bresp);
        if (bQ.notEmpty) begin
            if (axiMasterNap.bready) begin
                bQ.deq;
            end
        end
    endrule

    
    rule forwardAxiSignalAr;
        if (arQ.notFull) begin
            axiMasterNap.arready(True);
            if (axiMasterNap.arvalid) begin
                let recvBeat = AxiMmNapBeatAr{
                    arid: axiMasterNap.arid,
                    araddr: zeroExtend(axiMasterNap.araddr),
                    arlen: axiMasterNap.arlen,
                    arsize: axiMasterNap.arsize,
                    arburst: axiMasterNap.arburst,
                    arlock: axiMasterNap.arlock,
                    arqos: axiMasterNap.arqos
                };
                arQ.enq(recvBeat);
            end
        end
        else begin
            axiMasterNap.arready(False);
        end
    endrule


    rule forwardAxiSignalR;
        let rBeat = rQ.first;
        axiMasterNap.rvalid(rQ.notEmpty);
        axiMasterNap.rid(rBeat.rid);
        axiMasterNap.rdata(rBeat.rdata);
        axiMasterNap.rresp(rBeat.rresp);
        axiMasterNap.rlast(rBeat.rlast);

        if (rQ.notEmpty) begin
            if (axiMasterNap.rready) begin
                rQ.deq;
            end
        end
    endrule

    interface AcxNapMasterWrapperWritePipe  writePipeIfc;
        interface writeAddrPipeOut = ugToPipeOut(awQ);
        interface writeDataPipeOut = ugToPipeOut(wQ);
        interface writeRespPipeIn  = ugToPipeIn(bQ);
    endinterface

    interface AcxNapMasterWrapperReadPipe   readPipeIfc;
        interface readAddrPipeOut = ugToPipeOut(arQ);
        interface readRespPipeIn  = ugToPipeIn(rQ);
    endinterface
    
endmodule


(* always_ready, always_enabled*)
interface ACX_NAP_AXI_SLAVE_BVI_WRAPPER;
    
    // aw channel ===========
    // input port
    method Action awid(NapAxiAwid val);
    method Action awaddr(NapAxiAwaddr val);
    method Action awlen(NapAxiAwlen val);
    method Action awsize(NapAxiAwsize val);
    method Action awburst(NapAxiAwburst val);
    method Action awlock(Bool val);
    method Action awqos(NapAxiAwqos val);
    method Action awvalid(Bool val);
    // output port
    method Bool awready;

    // w channel ===========
    // input port
    method Action wdata(NapAxiWdata val);
    method Action wstrb(NapAxiWstrb val);
    method Action wlast(Bool val);
    method Action wvalid(Bool val);
    // output port
    method Bool wready;

    // b channel ===========
    // input port
    method Action bready(Bool val);
    // output port 
    method NapAxiBid bid;
    method NapAxiBresp bresp;
    method Bool bvalid;

    // ar channel ===========
    // input port
    method Action arid(NapAxiArid val);
    method Action araddr(NapAxiAraddr val);
    method Action arlen(NapAxiArlen val);
    method Action arsize(NapAxiArsize val);
    method Action arburst(NapAxiArburst val);
    method Action arlock(Bool val);
    method Action arqos(NapAxiArqos val);
    method Action arvalid(Bool val);
    // output port 
    method Bool arready;

    // r channel ===========
    // input port
    method Action rready(Bool val);
    // output port
    method NapAxiRid rid;
    method NapAxiRdata rdata;
    method NapAxiRresp rresp;
    method Bool rlast;
    method Bool rvalid;
endinterface


import "BVI" ACX_NAP_AXI_SLAVE =
module mkAcxNapAxiSlaveWrapperInner(ACX_NAP_AXI_SLAVE_BVI_WRAPPER);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    input_clock (clk) = clk;
    input_reset rstN(rstn) = rst;
    
    default_clock no_clock;
    no_reset;

    // aw channel ===========
    // input port
    method awid(awid) enable((*inhigh*) EN_NO_USE_1) clocked_by(clk) reset_by(no_reset);
    method awaddr(awaddr) enable((*inhigh*) EN_NO_USE_2) clocked_by(clk) reset_by(no_reset);
    method awlen(awlen) enable((*inhigh*) EN_NO_USE_3) clocked_by(clk) reset_by(no_reset);
    method awsize(awsize) enable((*inhigh*) EN_NO_USE_4) clocked_by(clk) reset_by(no_reset);
    method awburst(awburst) enable((*inhigh*) EN_NO_USE_5) clocked_by(clk) reset_by(no_reset);
    method awlock(awlock) enable((*inhigh*) EN_NO_USE_6) clocked_by(clk) reset_by(no_reset);
    method awqos(awqos) enable((*inhigh*) EN_NO_USE_7) clocked_by(clk) reset_by(no_reset);
    method awvalid(awvalid) enable((*inhigh*) EN_NO_USE_8) clocked_by(clk) reset_by(no_reset);
    // output port
    method awready awready clocked_by(clk) reset_by(no_reset);


    // w channel ===========
    // input port
    method wdata(wdata) enable((*inhigh*) EN_NO_USE_9) clocked_by(clk) reset_by(no_reset);
    method wstrb(wstrb) enable((*inhigh*) EN_NO_USE_10) clocked_by(clk) reset_by(no_reset);
    method wlast(wlast) enable((*inhigh*) EN_NO_USE_11) clocked_by(clk) reset_by(no_reset);
    method wvalid(wvalid) enable((*inhigh*) EN_NO_USE_12) clocked_by(clk) reset_by(no_reset);
   // output port
    method wready wready clocked_by(clk) reset_by(no_reset);

    // b channel ===========
    // input port
    method bready(bready) enable((*inhigh*) EN_NO_USE_13) clocked_by(clk) reset_by(no_reset);
    // output port 
    method bid bid clocked_by(clk) reset_by(no_reset);
    method bresp bresp clocked_by(clk) reset_by(no_reset);
    method bvalid bvalid clocked_by(clk) reset_by(no_reset);

    // ar channel ===========
    // input port
    method arid(arid) enable((*inhigh*) EN_NO_USE_14) clocked_by(clk) reset_by(no_reset);
    method araddr(araddr) enable((*inhigh*) EN_NO_USE_15) clocked_by(clk) reset_by(no_reset);
    method arlen(arlen) enable((*inhigh*) EN_NO_USE_16) clocked_by(clk) reset_by(no_reset);
    method arsize(arsize) enable((*inhigh*) EN_NO_USE_17) clocked_by(clk) reset_by(no_reset);
    method arburst(arburst) enable((*inhigh*) EN_NO_USE_18) clocked_by(clk) reset_by(no_reset);
    method arlock(arlock) enable((*inhigh*) EN_NO_USE_19) clocked_by(clk) reset_by(no_reset);
    method arqos(arqos) enable((*inhigh*) EN_NO_USE_20) clocked_by(clk) reset_by(no_reset);
    method arvalid(arvalid) enable((*inhigh*) EN_NO_USE_21) clocked_by(clk) reset_by(no_reset);
    // output port 
    method arready arready clocked_by(clk) reset_by(no_reset);
   
    // r channel ===========
    // input port
    method rready(rready) enable((*inhigh*) EN_NO_USE_22) clocked_by(clk) reset_by(no_reset);
    // output port
    method rid rid clocked_by(clk) reset_by(no_reset);
    method rdata rdata clocked_by(clk) reset_by(no_reset);
    method rresp rresp clocked_by(clk) reset_by(no_reset);
    method rlast rlast clocked_by(clk) reset_by(no_reset);
    method rvalid rvalid clocked_by(clk) reset_by(no_reset);

    schedule (awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready, bid, awready, 
                wready, bvalid, arready, rid, rdata, rresp, 
                rlast, rvalid, bresp
            ) CF (
                awid, awaddr, awlen, awsize, awburst, awlock, 
                awqos, awvalid, wdata, wstrb, wlast, wvalid, 
                bready, arid, araddr, arlen, arsize, arburst, 
                arlock, arqos, arvalid, rready, bresp, bvalid,
                awready, wready, bvalid, arready, rid, rdata,
                rresp, rlast, rvalid, bid);
endmodule




typedef 26 MOCK_HOST_ADDR_WIDTH;
typedef Bit#(MOCK_HOST_ADDR_WIDTH) MockHostAddr;
typedef TLog#(NOC_DATA_BUS_BYTE_WIDTH) NOC_DATA_BUS_BYTE_NUM_WIDTH;
typedef TSub#(MOCK_HOST_ADDR_WIDTH, NOC_DATA_BUS_BYTE_NUM_WIDTH) MOCK_HOST_INTERNAL_STORAGE_ADDR_WIDTH;
typedef Bit#(MOCK_HOST_INTERNAL_STORAGE_ADDR_WIDTH) MockHostInternalStorageAddr;

typedef BRAMRequestBE#(MockHostInternalStorageAddr, NocData, NOC_DATA_BUS_BYTE_WIDTH) MockHostBramRequest;

module mkAcxNapAxiSlaveWrapperInnerBluesim(ACX_NAP_AXI_SLAVE_BVI_WRAPPER);
    BRAM_Configure cfg = defaultValue;
    cfg.allowWriteResponseBypass = False;
    cfg.memorySize = 0;

`ifdef USE_MOCK_HOST 
    MockHostMem#(MockHostInternalStorageAddr, NocData, NOC_DATA_BUS_BYTE_WIDTH) hostMemMockHostBackend <- mkMockHostMem(cfg);
    let hostMem = hostMemMockHostBackend.hostMem;
`else
    BRAM2PortBE#(MockHostInternalStorageAddr, NocData, NOC_DATA_BUS_BYTE_WIDTH) hostMemBramBackend <- mkBRAM2ServerBE(cfg);
    let hostMem = hostMemBramBackend;
`endif
    

    FIFOF#(AxiMmNapBeatAw) awQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatW)   wQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatB)   bQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatAr) arQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatR)   rQ   <- mkUGFIFOF;

    Wire#(NapAxiAwid)       awidWire <- mkBypassWire;
    Wire#(NapAxiAwaddr)     awaddrWire <- mkBypassWire;
    Wire#(NapAxiAwlen)      awlenWire <- mkBypassWire;
    Wire#(NapAxiAwsize)     awsizeWire <- mkBypassWire;
    Wire#(NapAxiAwburst)    awburstWire <- mkBypassWire;
    Wire#(Bool)             awlockWire <- mkBypassWire;
    Wire#(NapAxiAwqos)      awqosWire <- mkBypassWire;
    Wire#(Bool)             awvalidWire <- mkBypassWire;

    Wire#(NapAxiWdata)  wdataWire   <- mkBypassWire;
    Wire#(NapAxiWstrb)  wstrbWire   <- mkBypassWire;
    Wire#(Bool)         wlastWire   <- mkBypassWire;
    Wire#(Bool)         wvalidWire  <- mkBypassWire;

    Wire#(Bool)             breadyWire <- mkBypassWire;

    Wire#(NapAxiArid)       aridWire <- mkBypassWire;
    Wire#(NapAxiAraddr)     araddrWire <- mkBypassWire;
    Wire#(NapAxiArlen)      arlenWire <- mkBypassWire;
    Wire#(NapAxiArsize)     arsizeWire <- mkBypassWire;
    Wire#(NapAxiArburst)    arburstWire <- mkBypassWire;
    Wire#(Bool)             arlockWire <- mkBypassWire;
    Wire#(NapAxiArqos)      arqosWire <- mkBypassWire;
    Wire#(Bool)             arvalidWire <- mkBypassWire;

    Wire#(Bool)             rreadyWire <- mkBypassWire;
    



    rule recvReqAw;
        if (awvalidWire && awQ.notFull) begin
            let entry = AxiMmNapBeatAw {
                awid    : awidWire,
                awaddr  : awaddrWire,
                awlen   : awlenWire,
                awsize  : awsizeWire,
                awburst : awburstWire,
                awlock  : awlockWire,
                awqos   : awqosWire
            };
            awQ.enq(entry);
        end
    endrule

    rule recvReqW;
        if (wvalidWire && wQ.notFull) begin
            let entry = AxiMmNapBeatW {
                wdata: wdataWire,
                wstrb: wstrbWire,
                wlast: wlastWire
            };
            wQ.enq(entry);
        end
    endrule

    rule recvReqAr;
        if (arvalidWire && arQ.notFull) begin
            let entry = AxiMmNapBeatAr {
                arid    : aridWire,
                araddr  : araddrWire,
                arlen   : arlenWire,
                arsize  : arsizeWire,
                arburst : arburstWire,
                arlock  : arlockWire,
                arqos   : arqosWire
            };
            arQ.enq(entry);
        end
    endrule

    rule sendRespB;
        if (breadyWire && bQ.notEmpty) begin
            bQ.deq;
        end
    endrule

    rule sendRespR;
        if (rreadyWire && rQ.notEmpty) begin
            rQ.deq;
        end
    endrule

    Reg#(AxiMmNapBeatAw) curReqAwReg <- mkRegU;
    Reg#(NapAxiAwlen) writeLenCounterReg <- mkRegU;
    Reg#(Bool) isInBurstWritingReg <- mkReg(False);
    Reg#(MockHostInternalStorageAddr) burstWriteAddrReg <- mkRegU;

    Reg#(AxiMmNapBeatAr) curReqArReg <- mkRegU;
    Reg#(NapAxiAwlen) readLenCounterReg <- mkRegU;
    Reg#(Bool) isInBurstReadingReg <- mkReg(False);
    Reg#(MockHostInternalStorageAddr) burstReadAddrReg <- mkRegU;

    FIFOF#(Tuple2#(Bool, AxiMmNapBeatAr)) inFlightReadRespQ <- mkFIFOF;


    rule handleWriteReq; 
        let writeLenCounter = writeLenCounterReg;

        if (!isInBurstWritingReg) begin
            if (awQ.notEmpty && wQ.notEmpty && bQ.notFull) begin
                let aw = awQ.first;
                awQ.deq;
                let w = wQ.first;
                wQ.deq;

                curReqAwReg <= aw;
                writeLenCounter = aw.awlen;
                writeLenCounterReg <= writeLenCounter - 1;
                if (writeLenCounter != 0) begin
                    isInBurstWritingReg <= True;
                    immAssert(
                        !w.wlast,
                        "data should not assert wlast in this beat",
                        $format("aw=", fshow(aw), "w=", fshow(w))
                    );
                end
                else begin
                    immAssert(
                        w.wlast,
                        "data should assert wlast in this beat",
                        $format("aw=", fshow(aw), "w=", fshow(w))
                    );
                    let bEntry = AxiMmNapBeatB{
                        bid: aw.awid,
                        bresp: 0
                    };
                    bQ.enq(bEntry);
                end

                MockHostInternalStorageAddr curAddr = truncate(aw.awaddr >> valueOf(NOC_DATA_BUS_BYTE_NUM_WIDTH));
                burstWriteAddrReg <= curAddr;

                MockHostBramRequest bramReq = BRAMRequestBE{
                    writeen: unpack(pack(w.wstrb)),
                    responseOnWrite: False,
                    address: curAddr,
                    datain: w.wdata
                };
                hostMem.portA.request.put(bramReq);
                // $display("aw=", fshow(aw), ", w=", fshow(w));
                // $display(
                //     "1 write bramReq curAddr=", fshow(bramReq.address),
                //     "writeen=", fshow(bramReq.writeen),
                //     "datain=", fshow(bramReq.datain)
                // );
            end
        end
        else begin
            if (wQ.notEmpty && bQ.notFull) begin
                let w = wQ.first;
                wQ.deq;

                writeLenCounterReg <= writeLenCounter - 1;
                if (writeLenCounter != 0) begin
                    isInBurstWritingReg <= True;
                    immAssert(
                        !w.wlast,
                        "data should not assert wlast in this beat",
                        $format("aw=", fshow(curReqAwReg), "w=", fshow(w))
                    );
                end
                else begin
                    isInBurstWritingReg <= False;
                    immAssert(
                        w.wlast,
                        "data should assert wlast in this beat",
                        $format("aw=", fshow(curReqAwReg), "w=", fshow(w))
                    );

                    let bEntry = AxiMmNapBeatB{
                        bid: curReqAwReg.awid,
                        bresp: 0
                    };
                    bQ.enq(bEntry);
                end

                let curAddr = burstWriteAddrReg + 1;
                burstWriteAddrReg <= curAddr;

                MockHostBramRequest bramReq = BRAMRequestBE{
                    writeen: unpack(pack(w.wstrb)),
                    responseOnWrite: False,
                    address: curAddr,
                    datain: w.wdata
                };
                hostMem.portA.request.put(bramReq);
                // $display("aw=", fshow(curReqAwReg), ", w=", fshow(w));
                // $display(
                //     "2 write bramReq curAddr=", fshow(bramReq.address),
                //     "writeen=", fshow(bramReq.writeen),
                //     "datain=", fshow(bramReq.datain)
                // );
            end
        end
        
    endrule


    rule handleReadReq;
        let readLenCounter = readLenCounterReg;

        if (!isInBurstReadingReg) begin
            if (arQ.notEmpty) begin
                let ar = arQ.first;
                arQ.deq;
               
                curReqArReg <= ar;
                readLenCounter = ar.arlen;
                readLenCounterReg <= readLenCounter - 1;
                let isLast = readLenCounter == 0;
                if (readLenCounter != 0) begin
                    isInBurstReadingReg <= True;
                end

                MockHostInternalStorageAddr curAddr = truncate(ar.araddr >> valueOf(NOC_DATA_BUS_BYTE_NUM_WIDTH));

                burstReadAddrReg <= curAddr;

                MockHostBramRequest bramReq = BRAMRequestBE{
                    writeen: 0,
                    responseOnWrite: False,
                    address: curAddr,
                    datain: 0
                };
                hostMem.portB.request.put(bramReq);
                inFlightReadRespQ.enq(tuple2(isLast, ar));
                // $display("read bramReq curAddr=", fshow(bramReq.address));
            end
        end
        else begin
            readLenCounterReg <= readLenCounter - 1;
            let isLast = readLenCounter == 0;
            if (isLast) begin
                isInBurstReadingReg <= False;
            end

            let curAddr = burstReadAddrReg + 1;
            burstReadAddrReg <= curAddr;

            MockHostBramRequest bramReq = BRAMRequestBE{
                writeen: 0,
                responseOnWrite: False,
                address: curAddr,
                datain: 0
            };
            hostMem.portB.request.put(bramReq);
            inFlightReadRespQ.enq(tuple2(isLast, curReqArReg));
            // $display("read bramReq curAddr=", fshow(bramReq.address));
        end
    endrule
    
    rule sendReadResp;
        if (rQ.notFull) begin
            let {isLast, ar} = inFlightReadRespQ.first;
            inFlightReadRespQ.deq;

            let resp <- hostMem.portB.response.get;
            let rEntry = AxiMmNapBeatR {
                rid: ar.arid,
                rdata: resp,
                rresp: 0,
                rlast: isLast
            };
            rQ.enq(rEntry);

            // $display("ar=", fshow(ar), ", resp=", fshow(resp));
        end
    endrule




    // aw channel ===========
    // input port
    method awid         = awidWire._write;
    method awaddr       = awaddrWire._write;
    method awlen        = awlenWire._write;
    method awsize       = awsizeWire._write;
    method awburst      = awburstWire._write;
    method awlock       = awlockWire._write;
    method awqos        = awqosWire._write;
    method awvalid      = awvalidWire._write;
    // output port
    method awready      = awQ.notFull;

    // w channel ===========
    // input port
    method wdata    = wdataWire._write;
    method wstrb    = wstrbWire._write;
    method wlast    = wlastWire._write;
    method wvalid   = wvalidWire._write;
    // output port
    method wready   = wQ.notFull;

    // b channel ===========
    // input port
    method bready   = breadyWire._write;
    // output port 
    method bid      = bQ.first.bid;
    method bresp    = bQ.first.bresp;
    method bvalid   = bQ.notEmpty;

    // ar channel ===========
    // input port
    method arid         = aridWire._write;
    method araddr       = araddrWire._write;
    method arlen        = arlenWire._write;
    method arsize       = arsizeWire._write;
    method arburst      = arburstWire._write;
    method arlock       = arlockWire._write;
    method arqos        = arqosWire._write;
    method arvalid      = arvalidWire._write;
    // output port
    method arready      = arQ.notFull;


    // r channel ===========
    // input port
    method rready = rreadyWire._write;
    // output port
    method rid      = rQ.first.rid;
    method rdata    = rQ.first.rdata;
    method rresp    = rQ.first.rresp;
    method rlast    = rQ.first.rlast;
    method rvalid   = rQ.notEmpty;
   
endmodule


module mkAcxNapAxiSlavePrimitiveWrapper(ACX_NAP_AXI_SLAVE_BVI_WRAPPER);
    ACX_NAP_AXI_SLAVE_BVI_WRAPPER inst;

    if (genVerilog) begin
        inst <- mkAcxNapAxiSlaveWrapperInner;
    end
    else begin
        inst <-mkAcxNapAxiSlaveWrapperInnerBluesim;
    end

    return inst;
endmodule


interface AcxNapSlaveWrapper;
    method Action sendWriteAddr(AxiMmNapBeatAw beat);
    method Action sendWriteData(AxiMmNapBeatW beat);
    method ActionValue#(AxiMmNapBeatB) recvWriteResp;

    method Action sendReadAddr(AxiMmNapBeatAr beat);
    method ActionValue#(AxiMmNapBeatR) recvReadResp;
endinterface


module mkAcxNapSlaveWrapper(AcxNapSlaveWrapper);
    let inner <- mkAcxNapSlaveWrapperPipe;

    method Action sendWriteAddr(AxiMmNapBeatAw beat) if (inner.writePipeIfc.writeAddrPipeIn.notFull);
        inner.writePipeIfc.writeAddrPipeIn.enq(beat);
    endmethod

    method Action sendWriteData(AxiMmNapBeatW beat) if (inner.writePipeIfc.writeDataPipeIn.notFull);
        inner.writePipeIfc.writeDataPipeIn.enq(beat);
    endmethod

    method ActionValue#(AxiMmNapBeatB) recvWriteResp if (inner.writePipeIfc.writeRespPipeOut.notEmpty);
        inner.writePipeIfc.writeRespPipeOut.deq;
        return inner.writePipeIfc.writeRespPipeOut.first;
    endmethod

    method Action sendReadAddr(AxiMmNapBeatAr beat) if (inner.readPipeIfc.readAddrPipeIn.notFull);
        inner.readPipeIfc.readAddrPipeIn.enq(beat);
    endmethod

    method ActionValue#(AxiMmNapBeatR) recvReadResp if (inner.readPipeIfc.readRespPipeOut.notEmpty);
        inner.readPipeIfc.readRespPipeOut.deq;
        return inner.readPipeIfc.readRespPipeOut.first;
    endmethod
endmodule

interface AcxNapSlaveWrapperWritePipe;
    interface PipeIn#(AxiMmNapBeatAw) writeAddrPipeIn;
    interface PipeIn#(AxiMmNapBeatW) writeDataPipeIn;
    interface PipeOut#(AxiMmNapBeatB) writeRespPipeOut;
endinterface

interface AcxNapSlaveWrapperReadPipe;
    interface PipeIn#(AxiMmNapBeatAr) readAddrPipeIn;
    interface PipeOut#(AxiMmNapBeatR) readRespPipeOut;
endinterface

interface AcxNapSlaveWrapperPipe;
    interface AcxNapSlaveWrapperWritePipe writePipeIfc;
    interface AcxNapSlaveWrapperReadPipe readPipeIfc;
endinterface

(* synthesize *)
module mkAcxNapSlaveWrapperPipe(AcxNapSlaveWrapperPipe);

    FIFOF#(AxiMmNapBeatAw) awQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatW)   wQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatB)   bQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatAr) arQ   <- mkUGFIFOF;
    FIFOF#(AxiMmNapBeatR)   rQ   <- mkUGFIFOF;


    
    let axiSlaveNap <- mkAcxNapAxiSlavePrimitiveWrapper;


    rule forwardAxiSignalAw;
        let awBeat = awQ.first;
        axiSlaveNap.awvalid(awQ.notEmpty);

        axiSlaveNap.awid(awBeat.awid);
        axiSlaveNap.awaddr(awBeat.awaddr);
        axiSlaveNap.awlen(awBeat.awlen);
        axiSlaveNap.awsize(awBeat.awsize);
        axiSlaveNap.awburst(awBeat.awburst);
        axiSlaveNap.awlock(awBeat.awlock);
        axiSlaveNap.awqos(awBeat.awqos);

        if (awQ.notEmpty) begin
            if (axiSlaveNap.awready) begin
                awQ.deq;
            end
        end
    endrule


    rule forwardAxiSignalW;
        let wBeat = wQ.first;
        axiSlaveNap.wvalid(wQ.notEmpty);

        axiSlaveNap.wdata(wBeat.wdata);
        axiSlaveNap.wstrb(wBeat.wstrb);
        axiSlaveNap.wlast(wBeat.wlast);

        if (wQ.notEmpty) begin
            if (axiSlaveNap.wready) begin
                wQ.deq;
            end
        end
    endrule


    rule forwardAxiSignalB;
        if (bQ.notFull) begin
            axiSlaveNap.bready(True);
            if (axiSlaveNap.bvalid) begin
                let recvBeat = AxiMmNapBeatB{
                    bid: axiSlaveNap.bid,
                    bresp: axiSlaveNap.bresp
                };
                bQ.enq(recvBeat);
            end
        end
        else begin
            axiSlaveNap.bready(False);
        end
    endrule

    
    rule forwardAxiSignalAr;
        let arBeat = arQ.first;
        axiSlaveNap.arvalid(arQ.notEmpty);
        axiSlaveNap.arid(arBeat.arid);
        axiSlaveNap.araddr(arBeat.araddr);
        axiSlaveNap.arlen(arBeat.arlen);
        axiSlaveNap.arsize(arBeat.arsize);
        axiSlaveNap.arburst(arBeat.arburst);
        axiSlaveNap.arlock(arBeat.arlock);
        axiSlaveNap.arqos(arBeat.arqos);

        if (arQ.notEmpty) begin
            if (axiSlaveNap.arready) begin
                arQ.deq;
            end
        end
        
    endrule

    rule forwardAxiSignalR;
        if (rQ.notFull) begin
            axiSlaveNap.rready(True);
            if (axiSlaveNap.rvalid) begin
                let recvBeat = AxiMmNapBeatR{
                    rid: axiSlaveNap.rid,
                    rdata: axiSlaveNap.rdata,
                    rresp: axiSlaveNap.rresp,
                    rlast: axiSlaveNap.rlast
                };
                rQ.enq(recvBeat);
            end
        end
        else begin
            axiSlaveNap.rready(False);
        end
    endrule

    
    interface AcxNapSlaveWrapperWritePipe writePipeIfc;
        interface writeAddrPipeIn   = ugToPipeIn(awQ);
        interface writeDataPipeIn   = ugToPipeIn(wQ);
        interface writeRespPipeOut  = ugToPipeOut(bQ);
    endinterface

    interface AcxNapSlaveWrapperReadPipe readPipeIfc;
        interface readAddrPipeIn    = ugToPipeIn(arQ);
        interface readRespPipeOut   = ugToPipeOut(rQ);
    endinterface
    
endmodule