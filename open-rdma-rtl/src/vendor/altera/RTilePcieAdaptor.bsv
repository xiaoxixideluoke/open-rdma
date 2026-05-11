import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import PcieTypes :: *;
import Cntrs :: *;
import BRAMCore :: *;
import Arbiter :: * ;
import Connectable :: *;
import ConfigReg :: *;
import MIMO :: *;
import Reserved :: *;
import Printf :: *;


import BasicDataTypes :: *;
import RdmaHeaders :: *;
import PAClib :: *;
import ConnectableF :: *;
import PrimUtils :: *;
import PrioritySearchBuffer :: *;
// import AxiBus :: *;
import DtldStream :: *;

import StreamShifterG :: *;
import FullyPipelineChecker :: *;

import Probe :: *;

`include "PcieMacros.bsv"

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} HeaderCreditInitSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} HeaderCreditInitAckSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} HeaderCreditUpdateSignalBundle deriving(Bits, FShow, Eq);

typedef 2 HEADER_CREDIT_UPDATE_CNT_WIDTH;
typedef Bit#(HEADER_CREDIT_UPDATE_CNT_WIDTH) HeaderCreditUpdateCnt;

typedef struct {
    HeaderCreditUpdateCnt cplh;
    HeaderCreditUpdateCnt nph;
    HeaderCreditUpdateCnt ph;
} HeaderCreditUpdateCntSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cpld;
    Bool npd;
    Bool pd;
} DataCreditInitSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cplh;
    Bool nph;
    Bool ph;
} DataCreditInitAckSignalBundle deriving(Bits, FShow, Eq);

typedef struct {
    Bool cpld;
    Bool npd;
    Bool pd;
} DataCreditUpdateSignalBundle deriving(Bits, FShow, Eq);

typedef 4 DATA_CREDIT_UPDATE_CNT_WIDTH;
typedef Bit#(DATA_CREDIT_UPDATE_CNT_WIDTH) DataCreditUpdateCnt;

typedef struct {
    DataCreditUpdateCnt cpld;
    DataCreditUpdateCnt npd;
    DataCreditUpdateCnt pd;
} DataCreditUpdateCntSignalBundle deriving(Bits, FShow, Eq);

typedef 4 PCIE_SEGMENT_CNT;
typedef TLog#(PCIE_SEGMENT_CNT) PCIE_SEGMENT_IDX_WIDTH;
typedef Bit#(PCIE_SEGMENT_IDX_WIDTH) PcieSegmentIdx;


typedef Bit#(PCIE_SEGMENT_CNT) SegmentSopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) SegmentEopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) SegmentDvalidSignalBundle;

typedef 3 PCIE_RX_EMPTY_WIDTH;
typedef Bit#(PCIE_RX_EMPTY_WIDTH) PcieRxEmpty;
typedef Vector#(PCIE_SEGMENT_CNT, PcieRxEmpty) SegmentEmptySignalBundle;

typedef 3 PCIE_BAR_ID_WIDTH;
typedef Bit#(PCIE_BAR_ID_WIDTH) PcieBarId;
typedef Vector#(PCIE_SEGMENT_CNT, PcieBarId) BarIdSignalBundle;

typedef 512 PCIE_TLP_HEADER_BUNDLE_WIDTH;
typedef TDiv#(PCIE_TLP_HEADER_BUNDLE_WIDTH, PCIE_SEGMENT_CNT) PCIE_TLP_HEADER_BUFFER_WIDTH;
typedef Bit#(PCIE_TLP_HEADER_BUFFER_WIDTH) PcieTlpHeaderBuffer;
typedef Vector#(PCIE_SEGMENT_CNT, PcieTlpHeaderBuffer) PcieTlpHeaderBusSegBundle;

typedef 1024 PCIE_TLP_DATA_BUNDLE_WIDTH;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, PCIE_SEGMENT_CNT) PCIE_TLP_DATA_SEGMENT_WIDTH;    // 256
typedef TDiv#(PCIE_TLP_DATA_SEGMENT_WIDTH, BYTE_WIDTH) PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH;    // 32
typedef Bit#(PCIE_TLP_DATA_SEGMENT_WIDTH) PcieTlpDataSegment;
typedef Vector#(PCIE_SEGMENT_CNT, PcieTlpDataSegment) PcieTlpDataBusSegBundle;

typedef Bit#(PCIE_SEGMENT_CNT) SopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) EopSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) HvalidSignalBundle;
typedef Bit#(PCIE_SEGMENT_CNT) DvalidSignalBundle;

typedef 16 CREDIT_COUNTER_WIDTH;
typedef Bit#(CREDIT_COUNTER_WIDTH) CreditCount;

typedef 4 DWORD_CNT_PER_FLOW_CONTROL_CREDIT;

typedef Bit#(TLog#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT)) DispatchChannelIdx;

typedef struct {
    PcieTlpDataBusSegBundle         data;
    PcieTlpHeaderBusSegBundle       header;
    SopSignalBundle                 sop;
    EopSignalBundle                 eop;
    HvalidSignalBundle              hvalid;
    DvalidSignalBundle              dvalid;
    BarIdSignalBundle               bar;
    SegmentEmptySignalBundle        empty;
} PcieRxBeat deriving (Bits, FShow);

typedef struct {
    PcieTlpDataBusSegBundle         data;
    PcieTlpHeaderBusSegBundle       header;
    SopSignalBundle                 sop;
    EopSignalBundle                 eop;
    HvalidSignalBundle              hvalid;
    DvalidSignalBundle              dvalid;
} PcieTxBeat deriving (Bits, FShow);

typedef 13 PCIE_TLP_DATA_BYTE_COUNT_WIDTH;
typedef Bit#(PCIE_TLP_DATA_BYTE_COUNT_WIDTH) PcieTlpDataByteCnt;

interface RTilePcieAdaptorRx;

    // input port
    (* prefix="" *)
    method Action setRxInputData(
        PcieTlpDataBusSegBundle         data,
        PcieTlpHeaderBusSegBundle       hdr,
        SopSignalBundle                 sop,
        EopSignalBundle                 eop,
        HvalidSignalBundle              hvalid,
        DvalidSignalBundle              dvalid,
        BarIdSignalBundle               bar,
        SegmentEmptySignalBundle        empty,
        HeaderCreditInitAckSignalBundle hcrdt_init_ack,
        DataCreditInitAckSignalBundle   dcrdt_init_ack
    );

    // output port
    method Bool                                 ready;
    method HeaderCreditInitSignalBundle         hcrdt_init;
    method HeaderCreditUpdateSignalBundle       hcrdt_update;
    method HeaderCreditUpdateCntSignalBundle    hcrdt_update_cnt;

    method DataCreditInitSignalBundle           dcrdt_init;
    method DataCreditUpdateSignalBundle         dcrdt_update;
    method DataCreditUpdateCntSignalBundle      dcrdt_update_cnt;

endinterface

interface RTilePcieAdaptorTx;

    // input port
    (* prefix="" *)
    method Action setTxInputData(
        HeaderCreditInitSignalBundle        hcrdt_init,
        HeaderCreditUpdateSignalBundle      hcrdt_update,
        HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt,
        DataCreditInitSignalBundle          dcrdt_init,
        DataCreditUpdateSignalBundle        dcrdt_update,
        DataCreditUpdateCntSignalBundle     dcrdt_update_cnt,
        Bool                                ready
    );

    // output port
    method HeaderCreditInitAckSignalBundle      hcrdt_init_ack;
    method DataCreditInitAckSignalBundle        dcrdt_init_ack;
    
    method PcieTlpHeaderBusSegBundle    hdr;
    method PcieTlpDataBusSegBundle      data;
    

    method SopSignalBundle              sop;
    method EopSignalBundle              eop;
    method HvalidSignalBundle           hvalid;
    method DvalidSignalBundle           dvalid;

endinterface

interface RTilePcieAdaptor;
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorRx rx;

    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorTx tx;

    interface PipeOut#(PcieRxBeat) pcieRxPipeOut;
    interface PipeIn#(PcieTxBeat) pcieTxPipeIn;

    interface PipeInB0#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    rxFlowControlReleaseReqPipeIn;
    interface PipeInB0#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    txFlowControlConsumeReqPipeIn;
    interface PipeOut#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))   txFlowControlAvaliablePipeOut;
    
endinterface

(* synthesize *)
module mkRTilePcieAdaptor(RTilePcieAdaptor);

    PcieCreditCounterSink#(CreditCount, HeaderCreditUpdateCnt) rxCreditPH <- mkPcieCreditCounterSink(784);
    PcieCreditCounterSink#(CreditCount, HeaderCreditUpdateCnt) rxCreditNPH <- mkPcieCreditCounterSink(784);
    PcieCreditCounterSink#(CreditCount, HeaderCreditUpdateCnt) rxCreditCPLH <- mkPcieCreditCounterSink(0);

    PcieCreditCounterSink#(CreditCount, DataCreditUpdateCnt) rxCreditPD <- mkPcieCreditCounterSink(1456);
    PcieCreditCounterSink#(CreditCount, DataCreditUpdateCnt) rxCreditNPD <- mkPcieCreditCounterSink(392);
    PcieCreditCounterSink#(CreditCount, DataCreditUpdateCnt) rxCreditCPLD <- mkPcieCreditCounterSink(0);

    PcieCreditCounterSource#(CreditCount, HeaderCreditUpdateCnt) txCreditPH <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, HeaderCreditUpdateCnt) txCreditNPH <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, HeaderCreditUpdateCnt) txCreditCPLH <- mkPcieCreditCounterSource;

    PcieCreditCounterSource#(CreditCount, DataCreditUpdateCnt) txCreditPD <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, DataCreditUpdateCnt) txCreditNPD <- mkPcieCreditCounterSource;
    PcieCreditCounterSource#(CreditCount, DataCreditUpdateCnt) txCreditCPLD <- mkPcieCreditCounterSource;

    FIFOF#(PcieRxBeat) pcieRxPipeOutQueue <- mkUGFIFOF;
    FIFOF#(PcieTxBeat) pcieTxPipeInQueue <- mkUGFIFOF;

    PipeInAdapterB0#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    rxFlowControlReleaseReqPipeInQueue <- mkPipeInAdapterB0;
    PipeInAdapterB0#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    txFlowControlConsumeReqPipeInQueue <- mkPipeInAdapterB0;
    FIFOF#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    txFlowControlAvaliablePipeOutQueue <- mkFIFOF;

    Wire#(Bool) txReadySignalWire <- mkBypassWire;
    Reg#(Bool) txTlpAcrossTwoBeatReg <- mkReg(False);

    Bool txValid = pcieTxPipeInQueue.notEmpty && txReadySignalWire;


   
    rule guard;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor guard"),
        //     ", txReadySignalWire=", fshow(txReadySignalWire),
        //     ", txTlpAcrossTwoBeatReg=", fshow(txTlpAcrossTwoBeatReg),
        //     ", pcieTxPipeInQueue.notEmpty=", fshow(pcieTxPipeInQueue.notEmpty),
        //     ", pcieTxPipeInQueue.notFull=", fshow(pcieTxPipeInQueue.notFull)
        // );

        if (txReadySignalWire) begin
            immAssert(
                !(txTlpAcrossTwoBeatReg && !pcieTxPipeInQueue.notEmpty),
                "Can't stop between sop and eop",
                $format("")
            );
        end

        // if (pcieTxPipeInQueue.notEmpty) begin
        //     $display(
        //         "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor guard"),
        //         ", pcieTxPipeInQueue.first=", fshow(pcieTxPipeInQueue.first)
        //     );
        // end


    endrule

    rule deq;
        if (txValid && pcieTxPipeInQueue.notEmpty) begin
            pcieTxPipeInQueue.deq;

            // use for assertion
            case ({pcieTxPipeInQueue.first.sop, pcieTxPipeInQueue.first.eop}) matches
                8'b0000_0000: begin
                    // nothing to do, not start, not end.
                end
                8'b1???_0???: begin
                    txTlpAcrossTwoBeatReg <= True;
                end
                8'b01??_00??: begin
                    txTlpAcrossTwoBeatReg <= True;
                end
                8'b001?_000?: begin
                    txTlpAcrossTwoBeatReg <= True;
                end
                8'b0001_0000: begin
                    txTlpAcrossTwoBeatReg <= True;
                end
                default: begin
                    txTlpAcrossTwoBeatReg <= False;
                end
            endcase

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor deq"),
            //     ", pcieTxPipeInQueue.first=", fshow(pcieTxPipeInQueue.first)
            // );
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor deq1"),
        //     ", txValid=", fshow(txValid),
        //     ", pcieTxPipeInQueue.notEmpty=", fshow(pcieTxPipeInQueue.notEmpty),
        //     ", txReadySignalWire=", fshow(txReadySignalWire)
        // );
    endrule

    rule handleRxFlowControlCreditRelease;
        let {phToRelease, nphToRelease, cplhToRelease, pdToRelease, npdToRelease, cpldToRelease} = rxFlowControlReleaseReqPipeInQueue.first;
        rxFlowControlReleaseReqPipeInQueue.deq;
        rxCreditPH.releaseCredit(phToRelease);
        rxCreditNPH.releaseCredit(nphToRelease);
        rxCreditCPLH.releaseCredit(cplhToRelease);
        rxCreditPD.releaseCredit(pdToRelease);
        rxCreditNPD.releaseCredit(npdToRelease);
        rxCreditCPLD.releaseCredit(cpldToRelease);
    endrule

    rule outputNewestCreditAvailable;
        let outputCredit = tuple6(txCreditPH.curAvailableCredit, txCreditNPH.curAvailableCredit, txCreditCPLH.curAvailableCredit, txCreditPD.curAvailableCredit, txCreditNPD.curAvailableCredit, txCreditCPLD.curAvailableCredit);
        txFlowControlAvaliablePipeOutQueue.enq(outputCredit);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor outputNewestCreditAvailable"),
        //     ", outputCredit=", fshow(outputCredit),
        //     ", txFlowControlAvaliablePipeOutQueue.notFull=", fshow(txFlowControlAvaliablePipeOutQueue.notFull),
        //     ", txFlowControlAvaliablePipeOutQueue.notEmpty=", fshow(txFlowControlAvaliablePipeOutQueue.notEmpty)
        // );
    endrule

    rule handleTxFlowControlCreditConsume;
        let {phToConsume, nphToConsume, cplhToConsume, pdToConsume, npdToConsume, cpldToConsume} = txFlowControlConsumeReqPipeInQueue.first;
        txFlowControlConsumeReqPipeInQueue.deq;

        let r1 <- txCreditPH.consumeCredit(phToConsume);
        let r2 <- txCreditNPH.consumeCredit(nphToConsume);
        let r3 <- txCreditCPLH.consumeCredit(cplhToConsume);
        let r4 <- txCreditPD.consumeCredit(pdToConsume);
        let r5 <- txCreditNPD.consumeCredit(npdToConsume);
        let r6 <- txCreditCPLD.consumeCredit(cpldToConsume);

        immAssert(
            r1 && r2 && r3 && r4 && r5 && r6,
            "no enough credit",
            $format(
                "txFlowControlConsumeReqPipeInQueue.first=", fshow(txFlowControlConsumeReqPipeInQueue.first),
                ", txCreditPH=", fshow(txCreditPH.curAvailableCredit),
                ", txCreditNPH=", fshow(txCreditNPH.curAvailableCredit),
                ", txCreditCPLH=", fshow(txCreditCPLH.curAvailableCredit),
                ", txCreditPD=", fshow(txCreditPD.curAvailableCredit),
                ", txCreditNPD=", fshow(txCreditNPD.curAvailableCredit),
                ", txCreditCPLD=", fshow(txCreditCPLD.curAvailableCredit)
            )
        );
    endrule


    interface RTilePcieAdaptorRx rx;
        // input port
        method Action setRxInputData(
            PcieTlpDataBusSegBundle         data,
            PcieTlpHeaderBusSegBundle       hdr,
            SopSignalBundle                 sop,
            EopSignalBundle                 eop,
            HvalidSignalBundle              hvalid,
            DvalidSignalBundle              dvalid,
            BarIdSignalBundle               bar,
            SegmentEmptySignalBundle        empty,
            HeaderCreditInitAckSignalBundle hcrdt_init_ack,
            DataCreditInitAckSignalBundle   dcrdt_init_ack
        );
            rxCreditPH.setInitAckSignal(hcrdt_init_ack.ph);
            rxCreditNPH.setInitAckSignal(hcrdt_init_ack.nph);
            rxCreditCPLH.setInitAckSignal(hcrdt_init_ack.cplh);
            rxCreditPD.setInitAckSignal(dcrdt_init_ack.ph);
            rxCreditNPD.setInitAckSignal(dcrdt_init_ack.nph);
            rxCreditCPLD.setInitAckSignal(dcrdt_init_ack.cplh);

            if ( (hvalid != 0) || (dvalid != 0) ) begin
                let beat = PcieRxBeat {
                    data: data, 
                    header: hdr,
                    sop: sop,
                    eop: eop,
                    hvalid: hvalid,
                    dvalid: dvalid,
                    bar: bar,
                    empty: empty
                };

                immAssert(
                    pcieRxPipeOutQueue.notFull,
                    "pcieRxPipeOutQueue is Full",
                    $format("")
                );

                pcieRxPipeOutQueue.enq(beat);

                if (beat.dvalid != 4'b1111) begin
                    $display(
                        "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor setRxInputData Non-full beat detected"),
                        ", beat=", fshow(beat)
                    );
                end
            end
            else begin
                // $display(
                //     "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor setRxInputData no hand-shake beat detected")
                // );
            end
        endmethod

        // output port
        method Bool                                 ready               = True;   // according to ug20316 Table 56
        method HeaderCreditInitSignalBundle         hcrdt_init          = unpack({pack(rxCreditCPLH.initSignal), pack(rxCreditNPH.initSignal), pack(rxCreditPH.initSignal)});
        method HeaderCreditUpdateSignalBundle       hcrdt_update        = unpack({pack(rxCreditCPLH.updateSignal), pack(rxCreditNPH.updateSignal), pack(rxCreditPH.updateSignal)});
        method HeaderCreditUpdateCntSignalBundle    hcrdt_update_cnt    = unpack({pack(rxCreditCPLH.updateCntSignal), pack(rxCreditNPH.updateCntSignal), pack(rxCreditPH.updateCntSignal)});

        method DataCreditInitSignalBundle           dcrdt_init          = unpack({pack(rxCreditCPLD.initSignal), pack(rxCreditNPD.initSignal), pack(rxCreditPD.initSignal)});
        method DataCreditUpdateSignalBundle         dcrdt_update        = unpack({pack(rxCreditCPLD.updateSignal), pack(rxCreditNPD.updateSignal), pack(rxCreditPD.updateSignal)});
        method DataCreditUpdateCntSignalBundle      dcrdt_update_cnt    = unpack({pack(rxCreditCPLD.updateCntSignal), pack(rxCreditNPD.updateCntSignal), pack(rxCreditPD.updateCntSignal)});
    endinterface

    interface RTilePcieAdaptorTx tx;
        // input port
        method Action setTxInputData(
            HeaderCreditInitSignalBundle        hcrdt_init,
            HeaderCreditUpdateSignalBundle      hcrdt_update,
            HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt,
            DataCreditInitSignalBundle          dcrdt_init,
            DataCreditUpdateSignalBundle        dcrdt_update,
            DataCreditUpdateCntSignalBundle     dcrdt_update_cnt,
            Bool                                ready
        );
            txCreditPH.setInputSignal(hcrdt_init.ph, hcrdt_update.ph, hcrdt_update_cnt.ph);
            txCreditNPH.setInputSignal(hcrdt_init.nph, hcrdt_update.nph, hcrdt_update_cnt.nph);
            txCreditCPLH.setInputSignal(hcrdt_init.cplh, hcrdt_update.cplh, hcrdt_update_cnt.cplh);
        
            txCreditPD.setInputSignal(dcrdt_init.pd, dcrdt_update.pd, dcrdt_update_cnt.pd);
            txCreditNPD.setInputSignal(dcrdt_init.npd, dcrdt_update.npd, dcrdt_update_cnt.npd);
            txCreditCPLD.setInputSignal(dcrdt_init.cpld, dcrdt_update.cpld, dcrdt_update_cnt.cpld);

            txReadySignalWire <= ready;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRTilePcieAdaptor setTxInputData "),
            //     ", IP core ready=", fshow(ready)
            // );
        endmethod

        // output port
        method HeaderCreditInitAckSignalBundle      hcrdt_init_ack = unpack({pack(txCreditCPLH.initAckSignal), pack(txCreditNPH.initAckSignal), pack(txCreditPH.initAckSignal)});
        method DataCreditInitAckSignalBundle        dcrdt_init_ack = unpack({pack(txCreditCPLD.initAckSignal), pack(txCreditNPD.initAckSignal), pack(txCreditPD.initAckSignal)});
        
        method PcieTlpHeaderBusSegBundle    hdr = txValid ? pcieTxPipeInQueue.first.header : unpack(0);
        method PcieTlpDataBusSegBundle      data = txValid ? pcieTxPipeInQueue.first.data : unpack(0);

        method SopSignalBundle              sop = txValid ? pcieTxPipeInQueue.first.sop : unpack(0);
        method EopSignalBundle              eop = txValid ? pcieTxPipeInQueue.first.eop : unpack(0);
        method HvalidSignalBundle           hvalid = txValid ? pcieTxPipeInQueue.first.hvalid : unpack(0);
        method DvalidSignalBundle           dvalid = txValid ? pcieTxPipeInQueue.first.dvalid : unpack(0);
    endinterface

    interface pcieRxPipeOut = ugToPipeOut(pcieRxPipeOutQueue);
    interface pcieTxPipeIn = ugToPipeIn(pcieTxPipeInQueue);
    interface rxFlowControlReleaseReqPipeIn = toPipeInB0(rxFlowControlReleaseReqPipeInQueue);
    interface txFlowControlConsumeReqPipeIn = toPipeInB0(txFlowControlConsumeReqPipeInQueue);
    interface txFlowControlAvaliablePipeOut = toPipeOut(txFlowControlAvaliablePipeOutQueue);
endmodule


interface PcieCreditCounterSink#(type tCounter, type tDelta);
    (* always_ready, always_enabled *) method Bool     initSignal;
    (* always_ready, always_enabled *) method Action   setInitAckSignal(Bool signal);
    (* always_ready, always_enabled *) method Bool     updateSignal;
    (* always_ready, always_enabled *) method tDelta   updateCntSignal;

    method Action releaseCredit(tCounter delta);
endinterface

typedef enum {
    PcieCreditCounterSinkStateWaitingAck = 0,
    PcieCreditCounterSinkStateTransferInitValue = 1,
    PcieCreditCounterSinkStateDelayInitRelease1 = 2,
    PcieCreditCounterSinkStateDelayInitRelease2 = 3,
    PcieCreditCounterSinkStateNormalOperation = 4
} PcieCreditCounterSinkState deriving(Bits, Eq, FShow);

module mkPcieCreditCounterSink#(tCounter initValue)(PcieCreditCounterSink#(tCounter, tDelta)) provisos(
        Bits#(tCounter, szCounter),
        Bits#(tDelta, szDelta),
        Bounded#(tDelta),
        Arith#(tCounter),
        ModArith#(tCounter),
        Add#(a__, szDelta, szCounter),
        Eq#(tCounter),
        FShow#(tDelta)
    );

    Reg#(PcieCreditCounterSinkState) stateReg <- mkReg(PcieCreditCounterSinkStateWaitingAck);

    Reg#(Bool) initSignalReg <- mkReg(False);
    Reg#(Bool) updateSignalReg <- mkReg(False);
    Reg#(tDelta) updateCntSignalReg <- mkReg(unpack(0));


    Wire#(Bool) initAckSignalWire <- mkBypassWire;
    Count#(tCounter) initCounter <- mkCount(initValue);
    Count#(tCounter) updateCounter <- mkCount(unpack(0));


    tDelta maxDelta = maxBound;
    rule waitingAck if (stateReg == PcieCreditCounterSinkStateWaitingAck);
        initSignalReg <= True;
        if (initAckSignalWire) begin
            stateReg <= PcieCreditCounterSinkStateTransferInitValue;
            tDelta delta = unpack(pack(initCounter) > zeroExtend(pack(maxDelta)) ? pack(maxDelta) : truncate(pack(initCounter)));

            updateSignalReg <= True;
            updateCntSignalReg <= delta;
            initCounter.decr(unpack(zeroExtend(pack(delta))));
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCreditCounterSink waitingAck"),
        //     ", initAckSignalWire=", fshow(initAckSignalWire)
        // );
    endrule

    rule transferInitValue if (stateReg == PcieCreditCounterSinkStateTransferInitValue);
        if (initCounter == 0) begin
            updateSignalReg <= False;
            stateReg <= PcieCreditCounterSinkStateDelayInitRelease1;
        end
        else begin
            tDelta delta = unpack(pack(initCounter) > zeroExtend(pack(maxDelta)) ? pack(maxDelta) : truncate(pack(initCounter)));
            updateCntSignalReg <= delta;
            initCounter.decr(unpack(zeroExtend(pack(delta))));
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCreditCounterSink transferInitValue")
        // );
    endrule

    rule delayInitRelease1 if (stateReg == PcieCreditCounterSinkStateDelayInitRelease1);
        stateReg <= PcieCreditCounterSinkStateDelayInitRelease2;
    endrule

    rule delayInitRelease2 if (stateReg == PcieCreditCounterSinkStateDelayInitRelease2);
        initSignalReg <= False;
        stateReg <= PcieCreditCounterSinkStateNormalOperation;
    endrule

    rule normalOperation if (stateReg == PcieCreditCounterSinkStateNormalOperation);
        if (updateCounter == 0) begin
            updateSignalReg <= False;
        end
        else begin
            updateSignalReg <= True;
            tDelta delta = unpack(pack(updateCounter) > zeroExtend(pack(maxDelta)) ? pack(maxDelta) : truncate(pack(updateCounter)));
            updateCntSignalReg <= delta;
            updateCounter.decr(unpack(zeroExtend(pack(delta))));
            // $display(
            //     "time=%0t:", $time, toGreen(" mkPcieCreditCounterSink normalOperation"),
            //     ", delta=", fshow(delta)
            // );
        end
    endrule

    method setInitAckSignal = initAckSignalWire._write;
    method Bool     initSignal = initSignalReg;
    method Bool     updateSignal = updateSignalReg;
    method tDelta   updateCntSignal = updateCntSignalReg;

    method Action releaseCredit(tCounter delta);
        updateCounter.incr(delta);
    endmethod
endmodule



interface PcieCreditCounterSource#(type tCounter, type tDelta);

    (* always_ready, always_enabled *) method Bool     initAckSignal;
    (* always_ready, always_enabled *) method Action   setInputSignal(Bool initSignal, Bool updateSignal, tDelta updateCntSignal);

    method ActionValue#(Bool)   consumeCredit(tCounter delta);
    method tCounter             curAvailableCredit;
endinterface

typedef enum {
    PcieCreditCounterSourceStateWaitingInit = 0,
    PcieCreditCounterSourceStateSendAck = 1,
    PcieCreditCounterSourceStateRecvInitValue = 2,
    PcieCreditCounterSourceStateNormalOperation = 3
} PcieCreditCounterSourceState deriving(Bits, Eq, FShow);

module mkPcieCreditCounterSource(PcieCreditCounterSource#(tCounter, tDelta)) provisos(
        Bits#(tCounter, szCounter),
        Bits#(tDelta, szDelta),
        Bounded#(tDelta),
        Bounded#(tCounter),
        Arith#(tCounter),
        ModArith#(tCounter),
        Add#(a__, szDelta, szCounter),
        Eq#(tCounter),
        Eq#(tDelta),
        Ord#(tCounter),
        FShow#(tDelta),
        FShow#(tCounter)
    );
    Reg#(PcieCreditCounterSourceState) stateReg <- mkReg(PcieCreditCounterSourceStateWaitingInit);

    Reg#(Bool) initAckSignalReg <- mkReg(False);
    Reg#(Bool) isFirstInitBeatReg <- mkReg(True);
    Reg#(Bool) isInfiniteCreditReg <- mkReg(False);

    Wire#(Bool) initSignalWire <- mkBypassWire;
    Wire#(Bool) updateSignalWire <- mkBypassWire;
    Wire#(tDelta) updateCntSignalWire <- mkBypassWire;

    Count#(tCounter) counter <- mkCount(unpack(0));

    rule waitingInit if (stateReg == PcieCreditCounterSourceStateWaitingInit);
        if (initSignalWire) begin
            stateReg <= PcieCreditCounterSourceStateSendAck;
        end
        $display(
            "time=%0t:", $time, toGreen(" mkPcieCreditCounterSource waitingInit")
        );
    endrule

    rule sendAck if (stateReg == PcieCreditCounterSourceStateSendAck);
        initAckSignalReg <= True;
        stateReg <= PcieCreditCounterSourceStateRecvInitValue;
        $display(
            "time=%0t:", $time, toGreen(" mkPcieCreditCounterSource sendAck")
        );
    endrule

    rule recvInitValue if (stateReg == PcieCreditCounterSourceStateRecvInitValue);
        initAckSignalReg <= False;
        if (!initSignalWire) begin
            stateReg <= PcieCreditCounterSourceStateNormalOperation;
        end
        else begin
            if (updateSignalWire) begin
                isFirstInitBeatReg <= False;
                if (isFirstInitBeatReg && updateCntSignalWire == unpack(0)) begin
                    isInfiniteCreditReg <= True;
                    counter <= maxBound;
                end
                else begin
                    counter.incr(unpack(zeroExtend(pack(updateCntSignalWire))));
                end
            end
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCreditCounterSource recvInitValue"),
        //     ", updateSignalWire=", fshow(updateSignalWire),
        //     ", updateCntSignalWire=", fshow(updateCntSignalWire)
        // );
    endrule

    rule normalOperation if (stateReg == PcieCreditCounterSourceStateNormalOperation);   
        if (updateSignalWire) begin
            counter.incr(unpack(zeroExtend(pack(updateCntSignalWire))));
        end 
    endrule

    method Action setInputSignal(Bool initSignal, Bool updateSignal, tDelta updateCntSignal);
        initSignalWire <= initSignal;
        updateSignalWire <= updateSignal;
        updateCntSignalWire <= updateCntSignal;
    endmethod

    method initAckSignal = initAckSignalReg;

    method ActionValue#(Bool) consumeCredit(tCounter delta);
        if (isInfiniteCreditReg || delta <= counter) begin
            if (!isInfiniteCreditReg) begin
                counter.decr(unpack(zeroExtend(pack(delta))));
            end
            return True;
        end
        else begin
            return False;
        end
    endmethod

    method curAvailableCredit = counter;
endmodule


typedef 3 PCIE_MAX_TLP_CNT;
typedef TLog#(PCIE_MAX_TLP_CNT) PCIE_RX_HANDLER_IDX_WIDTH;
typedef Bit#(PCIE_RX_HANDLER_IDX_WIDTH) PcieRxHandlerIdx;


typedef DtldStreamData#(DATA) RtilePcieUserStream;


typedef struct {
    PcieRxBeat rxBeat;
    PcieSegmentIdx startSegIdx;
} RawPcieRxStreamWithMeta deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderBuffer rawTlpHeader;
    PcieSegmentIdx startSegIdx;
} RawPcieRxTlpWithMeta deriving(Bits, FShow);

typedef Bit#(PCIE_TLP_DATA_BUNDLE_WIDTH) PcieDataStreamDataLsbRight;
typedef Bit#(PCIE_TLP_DATA_BUNDLE_WIDTH) PcieDataStreamDataLsbLeft;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, BYTE_WIDTH) PCIE_TLP_DATA_BUNDLE_BYTE_CNT;
typedef Bit#(TAdd#(1, TLog#(PCIE_TLP_DATA_BUNDLE_BYTE_CNT))) PcieDataStreamByteCnt;
typedef Bit#(TLog#(TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, BYTE_WIDTH))) PcieDataStreamByteIdx;

typedef DtldStreamData#(PcieDataStreamDataLsbRight) PcieDataStreamLsbRight;
typedef DtldStreamData#(PcieDataStreamDataLsbLeft) PcieDataStreamLsbLeft;

typedef 2048 RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_CNT;    // TODO: maybe can change to 1024
typedef TLog#(RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_CNT)  RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_INDEX_WIDTH;
typedef TAdd#(1, RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_INDEX_WIDTH)  RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_COUNT_WIDTH;

typedef Bit#(RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_INDEX_WIDTH) RtilePcieRxPayloadStorageRowIdx;
typedef Bit#(RTILE_PCIE_RX_PAYLOAD_STORAGE_ROW_COUNT_WIDTH) RtilePcieRxPayloadStorageRowCnt;
typedef RtilePcieRxPayloadStorageRowIdx RtilePcieRxPayloadStorageAddr;

typedef 4 RTILE_PCIE_USER_LOGIC_CHANNEL_CNT;
typedef Bit#(TLog#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT)) RtilePcieUserChannelIdx;

typedef 3 RTILE_PCIE_BYTE_CNT_IN_DW_WIDTH;
typedef Bit#(RTILE_PCIE_BYTE_CNT_IN_DW_WIDTH) RtilePcieByteCntInDw;

typedef struct {
    RtilePcieRxPayloadStorageAddr   addr;
    PcieTlpDataBusSegBundle         dataBundles;
} RtilePcieRxPayloadStorageWriteReq deriving(Bits, FShow);

typedef struct {
    ADDR                            addr;                       // 64
    PcieHeaderFieldExtendedTag      tag;                        // 10
    PcieHeaderFieldRequesterId      requesterId;                // 16
} RtilePcieRxTlpInfoMrRead deriving(Bits, FShow);

typedef struct {
    ADDR                            addr;                       // 64
    RtilePcieRxPayloadStorageAddr   firstBeatStorageAddr;       // 12
    PcieSegmentIdx                  firstBeatSegIdx;            // 2
    CreditCount                     pcieFcCreditPd;             // 12
} RtilePcieRxTlpInfoMrWrite deriving(Bits, FShow);

typedef struct {
    RtilePcieRxPayloadStorageAddr   firstBeatStorageAddr;       // 12
    PcieSegmentIdx                  firstBeatSegIdx;            // 2
    RtilePcieByteCntInDw            firstBeCnt;                 // 3
    PcieTlpDataByteCnt              byteCountInThisTlp;         // 13
    PcieHeaderFieldExtendedTag      tag;                        // 10
    Bool                            isLastCplt;                 // 1
    CreditCount                     pcieFcCreditCpltd;          // 12
} RtilePcieRxTlpInfoCplt deriving(Bits, FShow);

typedef union tagged {
    RtilePcieRxTlpInfoMrRead    TlpTypeMrRead;
    RtilePcieRxTlpInfoMrWrite   TlpTypeMrWrite;
    RtilePcieRxTlpInfoCplt      TlpTypeCplt;
    void                        TlpTypeInvalid;
} RtilePcieRxTlpInfo deriving(Bits, FShow);

function Bool isRtilePcieRxTlpInfoValid(RtilePcieRxTlpInfo element);
    return element matches TlpTypeInvalid ? False : True;
endfunction

interface PcieRxStreamSegmentFork;
    interface PipeIn#(PcieRxBeat) pcieRxPipeIn;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutVec;
    interface PipeOut#(RtilePcieRxPayloadStorageWriteReq) tlpRawBeatDataStorageWriteReqForCompleterPipeOut;
    interface PipeOut#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) memReadWriteReqTlpVecPipeOut;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpVecPipeOutVec;
    interface PipeOut#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    rxFlowControlReleaseReqPipeOut;
endinterface

(* synthesize *)
module mkPcieRxStreamSegmentFork(PcieRxStreamSegmentFork);
    FIFOF#(PcieRxBeat) pcieRxPipeInQueue <- mkLFIFOF;

    // The completer path is not fully-pipelined, it handles TLPs one by one if multi TLPs in the same beat. so we give it more space. 
    FIFOF#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) memReadWriteReqTlpVecPipeOutQueue <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_FOUR));

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutQueueVec <- replicateM(mkFIFOF);
    // TODO: Fixme: if multi segment has the same cplt channel idx, then it will take the mkPcieCompletionBuffer more than one beat to handle them. it will block the pipeline if there is not
    // a big enough buffer. but, what is big enough? Now, each channel can hold (1024 - 256) / 4 in-flight read request, so we use 256 here.
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpPipeOutQueueVec <- replicateM(mkSizedFIFOF(256));

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieRxPayloadStorageWriteReq)) tlpRawBeatDataStorageWriteReqPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) cpltTlpVecPipeOutVecInst = newVector;

    FIFOF#(RtilePcieRxPayloadStorageWriteReq) tlpRawBeatDataStorageWriteReqForCompleterPipeOutQueue <- mkFIFOF;

    FIFOF#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    rxFlowControlReleaseReqPipeOutQueue <- mkFIFOF;

    for (Integer handlerIdx = 0; handlerIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); handlerIdx = handlerIdx + 1) begin
        tlpRawBeatDataStorageWriteReqPipeOutVecInst[handlerIdx] = toPipeOut(tlpRawBeatDataStorageWriteReqPipeOutQueueVec[handlerIdx]);
        cpltTlpVecPipeOutVecInst[handlerIdx] = toPipeOut(cpltTlpPipeOutQueueVec[handlerIdx]);
    end

    Reg#(RtilePcieRxPayloadStorageAddr) storageWriteAddrReg <- mkReg(0);

    // Pipeline FIFOs
    FIFOF#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) dispatchTlpInfoPipelineQueue <- mkLFIFOF;


    // rule debug;
    //     if (!memReadWriteReqTlpVecPipeOutQueue.notFull) $display("time=%0t:", $time, toGreen(" mkPcieRxStreamSegmentFork debug FULL QUEUE memReadWriteReqTlpVecPipeOutQueue"));
    // endrule

    rule calcRxBeatMetaAndForkPayloadStorageAndReleasePcieRxFlowCredit;
        // A trick here. we assume that the whole system is fully-pipelined, there will be no back preasure.
        // so, when we receive a TLP, we can immediately tell the PCIe IP core that we have consumed the TLP header
        // and its payload (although we maybe even doesn't see the EOP of this TLP, but we are sure we can hold this TLP,
        // since we have enough storage for CPLT TLP and we assume that the BAR access is seldom, we won't block)
        
        let beat = pcieRxPipeInQueue.first;
        pcieRxPipeInQueue.deq;

        // Calc meta data begin ============================================

        for (Integer idx = 0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            tlpRawBeatDataStorageWriteReqPipeOutQueueVec[idx].enq(RtilePcieRxPayloadStorageWriteReq {
                addr: storageWriteAddrReg,
                dataBundles: beat.data
            });
        end
        tlpRawBeatDataStorageWriteReqForCompleterPipeOutQueue.enq(RtilePcieRxPayloadStorageWriteReq {
            addr: storageWriteAddrReg,
            dataBundles: beat.data
        });
        storageWriteAddrReg <= storageWriteAddrReg + 1;


        Bool isSopFlagLegal = case (pack(beat.sop))
            'b0100, 'b1000, 'b1100: begin
                if (beat.dvalid[1:0] == 2'b00) begin
                    False;
                end
                else begin
                    True;
                end
            end 
            'b1111: False;
            default: True;
        endcase;
        immAssert(
            isSopFlagLegal,
            "one of the following 2 assumption not hold: \n \
               1.The R-Tile PCIe IP does not use segment 2 and segment 3 if segment 0 AND segment 1 are unused \n\
               2.At most 3 TLPs in a beat\n",
            $format("beat=", fshow(beat))
        );


        Vector#(PCIE_MAX_TLP_CNT, Maybe#(PcieSegmentIdx)) tlpFirstSegmentIdxVec = case (pack(beat.sop)) matches
            'b0000: vec(tagged Invalid, tagged Invalid, tagged Invalid);
            'b0001: vec(tagged Valid 0, tagged Invalid, tagged Invalid);
            'b0010: vec(tagged Valid 1, tagged Invalid, tagged Invalid);
            'b0011: vec(tagged Valid 0, tagged Valid 1, tagged Invalid);
            'b0100: vec(tagged Valid 2, tagged Invalid, tagged Invalid);
            'b0101: vec(tagged Valid 0, tagged Valid 2, tagged Invalid);
            'b0110: vec(tagged Valid 1, tagged Valid 2, tagged Invalid);
            'b0111: vec(tagged Valid 0, tagged Valid 1, tagged Valid 2);
            'b1000: vec(tagged Valid 3, tagged Invalid, tagged Invalid);
            'b1001: vec(tagged Valid 0, tagged Valid 3, tagged Invalid);
            'b1010: vec(tagged Valid 1, tagged Valid 3, tagged Invalid);
            'b1011: vec(tagged Valid 0, tagged Valid 1, tagged Valid 3);
            'b1100: vec(tagged Valid 2, tagged Valid 3, tagged Invalid);
            'b1101: vec(tagged Valid 0, tagged Valid 2, tagged Valid 3);
            'b1110: vec(tagged Valid 1, tagged Valid 2, tagged Valid 3);
            'b1111: vec(tagged Invalid, tagged Invalid, tagged Invalid);
        endcase;
        
        Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo) simpleTlpInfoVec = newVector;
        for (Integer idx = 0; idx < valueOf(PCIE_MAX_TLP_CNT); idx = idx + 1) begin
            if (tlpFirstSegmentIdxVec[idx] matches tagged Valid .segIdx) begin

                // PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(beat.header[segIdx]));
                // $display(
                //     "time=%0t:", $time, toGreen(" mkPcieRxStreamSegmentFork calcRxBeatMetaAndForkPayloadStorage"),
                //     "segment_id=%d", idx, 
                //     ", tlpHeader=", fshow(tlpHeader)
                // );
                simpleTlpInfoVec[idx] = convertTlpToInternalDataType(beat.header[segIdx], storageWriteAddrReg, segIdx);
            end
            else begin
                simpleTlpInfoVec[idx] = tagged TlpTypeInvalid;
            end
        end

        dispatchTlpInfoPipelineQueue.enq(simpleTlpInfoVec);
        // Calc meta data end ============================================

        // Release pcie rx flow credit begin=====================

        Vector#(PCIE_SEGMENT_CNT, Bool) rxFlowControlCreditToRelasePh = replicate(False);
        Vector#(PCIE_SEGMENT_CNT, Bool) rxFlowControlCreditToRelaseNph = replicate(False);
        Vector#(PCIE_SEGMENT_CNT, Bool) rxFlowControlCreditToRelaseCplh = replicate(False);

        Vector#(PCIE_SEGMENT_CNT, CreditCount) rxFlowControlCreditToRelasePd = replicate(unpack(0));
        Vector#(PCIE_SEGMENT_CNT, CreditCount) rxFlowControlCreditToRelaseNpd = replicate(unpack(0));
        Vector#(PCIE_SEGMENT_CNT, CreditCount) rxFlowControlCreditToRelaseCpld = replicate(unpack(0));

        CreditCount phToRelease     = 0;
        CreditCount nphToRelease    = 0;
        CreditCount cplhToRelease   = 0;
        CreditCount pdToRelease     = 0;
        CreditCount npdToRelease    = 0;
        CreditCount cpldToRelease   = 0;


        for (Integer segIdx = 0; segIdx < valueOf(PCIE_SEGMENT_CNT); segIdx = segIdx + 1) begin
            if (beat.sop[segIdx] == 1'b1) begin
                // we have an tlp here
                let {isPostTlp, isNonPostedTlp, isCpltTlp, pdCredit, npdCredit, cpldCredit} = getFlowControlCreditFromRxTlp(beat.header[segIdx]);
                rxFlowControlCreditToRelasePh[segIdx] = isPostTlp;
                rxFlowControlCreditToRelaseNph[segIdx] = isNonPostedTlp;
                rxFlowControlCreditToRelaseCplh[segIdx] = isCpltTlp;
                rxFlowControlCreditToRelasePd[segIdx] = pdCredit;
                rxFlowControlCreditToRelaseNpd[segIdx] = npdCredit;
                rxFlowControlCreditToRelaseCpld[segIdx] = cpldCredit;
            end
        end

        for (Integer segIdx = 0; segIdx < valueOf(PCIE_SEGMENT_CNT); segIdx = segIdx + 1) begin
            phToRelease = phToRelease + zeroExtend(pack(rxFlowControlCreditToRelasePh[segIdx]));
            nphToRelease = nphToRelease + zeroExtend(pack(rxFlowControlCreditToRelaseNph[segIdx]));
            cplhToRelease = cplhToRelease + zeroExtend(pack(rxFlowControlCreditToRelaseCplh[segIdx]));
            pdToRelease = pdToRelease + rxFlowControlCreditToRelasePd[segIdx];
            npdToRelease = npdToRelease + rxFlowControlCreditToRelaseNpd[segIdx];
            cpldToRelease = cpldToRelease + rxFlowControlCreditToRelaseCpld[segIdx];
        end

        rxFlowControlReleaseReqPipeOutQueue.enq(tuple6(phToRelease, nphToRelease, cplhToRelease, pdToRelease, npdToRelease, cpldToRelease));


        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieRxStreamSegmentFork calcRxBeatMetaAndForkPayloadStorage"),
        //     ", simpleTlpInfoVec=", fshow(simpleTlpInfoVec)
        // );

    endrule

    rule dispatchTlpHeader;
        let simpleTlpInfoVec = dispatchTlpInfoPipelineQueue.first;
        dispatchTlpInfoPipelineQueue.deq;

        Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo) memRdWrTlpInfoVec = replicate(tagged TlpTypeInvalid);
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt))) cpltTlpInfoVec = replicate(replicate(tagged Invalid));

        Bool memRdWrHasTlp = False;
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool) channelHasClptTlpVec = replicate(False);

        for (Integer tlpIdx = 0; tlpIdx < valueOf(PCIE_MAX_TLP_CNT); tlpIdx = tlpIdx + 1) begin
            case (simpleTlpInfoVec[tlpIdx]) matches
                tagged TlpTypeMrRead .tlp: begin
                    memRdWrTlpInfoVec[tlpIdx] = simpleTlpInfoVec[tlpIdx];
                    memRdWrHasTlp = True;
                end
                tagged TlpTypeMrWrite .tlp: begin
                    memRdWrTlpInfoVec[tlpIdx] = simpleTlpInfoVec[tlpIdx];
                    memRdWrHasTlp = True;
                end
                tagged TlpTypeCplt .tlp: begin
                    DispatchChannelIdx dispatchIdx = truncate(tlp.tag);
                    cpltTlpInfoVec[dispatchIdx][tlpIdx] = tagged Valid tlp;
                    channelHasClptTlpVec[dispatchIdx] = True;
                end
                default: begin
                    // Nothing to do
                end
            endcase
        end

        for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
            case ({pack(isValid(cpltTlpInfoVec[channelIdx][2])), pack(isValid(cpltTlpInfoVec[channelIdx][1])), pack(isValid(cpltTlpInfoVec[channelIdx][0]))})
                'b010: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][1], tagged Invalid, tagged Invalid);
                end
                'b100: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][2], tagged Invalid, tagged Invalid);
                end
                'b101: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][0], cpltTlpInfoVec[channelIdx][2], tagged Invalid);
                end
                'b110: begin
                    cpltTlpInfoVec[channelIdx] = vec(cpltTlpInfoVec[channelIdx][1], cpltTlpInfoVec[channelIdx][2], tagged Invalid);
                end
                default: begin
                    // Nothing to do, since no order need to change.
                end
            endcase
        end


        case ({memRdWrTlpInfoVec[2] matches TlpTypeInvalid ? 1'b0 : 1'b1, memRdWrTlpInfoVec[1] matches TlpTypeInvalid ? 1'b0 : 1'b1, memRdWrTlpInfoVec[0] matches TlpTypeInvalid ? 1'b0 : 1'b1})
            'b010: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[1], tagged TlpTypeInvalid, tagged TlpTypeInvalid);
            end
            'b100: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[2], tagged TlpTypeInvalid, tagged TlpTypeInvalid);
            end
            'b101: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[0], memRdWrTlpInfoVec[2], tagged TlpTypeInvalid);
            end
            'b110: begin
                memRdWrTlpInfoVec = vec(memRdWrTlpInfoVec[1], memRdWrTlpInfoVec[2], tagged TlpTypeInvalid);
            end
            default: begin
                // Nothing to do, since no order need to change.
            end
        endcase


        for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
            if (channelHasClptTlpVec[channelIdx]) begin
                cpltTlpPipeOutQueueVec[channelIdx].enq(cpltTlpInfoVec[channelIdx]);
                // $display(
                //     "time=%0t:", $time, toGreen(" mkPcieRxStreamSegmentFork dispatchTlpHeader enqueue cpltTlpPipeOutQueueVec"),
                //     ", channelIdx=%d", channelIdx,
                //     ", cpltTlpInfoVec[channelIdx]=", fshow(cpltTlpInfoVec[channelIdx])
                // );
            end
        end

        if (memRdWrHasTlp) begin
            memReadWriteReqTlpVecPipeOutQueue.enq(memRdWrTlpInfoVec);
        end

    endrule
    

    interface pcieRxPipeIn = toPipeIn(pcieRxPipeInQueue);
    interface tlpRawBeatDataStorageWriteReqPipeOutVec = tlpRawBeatDataStorageWriteReqPipeOutVecInst;
    interface tlpRawBeatDataStorageWriteReqForCompleterPipeOut = toPipeOut(tlpRawBeatDataStorageWriteReqForCompleterPipeOutQueue);
    interface cpltTlpVecPipeOutVec = cpltTlpVecPipeOutVecInst;
    interface memReadWriteReqTlpVecPipeOut = toPipeOut(memReadWriteReqTlpVecPipeOutQueue);
    interface rxFlowControlReleaseReqPipeOut = toPipeOut(rxFlowControlReleaseReqPipeOutQueue);
endmodule


function RtilePcieRxTlpInfo convertTlpToInternalDataType(PcieTlpHeaderBuffer tlpBuffer, RtilePcieRxPayloadStorageAddr storageAddr, PcieSegmentIdx firstSegIdx);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    case ({pack(headerFirstDW.fmt), pack(headerFirstDW.typ)})
        {`PCIE_TLP_HEADER_FMT_3DW_NO_DATA, `PCIE_TLP_HEADER_TYPE_MEM_READ}: begin
            PcieTlpHeaderMemoryRead3Dw tlpHeader = unpack(truncateLSB(tlpBuffer));
            return tagged TlpTypeMrRead RtilePcieRxTlpInfoMrRead {
                addr        : unpack(zeroExtend({tlpHeader.addr, 2'b00})),                       
                tag         : unpack(truncate({
                                    pack(tlpHeader.memoryReadHeader.commonHeader.t9), 
                                    pack(tlpHeader.memoryReadHeader.commonHeader.t8), 
                                    pack(tlpHeader.memoryReadHeader.tag)})),                       
                requesterId : unpack(pack(tlpHeader.memoryReadHeader.requesterId))               
            };
        end
        {`PCIE_TLP_HEADER_FMT_3DW_WITH_DATA, `PCIE_TLP_HEADER_TYPE_MEM_WRITE}: begin
            PcieTlpHeaderMemoryWrite3Dw tlpHeader = unpack(truncateLSB(tlpBuffer));
            return tagged TlpTypeMrWrite RtilePcieRxTlpInfoMrWrite {
                addr                : unpack(zeroExtend({tlpHeader.addr, 2'b00})),                       
                firstBeatStorageAddr: storageAddr,
                firstBeatSegIdx     : firstSegIdx,
                pcieFcCreditPd      : (zeroExtend(tlpHeader.memoryWriteHeader.commonHeader.length) + fromInteger(valueOf(DWORD_CNT_PER_FLOW_CONTROL_CREDIT)-1)) >> valueOf(TLog#(DWORD_CNT_PER_FLOW_CONTROL_CREDIT))
            };
        end
        {`PCIE_TLP_HEADER_FMT_4DW_NO_DATA, `PCIE_TLP_HEADER_TYPE_MEM_READ}: begin
            PcieTlpHeaderMemoryRead4Dw tlpHeader = unpack(truncateLSB(tlpBuffer));
            return tagged TlpTypeMrRead RtilePcieRxTlpInfoMrRead {
                addr        : unpack({tlpHeader.addr, 2'b00}),                       
                tag         : unpack(truncate({
                                    pack(tlpHeader.memoryReadHeader.commonHeader.t9), 
                                    pack(tlpHeader.memoryReadHeader.commonHeader.t8), 
                                    pack(tlpHeader.memoryReadHeader.tag)})),                       
                requesterId : unpack(pack(tlpHeader.memoryReadHeader.requesterId))               
            };
        end
        {`PCIE_TLP_HEADER_FMT_4DW_WITH_DATA, `PCIE_TLP_HEADER_TYPE_MEM_WRITE}: begin
            PcieTlpHeaderMemoryWrite4Dw tlpHeader = unpack(truncateLSB(tlpBuffer));
            return tagged TlpTypeMrWrite RtilePcieRxTlpInfoMrWrite {
                addr                : unpack({tlpHeader.addr, 2'b00}),                       
                firstBeatStorageAddr: storageAddr,
                firstBeatSegIdx     : firstSegIdx,
                pcieFcCreditPd      : (zeroExtend(tlpHeader.memoryWriteHeader.commonHeader.length) + fromInteger(valueOf(DWORD_CNT_PER_FLOW_CONTROL_CREDIT)-1)) >> valueOf(TLog#(DWORD_CNT_PER_FLOW_CONTROL_CREDIT))       
            };
        end
        {`PCIE_TLP_HEADER_FMT_3DW_WITH_DATA, `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA}: begin
            let {byteCountInThisTlp, firstBeCnt, isLastCplt} = getDataLenFromTlpHeaderOfTypeCplt(tlpBuffer);
            let tag = getExtendedTagFromTlpCpltHeader(tlpBuffer);
            PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));
            return tagged TlpTypeCplt RtilePcieRxTlpInfoCplt{
                firstBeatStorageAddr: storageAddr,
                firstBeatSegIdx     : firstSegIdx,
                firstBeCnt          : firstBeCnt,
                byteCountInThisTlp  : byteCountInThisTlp,
                tag                 : tag,
                isLastCplt          : isLastCplt,
                pcieFcCreditCpltd   : (zeroExtend(tlpHeader.commonHeader.length) + fromInteger(valueOf(DWORD_CNT_PER_FLOW_CONTROL_CREDIT)-1)) >> valueOf(TLog#(DWORD_CNT_PER_FLOW_CONTROL_CREDIT))
            };
        end
        default: begin
            return tagged TlpTypeInvalid;
        end

    endcase
endfunction

function Tuple6#(Bool, Bool, Bool, CreditCount, CreditCount, CreditCount) getFlowControlCreditFromRxTlp(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    CreditCount dataCredit = (zeroExtend(headerFirstDW.length) + fromInteger(valueOf(DWORD_CNT_PER_FLOW_CONTROL_CREDIT)-1)) >> valueOf(TLog#(DWORD_CNT_PER_FLOW_CONTROL_CREDIT));
    Bool hasPayload = isPcieTlpHasPayload(tlpBuffer);

    Bool isMemWriteTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_MEM_REQ);
    Bool isMessageTlp  = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_NO_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA) && (headerFirstDW.typ matches `PCIE_TLP_HEADER_TYPE_MSG ? True : False);
    Bool isPostTlp  = isMemWriteTlp || isMessageTlp;

    Bool isMemReadTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_NO_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_NO_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_MEM_REQ || headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_MEM_LOCK_REQ);
    Bool isIoTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_NO_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_NO_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_IO);
    Bool isCgfTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_NO_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_NO_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CFG_TYPE_0 || headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CFG_TYPE_1);
    Bool isFetchAndAddAtomicTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_FETCH_ADD);
    Bool isSwapAtomicTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_IO_SWAP);
    Bool isCompareAndSwapAtomicTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_IO_CAS);    
    Bool isNonPostedTlp = isMemReadTlp || isIoTlp || isCgfTlp || isFetchAndAddAtomicTlp || isSwapAtomicTlp || isCompareAndSwapAtomicTlp;

    Bool isCpltNoLockTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_NO_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL);
    Bool isCpltWithLockTlp = (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_NO_DATA || headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL_LOCK);
    Bool isCpltTlp = isCpltNoLockTlp || isCpltWithLockTlp;

    let pdCredit = (hasPayload && isPostTlp) ? dataCredit : 0;
    let npdCredit = (hasPayload && isNonPostedTlp) ? dataCredit : 0;
    let cpldCredit = (hasPayload && isCpltTlp) ? dataCredit : 0;

    return tuple6(isPostTlp, isNonPostedTlp, isCpltTlp, pdCredit, npdCredit, cpldCredit);
endfunction



function Bool isPcieTlpHasPayload(PcieTlpHeaderBuffer tlpBuffer);
    PcieHeaderFieldFmt fmt = unpack(truncateLSB(tlpBuffer));
    return fmt == `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA || fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA;
endfunction

function PcieTlpHeaderCommon getPcieTlpHeaderCommon(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = unpack(truncateLSB(tlpBuffer));
    return headerFirstDW;
endfunction

function Bool isPcieTlpReadCplt(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    return (headerFirstDW.fmt == `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA) && (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA);
endfunction

function PcieHeaderFieldExtendedTag getExtendedTagFromTlpCpltHeader(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));
    return unpack(truncate({pack(tlpHeader.commonHeader.t9), pack(tlpHeader.commonHeader.t8), pack(tlpHeader.tag)}));
endfunction


function PcieTlpDataByteCnt getPayloadLengthInDW(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    PcieTlpDataByteCnt length = zeroExtend(headerFirstDW.length);
    length[valueOf(SizeOf#(PcieHeaderFieldLength))] = pack(headerFirstDW.length == 0);  // length == 0 means 4096 bytes
    return length;
endfunction

function Tuple2#(PcieTlpDataByteCnt, RtilePcieByteCntInDw) getDataLenFromTlpHeaderWithByteEn(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    PcieTlpDataByteCnt lengthInDw = getPayloadLengthInDW(tlpBuffer);
    PcieTlpDataByteCnt length = lengthInDw << 2; // convert from DW to Byte
    
    PcieTlpHeaderMemoryAccess tlpHeader = unpack(truncateLSB(tlpBuffer));
    RtilePcieByteCntInDw subValFirstBe = case (pack(tlpHeader.firstDwBe)) matches
        4'b???1: 0;
        4'b??10: 1;
        4'b?100: 2;
        4'b1000: 3;
        4'b0000: 4;
        default: 0;
    endcase;

    RtilePcieByteCntInDw subValLastBe = case (pack(tlpHeader.lastDwBe)) matches
        4'b1???: 0;
        4'b01??: 1;
        4'b001?: 2;
        4'b0001: 3;
        default: 0;
    endcase;

    length = length - zeroExtend(subValFirstBe + subValLastBe);
    RtilePcieByteCntInDw firstDwByteEnCnt = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - subValFirstBe;
    return tuple2(length, firstDwByteEnCnt);
endfunction

function Tuple3#(PcieTlpDataByteCnt, RtilePcieByteCntInDw, Bool) getDataLenFromTlpHeaderOfTypeCplt(PcieTlpHeaderBuffer tlpBuffer);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);
    PcieTlpDataByteCnt lengthInDw = getPayloadLengthInDW(tlpBuffer);
    PcieTlpDataByteCnt length = lengthInDw << 2; // convert from DW to Byte

    PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

    // for the first cplt, lowerAddr's 2-lsb means the address offset, which is the count of invalid bytes in the first payload DW
    // for other cplt, lowerAddr's 2-lsb must be zero, so the length won't be modified.
    RtilePcieByteCntInDw firstDwByteEnCnt = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - zeroExtend(tlpHeader.lowerAddress[1:0]);
    let adjustedLength = length - zeroExtend(tlpHeader.lowerAddress[1:0]);

    PcieTlpDataByteCnt extendedByteCount = zeroExtend(tlpHeader.byteCount);
    extendedByteCount[valueOf(PCIE_HEADER_FIELD_BYTE_COUNT_WIDTH)] = pack(tlpHeader.byteCount == 0);  // length == 0 means 4096 bytes

    Bool isLastCplt = adjustedLength >= extendedByteCount;
    return tuple3(isLastCplt ? extendedByteCount : adjustedLength, firstDwByteEnCnt, isLastCplt);
endfunction

function Maybe#(PcieDataStreamByteCnt) getSignedBiDirByteShiftOffsetFromTlpHeader(PcieTlpHeaderBuffer tlpBuffer, PcieSegmentIdx startSegIdx);
    PcieTlpHeaderCommon headerFirstDW = getPcieTlpHeaderCommon(tlpBuffer);

    if (!isPcieTlpHasPayload(tlpBuffer)) begin
        return tagged Invalid;
    end
    else begin
        Integer dwordInSegmentNumberWidth = valueOf(TLog#(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH)) - valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        PcieDataStreamByteCnt sourceLowerDwAddr = zeroExtend(startSegIdx) << dwordInSegmentNumberWidth;
        
        if (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_MEM_WRITE) begin
            ADDR addrDw = truncate(tlpBuffer) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);  // convert from byte aligned addr to DW aligned;

            Bit#(TSub#(TLog#(SizeOf#(PcieDataStreamByteIdx)), BYTE_DWORD_CONVERT_SHIFT_NUM)) tmpTruncateVar = truncate(addrDw);
            PcieDataStreamByteCnt targetLowerDwAddr = zeroExtend(tmpTruncateVar);

            return tagged Valid ((sourceLowerDwAddr - targetLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
        end
        else if (headerFirstDW.typ == `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA) begin
            PcieTlpHeaderCompletion tlpHeader = unpack(truncateLSB(tlpBuffer));

            PcieDataStreamByteCnt targetLowerDwAddr = zeroExtend(tlpHeader.lowerAddress) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);

            return tagged Valid ((sourceLowerDwAddr - targetLowerDwAddr) << valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
        end
        else begin
            return tagged Invalid;
        end
    end
endfunction

typedef struct {
    Bool isCplt;
    PcieHeaderFieldExtendedTag extTag;
    Bool isLastCplt;
} MetaForReceivedTlpDispatch deriving(Bits, FShow);

typedef struct {
    PcieDataStreamLsbRight  ds;
    PcieExtendTagHighPart   tagHigherPart;
    Bool                    isLastCplt;
} MemoeyMapAlignedDataStreamWithMetadata deriving(Bits, FShow);

typedef StreamShifterG#(PcieDataStreamDataLsbRight) PcieStreamShifter;

typedef 4096                                                            PCIE_MRRS;
typedef TMul#(PCIE_MRRS, BYTE_WIDTH)                                    PCIE_MRRS_WIDTH_IN_BITS;

typedef 4096                                                            PCIE_MAX_MPS_ALLOWED_IN_PCIE_SPEC;
typedef 512                                                             PCIE_MPS;
typedef TAdd#(1, TDiv#(PCIE_MPS, PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH))     PCIE_MAX_PAYLOAD_SEGMENT_CNT_PER_TLP;
typedef TLog#(PCIE_MAX_PAYLOAD_SEGMENT_CNT_PER_TLP)                     PCIE_SEGMENT_IDX_IN_TLP_WIDTH;
typedef TAdd#(1, PCIE_SEGMENT_IDX_IN_TLP_WIDTH)                         PCIE_SEGMENT_CNT_IN_TLP_WIDTH;
typedef Bit#(PCIE_SEGMENT_IDX_IN_TLP_WIDTH)                             PcieSegIdxInTlp;
typedef Bit#(PCIE_SEGMENT_CNT_IN_TLP_WIDTH)                             PcieSegCntInTlp;

typedef 64                                                              PCIE_RCB;
typedef TAdd#(1, TDiv#(PCIE_MRRS, PCIE_RCB))                            PCIE_MAX_CPLT_TLP_CNT_PER_READ_REQUEST;     // 65
typedef TLog#(PCIE_MAX_CPLT_TLP_CNT_PER_READ_REQUEST)                   PCIE_CPLT_TLP_IDX_IN_READ_REQUEST_WIDTH;    // 7
typedef TAdd#(1, PCIE_CPLT_TLP_IDX_IN_READ_REQUEST_WIDTH)               PCIE_CPLT_TLP_CNT_IN_READ_REQUEST_WIDTH;    // 8
typedef Bit#(PCIE_CPLT_TLP_IDX_IN_READ_REQUEST_WIDTH)                   PcieClptTlpIdxInReadRequest;                // 7
typedef Bit#(PCIE_CPLT_TLP_CNT_IN_READ_REQUEST_WIDTH)                   PcieClptTlpCntInReadRequest;                // 8

typedef 64                                                                  PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT;
typedef TAdd#(1, TDiv#(PCIE_MRRS, PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT))       PCIE_MAX_CPLT_DATA_SLOT_CNT_PER_READ_REQUEST;  // 65
typedef TLog#(PCIE_MAX_CPLT_DATA_SLOT_CNT_PER_READ_REQUEST)                 PCIE_CPLT_DATA_SLOT_IDX_IN_READ_REQUEST_WIDTH; // 7
typedef TAdd#(1, PCIE_CPLT_DATA_SLOT_IDX_IN_READ_REQUEST_WIDTH)             PCIE_CPLT_DATA_SLOT_CNT_IN_READ_REQUEST_WIDTH; // 8
typedef Bit#(PCIE_CPLT_DATA_SLOT_IDX_IN_READ_REQUEST_WIDTH)                 PcieClptDataSlotIdxInReadRequest;
typedef Bit#(PCIE_CPLT_DATA_SLOT_CNT_IN_READ_REQUEST_WIDTH)                 PcieClptDataSlotCntInReadRequest;               // 8

typedef 1444 RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH;
typedef 2016 RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_DEPTH;

typedef TLog#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_INDEX_WIDTH;
typedef TLog#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_DEPTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_INDEX_WIDTH;
typedef TAdd#(1, RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_INDEX_WIDTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_COUNT_WIDTH;
typedef TAdd#(1, RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_INDEX_WIDTH) RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_COUNT_WIDTH;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_INDEX_WIDTH) PcieHwCpltBufferHeaderSlotIdx;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_INDEX_WIDTH) PcieHwCpltBufferDataSlotIdx;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_COUNT_WIDTH) PcieHwCpltBufferHeaderSlotCnt;
typedef Bit#(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_COUNT_WIDTH) PcieHwCpltBufferDataSlotCnt;

typedef struct {
    PcieHwCpltBufferHeaderSlotCnt   headerSlotCnt;
    PcieHwCpltBufferDataSlotCnt     dataSlotCnt;
} PcieSharedCompletionBufferSlotAllocReq deriving(Bits, FShow);

typedef struct {
    PcieHwCpltBufferHeaderSlotCnt   headerSlotCnt;
    PcieHwCpltBufferDataSlotCnt     dataSlotCnt;
} PcieSharedCompletionBufferSlotDeAllocReq deriving(Bits, FShow);

interface PcieHwCpltBufferAllocator;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(PcieSharedCompletionBufferSlotAllocReq)) slotAllocReqPipeInVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(void)) slotAllocRespPipeOutVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(PcieSharedCompletionBufferSlotDeAllocReq)) slotDeAllocPipeInVec;
endinterface

(* synthesize *)
module mkPcieHwCpltBufferAllocator(PcieHwCpltBufferAllocator);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(PcieSharedCompletionBufferSlotAllocReq))     slotAllocReqPipeInVecInst    = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(void))                                      slotAllocRespPipeOutVecInst  = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(PcieSharedCompletionBufferSlotDeAllocReq))   slotDeAllocPipeInVecInst     = newVector;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInAdapterB0#(PcieSharedCompletionBufferSlotAllocReq))     tagAllocReqPipeInQueueVec    <- replicateM(mkPipeInAdapterB0);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(void))                                       tagAllocRespPipeOutQueueVec  <- replicateM(mkSizedFIFOF(10));
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInAdapterB0#(PcieSharedCompletionBufferSlotDeAllocReq))   tagDeAllocPipeInQueueVec     <- replicateM(mkPipeInAdapterB0);


    for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        slotAllocReqPipeInVecInst[idx]   = toPipeInB0(tagAllocReqPipeInQueueVec[idx]);
        slotAllocRespPipeOutVecInst[idx] = toPipeOut(tagAllocRespPipeOutQueueVec[idx]);
        slotDeAllocPipeInVecInst[idx]    = toPipeInB0(tagDeAllocPipeInQueueVec[idx]);
    end
    
    Reg#(PcieHwCpltBufferHeaderSlotCnt) headerUsedReg   <- mkReg(0);
    Reg#(PcieHwCpltBufferDataSlotCnt)   dataUsedReg     <- mkReg(0);

    // Pipeline Queues
    FIFOF#(Tuple3#(PcieHwCpltBufferHeaderSlotCnt, PcieHwCpltBufferDataSlotCnt, Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool))) preCalcAllocReqPipelineQueue <- mkLFIFOF;
    FIFOF#(Tuple2#(PcieHwCpltBufferHeaderSlotCnt, PcieHwCpltBufferDataSlotCnt)) preCalcDeallocReqPipelineQueue <- mkLFIFOF;


    // rule debug;
    //     if (!preCalcAllocReqPipelineQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  preCalcAllocReqPipelineQueue");
    //     end

    //     if (!preCalcDeallocReqPipelineQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  preCalcDeallocReqPipelineQueue");
    //     end

    //     if (!preCalcAllocReqPipelineQueue.notFull) begin
    //         if (!preCalcDeallocReqPipelineQueue.notEmpty) begin
    //             $display("time=%0t, ", $time, "DEBUG QUEUE EMPTY!!!  preCalcDeallocReqPipelineQueue");
    //         end
    //     end
    // endrule

    rule perCalcDealloc;
        PcieHwCpltBufferHeaderSlotCnt   decrHeader  = 0;
        PcieHwCpltBufferDataSlotCnt     decrData    = 0;

        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieSharedCompletionBufferSlotDeAllocReq) decrReqVec = replicate(unpack(0));
        for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            if (tagDeAllocPipeInQueueVec[idx].notEmpty) begin
                decrReqVec[idx] = tagDeAllocPipeInQueueVec[idx].first;
                tagDeAllocPipeInQueueVec[idx].deq;
            end
        end
        
        for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            decrHeader  = decrHeader    + decrReqVec[idx].headerSlotCnt;
            decrData    = decrData      + decrReqVec[idx].dataSlotCnt;
        end
        preCalcDeallocReqPipelineQueue.enq(tuple2(decrHeader, decrData));
    endrule

    rule perCalcAlloc;
        PcieHwCpltBufferHeaderSlotCnt   incrHeader    = 0;
        PcieHwCpltBufferDataSlotCnt     incrData      = 0;
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieSharedCompletionBufferSlotAllocReq) incrReqVec = replicate(unpack(0));

        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool) incrReqChannelFlag = replicate(False);
        for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            // important, we need to make sure the output channel is also not full, so the merge rule can't block.
            if (tagAllocReqPipeInQueueVec[idx].notEmpty && tagAllocRespPipeOutQueueVec[idx].notFull) begin
                incrReqVec[idx] = tagAllocReqPipeInQueueVec[idx].first;
                incrReqChannelFlag[idx] = True;
                tagAllocReqPipeInQueueVec[idx].deq;
            end
        end

        for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
            incrHeader  = incrHeader    + incrReqVec[idx].headerSlotCnt;
            incrData    = incrData      + incrReqVec[idx].dataSlotCnt;
        end
        preCalcAllocReqPipelineQueue.enq(tuple3(incrHeader, incrData, incrReqChannelFlag));
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieHwCpltBufferAllocator perCalcAlloc")
        // );
    endrule


    rule merge;
        let {incrHeader, incrData, incrReqChannelFlag} = preCalcAllocReqPipelineQueue.first;
        let {decrHeader, decrData} = preCalcDeallocReqPipelineQueue.first;

        preCalcDeallocReqPipelineQueue.deq;

        let enoughHeaderToAlloc = headerUsedReg + incrHeader    <= fromInteger(valueOf(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH));
        let enoughDataToAlloc   = dataUsedReg   + incrData      <= fromInteger(valueOf(RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_DATA_DEPTH));

        if (enoughHeaderToAlloc && enoughDataToAlloc) begin
            for (Integer idx = 0; idx <  valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
                if (incrReqChannelFlag[idx]) begin
                    if (tagAllocRespPipeOutQueueVec[idx].notFull) begin
                        tagAllocRespPipeOutQueueVec[idx].enq(unpack(0));
                    end
                    else begin
                        immFail("tagAlloc response Queue is Full, so alloc response is lost.", $format("channel idx = %d", idx));
                    end
                end
            end
            headerUsedReg   <= headerUsedReg    + incrHeader - decrHeader;
            dataUsedReg     <= dataUsedReg      + incrData   - decrData;
            preCalcAllocReqPipelineQueue.deq;
        end
        else begin
            headerUsedReg   <= headerUsedReg    - decrHeader;
            dataUsedReg     <= dataUsedReg      - decrData;
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieHwCpltBufferAllocator merge"),
        //     toBlue(", incrHeader="), fshow(incrHeader),
        //     toBlue(", incrData="), fshow(incrData),
        //     toBlue(", incrReqChannelFlag="), fshow(incrReqChannelFlag),
        //     toBlue(", decrHeader="), fshow(decrHeader),
        //     toBlue(", decrData="), fshow(decrData),
        //     toBlue(", headerUsedReg="), fshow(headerUsedReg),
        //     toBlue(", dataUsedReg="), fshow(dataUsedReg)
        // );
    endrule

    interface slotAllocReqPipeInVec      = slotAllocReqPipeInVecInst;
    interface slotAllocRespPipeOutVec    = slotAllocRespPipeOutVecInst;
    interface slotDeAllocPipeInVec       = slotDeAllocPipeInVecInst;
endmodule



// typedef 32 PCIE_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH;
// typedef Bit#(PCIE_COMPLETION_BUFFER_SLOT_USER_DATA_WIDTH) PcieCompletionBufferSlotUserData;

// according to UG21036, Total tag allowed is from 256 to 1023. We use the lower 2 bits of the 10 bits tag as channel index,
// so the higher 8 bits should range between 64~255.
typedef 64 PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE;
typedef 255 PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE;

typedef 8 PCIE_EXTENDED_TAG_HIGH_PART_WIDTH;
typedef Bit#(PCIE_EXTENDED_TAG_HIGH_PART_WIDTH) PcieExtendTagHighPart;

// typedef 512 PCIE_MIN_RCB_BIT_WIDTH;
// typedef TDiv#(PCIE_MIN_RCB_BIT_WIDTH, BYTE_WIDTH) PCIE_MIN_RCB_BYTE_WIDTH;
// typedef Bit#(PCIE_MIN_RCB_BIT_WIDTH) PcieRcbDataBlock;

typedef TAdd#(1, TSub#(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE, PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)) PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT;
typedef TExp#(TLog#(TMul#(2, RTILE_PCIE_RX_HARDWARE_CPLT_BUFFER_HEADER_DEPTH))) PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT;  // mul by 2 to leave enough space to prevent wrap around. use TExp to align power of 2.

typedef TLog#(PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT) PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_IDX_WIDTH;           // 12
typedef TAdd#(1, PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_IDX_WIDTH) PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT_WIDTH;

typedef Bit#(PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_IDX_WIDTH) CpltBufferCpltTlpInfoBufferAddr;        // 12
typedef Bit#(PCIE_COMPLETION_BUFFER_CPLT_TLP_INFO_BUFFER_ROW_CNT_WIDTH) CpltBufferCpltTlpInfoBufferCnt;         // 13

typedef PCIE_EXTENDED_TAG_HIGH_PART_WIDTH PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH;   // 8

typedef Bit#(PCIE_COMPLETION_BUFFER_TAG_SLOT_INDEX_WIDTH)           PcieCompletionBufferSlotIdx;
typedef Bit#(TLog#(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE)) PcieCompletionBufferSlotCnt;


typedef Bit#(TLog#(PCIE_HEADER_FIELD_FIRST_DW_BE_WIDTH))            InvalidByteNumInDw;

typedef TDiv#(SizeOf#(DATA), DWORD_WIDTH)       DWORD_CNT_PER_USER_LOGIC_BEAT;
typedef Bit#(TLog#(DWORD_CNT_PER_USER_LOGIC_BEAT)) DwordIdxInUserLogicBeat;

typedef struct {
    PcieClptTlpCntInReadRequest         maxCpltTlpCntNeeded;
    PcieClptDataSlotCntInReadRequest    hwClptBufDataSlotCntNeeded;
} PcieChannelPrivateCompletionBufferSlotAllocReq deriving(Bits, FShow);

// each PCIe read request correspond to a Tag, so each tag slot correspond to a PCIe read request
typedef struct {
    CpltBufferCpltTlpInfoBufferAddr                     cpltTlpListStartAddr;           // 12
    PcieClptTlpIdxInReadRequest                         cpltTlpListCurWriteOffset;      // 7

    PcieClptTlpCntInReadRequest                         maxCpltTlpCntNeeded;            // 8
    PcieClptDataSlotCntInReadRequest                    hwClptBufDataSlotCntNeeded;     // 8

    Bool                                                isCompleted; 
} PcieCompletionBufferTagSlotMeta deriving(Bits, FShow);

typedef struct {
    CpltBufferCpltTlpInfoBufferAddr                     cpltTlpListStartAddr; 
    PcieClptTlpIdxInReadRequest                         cpltTlpListCurReadOffset;
    PcieClptTlpIdxInReadRequest                         cpltTlpListTargetReadOffset;
} PcieCompletionBufferTagSlotMetaForOutputStage deriving(Bits, FShow);

typedef struct {
    RtilePcieRxPayloadStorageAddr   storageRowAddr;             // 12
    PcieSegmentIdx                  storageSegOffset;           // 2
    RtilePcieByteCntInDw            firstBeCnt;                 // 3
    PcieSegCntInTlp                 segCntLeftToRead;           // 6     
    PcieTlpDataByteCnt              byteCountLeftInThisTlp;     // 13
    Bool                            isLastCplt;                 // 1
} PcieCompletionBufferCpltTlpInfoForOutputStage deriving(Bits, FShow);

typedef struct {
    PcieSegmentIdx                  srcSegIdx;                  // 2
    RtilePcieByteCntInDw            firstBeCnt;                 // 3    
    PcieTlpDataByteCnt              byteCountLeftInThisTlp;     // 13
    Bool                            isLast;                     // 1
    Bool                            isLastCplt;                 // 1
} PcieCompletionBufferBeatInfoForOutputDataStreamGenerate deriving(Bits, FShow);

typedef enum {
    PcieCompletionBufferOutputStateSendStateInit = 0,
    PcieCompletionBufferOutputStateWaitStateRunning = 1
} PcieCompletionBufferOutputState deriving(Bits, Eq, FShow);

interface PcieCompletionBuffer;
    interface PipeInB0#(PcieChannelPrivateCompletionBufferSlotAllocReq) tagAllocReqPipeIn;
    interface PipeOut#(PcieHeaderFieldExtendedTag) tagAllocRespPipeOut;
    interface PipeInB0#(RtilePcieRxPayloadStorageWriteReq) tlpRawBeatDataStorageWriteReqPipeIn;
    interface PipeInB0#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt))) cpltTlpVecPipeIn;
    interface PipeOut#(PcieSharedCompletionBufferSlotDeAllocReq) sharedHwCpltBufferSlotDeAllocReqPipeOut;
    interface PipeOut#(RtilePcieUserStream) dataStreamPipeOut;
    (* always_enabled, always_ready *)
    method Action setChannelIdx(RtilePcieUserChannelIdx idx);
endinterface

(* synthesize *)
module mkPcieCompletionBuffer(PcieCompletionBuffer);

    PipeInAdapterB0#(PcieChannelPrivateCompletionBufferSlotAllocReq)              tagAllocReqPipeInQueue                          <- mkPipeInAdapterB0;
    FIFOF#(PcieHeaderFieldExtendedTag)                                  tagAllocRespPipeOutQueue                        <- mkFIFOF;
    PipeInAdapterB0#(RtilePcieRxPayloadStorageWriteReq)                   tlpRawBeatDataStorageWriteReqPipeInQueue        <- mkPipeInAdapterB0;
    PipeInAdapterB0#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))   cpltTlpVecPipeInQueue                           <- mkPipeInAdapterB0;
    FIFOF#(PcieSharedCompletionBufferSlotDeAllocReq)                    sharedHwCpltBufferSlotDeAllocReqPipeOutQueue    <- mkFIFOF;

    Wire#(RtilePcieUserChannelIdx) channelIdxWire <- mkBypassWire;
    Reg#(PcieExtendTagHighPart) tagAllocHeadReg <- mkReg(fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
    Reg#(PcieExtendTagHighPart) tagAllocTailReg <- mkReg(fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE)));
    Count#(PcieCompletionBufferSlotCnt) busySlotCounter <- mkCount(0);

    Reg#(CpltBufferCpltTlpInfoBufferAddr)   curCpltTlpBufferAddrToAllocReg <- mkReg(0);  

    Vector#(PCIE_SEGMENT_CNT, AutoInferBramQueuedOutput#(RtilePcieRxPayloadStorageAddr, PcieTlpDataSegment))            dataStreamStorageVec            <- replicateM(mkAutoInferBramQueuedOutput(False, "", "mkPcieCompletionBuffer dataStreamStorageVec"));
    Vector#(NUMERIC_TYPE_TWO, AutoInferBramQueuedOutput#(PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta)) slotMetaStorageDoubleWriteVec   <- replicateM(mkAutoInferBramQueuedOutput(False, "", "mkPcieCompletionBuffer slotMetaStorageDoubleWriteVec"));
    AutoInferBramQueuedOutput#(CpltBufferCpltTlpInfoBufferAddr, RtilePcieRxTlpInfoCplt)                                 cpltTlpInfoStorage              <- mkAutoInferBramQueuedOutput(False, "", "mkPcieCompletionBuffer cpltTlpInfoStorage");

    Integer slotMetaStorageBramIdxForPtrUpdateRead = 0;
    Integer slotMetaStorageBramIdxForOutputStatePollRead = 1;

    FIFOF#(Tuple2#(PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta)) slotMetaUpdateReqQueueForTagAlloc <- mkLFIFOF;
    FIFOF#(Tuple2#(PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta)) slotMetaUpdateReqQueueForWritePtrUpdate <- mkLFIFOF;
    FIFOF#(PcieCompletionBufferSlotIdx) slotMetaUpdateReqQueueForSlotRelease <- mkLFIFOF;

    Reg#(Maybe#(Vector#(PCIE_MAX_TLP_CNT, Maybe#(RtilePcieRxTlpInfoCplt)))) curInputCpltTlpVecMaybeReg <- mkReg(tagged Invalid);
    
    Reg#(Maybe#(PcieCompletionBufferTagSlotMetaForOutputStage))     curOutputSlotMetaMaybeReg   <- mkReg(tagged Invalid);
    Reg#(Maybe#(PcieCompletionBufferCpltTlpInfoForOutputStage))     curOutputCpltTlpMaybeReg    <- mkReg(tagged Invalid);

    DtldStreamConcator#(DATA, NUMERIC_TYPE_TWO) outputCpltStreamConcator <- mkDtldStreamConcator(DebugConf{name:"mkPcieCompletionBuffer outputCpltStreamConcator", enableDebug: False});

    // Pipeline FIFOs
    FIFOF#(RtilePcieRxTlpInfoCplt)                                              handleInputCpltTlpVecStep2PipelineQueue             <- mkSizedFIFOF(6);
    FIFOF#(PcieCompletionBufferTagSlotMetaForOutputStage)                       readCpltTlpInfoForOutputPipelineQueue               <- mkLFIFOF;
    FIFOF#(PcieCompletionBufferBeatInfoForOutputDataStreamGenerate)             outputDataStreamGenPipelineQueue                    <- mkSizedFIFOF(6);
    FIFOF#(Tuple2#(CpltBufferCpltTlpInfoBufferAddr, RtilePcieRxTlpInfoCplt))    handleCpltTlpInfoStorageWritePipelineQueue          <- mkLFIFOF;


    PrioritySearchBuffer#(NUMERIC_TYPE_SIX, PcieCompletionBufferSlotIdx, PcieCompletionBufferTagSlotMeta) slotMetaUpdateForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_SIX));
 
 
    // Reg#(Bool) newCompleteSlotSignalReg[3] <- mkCReg(3, False);


    // Reg#(Bool) newCompleteSlotSignalReg[3] <- mkCReg(3, False);

    Reg#(PcieCompletionBufferOutputState) outputStateReg <- mkReg(PcieCompletionBufferOutputStateSendStateInit);

    Reg#(Bool) isCurCpltOutputFirstBeatReg          <- mkReg(True);
    Reg#(Bool) isOriginReadReqOutputFirstBeatReg    <- mkReg(True);
    Reg#(Bool) isFirstCpltInOriginReadReqReg        <- mkReg(True);
    Reg#(DwordIdxInUserLogicBeat)   finalDataStreamConcatShiftDwordOffsetReg <- mkRegU;
    Reg#(RtilePcieUserStream)   previousDs <- mkRegU;


    Reg#(Bit#(3)) debugRuleRunCntHandleInputCpltTlpVecStep1C0 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntHandleInputCpltTlpVecStep1C1 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntHandleInputCpltTlpVecStep2C0 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntHandleInputCpltTlpVecStep2C1 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntOutputWaitStateQueryRespC0 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntOutputWaitStateQueryRespC1 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntReadCpltTlpInfoForOutputC0 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntReadCpltTlpInfoForOutputC1 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntReadDataStorageForOutputC0 <- mkReg(0);
    Reg#(Bit#(3)) debugRuleRunCntReadDataStorageForOutputC1 <- mkReg(0);

    Probe#(Bit#(3)) dummyProbe <- mkProbe;


    

    


    let outputCpltStreamConcatorDataPipeInConverter <- mkPipeInB0ToPipeIn(outputCpltStreamConcator.dataPipeIn, 1);
    let outputCpltStreamConcatorIsLastStreamFlagPipeInConverter <- mkPipeInB0ToPipeIn(outputCpltStreamConcator.isLastStreamFlagPipeIn, 1);

    let cpltTlpDataReadOutContinousChecker <- mkStreamFullyPipelineChecker(DebugConf{name: "mkPcieCompletionBuffer cpltTlpDataReadOutContinousChecker", enableDebug: True});


    // rule debug;
    //     if (!cpltTlpVecPipeInQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  cpltTlpVecPipeInQueue");
    //     end

    //     if (!handleInputCpltTlpVecStep2PipelineQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  handleInputCpltTlpVecStep2PipelineQueue");
    //     end
        
    //     if (!handleCpltTlpInfoStorageWritePipelineQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  handleCpltTlpInfoStorageWritePipelineQueue");
    //     end


    //     if (!slotMetaReadReqQueueForOutputData.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  slotMetaReadReqQueueForOutputData");
    //     end
            
    //     // if (!slotMetaReadRespQueueForPtrUpdate.notEmpty) begin
    //     //     $display("time=%0t, ", $time, "DEBUG QUEUE EMPTY!!!  slotMetaReadRespQueueForPtrUpdate");
    //     // end

    //     if (!slotMetaReadRespQueueForPtrUpdate.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  slotMetaReadRespQueueForPtrUpdate");
    //     end

    //     if (!slotMetaReadRespQueueForOutputData.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  slotMetaReadRespQueueForOutputData");
    //     end

    //     if (!slotMetaUpdateReqQueueForWritePtrUpdate.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  slotMetaUpdateReqQueueForWritePtrUpdate");
    //     end

    //     if (!slotMetaReadReqKeepOrderQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  slotMetaReadReqKeepOrderQueue");
    //     end
        
    //     if (!sharedHwCpltBufferSlotDeAllocReqPipeOutQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  sharedHwCpltBufferSlotDeAllocReqPipeOutQueue");
    //     end

    //     // if (!readCpltTlpInfoForOutputPipelineQueue.notFull) begin
    //     //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  readCpltTlpInfoForOutputPipelineQueue");
    //     // end

        
    // endrule


    rule probe;

        dummyProbe <=   debugRuleRunCntHandleInputCpltTlpVecStep1C0 ^ 
                        debugRuleRunCntHandleInputCpltTlpVecStep1C1 ^ 
                        debugRuleRunCntHandleInputCpltTlpVecStep2C0 ^ 
                        debugRuleRunCntHandleInputCpltTlpVecStep2C1 ^ 
                        debugRuleRunCntOutputWaitStateQueryRespC0 ^ 
                        debugRuleRunCntOutputWaitStateQueryRespC1 ^ 
                        debugRuleRunCntReadCpltTlpInfoForOutputC0 ^ 
                        debugRuleRunCntReadCpltTlpInfoForOutputC1 ^ 
                        debugRuleRunCntReadDataStorageForOutputC0 ^ 
                        debugRuleRunCntReadDataStorageForOutputC1;
    endrule


    rule handleDataStreamInput;
        let req = tlpRawBeatDataStorageWriteReqPipeInQueue.first;
        tlpRawBeatDataStorageWriteReqPipeInQueue.deq;

        for (Integer idx = 0; idx < valueOf(PCIE_SEGMENT_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].write(req.addr, req.dataBundles[idx]);
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleDataStreamInput"),
        //     toBlue(", req="), fshow(req)
        // );
    endrule

    rule assertChecker;
        // since the PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT is not 2^n now, maybe in the future it will become 2^n. If it become 2^n,
        // some width calculated by TLog#() will be wrong, so we need to check it. 
        immAssert(
            valueOf(PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT) < valueOf(TExp#(SizeOf#(PcieCompletionBufferSlotCnt))),
            "value overflow",
            $format("")
        );
    endrule

    rule muxSlotMetaUpdateReq;
        // writePtr update has higher priority
        if (slotMetaUpdateReqQueueForWritePtrUpdate.notEmpty) begin
            let {addr, data} = slotMetaUpdateReqQueueForWritePtrUpdate.first;
            slotMetaUpdateReqQueueForWritePtrUpdate.deq;
            for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
                slotMetaStorageDoubleWriteVec[idx].write(addr, data);
            end
            
        end
        else if (slotMetaUpdateReqQueueForSlotRelease.notEmpty) begin
            let addr = slotMetaUpdateReqQueueForSlotRelease.first;
            slotMetaUpdateReqQueueForSlotRelease.deq;
            for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
                slotMetaStorageDoubleWriteVec[idx].write(addr, unpack(0));
            end
        end
        else if (slotMetaUpdateReqQueueForTagAlloc.notEmpty) begin
            let {addr, data} = slotMetaUpdateReqQueueForTagAlloc.first;
            slotMetaUpdateReqQueueForTagAlloc.deq;
            for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
                slotMetaStorageDoubleWriteVec[idx].write(addr, data);
            end
        end
    endrule

    rule handleTagAlloc;
        if (busySlotCounter != fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_SLOT_COUNT))) begin
            let req = tagAllocReqPipeInQueue.first;
            tagAllocReqPipeInQueue.deq;

            let newSlot = PcieCompletionBufferTagSlotMeta {
                cpltTlpListStartAddr        : curCpltTlpBufferAddrToAllocReg,
                cpltTlpListCurWriteOffset   : 0,
                isCompleted                 : False,
                maxCpltTlpCntNeeded         : req.maxCpltTlpCntNeeded,
                hwClptBufDataSlotCntNeeded  : req.hwClptBufDataSlotCntNeeded
            };
            
            PcieHeaderFieldExtendedTag tag = unpack({pack(tagAllocHeadReg), pack(channelIdxWire)});
            slotMetaUpdateReqQueueForTagAlloc.enq(tuple2(tagAllocHeadReg, newSlot));

            tagAllocRespPipeOutQueue.enq(tag);

            if (tagAllocHeadReg == fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
                tagAllocHeadReg <= fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
            end
            else begin
                tagAllocHeadReg <= tagAllocHeadReg + 1;
            end
            busySlotCounter.incr(1);
            curCpltTlpBufferAddrToAllocReg <= curCpltTlpBufferAddrToAllocReg + zeroExtend(req.maxCpltTlpCntNeeded);

            // $display(
            //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleTagAlloc"),
            //     toBlue(", channelIdx="), fshow(channelIdxWire),
            //     toBlue(", tag="), fshow(tag)
            // );
        end

    endrule

    rule handleInputCpltTlpVecStep1;
        if (curInputCpltTlpVecMaybeReg matches tagged Valid .curInputCpltTlpVec) begin

            debugRuleRunCntHandleInputCpltTlpVecStep1C1 <= debugRuleRunCntHandleInputCpltTlpVecStep1C1 + 1;
            immAssert(
                isValid(curInputCpltTlpVec[0]),
                "input vector's first element must be valid",
                $format("")
            );

            let curCplt = fromMaybe(?, curInputCpltTlpVec[0]);

            PcieExtendTagHighPart slotIdx = unpack(truncateLSB(curCplt.tag));
            slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForPtrUpdateRead].putReadReq(slotIdx);            
            handleInputCpltTlpVecStep2PipelineQueue.enq(curCplt);

            let newInputCpltTlpVec = shiftOutFrom0(tagged Invalid, curInputCpltTlpVec, 1);
            if (isValid(newInputCpltTlpVec[0])) begin
                curInputCpltTlpVecMaybeReg <= tagged Valid newInputCpltTlpVec;
            end
            else begin
                if (cpltTlpVecPipeInQueue.notEmpty) begin
                    curInputCpltTlpVecMaybeReg <= tagged Valid cpltTlpVecPipeInQueue.first;
                    cpltTlpVecPipeInQueue.deq;
                end
                else begin
                    curInputCpltTlpVecMaybeReg <= tagged Invalid;
                end
            end

            // $display(
            //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleInputCpltTlpVecStep1 BUSY mode"),
            //     toBlue(", curInputCpltTlpVec="), fshow(curInputCpltTlpVec)
            // );

        end
        else begin
            debugRuleRunCntHandleInputCpltTlpVecStep1C0 <= debugRuleRunCntHandleInputCpltTlpVecStep1C0 + 1;


            curInputCpltTlpVecMaybeReg <= tagged Valid cpltTlpVecPipeInQueue.first;
            cpltTlpVecPipeInQueue.deq;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleInputCpltTlpVecStep1 IDLE mode"),
            //     toBlue(", cpltTlpVecPipeInQueue.first="), fshow(cpltTlpVecPipeInQueue.first)
            // );

            immAssert(
                isValid(cpltTlpVecPipeInQueue.first[0]),
                "input vector's first element must be valid",
                $format("")
            );
        end
    endrule

    rule handleInputCpltTlpVecStep2;
        debugRuleRunCntHandleInputCpltTlpVecStep2C0 <= debugRuleRunCntHandleInputCpltTlpVecStep2C0 + 1;
        let curCplt = handleInputCpltTlpVecStep2PipelineQueue.first;
        handleInputCpltTlpVecStep2PipelineQueue.deq;

        PcieExtendTagHighPart slotIdx = unpack(truncateLSB(curCplt.tag));
        let slotMetaReadFromBram = slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForPtrUpdateRead].readRespPipeOut.first;
        slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForPtrUpdateRead].readRespPipeOut.deq;

        let slotMetaFromForwardBufferMaybe      <- slotMetaUpdateForwardBuffer.search(slotIdx);
        PcieCompletionBufferTagSlotMeta slotMeta   = isValid(slotMetaFromForwardBufferMaybe) ? fromMaybe(?, slotMetaFromForwardBufferMaybe) : slotMetaReadFromBram;

        let cpltTlpEntryWriteAddr = slotMeta.cpltTlpListStartAddr + zeroExtend(slotMeta.cpltTlpListCurWriteOffset);
        handleCpltTlpInfoStorageWritePipelineQueue.enq(tuple2(cpltTlpEntryWriteAddr, curCplt));
        slotMeta.cpltTlpListCurWriteOffset = slotMeta.cpltTlpListCurWriteOffset + 1;
        
        if (curCplt.isLastCplt) begin
            slotMeta.isCompleted = True;
            sharedHwCpltBufferSlotDeAllocReqPipeOutQueue.enq(PcieSharedCompletionBufferSlotDeAllocReq{
                headerSlotCnt   : zeroExtend(slotMeta.maxCpltTlpCntNeeded),
                dataSlotCnt     : zeroExtend(slotMeta.hwClptBufDataSlotCntNeeded)
            });
            debugRuleRunCntHandleInputCpltTlpVecStep2C1 <= debugRuleRunCntHandleInputCpltTlpVecStep2C1 + 1;
        end

        slotMetaUpdateReqQueueForWritePtrUpdate.enq(tuple2(slotIdx, slotMeta));
        slotMetaUpdateForwardBuffer.enq(slotIdx, slotMeta);

        $display(
            "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleInputCpltTlpVecStep2"),
            ", channel [%0d]", channelIdxWire,
            toBlue(", slotMeta="), fshow(slotMeta)
        );
    endrule

    rule handleCpltTlpInfoStorageWrite;
        // for timing fix
        let {cpltTlpEntryWriteAddr, curCplt} = handleCpltTlpInfoStorageWritePipelineQueue.first;
        handleCpltTlpInfoStorageWritePipelineQueue.deq;
        cpltTlpInfoStorage.write(cpltTlpEntryWriteAddr, curCplt);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer handleCpltTlpInfoStorageWrite"),
        //     toBlue(", cpltTlpEntryWriteAddr="), fshow(cpltTlpEntryWriteAddr),
        //     toBlue(", curCplt="), fshow(curCplt)
        // );
    endrule

    rule sendStateQuery if (outputStateReg == PcieCompletionBufferOutputStateSendStateInit);

        slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForOutputStatePollRead].putReadReq(tagAllocTailReg);
        outputStateReg <= PcieCompletionBufferOutputStateWaitStateRunning;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer sendStateQuery"),
        //     toBlue(", tagAllocTailReg="), fshow(tagAllocTailReg)
        // );
    endrule

    rule outputWaitStateQueryResp if (outputStateReg == PcieCompletionBufferOutputStateWaitStateRunning);

        let slotMetaReadFromBram = slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForOutputStatePollRead].readRespPipeOut.first;
        slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForOutputStatePollRead].readRespPipeOut.deq;


        // let slotMetaFromForwardBufferMaybe      <- slotMetaUpdateForwardBuffer.search(tagAllocTailReg);
        // PcieCompletionBufferTagSlotMeta slotMeta   = isValid(slotMetaFromForwardBufferMaybe) ? fromMaybe(?, slotMetaFromForwardBufferMaybe) : slotMetaReadFromBram;
        
        PcieCompletionBufferTagSlotMeta slotMeta = slotMetaReadFromBram;

        if (slotMeta.isCompleted) begin

            slotMetaUpdateReqQueueForSlotRelease.enq(tagAllocTailReg);
            busySlotCounter.decr(1);

            readCpltTlpInfoForOutputPipelineQueue.enq(PcieCompletionBufferTagSlotMetaForOutputStage {
                cpltTlpListStartAddr        : slotMeta.cpltTlpListStartAddr,
                cpltTlpListCurReadOffset    : 0,
                cpltTlpListTargetReadOffset : slotMeta.cpltTlpListCurWriteOffset - 1  // because this points to the next write slot, so for the last valid one, need minus 1
            });

            let newTagAllocTail;
            if (tagAllocTailReg == fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MAX_VALUE))) begin
                newTagAllocTail = fromInteger(valueOf(PCIE_COMPLETION_BUFFER_TAG_HIGH_PART_MIN_VALUE));
            end 
            else begin
                newTagAllocTail = tagAllocTailReg + 1;
            end
            tagAllocTailReg <= newTagAllocTail;
            slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForOutputStatePollRead].putReadReq(newTagAllocTail);
            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer outputWaitStateQueryResp found complete"),
                ", channel [%0d]", channelIdxWire,
                toBlue(", slotMeta="), fshow(slotMeta),
                toBlue(", tagAllocTailReg="), fshow(tagAllocTailReg),
                toBlue(", newTagAllocTail="), fshow(newTagAllocTail)
            );
            debugRuleRunCntOutputWaitStateQueryRespC0 <= debugRuleRunCntOutputWaitStateQueryRespC0 + 1;
        end
        else begin
            slotMetaStorageDoubleWriteVec[slotMetaStorageBramIdxForOutputStatePollRead].putReadReq(tagAllocTailReg);
            debugRuleRunCntOutputWaitStateQueryRespC1 <= debugRuleRunCntOutputWaitStateQueryRespC1 + 1;
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer outputWaitStateQueryResp"),
        //     ", channel [%0d]", channelIdxWire,
        //     toBlue(", slotMeta="), fshow(slotMeta)
        // );

    endrule

    rule readCpltTlpInfoForOutput;
        if (curOutputSlotMetaMaybeReg matches tagged Valid .curOutputSlotMeta) begin
            debugRuleRunCntReadCpltTlpInfoForOutputC1 <= debugRuleRunCntReadCpltTlpInfoForOutputC1 + 1;
            let isLast = curOutputSlotMeta.cpltTlpListCurReadOffset == curOutputSlotMeta.cpltTlpListTargetReadOffset;
            let cpltTlpMetaAddr = curOutputSlotMeta.cpltTlpListStartAddr + zeroExtend(curOutputSlotMeta.cpltTlpListCurReadOffset);
            cpltTlpInfoStorage.putReadReq(cpltTlpMetaAddr);
            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer readCpltTlpInfoForOutput"),
                ", channel [%0d]", channelIdxWire,
                toBlue(", curOutputSlotMeta="), fshow(curOutputSlotMeta),
                toBlue(", cpltTlpMetaAddr="), fshow(cpltTlpMetaAddr)
            );
            if (isLast) begin
                if (readCpltTlpInfoForOutputPipelineQueue.notEmpty) begin
                    let slotMeta = readCpltTlpInfoForOutputPipelineQueue.first;
                    readCpltTlpInfoForOutputPipelineQueue.deq;
                    curOutputSlotMetaMaybeReg <= tagged Valid slotMeta;
                end
                else begin
                    curOutputSlotMetaMaybeReg <= tagged Invalid;
                end
            end
            else begin
                let newOutputSlotMeta = curOutputSlotMeta;
                newOutputSlotMeta.cpltTlpListCurReadOffset = newOutputSlotMeta.cpltTlpListCurReadOffset + 1;
                curOutputSlotMetaMaybeReg <= tagged Valid newOutputSlotMeta;
            end
        end
        else begin
            debugRuleRunCntReadCpltTlpInfoForOutputC0 <= debugRuleRunCntReadCpltTlpInfoForOutputC0 + 1;
            let slotMeta = readCpltTlpInfoForOutputPipelineQueue.first;
            readCpltTlpInfoForOutputPipelineQueue.deq;
            curOutputSlotMetaMaybeReg <= tagged Valid slotMeta;
        end
    endrule

    rule readDataStorageForOutput;

        PcieCompletionBufferCpltTlpInfoForOutputStage nextNewOutputCpltTlpInfo = ?;
        if (cpltTlpInfoStorage.readRespPipeOut.notEmpty) begin
            let cpltTlpInfoIn = cpltTlpInfoStorage.readRespPipeOut.first;
            let invalidByteCntInFirstDw = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - cpltTlpInfoIn.firstBeCnt;
            let totalBytesCntIncludeInvalidInThisTlp = cpltTlpInfoIn.byteCountInThisTlp + zeroExtend(invalidByteCntInFirstDw);

            // $display(
            //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer readDataStorageForOutput"),
            //     ", channel [%0d]", channelIdxWire,
            //     toBlue(", cpltTlpInfoStorage.readRespPipeOut.first="), fshow(cpltTlpInfoStorage.readRespPipeOut.first)
            // );
            let segCntInThisTlp = 1 + ((totalBytesCntIncludeInvalidInThisTlp - 1) >> fromInteger(valueOf(TLog#(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH))));

            nextNewOutputCpltTlpInfo = PcieCompletionBufferCpltTlpInfoForOutputStage {
                storageRowAddr          : cpltTlpInfoIn.firstBeatStorageAddr, 
                storageSegOffset        : cpltTlpInfoIn.firstBeatSegIdx,      
                firstBeCnt              : cpltTlpInfoIn.firstBeCnt,                
                segCntLeftToRead        : truncate(segCntInThisTlp),
                byteCountLeftInThisTlp  : cpltTlpInfoIn.byteCountInThisTlp,
                isLastCplt              : cpltTlpInfoIn.isLastCplt
            };
        end

        if (curOutputCpltTlpMaybeReg matches tagged Valid .curOutputCpltTlp) begin
            debugRuleRunCntReadDataStorageForOutputC1 <= debugRuleRunCntReadDataStorageForOutputC1 + 1;

            let curSegAddrInStorage = {pack(curOutputCpltTlp.storageRowAddr), pack(curOutputCpltTlp.storageSegOffset)};
            let isLastSegInThisCpltTlp = curOutputCpltTlp.segCntLeftToRead == 1;

            dataStreamStorageVec[curOutputCpltTlp.storageSegOffset].putReadReq(curOutputCpltTlp.storageRowAddr);
            outputDataStreamGenPipelineQueue.enq(PcieCompletionBufferBeatInfoForOutputDataStreamGenerate{
                srcSegIdx               : curOutputCpltTlp.storageSegOffset,             
                firstBeCnt              : curOutputCpltTlp.firstBeCnt,                
                byteCountLeftInThisTlp  : curOutputCpltTlp.byteCountLeftInThisTlp,
                isLast                  : isLastSegInThisCpltTlp,
                isLastCplt              : curOutputCpltTlp.isLastCplt
            });

            let nextOutputCpltTlp = curOutputCpltTlp;

            let nextSegAddrInStorage = curSegAddrInStorage + 1;
            RtilePcieRxPayloadStorageAddr   nextStorageRowAddr      = truncateLSB(nextSegAddrInStorage);
            PcieSegmentIdx                  nextStorageSegOffset    = truncate(nextSegAddrInStorage);

            let invalidByteCntInFirstDw = fromInteger(valueOf(BYTE_CNT_PER_DWOED)) - curOutputCpltTlp.firstBeCnt;
            let byteReadInThisSeg = fromInteger(valueOf(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH)) - zeroExtend(invalidByteCntInFirstDw);
            // in PCIe cplt, only the first DW in first cplt tlp can have leading invalid bytes
            // so set it to BYTE_CNT_PER_DWOED for the following read.
            nextOutputCpltTlp.firstBeCnt                = fromInteger(valueOf(BYTE_CNT_PER_DWOED));
            nextOutputCpltTlp.storageRowAddr            = nextStorageRowAddr;
            nextOutputCpltTlp.storageSegOffset          = nextStorageSegOffset;
            nextOutputCpltTlp.segCntLeftToRead          = nextOutputCpltTlp.segCntLeftToRead - 1;
            nextOutputCpltTlp.byteCountLeftInThisTlp    = nextOutputCpltTlp.byteCountLeftInThisTlp - byteReadInThisSeg;

            if (isLastSegInThisCpltTlp) begin
                if (cpltTlpInfoStorage.readRespPipeOut.notEmpty) begin
                    cpltTlpInfoStorage.readRespPipeOut.deq;
                    curOutputCpltTlpMaybeReg <= tagged Valid nextNewOutputCpltTlpInfo;
                end
                else begin
                    curOutputCpltTlpMaybeReg <= tagged Invalid;
                end
            end
            else begin
                curOutputCpltTlpMaybeReg <= tagged Valid nextOutputCpltTlp;
            end

            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer readDataStorageForOutput"),
                ", channel [%0d]", channelIdxWire,
                toBlue(", curOutputCpltTlp="), fshow(curOutputCpltTlp)
            );
        end
        else begin
            debugRuleRunCntReadDataStorageForOutputC0 <= debugRuleRunCntReadDataStorageForOutputC0 + 1;
            cpltTlpInfoStorage.readRespPipeOut.deq;
            curOutputCpltTlpMaybeReg <= tagged Valid nextNewOutputCpltTlpInfo;
            $display(
                "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer readDataStorageForOutput IDLE state"),
                ", channel [%0d]", channelIdxWire,
                toBlue(", nextNewOutputCpltTlpInfo="), fshow(nextNewOutputCpltTlpInfo)
            );
        end
    endrule

    // rule debug1;
    //     if (!outputDataStreamGenPipelineQueue.notFull) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE Full!!!  outputDataStreamGenPipelineQueue");
    //     end

    //     if (!outputDataStreamGenPipelineQueue.notEmpty) begin
    //         $display("time=%0t, ", $time, "DEBUG QUEUE EMPTY!!!  outputDataStreamGenPipelineQueue");
    //     end
    //     else begin
    //         let beatMeta = outputDataStreamGenPipelineQueue.first;

    //         if (!dataStreamStorageVec[beatMeta.srcSegIdx].readRespPipeOut.notEmpty) begin
    //             $display("time=%0t, ", $time, "DEBUG QUEUE EMPTY!!!  dataStreamStorageVec[%d].readRespPipeOut", beatMeta.srcSegIdx);
    //         end
    //     end
        
    // endrule

    rule getStorageReadRespAndConvertToDataStream;
        let beatMeta = outputDataStreamGenPipelineQueue.first;
        outputDataStreamGenPipelineQueue.deq;
        
        let readOutBeat = dataStreamStorageVec[beatMeta.srcSegIdx].readRespPipeOut.first;
        dataStreamStorageVec[beatMeta.srcSegIdx].readRespPipeOut.deq;

        BusByteCnt byteNum;
        DwordIdxInUserLogicBeat dwordCntForNextCpltShiftOffset;
        let isFirst = isCurCpltOutputFirstBeatReg;
        let isLast = beatMeta.isLast;
        BusByteIdx startByteIdx = zeroExtend(fromInteger(valueOf(BYTE_CNT_PER_DWOED))-beatMeta.firstBeCnt);


        if (isFirst && isLast) begin
            byteNum = truncate(beatMeta.byteCountLeftInThisTlp);
            dwordCntForNextCpltShiftOffset = truncate((fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - (zeroExtend(startByteIdx) + byteNum)) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
        end
        else if (isFirst) begin
            byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - zeroExtend(startByteIdx);
            dwordCntForNextCpltShiftOffset = 0;
        end
        else if (isLast) begin
            byteNum = truncate(beatMeta.byteCountLeftInThisTlp);
            dwordCntForNextCpltShiftOffset = truncate((fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - byteNum) >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
        end
        else begin
            byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
            dwordCntForNextCpltShiftOffset = 0;
        end

        if (!beatMeta.isLastCplt) begin
            immAssert(
                pack(zeroExtend(startByteIdx) + byteNum)[1:0] == 2'b0,
                "must aligned to 4 dword",
                $format("startByteIdx=", fshow(startByteIdx), ", byteNum=", fshow(byteNum))
            );
        end

        let ds = RtilePcieUserStream {
            data: readOutBeat,
            byteNum: truncate(byteNum),
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };

        let _ <- cpltTlpDataReadOutContinousChecker.putStreamBeatInfo(ds.isFirst, ds.isLast);

        isCurCpltOutputFirstBeatReg <= beatMeta.isLast;

        outputCpltStreamConcatorDataPipeInConverter.enq(ds);
        if (isFirst) begin
            outputCpltStreamConcatorIsLastStreamFlagPipeInConverter.enq(beatMeta.isLastCplt);
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieCompletionBuffer getStorageReadRespAndConvertToDataStream"),
        //     toBlue(", beatMeta="), fshow(beatMeta),
        //     toBlue(", readOutBeat="), fshow(readOutBeat),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule


    interface tagAllocReqPipeIn                                 = toPipeInB0(tagAllocReqPipeInQueue);
    interface tagAllocRespPipeOut                               = toPipeOut(tagAllocRespPipeOutQueue);
    interface tlpRawBeatDataStorageWriteReqPipeIn               = toPipeInB0(tlpRawBeatDataStorageWriteReqPipeInQueue);
    interface cpltTlpVecPipeIn                                  = toPipeInB0(cpltTlpVecPipeInQueue);
    interface sharedHwCpltBufferSlotDeAllocReqPipeOut           = toPipeOut(sharedHwCpltBufferSlotDeAllocReqPipeOutQueue);
    interface dataStreamPipeOut                                 = outputCpltStreamConcator.dataPipeOut;
    
    method setChannelIdx = channelIdxWire._write;
endmodule



typedef DtldStreamMemAccessMeta#(ADDR, Length) PcieStreamMeta;
typedef DtldStreamData#(PcieDataStreamDataLsbRight) PcieStreamData;


typedef struct {
    PcieHeaderFieldLength       length;
    PcieHeaderFieldLastDwBe     lastDwBe;
    PcieHeaderFieldFirstDwBe    firstDwBe;
} PcieLengthAndByteEn deriving(FShow, Bits);

typedef DtldStreamBiDirSlavePipes#(DATA, ADDR, Length)      PcieBiDirUserDataStreamSlavePipes;
typedef DtldStreamBiDirMasterPipes#(DATA, ADDR, Length)     PcieBiDirUserDataStreamMasterPipes;

typedef DtldStreamBiDirSlavePipesB0In#(DATA, ADDR, Length)   PcieBiDirUserDataStreamSlavePipesB0In;
typedef DtldStreamBiDirMasterPipesB0In#(DATA, ADDR, Length) PcieBiDirUserDataStreamMasterPipesB0In;

typedef Bit#(TAdd#(1, TLog#(TDiv#(TMul#(2,ATOMIC_OPERAND_WIDTH), BYTE_WIDTH)))) AtomicOperandCnt;
typedef Tuple2#(Bit#(TMul#(2,ATOMIC_OPERAND_WIDTH)), AtomicOperandCnt) AtomicOperandPack;

interface PcieRequestTlpHeaderGen;
    interface PcieBiDirUserDataStreamSlavePipesB0In                             dtldStreamSlavePipes;
    interface PipeInB0#(PcieTlpHeaderCompletion)                                cpltTlpHeaderPipeIn;
    interface PipeInB0#(RtilePcieUserStream)                                    cpltTlpDataStreamPipeIn;
    
    interface PipeOut#(PcieChannelPrivateCompletionBufferSlotAllocReq)          tagAllocReqPipeOut;
    interface PipeInB0#(PcieHeaderFieldExtendedTag)                               tagAllocRespPipeIn;

    interface PipeOut#(PcieSharedCompletionBufferSlotAllocReq)                  slotAllocReqPipeOut;
    interface PipeInB0#(void)                                                     slotAllocRespPipeIn;

    interface PipeOut#(PcieTlpHeaderBuffer)                                     tlpHeaderBufferPipeOut;
    interface PipeOut#(RtilePcieUserStream)                                     tlpDataStreamPipeOut;
endinterface

(*synthesize*)
module mkPcieRequestTlpHeaderGen#(Byte chIdxForDebug)(PcieRequestTlpHeaderGen);


    PipeInAdapterB0#(DtldStreamMemAccessMeta#(ADDR, Length))  slaveSideQueueWm                <- mkPipeInAdapterB1;  // Note & TODO: change this to B0 will lead cocotb handshake error. should fix cocotb in the future
    PipeInAdapterB0#(RtilePcieUserStream)                     slaveSideQueueWd                <- mkPipeInAdapterB1;  // Note & TODO: change this to B0 will lead cocotb handshake error. should fix cocotb in the future
    PipeInAdapterB0#(DtldStreamMemAccessMeta#(ADDR, Length))  slaveSideQueueRm                <- mkPipeInAdapterB0;
    FIFOF#(RtilePcieUserStream)                               slaveSideQueueRd                <- mkFIFOF;

    PipeInAdapterB0#(RtilePcieUserStream)                     cpltTlpDataStreamPipeInQueue    <- mkPipeInAdapterB0;

    PipeInAdapterB0#(PcieHeaderFieldExtendedTag)                    tagAllocRespPipeInQueue  <- mkPipeInAdapterB0;
    FIFOF#(PcieChannelPrivateCompletionBufferSlotAllocReq)          tagAllocReqPipeOutQueue <- mkFIFOF;

    PipeInAdapterB0#(void)                                            slotAllocRespPipeInQueue <- mkPipeInAdapterB0;
    FIFOF#(PcieSharedCompletionBufferSlotAllocReq)                  slotAllocReqPipeOutQueue <- mkFIFOF;

    FIFOF#(PcieTlpHeaderMemoryRead4Dw)  readTlpQueue                <- mkLFIFOF;
    FIFOF#(AtomicOperandPack) atomicOperandQueue <- mkLFIFOF;
    FIFOF#(PcieTlpHeaderMemoryWrite4Dw) writeTlpQueue               <- mkLFIFOF;
    PipeInAdapterB0#(PcieTlpHeaderCompletion)     cpltTlpQueue        <- mkPipeInAdapterB0;

    FIFOF#(PcieTlpHeaderBuffer)         arbittedTlpBufferQueue      <- mkFIFOF;
    FIFOF#(RtilePcieUserStream)         arbittedTlpDataStreamQueue  <- mkFIFOF;
    Reg#(Bool)                          isOutputingPayloadStreamReg <- mkReg(False);
    
        
    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  tagAllocToReadTlpGenPipelineQ          <- mkLFIFOF;

    // must enable this check since the IP requires the output can not pause between sop and eop.
    let writeStreamFullyPipelineChecker <- mkStreamFullyPipelineChecker(DebugConf{name: "mkPcieRequestTlpHeaderGen writeStreamFullyPipelineChecker", enableDebug: True});

    function Tuple3#(PcieHeaderFieldFirstDwBe, PcieHeaderFieldLastDwBe, Length) genFirstLastBeAndLengthDw(ADDR startAddr, Length len);
        // TODO: can reduce the bit width of the add operation.    
        ADDR endAddr = startAddr + unpack(zeroExtend(pack(len))) - 1;
        let startDwordAddr = startAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        let endDwordAddr = endAddr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
        let lengthInDw = endDwordAddr - startDwordAddr + 1;
        PcieHeaderFieldFirstDwBe    firstDwBe = case (pack(startAddr)[1:0])
                                                    2'b00: 4'b1111;
                                                    2'b01: 4'b1110;
                                                    2'b10: 4'b1100;
                                                    2'b11: 4'b1000;
                                                endcase;

        PcieHeaderFieldLastDwBe     lastDwBe = case (pack(endAddr)[1:0])
                                                    2'b00: 4'b0001;
                                                    2'b01: 4'b0011;
                                                    2'b10: 4'b0111;
                                                    2'b11: 4'b1111;
                                                endcase;

        let isOnlyDword = startDwordAddr == endDwordAddr;
        if (isOnlyDword) begin
            firstDwBe = firstDwBe & lastDwBe;  // use lastDwBe as a bitmask
            lastDwBe = 0;
        end

        return tuple3(firstDwBe, lastDwBe, truncate(lengthInDw));
    endfunction
    
    function Tuple2#(PcieHeaderFieldType, OperandNum) getTlpHeaderType(MemAccessType accessType);
        case (accessType)
            MemAccessTypeNormalReadWrite    : return tuple2(`PCIE_TLP_HEADER_TYPE_MEM_READ, 2'b00);
            MemAccessTypeFetchAdd           : return tuple2(`PCIE_TLP_HEADER_TYPE_FETCH_ADD, 2'b01);
            MemAccessTypeSwap               : return tuple2(`PCIE_TLP_HEADER_TYPE_IO_SWAP, 2'b01);
            MemAccessTypeCAS                : return tuple2(`PCIE_TLP_HEADER_TYPE_IO_CAS, 2'b10);
            default   : return tuple2(5'b00000, 2'b00);  
        endcase
    endfunction

    function AtomicOperandPack generateDataAndByteNum(AtomicOperand operand_1, AtomicOperand operand_2, Bit#(2) opNum, OperandSize opSize);
        Bit#(TMul#(2, ATOMIC_OPERAND_WIDTH)) result = 0;
        if(opNum == 2'b10) begin
            result = {truncate(result), opSize == ONE_DW ? pack(operand_2)[valueOf(DWORD_WIDTH)-1:0] : pack(operand_2), opSize == ONE_DW ? pack(operand_1)[valueOf(DWORD_WIDTH)-1:0] : pack(operand_1)};
        end 
        else if(opNum == 2'b01) begin
            result = {truncate(result), opSize == ONE_DW ? pack(operand_1)[valueOf(DWORD_WIDTH)-1:0] : pack(operand_1)};
        end
        
        AtomicOperandCnt byteNum;
        case (opNum)
            2'b00  : byteNum = 0;
            2'b01  : byteNum = opSize == ONE_DW ? 4 : 8;
            2'b10  : byteNum = opSize == ONE_DW ? 8 : 16;
            default: byteNum = 0;
        endcase
        return tuple2(result, byteNum);
    endfunction

    rule debug;

        // if (!tagAllocReqPipeOutQueue.notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  tagAllocReqPipeOutQueue");
        // end
        // if (!slotAllocReqPipeOutQueue.notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  slotAllocReqPipeOutQueue");
        // end
        // if (!readTlpQueue.notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  readTlpQueue");
        // end
        // if (!writeTlpQueue.notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  writeTlpQueue");
        // end
        // if (!arbittedTlpBufferQueue.notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  arbittedTlpBufferQueue");
        // end
        // if (!arbittedTlpDataStreamQueue.notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  arbittedTlpDataStreamQueue");
        // end
    endrule

    rule genTlpMwr;
        
        let wm = slaveSideQueueWm.first;
        slaveSideQueueWm.deq;


        let {firstDwBe, lastDwBe, lengthInDw} = genFirstLastBeAndLengthDw(wm.addr, wm.totalLen);
        
        let commonHeader = PcieTlpHeaderCommon {
            fmt     : `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA,
            typ     : `PCIE_TLP_HEADER_TYPE_MEM_WRITE,
            t9      : False,
            tc      : 0,
            t8      : False,
            attrh   : False,
            ln      : False,
            th      : False,
            td      : False,
            ep      : False,
            attrl   : wm.noSnoop ? 2'b01 : 2'b00,
            at      : 0,
            length  : unpack(truncate(pack(lengthInDw)))
        };
        
        let memoryWriteHeader = PcieTlpHeaderMemoryWrite {
            commonHeader    : commonHeader,
            requesterId     : 16'h0000,  // will filled by IP core
            st              : 0,
            lastDwBe        : lastDwBe,
            firstDwBe       : firstDwBe
        };

        let tlp = PcieTlpHeaderMemoryWrite4Dw {
            memoryWriteHeader   : memoryWriteHeader,
            addr                : unpack(truncateLSB(pack(wm.addr))),
            ph                  : 0
        };

        writeTlpQueue.enq(tlp);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieRequestTlpHeaderGen genTlpMwr"),
        //     toBlue(", wm="), fshow(wm),
        //     toBlue(", lengthInDw="), fshow(lengthInDw),
        //     toBlue(", firstDwBe="), fshow(firstDwBe),
        //     toBlue(", lastDwBe="), fshow(lastDwBe),
        //     toBlue(", tlp="), fshow(tlp)
        // );


    endrule


    rule sendGenPcieTagReq;
        let rm = slaveSideQueueRm.first;
        slaveSideQueueRm.deq;
        
        immAssert(
            rm.accessType == MemAccessTypeNormalReadWrite || (pack(rm.totalLen) == 4 && pack(rm.addr)[1:0] == 0) || (pack(rm.totalLen) == 8 && pack(rm.addr)[2:0] == 0),
            "the operand size of AtomicOp Request must be 32Bits or 64Bits and the Address must be naturally aligned with the operand size.",
            $format("rm=", fshow(rm))
        );

        ADDR endAddr = rm.addr + unpack(zeroExtend(pack(rm.totalLen))) - 1; 

        let startRcbIdx = rm.addr >> valueOf(TLog#(PCIE_RCB));
        let endRcbIdx = endAddr >> valueOf(TLog#(PCIE_RCB));

        let startHwClptBufDataSlotIdx = rm.addr >> valueOf(TLog#(PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT));
        let endHwClptBufDataSlotIdx = endAddr >> valueOf(TLog#(PCIE_BYTE_PER_HW_CPLT_BUFFER_SLOT));


        let hwClptBufDataSlotCntNeeded = 1 + (endHwClptBufDataSlotIdx - startHwClptBufDataSlotIdx);
        let maxCpltTlpCntNeeded        = 1 + (endRcbIdx - startRcbIdx);

        let tagAllocReq = PcieChannelPrivateCompletionBufferSlotAllocReq {
            hwClptBufDataSlotCntNeeded  : truncate(hwClptBufDataSlotCntNeeded),
            maxCpltTlpCntNeeded         : truncate(maxCpltTlpCntNeeded)
        };

        let slotAllocReq = PcieSharedCompletionBufferSlotAllocReq {
            headerSlotCnt   : truncate(hwClptBufDataSlotCntNeeded),
            dataSlotCnt     : truncate(maxCpltTlpCntNeeded)
        };

        tagAllocReqPipeOutQueue.enq(tagAllocReq);
        slotAllocReqPipeOutQueue.enq(slotAllocReq);
        tagAllocToReadTlpGenPipelineQ.enq(rm);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieRequestTlpHeaderGen sendGenPcieTagReq"),
        //     toBlue(", rm="), fshow(rm)
        // );
    endrule


    rule genTlpMrd;
        
        let rm = tagAllocToReadTlpGenPipelineQ.first;
        tagAllocToReadTlpGenPipelineQ.deq;

        let tag = tagAllocRespPipeInQueue.first;
        tagAllocRespPipeInQueue.deq;

        slotAllocRespPipeInQueue.deq;

        let {firstDwBe, lastDwBe, lengthInDw} = genFirstLastBeAndLengthDw(rm.addr, rm.totalLen);
        let {typ, opNum} = getTlpHeaderType(rm.accessType);

        let commonHeader = PcieTlpHeaderCommon {
            fmt     : (rm.accessType == MemAccessTypeNormalReadWrite) ? `PCIE_TLP_HEADER_FMT_4DW_NO_DATA : `PCIE_TLP_HEADER_FMT_4DW_WITH_DATA,
            typ     : typ,
            t9      : unpack(tag[9]),
            tc      : 0,
            t8      : unpack(tag[8]),
            attrh   : False,
            ln      : False,
            th      : False,
            td      : False,
            ep      : False,
            attrl   : 0,
            at      : 0,
            length  : unpack(truncate(pack(lengthInDw)))
        };
        
        let memoryReadHeader = PcieTlpHeaderMemoryRead {
            commonHeader    : commonHeader,
            requesterId     : 16'h0000,  // will filled by IP core
            tag             : truncate(tag),
            lastDwBe        : lastDwBe,
            firstDwBe       : firstDwBe
        };

        let tlp = PcieTlpHeaderMemoryRead4Dw {
            memoryReadHeader    : memoryReadHeader,
            addr                : unpack(truncateLSB(pack(rm.addr))),
            ph                  : 0
        };

        OperandSize opSize = rm.totalLen == 4 ? ONE_DW : TWO_DW;
        let {data, byteNum} = generateDataAndByteNum(rm.operand_1, rm.operand_2, opNum, opSize);
        readTlpQueue.enq(tlp);
        atomicOperandQueue.enq(tuple2(data, byteNum));
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieRequestTlpHeaderGen genTlpMrd"),
        //     toBlue(", rm="), fshow(rm),
        //     toBlue(", tlp="), fshow(tlp)
        // );
    endrule


    rule arbitOutputTlp if (!isOutputingPayloadStreamReg);
        // we use a fixed priority here. The MWr is for network packet receive, can't be blocked. so it should have the highest priority.
        // for cplt, it will affect the waiting time of the software, and there is few cplt packet, so it has the lowest priority.
        if (writeTlpQueue.notEmpty && slaveSideQueueWd.notEmpty) begin
            arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(writeTlpQueue.first)));
            writeTlpQueue.deq;
            let ds = slaveSideQueueWd.first;
            slaveSideQueueWd.deq;


            arbittedTlpDataStreamQueue.enq(ds);
            if (!ds.isLast) begin
                isOutputingPayloadStreamReg <= True;
            end

            let _ <- writeStreamFullyPipelineChecker.putStreamBeatInfo(ds.isFirst, ds.isLast);
        end
        else if (readTlpQueue.notEmpty) begin
            arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(readTlpQueue.first)));
            readTlpQueue.deq;

            let {data, byteNum} = atomicOperandQueue.first;
            atomicOperandQueue.deq;

            // generate a fake only stream for the payload and header merge.
            let ds = RtilePcieUserStream {
                data        : zeroExtend(data),
                byteNum     : zeroExtend(byteNum),
                startByteIdx: unpack(0),
                isFirst     : True,
                isLast      : True
            };
            arbittedTlpDataStreamQueue.enq(ds);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkPcieRequestTlpHeaderGen arbitOutputTlp readTlpQueue"),
            //     toBlue(", readTlpQueue.first="), fshow(readTlpQueue.first)
            // );
        end
        else if (cpltTlpQueue.notEmpty) begin
            arbittedTlpBufferQueue.enq(zeroExtendLSB(pack(cpltTlpQueue.first)));
            cpltTlpQueue.deq;

            let ds = cpltTlpDataStreamPipeInQueue.first;
            cpltTlpDataStreamPipeInQueue.deq;
            arbittedTlpDataStreamQueue.enq(ds);
            immAssert(
                ds.isFirst && ds.isLast && ds.byteNum <= 8 && ds.startByteIdx <= 3,
                "for read cplt, only support ONLY cplt TLP with max payload not exceed 64-bits",
                $format("ds=", fshow(ds))
            );

            // $display(
            //     "time=%0t:", $time, toGreen(" mkPcieRequestTlpHeaderGen arbitOutputTlp cpltTlpQueue"),
            //     toBlue(", cpltTlpQueue.first="), fshow(cpltTlpQueue.first),
            //     toBlue(", ds="), fshow(ds)
            // );
        end
        
    endrule

    rule arbitOutputDataStream if (isOutputingPayloadStreamReg);
        let ds = slaveSideQueueWd.first;
        slaveSideQueueWd.deq;
        arbittedTlpDataStreamQueue.enq(ds);
        if (ds.isLast) begin
            isOutputingPayloadStreamReg <= False;
        end
        let _ <- writeStreamFullyPipelineChecker.putStreamBeatInfo(ds.isFirst, ds.isLast);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPcieRequestTlpHeaderGen[%d] arbitOutputDataStream"), chIdxForDebug,
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule


    interface DtldStreamBiDirSlavePipesB0In dtldStreamSlavePipes;
        interface DtldStreamSlaveWritePipesB0In writePipeIfc;
            interface  writeMetaPipeIn  = toPipeInB0(slaveSideQueueWm);
            interface  writeDataPipeIn  = toPipeInB0(slaveSideQueueWd);
        endinterface

        interface DtldStreamSlaveReadPipesB0In readPipeIfc;
            interface  readMetaPipeIn  = toPipeInB0(slaveSideQueueRm);
            interface  readDataPipeOut = toPipeOut(slaveSideQueueRd);
        endinterface
    endinterface

    interface cpltTlpDataStreamPipeIn       = toPipeInB0(cpltTlpDataStreamPipeInQueue);

    interface tagAllocReqPipeOut            = toPipeOut(tagAllocReqPipeOutQueue);
    interface tagAllocRespPipeIn            = toPipeInB0(tagAllocRespPipeInQueue);

    interface slotAllocReqPipeOut           = toPipeOut(slotAllocReqPipeOutQueue);
    interface slotAllocRespPipeIn           = toPipeInB0(slotAllocRespPipeInQueue);
    
    interface cpltTlpHeaderPipeIn           = toPipeInB0(cpltTlpQueue);
    interface tlpHeaderBufferPipeOut        = toPipeOut(arbittedTlpBufferQueue);
    interface tlpDataStreamPipeOut          = toPipeOut(arbittedTlpDataStreamQueue);
endmodule






typedef 2                                                   RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT;
typedef Bit#(TLog#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT))    RtilePcieTxPingPongChannelIdx;
typedef TLog#(PCIE_TLP_DATA_SEGMENT_BYTE_WIDTH) RTILE_PCIE_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM;

typedef 256 RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH;  // each row of the buffer stores a double-width-seg
typedef TLog#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH) RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH;
typedef Bit#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH) RtilePcieTxChannelBufferAddr;


// Since the Tx interface only allow new TLP start on it's first and third segment, we can think for the TX path, there are two virtual 
// DOUBLE-WIDTH-SEGMENT in one beat, each double-width-segment is 512 bit in width. so we will mainly focus on handling the double-width-segment
typedef 2 PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG;
typedef Bit#(TLog#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG))                               RtilePcieTxSegIdxInDoubleWidthSeg;
typedef Bit#(TAdd#(1, TLog#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)))                     RtilePcieTxSegCntInDoubleWidthSeg;

typedef TMul#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, PCIE_TLP_DATA_SEGMENT_WIDTH)            RTILE_PCIE_TX_DATA_DOUBLE_WIDTH_SEGMENT_WIDTH;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, RTILE_PCIE_TX_DATA_DOUBLE_WIDTH_SEGMENT_WIDTH)    RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_CNT_PER_USER_INPUT_BEAT; // ?
typedef TLog#(RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_CNT_PER_USER_INPUT_BEAT)                       RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH;
typedef Bit#(RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH)                      RtilePcieTxChannelBufferRowDoubleWidthSegIdx;
typedef RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH                            RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET;

typedef TAdd#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH, RTILE_PCIE_TX_DOUBLE_WIDTH_SEG_INDEX_IN_BUFFER_ROW_WIDTH)    RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DOUBLE_WIDTH_SEG_ADDR_WIDTH;
// The higher part of RtilePcieTxChannelBufferSegAddr is the row address in storage, and the lower part is the seg index in the double-width-seg.
typedef Bit#(RTILE_PCIE_TX_SINGLE_USER_CHANNEL_BUFFER_DOUBLE_WIDTH_SEG_ADDR_WIDTH)                                              RtilePcieTxChannelBufferSegAddr;
typedef RtilePcieTxChannelBufferSegAddr                                                                                         RtilePcieTxChannelBufferSegCnt;  // infact, we can redefine it to a shorter type to just hold a 4kB packte and addtional header part.

// input DATA is buffered in a BRAM, each BRAM row has an address, and we further divide one row into segemnts, and give each segment and index.
// in this way, the higher part of the address is BRAM row address, and the lower part of the address is the segment index inside a row;
typedef TDiv#(SizeOf#(DATA), PCIE_TLP_DATA_SEGMENT_WIDTH)               RTILE_PCIE_TX_SEG_CNT_PER_USER_INPUT_BEAT;
typedef TMax#(1, TLog#(RTILE_PCIE_TX_SEG_CNT_PER_USER_INPUT_BEAT))      RTILE_PCIE_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH;
typedef Bit#(RTILE_PCIE_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH)               RtilePcieTxChannelBufferRowSegIdx;
typedef TLog#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)                     RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET;

typedef enum  {
    RtilePcieFlowControlTlpTypeEnumP,
    RtilePcieFlowControlTlpTypeEnumNP,
    RtilePcieFlowControlTlpTypeEnumCPLT
} RtilePcieFlowControlTlpTypeEnum deriving(FShow, Bits, Eq);


typedef struct {
    RtilePcieTxChannelBufferSegAddr             startSegAddr;
    RtilePcieTxChannelBufferSegCnt              segCnt;
    Bool                                        isStorageRowCountSmall;  // To improve timing
    RtilePcieFlowControlTlpTypeEnum             flowControlTlpType;
    CreditCount                                 flowControlCreditConsumed;
} RtilePcieTxBufferRange deriving(Bits, FShow);


typedef struct {
    RtilePcieUserChannelIdx                         srcChannelIdx;                  // 2
    RtilePcieTxChannelBufferSegAddr                 startSegAddr;                   // 9
    RtilePcieTxChannelBufferSegCnt                  segCnt;                         // 9
    Bool                                            isStorageRowCountSmall;         // 1
    RtilePcieFlowControlTlpTypeEnum                 flowControlTlpType;             // 2
    CreditCount                                     flowControlCreditConsumed;      // 16
    ReservedZero#(25)                               reserved;                       // make this struct's size is power of two, or the MIMO FIFO will use dsp block to implement multiply operation. cause very bad timing.
} RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset deriving(Bits, FShow);

typedef struct {
    RtilePcieUserChannelIdx             srcChannelIdx;
    RtilePcieTxChannelBufferAddr        startRowAddr;
    PcieSegmentIdx                      zeroBasedSegCnt;
    Bool                                isFirst;
    Bool                                isLast;
    // Bool                                isOutputBeatLast;
} RtilePcieTxPingPongChannelMetaEntry deriving(Bits, FShow);


interface RtilePcieTxUserInputGearboxStorageAndMetaExtractor;
    interface PipeInB0#(RtilePcieUserStream)                          streamPipeIn;
    interface PipeInB0#(PcieTlpHeaderBuffer)                          txTlpHeaderBufferPipeIn;
    interface PipeOut#(RtilePcieTxBufferRange)                      packetMetaPipeOut;

    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(RtilePcieTxBramBufferReadReq))  bramReadReqPipeInVec;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, DATA)))  bramReadRespPipeOutVec;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(PcieTlpHeaderBuffer))  bramTlpHeaderReadRespPipeOutVec;
endinterface

(* synthesize *)
module mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor#(Byte chIdxForDebug)(RtilePcieTxUserInputGearboxStorageAndMetaExtractor);
    PipeInAdapterB0#(RtilePcieUserStream)             streamPipeInQueue               <- mkPipeInAdapterB0;
    PipeInAdapterB0#(PcieTlpHeaderBuffer)             txTlpHeaderBufferPipeInQueue    <- mkPipeInAdapterB0;
    FIFOF#(RtilePcieTxBufferRange)                  packetMetaPipeOutQueue          <- mkSizedFIFOF(16);//buffer req when pingpoongfork blocked

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(RtilePcieTxBramBufferReadReq)) bramReadReqPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeInAdapterB0#(RtilePcieTxBramBufferReadReq)) bramReadReqPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, DATA))) bramReadRespPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, DATA))) bramReadRespPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(PcieTlpHeaderBuffer)) bramTlpHeaderReadRespPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(PcieTlpHeaderBuffer)) bramTlpHeaderReadRespPipeOutQueueVec <- replicateM(mkFIFOF);
    
    for (Integer idx=0; idx < valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG); idx = idx + 1) begin
        bramReadReqPipeInVecInst[idx]               = toPipeInB0(bramReadReqPipeInQueueVec[idx]);
        bramReadRespPipeOutVecInst[idx]             = toPipeOut(bramReadRespPipeOutQueueVec[idx]);
        bramTlpHeaderReadRespPipeOutVecInst[idx]    = toPipeOut(bramTlpHeaderReadRespPipeOutQueueVec[idx]);
    end

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, 
            Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, 
                    AutoInferBramQueuedOutput#(RtilePcieTxChannelBufferAddr, DATA)))  dataStreamStorageVec  <- replicateM(replicateM(mkAutoInferBramQueuedOutput(False, "", "mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor dataStreamStorageVec")));

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, 
            AutoInferBramQueuedOutput#(RtilePcieTxChannelBufferAddr, PcieTlpHeaderBuffer))  tlpHeaderStorageVec  <- replicateM(mkAutoInferBramQueuedOutput(False, "", "mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor tlpHeaderStorageVec"));

    Reg#(RtilePcieTxChannelBufferAddr)      curRowAddrReg               <- mkReg(0);
    Reg#(RtilePcieTxChannelBufferAddr)      startRowAddrReg             <- mkReg(0);
    Reg#(RtilePcieTxChannelBufferSegCnt)    curSegCntReg                <- mkReg(0);
    Reg#(Bool)                              isFirstReg                  <- mkReg(True);
    Reg#(Tuple2#(RtilePcieFlowControlTlpTypeEnum, CreditCount)) tlpFlowControlCreditReg <- mkRegU;


    // rule debug;
    //     if (!streamPipeInQueue.notFull) begin
    //         $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug"),  toBlue(", streamPipeInQueue is Full"));
    //     end

    //     if (!packetMetaPipeOutQueue.notFull) begin
    //         $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug"),  toBlue(", packetMetaPipeOutQueue is Full"));
    //     end
    //     for (Integer idx=0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
    //         if (!bramReadReqPipeInQueueVec[idx].notFull) begin
    //             $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug [idx=%d]"), idx, toBlue(", bramReadReqPipeInQueueVec is Full"));
    //         end
    //         if (!bramReadRespPipeOutQueueVec[idx].notFull) begin
    //             $display("time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor debug [idx=%d]"), idx, toBlue(", bramReadRespPipeOutQueueVec is Full"));
    //         end
    //     end
    // endrule


    for (Integer idx=0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        rule handleStorageReadReq;
            let req = bramReadReqPipeInQueueVec[idx].first;
            bramReadReqPipeInQueueVec[idx].deq;
            for (Integer segIdx = 0; segIdx < valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG); segIdx = segIdx + 1) begin
                dataStreamStorageVec[idx][segIdx].putReadReq(req.addr);
            end
            if (req.needReadTlpBuffer) begin
                tlpHeaderStorageVec[idx].putReadReq(req.addr);
            end
        endrule

        rule handlePayloadStorageReadResp;
            Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, DATA) outputVec = newVector;
            for (Integer segIdx = 0; segIdx < valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG); segIdx = segIdx + 1) begin
                outputVec[segIdx] = dataStreamStorageVec[idx][segIdx].readRespPipeOut.first;
                dataStreamStorageVec[idx][segIdx].readRespPipeOut.deq;
            end

            bramReadRespPipeOutQueueVec[idx].enq(outputVec);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor handlePayloadStorageReadResp [idx=%d]"), idx,
            //     toBlue(", outputVec="), fshow(outputVec)
            // );
        endrule

        rule handleTlpStorageReadResp;
            let resp = tlpHeaderStorageVec[idx].readRespPipeOut.first;
            tlpHeaderStorageVec[idx].readRespPipeOut.deq;
            bramTlpHeaderReadRespPipeOutQueueVec[idx].enq(resp);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor handleTlpStorageReadResp [idx=%d]"), idx,
            //     toBlue(", resp="), fshow(resp)
            // );
        endrule
    end

    rule handleMetaCalc;
        let ds = streamPipeInQueue.first;
        streamPipeInQueue.deq;

        let                                 curSegCnt               = curSegCntReg;
        RtilePcieTxSegIdxInDoubleWidthSeg   curIdxInDoubleWidthSeg  = truncate(curSegCnt);

        let newSegCnt = curSegCnt + fromInteger(valueOf(RTILE_PCIE_TX_SEG_CNT_PER_USER_INPUT_BEAT));
        let nextBeatRowAddr = lsb(curSegCnt) == 1 ? curRowAddrReg + 1 : curRowAddrReg;

        let tlpFlowControlCredit = tlpFlowControlCreditReg;
        if (isFirstReg) begin
            let tlpHeaderBuf = txTlpHeaderBufferPipeInQueue.first;
            txTlpHeaderBufferPipeInQueue.deq;
            for (Integer idx = 0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
                tlpHeaderStorageVec[idx].write(curRowAddrReg, tlpHeaderBuf);
            end


            let {isPostTlp, isNonPostedTlp, isCpltTlp, pdCredit, npdCredit, cpldCredit} = getFlowControlCreditFromRxTlp(tlpHeaderBuf);
            case ({pack(isPostTlp), pack(isNonPostedTlp), pack(isCpltTlp)}) 
                3'b100: tlpFlowControlCredit = tuple2(RtilePcieFlowControlTlpTypeEnumP, pdCredit);
                3'b010: tlpFlowControlCredit = tuple2(RtilePcieFlowControlTlpTypeEnumNP, npdCredit);
                3'b001: tlpFlowControlCredit = tuple2(RtilePcieFlowControlTlpTypeEnumCPLT, cpldCredit);
                default: immFail("should not reach here", $format("credit info = ", fshow(getFlowControlCreditFromRxTlp(tlpHeaderBuf))));
            endcase
            tlpFlowControlCreditReg <= tlpFlowControlCredit;
        end

        if (ds.isLast) begin

            let {flowControlTlpType, flowControlCreditConsumed} = tlpFlowControlCredit;
            let outputEntry = RtilePcieTxBufferRange {
                startSegAddr                : zeroExtend(startRowAddrReg) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET),
                segCnt                      : newSegCnt,
                isStorageRowCountSmall      : (newSegCnt >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)),
                flowControlTlpType          : flowControlTlpType,
                flowControlCreditConsumed   : flowControlCreditConsumed
            };
            packetMetaPipeOutQueue.enq(outputEntry);
            newSegCnt = 0;

            startRowAddrReg <=  curRowAddrReg + 1;
            nextBeatRowAddr =   curRowAddrReg + 1;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor[%d] handleMetaCalc"), chIdxForDebug,
            //     toBlue(", outputEntry="), fshow(outputEntry)
            // );
        end

        for (Integer idx = 0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx][curIdxInDoubleWidthSeg].write(curRowAddrReg, ds.data);
        end

        curSegCntReg  <= newSegCnt;
        curRowAddrReg <= nextBeatRowAddr;
        isFirstReg <= ds.isLast;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor[%d] handleMetaCalc BRAMwrite"), chIdxForDebug,
        //     toBlue(", curRowAddrReg="), fshow(curRowAddrReg),
        //     toBlue(", curSegCntReg="), fshow(curSegCntReg),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface streamPipeIn                      = toPipeInB0(streamPipeInQueue);
    interface txTlpHeaderBufferPipeIn           = toPipeInB0(txTlpHeaderBufferPipeInQueue);
    interface packetMetaPipeOut                 = toPipeOut(packetMetaPipeOutQueue);
    interface bramReadReqPipeInVec              = bramReadReqPipeInVecInst;
    interface bramTlpHeaderReadRespPipeOutVec   = bramTlpHeaderReadRespPipeOutVecInst;
    interface bramReadRespPipeOutVec            = bramReadRespPipeOutVecInst;
endmodule


typedef 2 RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT;  // from user guide, new tlp can only start on seg 0 and 2, so max two new packet per beat.
typedef 2 RTILE_PCIE_TX_MAX_PACKET_PER_BEAT;
typedef TDiv#(PCIE_TLP_DATA_BUNDLE_WIDTH, RTILE_PCIE_TX_DATA_DOUBLE_WIDTH_SEGMENT_WIDTH) RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT;  // 2
typedef Bit#(TLog#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT)) RtilePcieTxOutputBeatNewPacketIndex;

typedef Bit#(TLog#(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) RtilePcieTxBramRowIndexInOutputBeat;
typedef TAdd#(1, TLog#(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_WIDTH;
typedef TAdd#(1, RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_WIDTH) RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_SUM_RESULT_WIDTH;
typedef Bit#(RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_WIDTH) RtilePcieTxSmallBramRowCnt;
typedef Bit#(RTILE_PCIE_TX_SMALL_BRAM_ROW_COUNT_SUM_RESULT_WIDTH) RtilePcieTxSmallBramRowCntSumResult;


typedef Vector#(RTILE_PCIE_TX_MAX_PACKET_PER_BEAT, Maybe#(RtilePcieTxPingPongChannelMetaEntry)) RtilePcieTxPingPongChannelMetaBundle;

interface RtilePcieTxPingPongFork;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(RtilePcieTxBufferRange)) packetMetaPipeInVec;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(RtilePcieTxPingPongChannelMetaBundle))  pingpongChannelMetaPipeOutVec;
    interface PipeOut#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))   txFlowControlConsumeReqPipeOut;
    interface PipeIn#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    txFlowControlAvaliablePipeIn;
endinterface

(* synthesize *)
module mkRtilePcieTxPingPongFork(RtilePcieTxPingPongFork);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(RtilePcieTxBufferRange)) packetMetaPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInAdapterB0#(RtilePcieTxBufferRange)) packetMetaPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeOut#(RtilePcieTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, FIFOF#(RtilePcieTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    
    FIFOF#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    txFlowControlConsumeReqPipeOutQueue <- mkFIFOF;
    FIFOF#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))    txFlowControlAvaliablePipeInQueue <- mkLFIFOF;

    for (Integer idx=0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        packetMetaPipeInVecInst[idx] = toPipeInB0(packetMetaPipeInQueueVec[idx]);
    end

    for (Integer idx=0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        pingpongChannelMetaPipeOutVecInst[idx] = toPipeOut(pingpongChannelMetaPipeOutQueueVec[idx]);
    end


    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Reg#(Maybe#(RtilePcieTxBufferRange))) curDataRangeRegVec <- replicateM(mkReg(tagged Invalid));
    Reg#(RtilePcieUserChannelIdx)       curInputRoundRobinIdxReg <- mkReg(0);
    Reg#(RtilePcieTxPingPongChannelIdx) curOutputRoundRobinIdxReg <- mkReg(0);
    // Reg#(RtilePcieTxChannelBufferRowSegIdx) prevDestSegOffsetReg <- mkReg(0);

    let mimoCfg = MIMOConfiguration {
        unguarded: False,
        bram_based: False
    };
    MIMO#(
        RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT,
            RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT,
            TMul#(2, RTILE_PCIE_USER_LOGIC_CHANNEL_CNT),
            RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset
    ) selectedInputChannelMetaMIMO <- mkMIMO(mimoCfg);
    

    Reg#(Maybe#(RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset)) curMetaMaybeReg <- mkReg(tagged Invalid);
    Reg#(Bool) isFirstReg <- mkReg(True);

    // Pipeline Queues
    FIFOF#(Tuple2#(
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset),
        LUInt#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT)
    ))  flowControlCheckPipelineQueue <- mkLFIFOF;
    FIFOF#(Tuple2#(
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset),
        LUInt#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT)
    ))  mimoInputPipelineQueue <- mkLFIFOF;

    FIFOF#(RtilePcieTxPingPongChannelMetaBundle) outputTimingFixPipelineQueue <- mkFIFOFWithFullAssert(DebugConf{name:"mkRtilePcieTxPingPongFork outputTimingFixPipelineQueue",enableDebug:True});

    rule debug;
        // if (!txFlowControlAvaliablePipeInQueue.notEmpty) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE EMPTY!!!  txFlowControlAvaliablePipeInQueue");
        // end
        // else begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE Not EMPTY!!!  txFlowControlAvaliablePipeInQueue.first=", fshow(txFlowControlAvaliablePipeInQueue.first));
        // end

        // if (!flowControlCheckPipelineQueue.notEmpty) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE EMPTY!!!  flowControlCheckPipelineQueue");
        // end
        // else begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE Not EMPTY!!!  flowControlCheckPipelineQueue.first=", fshow(flowControlCheckPipelineQueue.first));
        // end

        // if (!pingpongChannelMetaPipeOutQueueVec[0].notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  pingpongChannelMetaPipeOutQueueVec[0]");
        // end

        // if (!pingpongChannelMetaPipeOutQueueVec[1].notFull) begin
        //     $display("time=%0t, ", $time, "DEBUG QUEUE FULL!!!  pingpongChannelMetaPipeOutQueueVec[1]");
        // end
        
    endrule


    rule guard;
        immAssert(
            valueOf(SizeOf#(RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset)) == valueOf(TExp#(TLog#(SizeOf#(RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset)))),
            "the size of RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset must be 2's power",
            $format("")
        );
    endrule

    rule prepareRoundRobinChannelOrder;
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset) vecToEnq = newVector;
        Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, Bool) needDeqFlagVec = replicate(False);
        let curInputRoundRobinIdx = curInputRoundRobinIdxReg;
        let enqCnt = 0;
        let inputQueueStatus = {
            pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].notEmpty),
            pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].notEmpty),
            pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].notEmpty),
            pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].notEmpty)
        };
        case (inputQueueStatus) matches
            4'b0000: begin
            end
            4'b0001: begin
                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+3,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt, 
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 1;
            end
            4'b0010: begin
                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+2,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt,
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 1;
            end
            4'b0011: begin
                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+2,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt, 
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+3,
                    startSegAddr                : inMeta1.startSegAddr, 
                    segCnt                      : inMeta1.segCnt, 
                    isStorageRowCountSmall      : inMeta1.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta1.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta1.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b0100: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+1,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt,
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall, 
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 1;
            end
            4'b0101: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+1,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt, 
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+3,
                    startSegAddr                : inMeta1.startSegAddr, 
                    segCnt                      : inMeta1.segCnt, 
                    isStorageRowCountSmall      : inMeta1.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta1.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta1.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b011?: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+1,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt, 
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };

                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+2,
                    startSegAddr                : inMeta1.startSegAddr, 
                    segCnt                      : inMeta1.segCnt, 
                    isStorageRowCountSmall      : inMeta1.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta1.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta1.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b1000: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+0,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt,
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                curInputRoundRobinIdx = curInputRoundRobinIdx + 1;
                enqCnt = 1;
            end
            4'b1001: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+0,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt, 
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+3,
                    startSegAddr                : inMeta1.startSegAddr, 
                    segCnt                      : inMeta1.segCnt, 
                    isStorageRowCountSmall      : inMeta1.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta1.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta1.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b101?: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+0,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt, 
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                // prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+2,
                    startSegAddr                : inMeta1.startSegAddr, 
                    segCnt                      : inMeta1.segCnt, 
                    isStorageRowCountSmall      : inMeta1.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta1.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta1.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b11??: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+0,
                    startSegAddr                : inMeta0.startSegAddr, 
                    segCnt                      : inMeta0.segCnt, 
                    isStorageRowCountSmall      : inMeta0.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta0.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta0.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };

                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[1] = RtilePcieTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx               : curInputRoundRobinIdx+1,
                    startSegAddr                : inMeta1.startSegAddr, 
                    segCnt                      : inMeta1.segCnt, 
                    isStorageRowCountSmall      : inMeta1.isStorageRowCountSmall,
                    flowControlTlpType          : inMeta1.flowControlTlpType,
                    flowControlCreditConsumed   : inMeta1.flowControlCreditConsumed,
                    reserved                    : unpack(0)
                };
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 2;
            end
        endcase

        
        if (enqCnt != 0) begin
            curInputRoundRobinIdxReg <= curInputRoundRobinIdx;

            if (needDeqFlagVec[0] == True) begin
                packetMetaPipeInQueueVec[0].deq;
            end
            if (needDeqFlagVec[1] == True) begin
                packetMetaPipeInQueueVec[1].deq;
            end
            if (needDeqFlagVec[2] == True) begin
                packetMetaPipeInQueueVec[2].deq;
            end
            if (needDeqFlagVec[3] == True) begin
                packetMetaPipeInQueueVec[3].deq;
            end
        end

        flowControlCheckPipelineQueue.enq(tuple2(vecToEnq, enqCnt));

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork prepareRoundRobinChannelOrder"),
        //     toBlue(", inputQueueStatus="), fshow(inputQueueStatus),
        //     toBlue(", enqCnt="), fshow(enqCnt),
        //     toBlue(", vecToEnq="), fshow(vecToEnq)
        // );
    endrule

    rule checkFlowControlCredit;
        let {vecToEnq, enqCnt} = flowControlCheckPipelineQueue.first;
        
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, Bool) txFlowControlCreditToConsumePh = replicate(False);
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, Bool) txFlowControlCreditToConsumeNph = replicate(False);
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, Bool) txFlowControlCreditToConsumeCplh = replicate(False);

        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, CreditCount) txFlowControlCreditToConsumePd = replicate(unpack(0));
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, CreditCount) txFlowControlCreditToConsumeNpd = replicate(unpack(0));
        Vector#(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT, CreditCount) txFlowControlCreditToConsumeCpld = replicate(unpack(0));

        for (Integer tlpIdx = 0; tlpIdx < valueOf(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT); tlpIdx = tlpIdx + 1) begin
            
            let isThisSlotValid = fromInteger(tlpIdx+1) <= enqCnt;
            let creditToConsume = isThisSlotValid ? vecToEnq[tlpIdx].flowControlCreditConsumed : 0;

            case (vecToEnq[tlpIdx].flowControlTlpType)
                RtilePcieFlowControlTlpTypeEnumP: begin
                    txFlowControlCreditToConsumePh[tlpIdx] = isThisSlotValid;
                    txFlowControlCreditToConsumePd[tlpIdx] = creditToConsume;
                end
                RtilePcieFlowControlTlpTypeEnumNP: begin
                    txFlowControlCreditToConsumeNph[tlpIdx] = isThisSlotValid;
                    txFlowControlCreditToConsumeNpd[tlpIdx] = creditToConsume;
                end
                RtilePcieFlowControlTlpTypeEnumCPLT: begin
                    txFlowControlCreditToConsumeCplh[tlpIdx] = isThisSlotValid;
                    txFlowControlCreditToConsumeCpld[tlpIdx] = creditToConsume;
                end
                default: begin
                    immFail("should not reach here", $format("vecToEnq=", fshow(vecToEnq)));
                end
            endcase
        end

        CreditCount phToConsume     = 0;
        CreditCount nphToConsume    = 0;
        CreditCount cplhToConsume   = 0;
        CreditCount pdToConsume     = 0;
        CreditCount npdToConsume    = 0;
        CreditCount cpldToConsume   = 0;

        for (Integer tlpIdx = 0; tlpIdx < valueOf(RTILE_PCIE_TX_MAX_NEW_PACKET_PER_BEAT); tlpIdx = tlpIdx + 1) begin
            phToConsume = phToConsume + zeroExtend(pack(txFlowControlCreditToConsumePh[tlpIdx]));
            nphToConsume = nphToConsume + zeroExtend(pack(txFlowControlCreditToConsumeNph[tlpIdx]));
            cplhToConsume = cplhToConsume + zeroExtend(pack(txFlowControlCreditToConsumeCplh[tlpIdx]));
            pdToConsume = pdToConsume + txFlowControlCreditToConsumePd[tlpIdx];
            npdToConsume = npdToConsume + txFlowControlCreditToConsumeNpd[tlpIdx];
            cpldToConsume = cpldToConsume + txFlowControlCreditToConsumeCpld[tlpIdx];
        end

        // txFlowControlAvaliablePipeInQueue is filled by a "always enabled" rule, so we must consume it as soon as possible, no matter have tlps or not.
        // so, this rule should not be blocked.
        let {availableCreditPh, availableCreditNph, availableCreditCplh, availableCreditPd, availableCreditNpd, availableCreditCpld} = txFlowControlAvaliablePipeInQueue.first;
        txFlowControlAvaliablePipeInQueue.deq;

        let hasEnoughCredit =   phToConsume <= availableCreditPh        && 
                                nphToConsume <= availableCreditNph      &&
                                pdToConsume <= availableCreditPd        &&
                                npdToConsume <= availableCreditNpd;
                                // note cplh and cpld should be infinite, no need to check
                                // cplhToConsume <= availableCreditCplh    &&
                                // cpldToConsume <= availableCreditCpld;

        if (enqCnt == 0) begin
            flowControlCheckPipelineQueue.deq;
        end
        else if (hasEnoughCredit) begin

            // IMPORTANT!!!!
            // since MIMO's enq doesn't have guard (infact, it has guard, but the guard only check if it can enq at least one element), to make sure 
            // there are enough space for `enqCnt`, we can't relay on enq's guard to block the rule from being fired.
            // so, we need to move all the "Actions"(i.e., code that will change the state) into the following IF block. And only leave combinational logic
            // out of the IF block
            if (enqCnt != 0 && selectedInputChannelMetaMIMO.enqReadyN(enqCnt)) begin
                flowControlCheckPipelineQueue.deq;
                selectedInputChannelMetaMIMO.enq(enqCnt, vecToEnq);
                txFlowControlConsumeReqPipeOutQueue.enq(tuple6(phToConsume, nphToConsume, cplhToConsume, pdToConsume, npdToConsume, cpldToConsume));
                // $display(
                //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork checkFlowControlCredit enough credit, pass"),
                //     toBlue(", enqCnt="), fshow(enqCnt),
                //     toBlue(", vecToEnq="), fshow(vecToEnq)
                // );
            end
        end
        else begin
            $display(
                "time=%0t:", $time, toRed(" mkRtilePcieTxPingPongFork checkFlowControlCredit No enough credit for tx"),
                toBlue(", phToConsume="), fshow(phToConsume),
                toBlue(", availableCreditPh="), fshow(availableCreditPh),
                toBlue(", nphToConsume="), fshow(nphToConsume),
                toBlue(", availableCreditNph="), fshow(availableCreditNph),
                toBlue(", cplhToConsume="), fshow(cplhToConsume),
                toBlue(", availableCreditCplh="), fshow(availableCreditCplh),
                toBlue(", pdToConsume="), fshow(pdToConsume),
                toBlue(", availableCreditPd="), fshow(availableCreditPd),
                toBlue(", npdToConsume="), fshow(npdToConsume),
                toBlue(", availableCreditNpd="), fshow(availableCreditNpd),
                toBlue(", cpldToConsume="), fshow(cpldToConsume),
                toBlue(", availableCreditCpld="), fshow(availableCreditCpld)
            );
        end
    endrule

    // rule forwardRoundRobinResultToMimoBuffer;
    //     let {vecToEnq, enqCnt} = mimoInputPipelineQueue.first;
    //     mimoInputPipelineQueue.deq;
    //     if (enqCnt != 0) begin
    //         selectedInputChannelMetaMIMO.enq(enqCnt, vecToEnq);
    //     end
    // endrule


    rule dispatch;
        RtilePcieTxPingPongChannelMetaBundle outputMetaBundle = replicate(tagged Invalid);

        if (curMetaMaybeReg matches tagged Valid .curMeta) begin

            let onePacketMetaAvailable      = True;
            let twoPacketMetaAvailable      = selectedInputChannelMetaMIMO.deqReadyN(1);

            let packetOneMeta   = curMeta;
            let packetTwoMeta   = twoPacketMetaAvailable ? selectedInputChannelMetaMIMO.first[0] : ?;

            RtilePcieTxSmallBramRowCnt packetOneSmallBramRowCnt   = truncate((packetOneMeta.segCnt - 1) >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) + 1;
            RtilePcieTxSmallBramRowCnt packetTwoSmallBramRowCnt   = truncate((packetTwoMeta.segCnt - 1)  >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) + 1;

            RtilePcieTxSmallBramRowCntSumResult onePacketSmallBramRowCntSum   =                               zeroExtend(packetOneSmallBramRowCnt);
            RtilePcieTxSmallBramRowCntSumResult twoPacketSmallBramRowCntSum   = onePacketSmallBramRowCntSum + zeroExtend(packetTwoSmallBramRowCnt);

            let packetOneWillEndInThisBeat   = packetOneMeta.isStorageRowCountSmall   && onePacketSmallBramRowCntSum   <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            let packetTwoWillEndInThisBeat   = packetTwoMeta.isStorageRowCountSmall   && twoPacketSmallBramRowCntSum   <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            
            let beatWillHoldOnePacket   = onePacketMetaAvailable;
            let beatWillHoldTwoPacket   = twoPacketMetaAvailable   && packetOneMeta.isStorageRowCountSmall && onePacketSmallBramRowCntSum < fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));

            RtilePcieTxSmallBramRowCnt smallStorgeRowCntLeftForPacketOne     = fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            RtilePcieTxSmallBramRowCnt smallStorgeRowCntLeftForPacketTwo     = fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) - truncate(onePacketSmallBramRowCntSum);

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch"),
            //     toBlue(", beatWillHoldPacket="), fshow(beatWillHoldTwoPacket ? 2 : 1),
            //     toBlue(", packetOneSmallBramRowCnt="), fshow(packetOneSmallBramRowCnt),
            //     toBlue(", packetTwoSmallBramRowCnt="), fshow(packetTwoSmallBramRowCnt),
            //     toBlue(", onePacketSmallBramRowCntSum="), fshow(onePacketSmallBramRowCntSum),
            //     toBlue(", twoPacketSmallBramRowCntSum="), fshow(twoPacketSmallBramRowCntSum),
            //     toBlue(", smallStorgeRowCntLeftForPacketOne="), fshow(smallStorgeRowCntLeftForPacketOne),
            //     toBlue(", smallStorgeRowCntLeftForPacketTwo="), fshow(smallStorgeRowCntLeftForPacketTwo),
            //     toBlue(", packetOneMeta="), fshow(packetOneMeta),
            //     toBlue(", packetTwoMeta="), fshow(packetTwoMeta)
            // );

            if (beatWillHoldTwoPacket) begin
                outputMetaBundle[0] = tagged Valid RtilePcieTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetOneMeta.segCnt-1),
                    isFirst         : isFirstReg,        
                    isLast          : True
                };
                outputMetaBundle[1] = tagged Valid RtilePcieTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetTwoMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetTwoMeta.startSegAddr),
                    zeroBasedSegCnt : packetTwoWillEndInThisBeat ? truncate(packetTwoMeta.segCnt-1) : ((zeroExtend(smallStorgeRowCntLeftForPacketTwo) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) - 1),
                    isFirst         : True,
                    isLast          : packetTwoWillEndInThisBeat
                    // isOutputBeatLast: 
                };


                // immAssert(selectedInputChannelMetaMIMO.deqReadyN(1), "MIMO Queue doesn't have enough element", $format(""));
                if (packetTwoWillEndInThisBeat) begin
                    if(selectedInputChannelMetaMIMO.deqReadyN(2))begin //if more than 1 req in the MIMO,move the second one into curMetaMaybeReg directly
                        curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[1];
                        isFirstReg <= True;
                        selectedInputChannelMetaMIMO.deq(2);
                    end else begin 
                        curMetaMaybeReg <= tagged Invalid;
                        isFirstReg <= True;
                        selectedInputChannelMetaMIMO.deq(1);
                    end
                end
                else begin
                    let nextCurMeta                     = packetTwoMeta;
                    let segCntDelta                     = zeroExtend(smallStorgeRowCntLeftForPacketTwo) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET);
                    nextCurMeta.startSegAddr            = nextCurMeta.startSegAddr + segCntDelta;
                    nextCurMeta.segCnt                  = nextCurMeta.segCnt - segCntDelta;
                    nextCurMeta.isStorageRowCountSmall  = (nextCurMeta.segCnt >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
                    curMetaMaybeReg                     <= tagged Valid nextCurMeta;
                    isFirstReg                          <= False;
                    selectedInputChannelMetaMIMO.deq(1);
                end
            end
            else if (beatWillHoldOnePacket) begin
                outputMetaBundle[0] = tagged Valid RtilePcieTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : packetOneWillEndInThisBeat ? truncate(packetOneMeta.segCnt - 1) : ((zeroExtend(smallStorgeRowCntLeftForPacketOne) << valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) - 1),
                    isFirst         : isFirstReg,
                    isLast          : packetOneWillEndInThisBeat
                };

                if (packetOneWillEndInThisBeat) begin
                    if (selectedInputChannelMetaMIMO.deqReadyN(1)) begin
                        curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[0];
                        selectedInputChannelMetaMIMO.deq(1);
                    end
                    else begin
                        curMetaMaybeReg <= tagged Invalid;
                    end
                    isFirstReg <= True;
                end
                else begin
                    let nextCurMeta                     = packetOneMeta;
                    let segCntDelta                     = fromInteger(valueOf(PCIE_SEGMENT_CNT));
                    nextCurMeta.startSegAddr            = nextCurMeta.startSegAddr + segCntDelta;
                    nextCurMeta.segCnt                  = nextCurMeta.segCnt - segCntDelta;
                    nextCurMeta.isStorageRowCountSmall  = (nextCurMeta.segCnt >> valueOf(RTILE_PCIE_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
                    curMetaMaybeReg                     <= tagged Valid nextCurMeta;
                    isFirstReg                          <= False;
                end
            end
            else begin
                immFail("should not reach here", $format(""));
            end

            outputTimingFixPipelineQueue.enq(outputMetaBundle);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch final output"),
            //     toBlue(", curOutputRoundRobinIdxReg="), fshow(curOutputRoundRobinIdxReg),
            //     toBlue(", outputMetaBundle="), fshow(outputMetaBundle)
            // );

        end
        else begin
            if (selectedInputChannelMetaMIMO.deqReadyN(1)) begin
                curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[0];
                selectedInputChannelMetaMIMO.deq(1);
                // $display(
                //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch IDLE"),
                //     toBlue(", selectedInputChannelMetaMIMO.first[0]="), fshow(selectedInputChannelMetaMIMO.first[0])
                // );
            end
            else begin
                // $display(
                //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork dispatch IDLE and not new packet")
                // );
            end
        end
    endrule

    rule forwardOutput;
        let outputMetaBundle = outputTimingFixPipelineQueue.first;
        outputTimingFixPipelineQueue.deq;
        curOutputRoundRobinIdxReg <= curOutputRoundRobinIdxReg + 1;
        pingpongChannelMetaPipeOutQueueVec[curOutputRoundRobinIdxReg].enq(outputMetaBundle);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongFork forwardOutput"),
        //     toBlue(", outputMetaBundle="), fshow(outputMetaBundle)
        // );
    endrule

    
    interface packetMetaPipeInVec = packetMetaPipeInVecInst;
    interface pingpongChannelMetaPipeOutVec = pingpongChannelMetaPipeOutVecInst;
    interface txFlowControlConsumeReqPipeOut = toPipeOut(txFlowControlConsumeReqPipeOutQueue);
    interface txFlowControlAvaliablePipeIn = toPipeIn(txFlowControlAvaliablePipeInQueue);
endmodule



typedef struct {
    RtilePcieTxChannelBufferAddr    addr;
    Bool                            needReadTlpBuffer;
} RtilePcieTxBramBufferReadReq deriving (FShow, Bits);

typedef struct {
    RtilePcieUserChannelIdx             srcChannelIdx;
    RtilePcieTxChannelBufferRowSegIdx   zeroBasedValidSegCnt;
    Bool                                isFirst;
    Bool                                isLast;
    Bool                                isOutputBeatLast;
} RtilePcieTxPingPongChannelBramReadPipelineEntry deriving (FShow, Bits);


typedef struct {
    PcieTlpDataBusSegBundle             dataBuf;
    PcieTlpHeaderBusSegBundle           header;
    SopSignalBundle                     sop;
    EopSignalBundle                     eop;
    HvalidSignalBundle                  hvalid;
    DvalidSignalBundle                  dvalid;
} RtilePcieTxPingPongChannelOutputEntry deriving (FShow, Bits);

interface RtilePcieTxPingPongSingleChannel;
    interface PipeInB0#(RtilePcieTxPingPongChannelMetaBundle)      metaPipeIn;
    interface PipeOut#(RtilePcieTxPingPongChannelOutputEntry)    beatPipeOut;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieTxBramBufferReadReq))  bramReadReqPipeOutVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(PcieTlpHeaderBuffer))    bramTlpHeaderReadRespPipeInVec;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, DATA)))    bramReadRespPipeInVec;
endinterface

(* synthesize *)
module mkRtilePcieTxPingPongSingleChannel#(Byte chIdxForDebug)(RtilePcieTxPingPongSingleChannel);
    PipeInAdapterB0#(RtilePcieTxPingPongChannelMetaBundle)  metaPipeInQueue       <- mkPipeInAdapterB0;
    FIFOF#(RtilePcieTxPingPongChannelOutputEntry) beatPipeOutQueue      <- mkFIFOF;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeOut#(RtilePcieTxBramBufferReadReq))  bramReadReqPipeOutVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, FIFOF#(RtilePcieTxBramBufferReadReq))    bramReadReqPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, DATA)))   bramReadRespPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInAdapterB0#(Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, DATA)))    bramReadRespPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInB0#(PcieTlpHeaderBuffer))   bramTlpHeaderReadRespPipeInVecInst = newVector;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PipeInAdapterB0#(PcieTlpHeaderBuffer))    bramTlpHeaderReadRespPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    for (Integer idx=0; idx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        bramReadReqPipeOutVecInst[idx]          = toPipeOut(bramReadReqPipeOutQueueVec[idx]);
        bramReadRespPipeInVecInst[idx]          = toPipeInB0(bramReadRespPipeInQueueVec[idx]);
        bramTlpHeaderReadRespPipeInVecInst[idx] = toPipeInB0(bramTlpHeaderReadRespPipeInQueueVec[idx]);
    end

    
    Reg#(Maybe#(RtilePcieTxPingPongChannelMetaEntry)) curMetaEntryMaybeReg <- mkReg(tagged Invalid);
    Reg#(RtilePcieTxPingPongChannelMetaBundle) curInputMetaBundleReg <- mkRegU;

    Reg#(RtilePcieTxBramRowIndexInOutputBeat) outputBeatEmptyStorageRowCntReg <- mkReg(fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)-1));


    Reg#(RtilePcieTxPingPongChannelOutputEntry) outputEntryReg  <- mkReg(unpack(0));
    Reg#(Bool)                                  isFirstReg      <- mkReg(True);

    // Pipeline FIFOs
    FIFOF#(RtilePcieTxPingPongChannelBramReadPipelineEntry) bramReadPipelineQueue <- mkSizedFIFOF(8);
    FIFOF#(Tuple2#(RtilePcieTxBramRowIndexInOutputBeat, RtilePcieTxPingPongChannelOutputEntry))  finalShiftPipelineQueue <- mkLFIFOF;

    rule sendBramReadReq;
        let zeroBasedValidSegCnt = ?;

        if (curMetaEntryMaybeReg matches tagged Valid .curMetaEntry) begin

            let isCurMetaEntryLast = (curMetaEntry.zeroBasedSegCnt <= fromInteger(valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)-1));
            let isPacketLast = isCurMetaEntryLast && curMetaEntry.isLast;
            let haveNextValidPacketMeta = isValid(curInputMetaBundleReg[0]);
            let isOutputBeatLast = isCurMetaEntryLast && !haveNextValidPacketMeta;

            if (!isPacketLast) begin
                zeroBasedValidSegCnt = fromInteger(valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG)-1);
            end
            else begin
                zeroBasedValidSegCnt = truncate(curMetaEntry.zeroBasedSegCnt);
            end


            bramReadReqPipeOutQueueVec[curMetaEntry.srcChannelIdx].enq(RtilePcieTxBramBufferReadReq{
                addr                : curMetaEntry.startRowAddr,
                needReadTlpBuffer   : isFirstReg
            });

            bramReadPipelineQueue.enq(RtilePcieTxPingPongChannelBramReadPipelineEntry {
                srcChannelIdx       : curMetaEntry.srcChannelIdx,
                zeroBasedValidSegCnt: zeroBasedValidSegCnt,
                isFirst             : isFirstReg,
                isLast              : isPacketLast,
                isOutputBeatLast    : isOutputBeatLast
            });

            let nextCurMetaEntryMaybe;
            if (!isCurMetaEntryLast) begin
                let nextCurMetaEntry = curMetaEntry;
                nextCurMetaEntry.zeroBasedSegCnt = nextCurMetaEntry.zeroBasedSegCnt - fromInteger(valueOf(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG));
                nextCurMetaEntry.startRowAddr = nextCurMetaEntry.startRowAddr + 1;
                nextCurMetaEntryMaybe = tagged Valid nextCurMetaEntry;
                isFirstReg <= False;
            end
            else begin
                if (haveNextValidPacketMeta) begin
                    curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, curInputMetaBundleReg, 1);
                    nextCurMetaEntryMaybe = curInputMetaBundleReg[0];
                    immAssert(isValid(curInputMetaBundleReg[0]), "must always be valid", $format(""));
                    isFirstReg <= fromMaybe(?, curInputMetaBundleReg[0]).isFirst;
                end
                else begin
                    if (metaPipeInQueue.notEmpty) begin
                        curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, metaPipeInQueue.first, 1);
                        nextCurMetaEntryMaybe = metaPipeInQueue.first[0];
                        metaPipeInQueue.deq;
                        immAssert(isValid(metaPipeInQueue.first[0]), "must always be valid", $format(""));
                        isFirstReg <= fromMaybe(?, metaPipeInQueue.first[0]).isFirst;
                    end
                    else begin
                        nextCurMetaEntryMaybe = tagged Invalid;
                    end
                end
            end
            curMetaEntryMaybeReg <= nextCurMetaEntryMaybe;
        end
        else begin
            curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, metaPipeInQueue.first, 1);
            curMetaEntryMaybeReg <= metaPipeInQueue.first[0];
            metaPipeInQueue.deq;

            immAssert(isValid(metaPipeInQueue.first[0]), "must always be valid", $format(""));
            isFirstReg <= fromMaybe(?, metaPipeInQueue.first[0]).isFirst;
            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongSingleChannel[%d] sendBramReadReq IDLE"), chIdxForDebug,
            //     toBlue(", metaPipeInQueue.first="), fshow(metaPipeInQueue.first)
            // );
        end
    endrule


    rule handleBramReadRespAndMergeHeader;
        let bramReadBeatMeta = bramReadPipelineQueue.first;
        bramReadPipelineQueue.deq;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongSingleChannel[%d] handleBramReadRespAndMergeHeader"), chIdxForDebug,
        //     toBlue(", bramReadBeatMeta="), fshow(bramReadBeatMeta)
        // );

        let readResp = bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].first;
        bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].deq;

        let outputEntry                     = outputEntryReg;
        let outputBeatEmptyStorageRowCnt    = outputBeatEmptyStorageRowCntReg;

        Vector#(PCIE_TX_SEG_CNT_PER_DOUBLE_WIDTH_SEG, PcieTlpDataSegment) readRespAsSegBundle = unpack(pack(readResp));
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[0]);
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[1]);


        let tlpHasPayload = True;
        if (bramReadBeatMeta.isFirst) begin
            outputEntry.hvalid = {2'b01, truncateLSB(outputEntry.hvalid)};
            outputEntry.sop = {2'b01, truncateLSB(outputEntry.sop)};

            let tlpHeaderBuf = bramTlpHeaderReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].first;
            bramTlpHeaderReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].deq;

            tlpHasPayload = isPcieTlpHasPayload(tlpHeaderBuf);

            outputEntry.header = shiftInAtN(outputEntry.header, tlpHeaderBuf);
            outputEntry.header = shiftInAtN(outputEntry.header, unpack(0));
        end
        else begin
            outputEntry.header = shiftInAtN(outputEntry.header, unpack(0));
            outputEntry.header = shiftInAtN(outputEntry.header, unpack(0));
            outputEntry.hvalid = {2'b00, truncateLSB(outputEntry.hvalid)};
            outputEntry.sop = {2'b00, truncateLSB(outputEntry.sop)};
        end

        case (bramReadBeatMeta.zeroBasedValidSegCnt)
            0: begin
                outputEntry.dvalid = {tlpHasPayload ? (bramReadBeatMeta.isLast ? 2'b01: 2'b11) : 2'b00, truncateLSB(outputEntry.dvalid)};
                outputEntry.eop = {bramReadBeatMeta.isLast ? 2'b01: 2'b00, truncateLSB(outputEntry.eop)};
            end
            1: begin
                outputEntry.dvalid = {tlpHasPayload ? (bramReadBeatMeta.isLast ? 2'b11: 2'b11) : 2'b00, truncateLSB(outputEntry.dvalid)};
                outputEntry.eop = {bramReadBeatMeta.isLast ? 2'b10: 2'b00, truncateLSB(outputEntry.eop)};
            end
        endcase
    

        if (bramReadBeatMeta.isOutputBeatLast) begin
            finalShiftPipelineQueue.enq(tuple2(outputBeatEmptyStorageRowCnt, outputEntry));
            outputBeatEmptyStorageRowCntReg <= fromInteger(valueOf(RTILE_PCIE_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)-1);
        end
        else begin
            outputBeatEmptyStorageRowCntReg <= outputBeatEmptyStorageRowCnt - 1;
        end
        outputEntryReg <= outputEntry;
    endrule

    rule finalShift;
        RtilePcieTxBramRowIndexInOutputBeat      outputBeatEmptyStorageRowCnt;
        RtilePcieTxPingPongChannelOutputEntry    outputEntry;

        {outputBeatEmptyStorageRowCnt, outputEntry} = finalShiftPipelineQueue.first;
        finalShiftPipelineQueue.deq;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongSingleChannel[%d] finalShift before shift"), chIdxForDebug,
        //     toBlue(", outputBeatEmptyStorageRowCnt="), fshow(outputBeatEmptyStorageRowCnt),
        //     toBlue(", outputEntry="), fshow(outputEntry)
        // );

        case (outputBeatEmptyStorageRowCnt)
            0: begin
                // nothing to do
            end
            1: begin
                for (Integer idx = 0; idx < 2; idx = idx + 1) begin
                    outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, unpack(0));
                    outputEntry.header = shiftInAtN(outputEntry.header, unpack(0));
                    outputEntry.sop = {1'b0, truncateLSB(outputEntry.sop)};
                    outputEntry.eop = {1'b0, truncateLSB(outputEntry.eop)};
                    outputEntry.hvalid = {1'b0, truncateLSB(outputEntry.hvalid)};
                    outputEntry.dvalid = {1'b0, truncateLSB(outputEntry.dvalid)};
                end 
            end
        endcase
        beatPipeOutQueue.enq(outputEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongSingleChannel[%d] finalShift after shift"), chIdxForDebug,
        //     toBlue(", outputEntry="), fshow(outputEntry)
        // );
    endrule

   

    interface metaPipeIn                        = toPipeInB0(metaPipeInQueue);
    interface bramTlpHeaderReadRespPipeInVec    = bramTlpHeaderReadRespPipeInVecInst;
    interface beatPipeOut                       = toPipeOut(beatPipeOutQueue);
    interface bramReadReqPipeOutVec             = bramReadReqPipeOutVecInst;
    interface bramReadRespPipeInVec             = bramReadRespPipeInVecInst;
endmodule

interface RtilePcieTxPingPongJoin;
    interface Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(RtilePcieTxPingPongChannelOutputEntry))    pingpongBeatPipeInVec;
    interface PipeOut#(PcieTxBeat)                                                                            rtilePcieTxPipeOut;
endinterface

(* synthesize *)
module mkRtilePcieTxPingPongJoin(RtilePcieTxPingPongJoin);
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeInAdapterB0#(RtilePcieTxPingPongChannelOutputEntry))     pingpongBeatPipeInQueueVec <- replicateM(mkPipeInAdapterB0);
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(RtilePcieTxPingPongChannelOutputEntry))    pingpongBeatPipeInVecInst  = newVector;
    FIFOF#(PcieTxBeat) rtilePcieTxPipeOutQueue <- mkFIFOF;

    for (Integer idx = 0; idx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        pingpongBeatPipeInVecInst[idx] = toPipeInB0(pingpongBeatPipeInQueueVec[idx]);
    end

    Reg#(RtilePcieTxPingPongChannelIdx) curChannelIdxReg <- mkReg(0);

    rule doJoin;
        let inputBeat = pingpongBeatPipeInQueueVec[curChannelIdxReg].first;
        pingpongBeatPipeInQueueVec[curChannelIdxReg].deq;
        curChannelIdxReg <= curChannelIdxReg + 1;

        let beatOut = PcieTxBeat{
            data        : inputBeat.dataBuf,
            header      : inputBeat.header,
            sop         : inputBeat.sop,
            eop         : inputBeat.eop,
            hvalid      : inputBeat.hvalid,
            dvalid      : inputBeat.dvalid
        };
        rtilePcieTxPipeOutQueue.enq(beatOut);

        $display(
            "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongJoin doJoin"),
            toBlue(", curChannelIdxReg="), fshow(curChannelIdxReg),
            toBlue(", beatOut="), fshow(beatOut)
        );
    endrule

    // rule debug;
    //     $display(
    //         "time=%0t:", $time, toGreen(" mkRtilePcieTxPingPongJoin debug"),
    //         toBlue(", pingpongBeatPipeInQueueVec[0].notEmpty"), fshow(pingpongBeatPipeInQueueVec[0].notEmpty),
    //         toBlue(", pingpongBeatPipeInQueueVec[1].notEmpty"), fshow(pingpongBeatPipeInQueueVec[1].notEmpty)
    //     );
    // endrule

    interface pingpongBeatPipeInVec     = pingpongBeatPipeInVecInst;
    interface rtilePcieTxPipeOut        = toPipeOut(rtilePcieTxPipeOutQueue);
endmodule

typedef 4 RTILE_PCIE_COMPLETER_MAX_READ_WRITE_BYTE_CNT;

interface RtilePcieCompleter;
    interface PcieBiDirUserDataStreamMasterPipes                                dtldStreamMasterPipes;

    interface PipeInB0#(RtilePcieRxPayloadStorageWriteReq)                        tlpRawBeatDataStorageWriteReqPipeIn;
    interface PipeInB0#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo))            memReadWriteReqTlpVecPipeIn;

    interface PipeOut#(PcieTlpHeaderCompletion)                                  cpltTlpHeaderPipeOut;
    interface PipeOut#(RtilePcieUserStream)                                      cpltTlpDataStreamPipeOut;
endinterface

(* synthesize *)
module mkRtilePcieCompleter(RtilePcieCompleter);
    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  masterSideQueueWm         <- mkFIFOF;
    FIFOF#(RtilePcieUserStream)                     masterSideQueueWd         <- mkFIFOF;
    FIFOF#(DtldStreamMemAccessMeta#(ADDR, Length))  masterSideQueueRm         <- mkFIFOF;
    FIFOF#(RtilePcieUserStream)                     masterSideQueueRd         <- mkLFIFOF;

    PipeInAdapterB0#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo)) memReadWriteReqTlpVecPipeInQueue <- mkPipeInAdapterB0;
    PipeInAdapterB0#(RtilePcieRxPayloadStorageWriteReq)             tlpRawBeatDataStorageWriteReqPipeInQueue        <- mkPipeInAdapterB0;

    FIFOF#(PcieTlpHeaderCompletion)                 cpltTlpHeaderPipeOutQueue       <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_SIXTEEN));
    FIFOF#(RtilePcieUserStream)                     cpltTlpDataStreamPipeOutQueue   <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_SIXTEEN));

    FIFOF#(RtilePcieRxTlpInfoMrRead)                unfinishedReadReqQueue <- mkSizedFIFOF(10);

    // TODO: try optmize this buffer, don't storage all input datastream only for seldom completer's request.
    // maybe we canextract and embed all data (32 or 64 bits) into RtilePcieRxTlpInfo
    Vector#(PCIE_SEGMENT_CNT, AutoInferBramQueuedOutput#(RtilePcieRxPayloadStorageAddr, PcieTlpDataSegment))    dataStreamStorageVec            <- replicateM(mkAutoInferBramQueuedOutput(False, "", "mkRtilePcieCompleter dataStreamStorageVec"));


    // Pipeline Queues:
    FIFOF#(Tuple2#(ADDR, PcieSegmentIdx))    readBramKeepOrderAndPipelineQueue <- mkSizedFIFOF(4);

    // rule debug;
    //     if (!masterSideQueueWm.notFull) $display("time=%0t:", $time, toGreen(" mkRtilePcieCompleter debug FULL QUEUE masterSideQueueWm"));
    //     if (!masterSideQueueWd.notFull) $display("time=%0t:", $time, toGreen(" mkRtilePcieCompleter debug FULL QUEUE masterSideQueueWd"));
    // endrule

    rule handleDataStreamInput;
        let req = tlpRawBeatDataStorageWriteReqPipeInQueue.first;
        tlpRawBeatDataStorageWriteReqPipeInQueue.deq;

        for (Integer idx = 0; idx < valueOf(PCIE_SEGMENT_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].write(req.addr, req.dataBundles[idx]);
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieCompleter handleDataStreamInput"),
        //     toBlue(", req="), fshow(req)
        // );
    endrule

    Reg#(Maybe#(Vector#(PCIE_MAX_TLP_CNT, RtilePcieRxTlpInfo))) curInputTlpVecMaybeReg <- mkReg(tagged Invalid);


    rule handleInputTlpVecStep1;
        if (curInputTlpVecMaybeReg matches tagged Valid .curInputTlpVec) begin
            immAssert(
                isRtilePcieRxTlpInfoValid(curInputTlpVec[0]),
                "input vector's first element must be valid",
                $format("")
            );

            let curInputTlp = curInputTlpVec[0];

            case (curInputTlp) matches
                tagged TlpTypeMrRead .readReqTlp: begin
                    unfinishedReadReqQueue.enq(readReqTlp);
                    masterSideQueueRm.enq(DtldStreamMemAccessMeta{
                        addr        : readReqTlp.addr,
                        totalLen    : fromInteger(valueOf(RTILE_PCIE_COMPLETER_MAX_READ_WRITE_BYTE_CNT)),
                        accessType  : MemAccessTypeNormalReadWrite,
                        operand_1   : 0,
                        operand_2   : 0,
                        noSnoop     : False
                    });
                end
                tagged TlpTypeMrWrite .writeReqTlp: begin
                    dataStreamStorageVec[writeReqTlp.firstBeatSegIdx].putReadReq(writeReqTlp.firstBeatStorageAddr);
                    readBramKeepOrderAndPipelineQueue.enq(tuple2(writeReqTlp.addr, writeReqTlp.firstBeatSegIdx));
                end
                default: begin
                    immFail("only support TlpTypeMrRead and TlpTypeMrWrite here", $format("curInputTlp=", fshow(curInputTlp)));
                end
            endcase

            let newInputCpltTlpVec = shiftOutFrom0(tagged TlpTypeInvalid, curInputTlpVec, 1);
            if (isRtilePcieRxTlpInfoValid(newInputCpltTlpVec[0])) begin
                curInputTlpVecMaybeReg <= tagged Valid newInputCpltTlpVec;
            end
            else begin
                if (memReadWriteReqTlpVecPipeInQueue.notEmpty) begin
                    curInputTlpVecMaybeReg <= tagged Valid memReadWriteReqTlpVecPipeInQueue.first;
                    memReadWriteReqTlpVecPipeInQueue.deq;
                end
                else begin
                    curInputTlpVecMaybeReg <= tagged Invalid;
                end
            end

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieCompleter handleInputTlpVecStep1 BUSY mode"),
            //     toBlue(", curInputTlpVec="), fshow(curInputTlpVec)
            // );

        end
        else begin
            curInputTlpVecMaybeReg <= tagged Valid memReadWriteReqTlpVecPipeInQueue.first;
            memReadWriteReqTlpVecPipeInQueue.deq;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkRtilePcieCompleter handleInputTlpVecStep1 IDLE mode"),
            //     toBlue(", memReadWriteReqTlpVecPipeInQueue.first="), fshow(memReadWriteReqTlpVecPipeInQueue.first)
            // );

            immAssert(
                isRtilePcieRxTlpInfoValid(memReadWriteReqTlpVecPipeInQueue.first[0]),
                "input vector's first element must be valid",
                $format("")
            );
        end
    endrule


    rule handleBramReadResp;
        let {writeAddr, segIdx} = readBramKeepOrderAndPipelineQueue.first;
        readBramKeepOrderAndPipelineQueue.deq;
        
        let writeDataOrigin = dataStreamStorageVec[segIdx].readRespPipeOut.first;
        dataStreamStorageVec[segIdx].readRespPipeOut.deq;

        masterSideQueueWm.enq(DtldStreamMemAccessMeta{
            addr        : writeAddr,
            totalLen    : fromInteger(valueOf(RTILE_PCIE_COMPLETER_MAX_READ_WRITE_BYTE_CNT)),
            accessType  : MemAccessTypeNormalReadWrite,
            operand_1   : 0,
            operand_2   : 0,
            noSnoop     : False
        });

        Dword writeDataValid    = truncate(writeDataOrigin);
        DATA  data              = unpack(zeroExtend(writeDataValid));
        masterSideQueueWd.enq(RtilePcieUserStream{
            data        : data,
            byteNum     : fromInteger(valueOf(RTILE_PCIE_COMPLETER_MAX_READ_WRITE_BYTE_CNT)),
            startByteIdx: 0,
            isFirst     : True,
            isLast      : True
        });

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieCompleter handleBramReadResp"),
        //     toBlue(", writeAddr="), fshow(writeAddr),
        //     toBlue(", segIdx="), fshow(segIdx),
        //     toBlue(", writeDataOrigin="), fshow(writeDataOrigin)
        // );
    endrule

    rule handleCompleterReadResp;
        let ds = masterSideQueueRd.first;
        masterSideQueueRd.deq;
        immAssert(
            ds.byteNum == fromInteger(valueOf(RTILE_PCIE_COMPLETER_MAX_READ_WRITE_BYTE_CNT)) && ds.startByteIdx == 0 && ds.isFirst && ds.isLast,
            "completer's read resp not a valid one",
            $format("ds=", fshow(ds))
        );

        let readTlpMeta = unfinishedReadReqQueue.first;
        unfinishedReadReqQueue.deq;

        let commonHeader = PcieTlpHeaderCommon {
            fmt     : `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA,
            typ     : `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA,
            t9      : unpack(readTlpMeta.tag[9]),
            tc      : 0,
            t8      : unpack(readTlpMeta.tag[8]),
            attrh   : False,
            ln      : False,
            th      : False,
            td      : False,
            ep      : False,
            attrl   : 0,
            at      : 0,
            length  : fromInteger(valueOf(TDiv#(RTILE_PCIE_COMPLETER_MAX_READ_WRITE_BYTE_CNT, BYTE_CNT_PER_DWOED)))
        };

        let tlp = PcieTlpHeaderCompletion {
            commonHeader    : commonHeader,
            completerId     : unpack(0),  // will fill by ip core
            cpltStatus      : unpack(0),
            bcm             : unpack(0),
            byteCount       : fromInteger(valueOf(RTILE_PCIE_COMPLETER_MAX_READ_WRITE_BYTE_CNT)),
            requesterId     : readTlpMeta.requesterId,              // TODO: checck if this can be omitted
            tag             : unpack(truncate(readTlpMeta.tag)),
            rsv1            : unpack(0),
            lowerAddress    : truncate(readTlpMeta.addr)
        };

        cpltTlpHeaderPipeOutQueue.enq(tlp);
        cpltTlpDataStreamPipeOutQueue.enq(ds);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRtilePcieCompleter handleCompleterReadResp"),
        //     toBlue(", tlp="), fshow(tlp),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule



    interface DtldStreamBiDirMasterPipes dtldStreamMasterPipes;
        interface DtldStreamMasterWritePipes writePipeIfc;
            interface  writeMetaPipeOut  = toPipeOut(masterSideQueueWm);
            interface  writeDataPipeOut  = toPipeOut(masterSideQueueWd);
        endinterface

        interface DtldStreamMasterReadPipes readPipeIfc;
            interface  readMetaPipeOut  = toPipeOut(masterSideQueueRm);
            interface  readDataPipeIn   = toPipeIn(masterSideQueueRd);
        endinterface
    endinterface

    interface tlpRawBeatDataStorageWriteReqPipeIn = toPipeInB0(tlpRawBeatDataStorageWriteReqPipeInQueue);
    interface memReadWriteReqTlpVecPipeIn = toPipeInB0(memReadWriteReqTlpVecPipeInQueue);

    interface cpltTlpHeaderPipeOut      = toPipeOut(cpltTlpHeaderPipeOutQueue);
    interface cpltTlpDataStreamPipeOut  = toPipeOut(cpltTlpDataStreamPipeOutQueue);
endmodule


interface RTilePcie;
    interface PipeIn#(PcieRxBeat)                                                                                   pcieRxPipeIn;
    interface PipeOut#(PcieTxBeat)                                                                                  pcieTxPipeOut;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieBiDirUserDataStreamSlavePipesB0In)                     streamSlaveIfcVec;
    interface PcieBiDirUserDataStreamMasterPipes                                                                    streamMasterIfc;
    interface PipeOut#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))       rxFlowControlReleaseReqPipeOut;
    interface PipeOut#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))       txFlowControlConsumeReqPipeOut;
    interface PipeIn#(Tuple6#(CreditCount, CreditCount, CreditCount, CreditCount, CreditCount, CreditCount))        txFlowControlAvaliablePipeIn;
endinterface


(* synthesize *)
module mkRTilePcie(RTilePcie);
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieBiDirUserDataStreamSlavePipesB0In)     streamSlaveIfcVecInst = newVector;

    let pcieRxStreamSegmentFork <- mkPcieRxStreamSegmentFork;
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieCompletionBuffer) cpltBufferVec <- replicateM(mkPcieCompletionBuffer);
    let pcieHwCpltBufferAllocator <- mkPcieHwCpltBufferAllocator;

    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieRequestTlpHeaderGen) tlpHeaderGenVec <- genWithM(compose(mkPcieRequestTlpHeaderGen, fromInteger));
    Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, RtilePcieTxUserInputGearboxStorageAndMetaExtractor) userInputGearboxStorageAndMetaExtractorVec <- genWithM(compose(mkRtilePcieTxUserInputGearboxStorageAndMetaExtractor, fromInteger));
    let rtilePcieTxPingPongFork <- mkRtilePcieTxPingPongFork;
    Vector#(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT, RtilePcieTxPingPongSingleChannel) rtilePcieTxPingPongSingleChannelVec <- genWithM(compose(mkRtilePcieTxPingPongSingleChannel, fromInteger));
    let rtilePcieTxPingPongJoin <- mkRtilePcieTxPingPongJoin;
    let pcieCompleter <- mkRtilePcieCompleter;

    mkConnection(pcieRxStreamSegmentFork.tlpRawBeatDataStorageWriteReqForCompleterPipeOut, pcieCompleter.tlpRawBeatDataStorageWriteReqPipeIn);  // already Nr
    mkConnection(pcieRxStreamSegmentFork.memReadWriteReqTlpVecPipeOut, pcieCompleter.memReadWriteReqTlpVecPipeIn);  // already Nr
    // TODO: only connect completer's complete message to channel 0, maybe we should spread it across 4 channels if needed
    mkConnection(pcieCompleter.cpltTlpHeaderPipeOut, tlpHeaderGenVec[0].cpltTlpHeaderPipeIn);   // already Nr
    mkConnection(pcieCompleter.cpltTlpDataStreamPipeOut, tlpHeaderGenVec[0].cpltTlpDataStreamPipeIn);  // already Nr

    for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
        mkConnection(pcieRxStreamSegmentFork.tlpRawBeatDataStorageWriteReqPipeOutVec[channelIdx], cpltBufferVec[channelIdx].tlpRawBeatDataStorageWriteReqPipeIn);  // already Nr
        mkConnection(pcieRxStreamSegmentFork.cpltTlpVecPipeOutVec[channelIdx], cpltBufferVec[channelIdx].cpltTlpVecPipeIn);  // already Nr
        mkConnection(cpltBufferVec[channelIdx].sharedHwCpltBufferSlotDeAllocReqPipeOut, pcieHwCpltBufferAllocator.slotDeAllocPipeInVec[channelIdx]);  // already Nr

        streamSlaveIfcVecInst[channelIdx].writePipeIfc.writeMetaPipeIn  = tlpHeaderGenVec[channelIdx].dtldStreamSlavePipes.writePipeIfc.writeMetaPipeIn;
        streamSlaveIfcVecInst[channelIdx].writePipeIfc.writeDataPipeIn  = tlpHeaderGenVec[channelIdx].dtldStreamSlavePipes.writePipeIfc.writeDataPipeIn;
        streamSlaveIfcVecInst[channelIdx].readPipeIfc.readMetaPipeIn    = tlpHeaderGenVec[channelIdx].dtldStreamSlavePipes.readPipeIfc.readMetaPipeIn;
        streamSlaveIfcVecInst[channelIdx].readPipeIfc.readDataPipeOut   = cpltBufferVec[channelIdx].dataStreamPipeOut;

        mkConnection(tlpHeaderGenVec[channelIdx].tagAllocReqPipeOut, cpltBufferVec[channelIdx].tagAllocReqPipeIn);  // already Nr
        mkConnection(cpltBufferVec[channelIdx].tagAllocRespPipeOut, tlpHeaderGenVec[channelIdx].tagAllocRespPipeIn);  // already Nr

        mkConnection(tlpHeaderGenVec[channelIdx].slotAllocReqPipeOut, pcieHwCpltBufferAllocator.slotAllocReqPipeInVec[channelIdx]);  // already Nr
        mkConnection(pcieHwCpltBufferAllocator.slotAllocRespPipeOutVec[channelIdx], tlpHeaderGenVec[channelIdx].slotAllocRespPipeIn);  // already Nr

        mkConnection(tlpHeaderGenVec[channelIdx].tlpDataStreamPipeOut, userInputGearboxStorageAndMetaExtractorVec[channelIdx].streamPipeIn);  // already Nr
        mkConnection(userInputGearboxStorageAndMetaExtractorVec[channelIdx].packetMetaPipeOut, rtilePcieTxPingPongFork.packetMetaPipeInVec[channelIdx]);  // already Nr
        mkConnection(tlpHeaderGenVec[channelIdx].tlpHeaderBufferPipeOut, userInputGearboxStorageAndMetaExtractorVec[channelIdx].txTlpHeaderBufferPipeIn);  // already Nr

        for (Integer pingPongChannelIdx = 0; pingPongChannelIdx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); pingPongChannelIdx = pingPongChannelIdx + 1) begin
            mkConnection(rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].bramReadReqPipeOutVec[channelIdx], userInputGearboxStorageAndMetaExtractorVec[channelIdx].bramReadReqPipeInVec[pingPongChannelIdx]);  // already Nr
            mkConnection(userInputGearboxStorageAndMetaExtractorVec[channelIdx].bramReadRespPipeOutVec[pingPongChannelIdx], rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].bramReadRespPipeInVec[channelIdx]);  // already Nr
            mkConnection(userInputGearboxStorageAndMetaExtractorVec[channelIdx].bramTlpHeaderReadRespPipeOutVec[pingPongChannelIdx], rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].bramTlpHeaderReadRespPipeInVec[channelIdx]);  // already Nr
        end
    end

    for (Integer pingPongChannelIdx = 0; pingPongChannelIdx < valueOf(RTILE_PCIE_TX_PING_PONG_CHANNEL_CNT); pingPongChannelIdx = pingPongChannelIdx + 1) begin
        mkConnection(rtilePcieTxPingPongFork.pingpongChannelMetaPipeOutVec[pingPongChannelIdx], rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].metaPipeIn);  // already Nr
        mkConnection(rtilePcieTxPingPongSingleChannelVec[pingPongChannelIdx].beatPipeOut,  rtilePcieTxPingPongJoin.pingpongBeatPipeInVec[pingPongChannelIdx]);  // already Nr
    end

    rule setCpltBufChannelIdx;
        for (Integer channelIdx = 0; channelIdx < valueOf(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT); channelIdx = channelIdx + 1) begin
            cpltBufferVec[channelIdx].setChannelIdx(fromInteger(channelIdx));
        end
    endrule

    interface pcieRxPipeIn                      = pcieRxStreamSegmentFork.pcieRxPipeIn;
    interface streamSlaveIfcVec                 = streamSlaveIfcVecInst;
    interface pcieTxPipeOut                     = rtilePcieTxPingPongJoin.rtilePcieTxPipeOut;
    interface streamMasterIfc                   = pcieCompleter.dtldStreamMasterPipes;
    interface rxFlowControlReleaseReqPipeOut    = pcieRxStreamSegmentFork.rxFlowControlReleaseReqPipeOut;
    interface txFlowControlConsumeReqPipeOut    = rtilePcieTxPingPongFork.txFlowControlConsumeReqPipeOut;
    interface txFlowControlAvaliablePipeIn      = rtilePcieTxPingPongFork.txFlowControlAvaliablePipeIn;
endmodule
