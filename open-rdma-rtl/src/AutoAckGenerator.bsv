import RegFile :: * ;
import FIFOF :: *;
import ClientServer :: *;
import Connectable :: *;
import PAClib :: *;
import PrimUtils :: *;
import Vector :: *;
import BuildVector :: *;
import GetPut :: *;
import Printf:: *;
import MIMO :: *;

import Settings :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;
import Ringbuf :: *;
import Descriptors :: *;
import EthernetTypes :: *;
import EthernetFrameIO256 :: *;
import QPContext :: *;
import IoChannels :: *;

import ConnectableF :: *;

import PsnContinousChecker :: *;
import FullyPipelineChecker :: *;

typedef struct {
    PSN         psn;
    QPN         qpn;
    EntryQPC    qpc;
} AutoAckGeneratorReq deriving(Bits, FShow);

typedef struct {
    QPN         qpn;
    EntryQPC    qpc;
} AutoAckGeneratorToHandleMergedBitmapPipelineEntry deriving(Bits, FShow);

typedef struct {
    QPN         qpn;
    EntryQPC    qpc;
    BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary) bitmapUpdateResp;
} AutoAckGeneratorToGenAutoAckEthPacketPipelineEntry deriving(Bits, FShow);

typedef struct {
    Dword lastEntryReceiveTime;
    MSN   ackMsn;
    Bool  hasReported;
} AutoAckGenAtomicUpdateStorageEntry deriving(Bits, FShow);

typedef enum {
    AutoAckGenBackgroundPollingStateSendReadReq = 0,
    AutoAckGenBackgroundPollingStateGetReadResp = 1,
    AutoAckGenBackgroundPollingStateHandleResp = 2
}  AutoAckGenBackgroundPollingState deriving(Bits, Eq, FShow);

typedef 5000 AUTO_ACK_POLLING_TIMEOUT_TICKS;

interface AutoAckGenerator;
    interface PipeInB0#(AutoAckGeneratorReq) reqPipeIn;

    interface PipeOut#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeOut;
    interface PipeOut#(RdmaSendPacketMeta)          rdmaPacketMetaPipeOut;
    interface PipeOut#(DataStream)                  rdmaPayloadPipeOut;

    interface PipeOut#(RingbufRawDescriptor) metaReportDescPipeOut;

    interface PipeIn#(IndexQP) resetReqPipeIn;
    // interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface

(* synthesize *)
module mkAutoAckGenerator(AutoAckGenerator);

    FIFOF#(IndexQP) resetReqPipeInQueue <- mkLFIFOF;


    PipeInAdapterB0#(AutoAckGeneratorReq) reqPipeInQueue <- mkPipeInAdapterB0;
    FIFOF#(RingbufRawDescriptor) metaReportDescPipeOutQueue <- mkFIFOF;

    FIFOF#(ThinMacIpUdpMetaDataForSend) ethernetPacketGeneratorMacIpUdpMetaPipeOutQueue <- mkFIFOF;
    FIFOF#(RdmaSendPacketMeta) ethernetPacketGeneratorRdmaPacketMetaPipeOutQueue <- mkFIFOF;
    FIFOF#(DataStream) rdmaPayloadPipeOutQueue <- mkFIFOF;  // dummy one, not used

    Reg#(Dword) curTimeReg <- mkReg(0);
    Reg#(IndexQP) pollingQpIdxReg <- mkReg(0);

    AutoInferBramQueuedOutput#(IndexQP, Dword) lastReportTimeStorage <- mkAutoInferBramQueuedOutput(False, "", "lastReportTimeStorage");

    function AutoAckGenAtomicUpdateStorageEntry atomicUpdateFunction(AutoAckGenAtomicUpdateStorageEntry oldVal, Bool reqVal, Bool isReset);
        let needSendAckNow = reqVal;
        if (isReset) begin
            oldVal.ackMsn = 0;
            oldVal.lastEntryReceiveTime = 0;
            oldVal.hasReported = True;
        end
        else begin
            oldVal.ackMsn = needSendAckNow ? oldVal.ackMsn + 1 : oldVal.ackMsn;
            oldVal.lastEntryReceiveTime = curTimeReg;
            oldVal.hasReported = reqVal;
        end
        return oldVal;
    endfunction

    AtomicUpdateStorage#(IndexQP, AutoAckGenAtomicUpdateStorageEntry, Bool) autoAckMetaAtomicUpdateStorage <- mkAtomicUpdateStorage(
        atomicUpdateFunction,
        "init_bram_auto_ack_meta_storage"
    );


    let mimoCfg = MIMOConfiguration {
        unguarded: False,
        bram_based: False
    };
    MIMO#(
        NUMERIC_TYPE_TWO,
        NUMERIC_TYPE_ONE,
        NUMERIC_TYPE_FOUR,
        RingbufRawDescriptor
    ) metaReportMimoQueue <- mkMIMO(mimoCfg);
    FIFOF#(RingbufRawDescriptor) pollingTimeoutDescQueue <- mkFIFOF;

    // Pipeline Queues
    FIFOF#(AutoAckGeneratorToHandleMergedBitmapPipelineEntry) handleMergedBitmapPipelineQueue <- mkFIFOF;
    FIFOF#(AutoAckGeneratorToGenAutoAckEthPacketPipelineEntry) genAutoAckEthPacketPipelineQueue <- mkSizedFIFOF(3);

    FIFOF#(Tuple3#(
            BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary),
            AtomicUpdateStorageUpdateResp#(IndexQP, AutoAckGenAtomicUpdateStorageEntry),
            KeyQP
        )) genAutoAckReportDescriptorPipelineQueue <- mkLFIFOF;
    
    Reg#(Tuple4#(
            BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary),
            AutoAckGenAtomicUpdateStorageEntry,
            Dword,
            IndexQP
        )) pollingQueryRespPipelineReg <- mkRegU;

    Reg#(AutoAckGenBackgroundPollingState) backgroundPollingStateReg <- mkReg(AutoAckGenBackgroundPollingStateSendReadReq);

    BitmapWindowStorage#(IndexQP, AckBitmap, PsnMergeWindowBoundary, ACK_WINDOW_STRIDE) bitmapStorage <- mkBitmapWindowStorage;
    let bitmapStorageReqPipeInAdapter <- mkPipeInB0ToPipeInWithDebug(bitmapStorage.reqPipeIn, 1, DebugConf{name: "bitmapStorageReqPipeInAdapter", enableDebug: False} );
    
    rule timerTask;
        curTimeReg <= curTimeReg + 1;
    endrule

    Reg#(Bool) bramInitedReg <- mkReg(False);
    Reg#(IndexQP) bramInitPtrReg <- mkReg(0);

    rule bramInit if (!bramInitedReg);
        if (bramInitPtrReg == maxBound) begin
            bramInitedReg <= True;
        end
        
        lastReportTimeStorage.write(bramInitPtrReg, 0);
        bramInitPtrReg <= bramInitPtrReg + 1;
    endrule

    rule forwardInputReqToPsnBitMapStorage;
        let req = reqPipeInQueue.first;
        reqPipeInQueue.deq;

        let updateReq = BitmapWindowStorageUpdateReq {
            psn: req.psn,
            qpn: req.qpn
        };
        bitmapStorageReqPipeInAdapter.enq(updateReq);
        
        let outPipelineEntry = AutoAckGeneratorToHandleMergedBitmapPipelineEntry {
            qpn: req.qpn,
            qpc: req.qpc
        };
        handleMergedBitmapPipelineQueue.enq(outPipelineEntry);

        $display(
            "time=%0t:", $time, toGreen(" mkAutoAckGenerator forwardInputReqToPsnBitMapStorage"),
            toBlue(", req="), fshow(req)
        );
    endrule

    rule handleMergedBitmap;
        let bitmapResp = bitmapStorage.respPipeOut.first;
        bitmapStorage.respPipeOut.deq;

        let pipelineEntryIn = handleMergedBitmapPipelineQueue.first;
        handleMergedBitmapPipelineQueue.deq;

        let hasPacketLost = bitmapResp.isShiftWindow && bitmapResp.windowShiftedOutData != -1;
        let needSendAckNow = hasPacketLost;
        let autoAckMetaUpdateReq = AtomicUpdateStorageUpdateReq {
            rowAddr: bitmapResp.rowAddr,
            reqData: needSendAckNow
        };
        autoAckMetaAtomicUpdateStorage.reqPipeIn.enq(autoAckMetaUpdateReq);

        let outPipelineEntry = AutoAckGeneratorToGenAutoAckEthPacketPipelineEntry {
            qpn: pipelineEntryIn.qpn,
            qpc: pipelineEntryIn.qpc,
            bitmapUpdateResp: bitmapResp
        };
        genAutoAckEthPacketPipelineQueue.enq(outPipelineEntry);
        
        $display(
            "time=%0t:", $time, toGreen(" mkAutoAckGenerator handleMergedBitmap"),
            toBlue(", bitmapResp="), fshow(bitmapResp),
            toBlue(", hasPacketLost="), fshow(hasPacketLost),
            toBlue(", needSendAckNow="), fshow(needSendAckNow)
        );
    endrule

    rule genAutoAckEthPacket;

        let ackMsnInfo = autoAckMetaAtomicUpdateStorage.respPipeOut.first;
        autoAckMetaAtomicUpdateStorage.respPipeOut.deq;

        let pipelineEntryIn = genAutoAckEthPacketPipelineQueue.first;
        genAutoAckEthPacketPipelineQueue.deq;

        let qpCtx       = pipelineEntryIn.qpc;
        let bitmapInfo  = pipelineEntryIn.bitmapUpdateResp;

        let needSendAckNow  = ackMsnInfo.newValue.hasReported;
        let isPacketLost    = needSendAckNow;

        if (needSendAckNow) begin
            let thinMacIpUdpMetaDataForSend = ThinMacIpUdpMetaDataForSend {
                dstMacAddr: qpCtx.peerMacAddr,
                ipDscp: 0,
                ipEcn: 0,
                dstIpAddr: qpCtx.peerIpAddr,
                srcPort: qpCtx.localUdpPort,
                dstPort: fromInteger(valueOf(UDP_PORT_RDMA)),
                udpPayloadLen: fromInteger(valueOf(RDMA_FIXED_HEADER_BYTE_NUM)),
                ethType: fromInteger(valueOf(ETH_TYPE_IP))
            };

            let rdmaSendPacketMeta = RdmaSendPacketMeta {
                header:RdmaBthAndExtendHeader{
                    bth: BTH {
                        trans    : TRANS_TYPE_RC,
                        opcode   : ACKNOWLEDGE,
                        solicited: False,
                        isRetry  : False,
                        padCnt   : unpack(0),
                        tver     : unpack(0),
                        msn      : ackMsnInfo.oldValue.ackMsn,  // msn should start from 0, if use newValue's msn, it becomes one
                        fecn     : unpack(0),
                        becn     : unpack(0),
                        resv6    : unpack(0),
                        dqpn     : qpCtx.peerQPN,
                        ackReq   : False,
                        resv7    : unpack(0),
                        psn      : zeroExtendLSB(bitmapInfo.newEntry.leftBound)
                    },
                    rdmaExtendHeaderBuf: buildRdmaExtendHeaderBuffer(pack(AETH{
                            preBitmap:  bitmapInfo.oldEntry.data,
                            newBitmap:  bitmapInfo.newEntry.data,
                            isPacketLost: True,
                            isWindowSlided: True,
                            isSendByDriver: False,
                            resv0: unpack(0),
                            preBitmapPsn: zeroExtendLSB(bitmapInfo.oldEntry.leftBound)
                        }))
                },
                hasPayload: False
            };
            ethernetPacketGeneratorMacIpUdpMetaPipeOutQueue.enq(thinMacIpUdpMetaDataForSend);
            ethernetPacketGeneratorRdmaPacketMetaPipeOutQueue.enq(rdmaSendPacketMeta);

            let qpnKeyPart = qpCtx.qpnKeyPart;
            genAutoAckReportDescriptorPipelineQueue.enq(tuple3(bitmapInfo, ackMsnInfo, qpnKeyPart));

            $display(
                "time=%0t:", $time, toGreen(" mkAutoAckGenerator genAutoAckEthPacket send ack now"),
                toBlue(", ackMsnInfo="), fshow(ackMsnInfo),
                toBlue(", pipelineEntryIn="), fshow(pipelineEntryIn),
                toBlue(", thinMacIpUdpMetaDataForSend="), fshow(thinMacIpUdpMetaDataForSend),
                toBlue(", rdmaSendPacketMeta="), fshow(rdmaSendPacketMeta),
                toBlue(", bitmapInfo="), fshow(bitmapInfo),
                toBlue(", qpnKeyPart="), fshow(qpnKeyPart)
            );
            
        end

        $display(
            "time=%0t:", $time, toGreen(" mkAutoAckGenerator genAutoAckEthPacket run"),
            toBlue(", ackMsnInfo="), fshow(ackMsnInfo),
            toBlue(", pipelineEntryIn="), fshow(pipelineEntryIn)
        );
    endrule

    rule genAutoAckReportDescriptor;
        let {bitmapInfo, ackMsnInfo, qpnKeyPart} = genAutoAckReportDescriptorPipelineQueue.first;
        

        // write them in a function to make sure they are all comb logic.
        function Vector#(NUMERIC_TYPE_TWO, RingbufRawDescriptor) genDescVector();
            
            let commonHeader = RingbufDescCommonHead {
                valid           : True,
                hasNextFrag     : False,
                reserved0       : unpack(0),
                isExtendOpcode  : False,
                opCode          : {pack(TRANS_TYPE_RC), pack(ACKNOWLEDGE)}
            };

            let desc0 = MetaReportQueueAckDesc{
                nowBitmap       : bitmapInfo.newEntry.data,
                msn             : ackMsnInfo.oldValue.ackMsn,
                qpn             : genQPN(ackMsnInfo.rowAddr, qpnKeyPart),
                psnNow          : zeroExtendLSB(bitmapInfo.newEntry.leftBound),
                reserved2       : unpack(0),
                psnBeforeSlide  : zeroExtendLSB(bitmapInfo.oldEntry.leftBound),
                reserved1       : unpack(0),
                isPacketLost    : True,
                isWindowSlided  : True,
                isSendByDriver  : False,
                isSendByLocalHw : True,
                reserved0       : unpack(0),
                commonHeader    : commonHeader
            };
            desc0.commonHeader.hasNextFrag = True;

            let desc1 = MetaReportQueueAckExtraDesc{
                preBitmap   :   bitmapInfo.oldEntry.data,
                reserved2   :   unpack(0),
                reserved1   :   unpack(0),
                reserved0   :   unpack(0),
                commonHeader:   commonHeader
            };

            return vec(pack(desc0), pack(desc1));
        endfunction

        let vecToEnq = genDescVector;
        if (metaReportMimoQueue.enqReadyN(2)) begin
            metaReportMimoQueue.enq(2, vecToEnq);
            genAutoAckReportDescriptorPipelineQueue.deq;

            $display(
                "time=%0t:", $time, toGreen(" mkAutoAckGenerator genAutoAckReportDescriptor"),
                toBlue(", vecToEnq="), fshow(vecToEnq)
            );
        end

        $display(
            "time=%0t:", $time, toGreen(" mkAutoAckGenerator genAutoAckReportDescriptor run")
        );
        
    endrule

    rule forwardMetaReportDescToOutput;
        if (metaReportMimoQueue.deqReadyN(1)) begin
            metaReportMimoQueue.deq(1);
            let desc = metaReportMimoQueue.first[0];
            metaReportDescPipeOutQueue.enq(desc);
            $display(
                "time=%0t:", $time, toGreen(" mkAutoAckGenerator forwardMetaReportDescToOutput"),
                toBlue(", desc="), fshow(desc)
            );
        end
        else if (pollingTimeoutDescQueue.notEmpty) begin  
            let desc = pollingTimeoutDescQueue.first;
            pollingTimeoutDescQueue.deq;
            metaReportDescPipeOutQueue.enq(desc);
            $display(
                "time=%0t:", $time, toGreen(" mkAutoAckGenerator forwardMetaReportDescToOutput"),
                toBlue(", desc="), fshow(desc)
            );
        end
    endrule

    rule sendPollingReq if (bramInitedReg && backgroundPollingStateReg == AutoAckGenBackgroundPollingStateSendReadReq);
        bitmapStorage.readOnlyReqPipeIn.enq(pollingQpIdxReg);
        autoAckMetaAtomicUpdateStorage.readOnlyReqPipeIn.enq(pollingQpIdxReg);
        lastReportTimeStorage.putReadReq(pollingQpIdxReg);
        backgroundPollingStateReg <= AutoAckGenBackgroundPollingStateGetReadResp;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAutoAckGenerator sendPollingReq"),
        //     toBlue(", pollingQpIdxReg="), fshow(pollingQpIdxReg)
        // );
    endrule

    rule getPollingResp if (bramInitedReg && backgroundPollingStateReg == AutoAckGenBackgroundPollingStateGetReadResp);
        let bitmapInfo = bitmapStorage.readOnlyRespPipeOut.first;
        let ackMeta = autoAckMetaAtomicUpdateStorage.readOnlyRespPipeOut.first;
        let lastPollInfo = lastReportTimeStorage.readRespPipeOut.first;
        lastReportTimeStorage.readRespPipeOut.deq;
        bitmapStorage.readOnlyRespPipeOut.deq;
        autoAckMetaAtomicUpdateStorage.readOnlyRespPipeOut.deq;
        backgroundPollingStateReg <= AutoAckGenBackgroundPollingStateHandleResp;
        pollingQpIdxReg <= pollingQpIdxReg + 1;

        pollingQueryRespPipelineReg <= tuple4(bitmapInfo, ackMeta, lastPollInfo, pollingQpIdxReg);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkAutoAckGenerator getPollingResp"),
        //     toBlue(", bitmapInfo="), fshow(bitmapInfo),
        //     toBlue(", ackMeta="), fshow(ackMeta),
        //     toBlue(", lastPollInfo="), fshow(lastPollInfo),
        //     toBlue(", pollingQpIdxReg="), fshow(pollingQpIdxReg)
        // );
    endrule

    rule handlePollingResult if (bramInitedReg && backgroundPollingStateReg == AutoAckGenBackgroundPollingStateHandleResp);
        let {bitmapInfo, ackMeta, lastPollInfo, pollingQpIdx} = pollingQueryRespPipelineReg;
        if (!ackMeta.hasReported) begin
            $display(
                "time=%0t:", $time, toGreen(" mkAutoAckGenerator handlePollingResult"),
                toBlue(", pollingQueryRespPipelineReg="), fshow(pollingQueryRespPipelineReg)
            );


            let lastReportTimeTriggeredByPolling = lastPollInfo;
            // we can't modify the value stored in ackMeta (The storage BRAM can't be write from two different place), so we need another gate to control whether to send ack or not.
            // the following condition covers the following two case:
            //   * the ack was send because the packet's BTH required. In this case, ackMeta.hasReported should be True, and the two time are set to be equal.
            //   * the ack was send by polling, after polling send an ack, the two time are set to be equal.
            let lastRecvPacketHasBeenReported = lastReportTimeTriggeredByPolling == ackMeta.lastEntryReceiveTime;
            let lastRecvPacketIsOldEnough = curTimeReg - ackMeta.lastEntryReceiveTime > fromInteger(valueOf(AUTO_ACK_POLLING_TIMEOUT_TICKS));

            if ((!lastRecvPacketHasBeenReported) && lastRecvPacketIsOldEnough) begin
                let commonHeader = RingbufDescCommonHead {
                    valid           : True,
                    hasNextFrag     : False,
                    reserved0       : unpack(0),
                    isExtendOpcode  : False,
                    opCode          : {pack(TRANS_TYPE_RC), pack(ACKNOWLEDGE)}
                };

                let desc0 = MetaReportQueueAckDesc{
                    nowBitmap       : bitmapInfo.data,
                    msn             : 0,
                    qpn             : genQPN(pollingQpIdx, bitmapInfo.qpnKeyPart),       
                    psnNow          : zeroExtendLSB(bitmapInfo.leftBound),
                    reserved2       : unpack(0),
                    psnBeforeSlide  : unpack(0), // don't care since isWindowSlided = False
                    reserved1       : unpack(0),
                    isPacketLost    : False,
                    isWindowSlided  : False,
                    isSendByDriver  : False,
                    isSendByLocalHw : True,
                    reserved0       : unpack(0),
                    commonHeader    : commonHeader
                };
                pollingTimeoutDescQueue.enq(pack(desc0));
                lastReportTimeStorage.write(pollingQpIdx, ackMeta.lastEntryReceiveTime);

                $display(
                    "time=%0t:", $time, toGreen(" mkAutoAckGenerator handlePollingResult new report"),
                    toBlue(", pollingQpIdx="), fshow(pollingQpIdx),
                    toBlue(", ackMeta="), fshow(ackMeta)
                );
            end
        end
        else begin
            lastReportTimeStorage.write(pollingQpIdx, ackMeta.lastEntryReceiveTime);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkAutoAckGenerator handlePollingResult already reported"),
            //     toBlue(", pollingQpIdx="), fshow(pollingQpIdx),
            //     toBlue(", ackMeta="), fshow(ackMeta)
            // );
        end
        backgroundPollingStateReg <= AutoAckGenBackgroundPollingStateSendReadReq;
    endrule

    rule forwardQpResetSignal;
        let req = resetReqPipeInQueue.first;
        resetReqPipeInQueue.deq;
        bitmapStorage.resetReqPipeIn.enq(req);
        autoAckMetaAtomicUpdateStorage.resetReqPipeIn.enq(req);
    endrule

    interface reqPipeIn = toPipeInB0(reqPipeInQueue);
    
    interface macIpUdpMetaPipeOut = toPipeOut(ethernetPacketGeneratorMacIpUdpMetaPipeOutQueue);
    interface rdmaPacketMetaPipeOut = toPipeOut(ethernetPacketGeneratorRdmaPacketMetaPipeOutQueue);
    interface rdmaPayloadPipeOut = toPipeOut(rdmaPayloadPipeOutQueue);
    interface metaReportDescPipeOut = toPipeOut(metaReportDescPipeOutQueue);

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQueue);
    // interface resetRespPipeOut = allPacketPsnBitmapStorage.resetRespPipeOut;

endmodule

