import Vector :: *;
import BuildVector :: *;
import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import Clocks :: *;
import MIMO :: *;

import FullyPipelineChecker :: *;
import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import CsrRootConnector :: *;
import CsrAddress :: *;
import CsrFramework :: *;

import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import PayloadGenAndCon :: *;
import QPContext :: *;
import PacketGenAndParse :: *;
import IoChannels :: *;
import Descriptors :: *;
import Ringbuf :: *;
import AutoAckGenerator :: *;
import CnpPacketGen :: *;

typedef Bit#(TAdd#(1, SizeOf#(Length))) TruncatedAddrForMrBoundCheck;

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    Bool isFirstPacket;
    ThinMacIpUdpMetaDataForRecv peerMacIpUdpMeta;
    SimulationTime  fpDebugTime;
} CheckQpcAndMrTablePipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    Bool isMrLowerAddrBoundOk;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
    TruncatedAddrForMrBoundCheck deltaLen;
    ThinMacIpUdpMetaDataForRecv peerMacIpUdpMeta;
    SimulationTime  fpDebugTime;
} CheckMrTableStep2PipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    Bool isMrLowerAddrBoundOk;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
    TruncatedAddrForMrBoundCheck deltaLen;
    ThinMacIpUdpMetaDataForRecv peerMacIpUdpMeta;
    SimulationTime  fpDebugTime;
} CheckMrTableStep3PipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
    ThinMacIpUdpMetaDataForRecv peerMacIpUdpMeta;
    SimulationTime  fpDebugTime;
} IssuePayloadConReqOrDiscardPipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
    ThinMacIpUdpMetaDataForRecv peerMacIpUdpMeta;
    SimulationTime  fpDebugTime;
} HandleConRespPipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    SimulationTime  fpDebugTime;
} GenMetaReportQueueDescPipelineEntry deriving(Bits, FShow);

interface RQ;
    interface BlueRdmaCsrUpStreamPort                   csrUpStreamPort;

    interface ClientP#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryClt; 
    interface ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

    interface PipeInB0#(IoChannelEthDataStream) ethernetFramePipeIn;
    interface PipeOut#(DataStream) otherRawPacketPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 

    interface PipeOut#(PayloadConReq) payloadConReqPipeOut;
    interface PipeOut#(DataStream) payloadConStreamPipeOut;
    interface PipeIn#(Bool) payloadConRespPipeIn;

    interface PipeOut#(RingbufRawDescriptor)    metaReportDescPipeOut;
    interface PipeOut#(AutoAckGeneratorReq)     autoAckGenReqPipeOut;
    interface PipeOut#(CnpPacketGenReq)         genCnpReqPipeOut;
endinterface

// FIXME: handle illegal packet length. don't trust length or other meta extracted from header. 
//        only trust what you have really received.
//        And for packet that isn't normal, make sure all related queues are dequeued. otherwise deadlock.
(* synthesize *)
module mkRQ#(Word channelIdx)(RQ);

    FIFOF#(RingbufRawDescriptor)    metaReportDescPipeOutQueue  <- mkFIFOF;
    FIFOF#(AutoAckGeneratorReq)     autoAckGenReqPipeOutQueue   <- mkFIFOF;
    FIFOF#(CnpPacketGenReq)         genCnpReqPipeOutQueue       <- mkFIFOF;
    
    PacketParse packetParser <- mkPacketParse;
    FIFOF#(DataStream) payloadStorage <- mkSizedFIFOF(valueOf(PAYLOAD_STORAGE_CAPACITY_FOR_RQ_INPUT_DATA_STREAM_BUF));
    mkConnection(packetParser.rdmaPayloadPipeOut, toPipeIn(payloadStorage));

    QueuedClientP#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryCltInst <- mkQueuedClientP(DebugConf{name: "qpcQueryCltInst in RQ", enableDebug: False});
    QueuedClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryCltInst <- mkQueuedClientP(DebugConf{name: "mrTableQueryCltInst", enableDebug: False});

    FIFOF#(PayloadConReq) conReqPipeOutQ <- mkSizedFIFOF(4);
    FIFOF#(Bool) conRespPipeInQ <- mkSizedFIFOF(4);

    // invalid request payload filter related
    FIFOF#(Bool) filterCmdQ <-  mkSizedFIFOF(4);
    FIFOF#(DataStream) filteredDataStreamForConsumeQ <- mkFIFOF;

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

    // Pipeline Queues
    FIFOF#(CheckQpcAndMrTablePipelineEntry) checkQpcAndMrTablePipeQ <- mkSizedFIFOF(4);
    FIFOF#(CheckMrTableStep2PipelineEntry) checkMrTableStep2PipeQ <- mkSizedFIFOF(2);
    FIFOF#(CheckMrTableStep3PipelineEntry) checkMrTableStep3PipeQ <- mkSizedFIFOF(2);
    FIFOF#(IssuePayloadConReqOrDiscardPipelineEntry) issuePayloadConReqOrDiscardPipeQ <- mkSizedFIFOF(2);
    // For a 4096 PMTU packet followed by all packet that without payload. When consuming a big packet, all small packets has to waiting in the queue
    FIFOF#(HandleConRespPipelineEntry) handleConRespPipeQ <- mkRegisteredSizedFIFOF(valueOf(TDiv#(TDiv#(MAX_PMTU, DATA_BUS_BYTE_WIDTH), RDMA_PACKET_HEADER_BETA_CNT)));

    FIFOF#(GenMetaReportQueueDescPipelineEntry) handleGenMetaReportQueueDescPipeQ <- mkLFIFOF;

    

    // Metrics Regs
    Reg#(Dword) metricsInvalidQpAccessCntReg        <- mkReg(0);
    Reg#(Dword) metricsInvalidOpcodeCntReg          <- mkReg(0);
    Reg#(Dword) metricsInvalidMrKeyCntReg           <- mkReg(0);
    Reg#(Dword) metricsMemAccessOutOfBoundCntReg    <- mkReg(0);
    Reg#(Dword) metricsInvalidMrAccessFlagCntReg    <- mkReg(0);
    Reg#(Dword) metricsInvalidHeaderCntReg          <- mkReg(0);
    Reg#(Dword) metricsInvalidQpContextCntReg       <- mkReg(0);
    Reg#(Dword) metricsCorruptPktLengthCntReg       <- mkReg(0);
    Reg#(Dword) metricsUnknownErrorCntReg           <- mkReg(0);

    Reg#(Bit#(4)) metricsDebugCounter0Reg           <- mkReg(0);
    Reg#(Bit#(4)) metricsDebugCounter1Reg           <- mkReg(0);
    Reg#(Bit#(4)) metricsDebugCounter2Reg           <- mkReg(0);
    Reg#(Bit#(4)) metricsDebugCounter3Reg           <- mkReg(0);
    Reg#(Bit#(4)) metricsDebugCounter4Reg           <- mkReg(0);
    Reg#(Bit#(4)) metricsDebugCounter5Reg           <- mkReg(0);
    Reg#(Bit#(4)) metricsDebugCounter6Reg           <- mkReg(0);
    Reg#(Bit#(4)) metricsDebugCounter7Reg           <- mkReg(0);



    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
            let regIdx = req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
            let routingMask = fromInteger(valueOf(CSR_ADDR_ROUTING_MASK_FOR_METRICS_OF_SINGLE_RQ));
            let leafMask = fromInteger(valueOf(CSR_ADDR_LEAF_MASK_FOR_METRICS_RQ_PACKET_VERIFY));

            if ((regIdx & routingMask) == fromInteger(valueOf(CSR_ADDR_ROUTING_FOR_METRICS_OF_ETHERNET_FRAME_IO_RECV))) begin
                return tagged CsrNodeResultForward 0;
            end
            else if (req.isWrite) begin
                return tagged CsrNodeResultNotMatched;
            end
            else begin
                case (regIdx & leafMask)
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_INV_QP_ACCESS_FLAG_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsInvalidQpAccessCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_INV_OPCODE_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsInvalidOpcodeCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_INV_MR_KEY_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsInvalidMrKeyCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_MEM_OOB_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsMemAccessOutOfBoundCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_INV_MR_ACCESS_FLAG_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsInvalidMrAccessFlagCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_INV_HEADER_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsInvalidHeaderCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_INV_QP_CTX_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsInvalidQpContextCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_PKT_LEN_ERR_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsCorruptPktLengthCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_PACKET_VERIFY_UNKNOWN_ERR_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsUnknownErrorCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_RQ_DEBUG_COUNTER_1)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack({
                            metricsDebugCounter7Reg,
                            metricsDebugCounter6Reg,
                            metricsDebugCounter5Reg,
                            metricsDebugCounter4Reg,
                            metricsDebugCounter3Reg,
                            metricsDebugCounter2Reg,
                            metricsDebugCounter1Reg,
                            metricsDebugCounter0Reg
                        })};
                    end
                    default: begin
                        return tagged CsrNodeResultNotMatched;
                    end
                endcase
            end
        endactionvalue
    endfunction
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_ONE), "mkInputPacketClassifier");
    mkConnection(packetParser.csrUpStreamPort, csrNode.downStreamPortsVec[0]);

    rule printDebugInfo;
        if (!payloadStorage.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ payloadStorage");
        if (!checkQpcAndMrTablePipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ checkQpcAndMrTablePipeQ");
        if (!checkMrTableStep2PipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ checkMrTableStep2PipeQ");
        if (!checkMrTableStep3PipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ checkMrTableStep3PipeQ");
        if (!issuePayloadConReqOrDiscardPipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ issuePayloadConReqOrDiscardPipeQ");
        if (!handleConRespPipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ handleConRespPipeQ");
        if (!metaReportDescPipeOutQueue.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ metaReportDescPipeOutQueue");
        if (!autoAckGenReqPipeOutQueue.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ autoAckGenReqPipeOutQueue");
        if (!genCnpReqPipeOutQueue.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ genCnpReqPipeOutQueue");
        if (!handleGenMetaReportQueueDescPipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ handleGenMetaReportQueueDescPipeQ");
        
    endrule


    rule sendQpcQueryReqAndSomeSimpleParse;
        let curFpDebugTime <- getSimulationTime;
        let rdmaPacketMeta = packetParser.rdmaPacketMetaPipeOut.first;
        packetParser.rdmaPacketMetaPipeOut.deq;

        let peerMacIpUdpMeta = packetParser.rdmaMacIpUdpMetaPipeOut.first;
        packetParser.rdmaMacIpUdpMetaPipeOut.deq;

        let bth = rdmaPacketMeta.header.bth;
        let reth = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);

        let qpcQueryResp = ReadReqQPC{
            qpn: bth.dqpn,
            needCheckKey: True
        };
        qpcQueryCltInst.putReq(qpcQueryResp);

        
        
        let isRespNeedDMAWrite  = rdmaRespNeedDmaWrite(bth.opcode);
        let isReqNeedDMAWrite   = rdmaReqNeedDmaWrite(bth.opcode);
        let isZeroPayload       = isZeroR(reth.dlen);
        let isNeedQueryMrTable  = (isRespNeedDMAWrite || isReqNeedDMAWrite) && !isZeroPayload;
        let isFirstPacket       = isFirstRdmaOpCode(bth.opcode);


        let packetStatus = RdmaRecvPacketStatusNormal;

        if (isNeedQueryMrTable) begin
            let mrTableQueryReq = MrTableQueryReq{
                idx: rkey2IndexMR(reth.rkey)
            };
            mrTableQueryCltInst.putReq(mrTableQueryReq);

            if (getMrRawIndexPartFromRkey(reth.rkey) >= fromInteger(valueOf(MAX_MR))) begin
                packetStatus = RdmaRecvPacketStatusMrIdxOverflow;
            end
        end

        
        if (getQpnRawIndexPart(bth.dqpn) >= fromInteger(valueOf(MAX_QP))) begin
            packetStatus = RdmaRecvPacketStatusQpIdxOverflow;
        end

        

        let pipelineEntryOut = CheckQpcAndMrTablePipelineEntry{
            rdmaPacketMeta      : rdmaPacketMeta,
            packetStatus        : packetStatus,
            isNeedQueryMrTable  : isNeedQueryMrTable,
            isZeroPayload       : isZeroPayload,
            isFirstPacket       : isFirstPacket,
            peerMacIpUdpMeta    : peerMacIpUdpMeta,
            fpDebugTime         : curFpDebugTime
        };
        checkQpcAndMrTablePipeQ.enq(pipelineEntryOut);

        $display(
            "time=%0t:", $time, toGreen(" mkRQ sendQpcQueryReqAndSomeSimpleParse"),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut),
            toBlue(", isRespNeedDMAWrite="), fshow(isRespNeedDMAWrite),
            toBlue(", isReqNeedDMAWrite="), fshow(isReqNeedDMAWrite),
            toBlue(", reth="), fshow(reth)
        );
        checkFullyPipeline(rdmaPacketMeta.fpDebugTime, 1, 2000, DebugConf{name: "mkRQ sendQpcQueryReqAndSomeSimpleParse", enableDebug: True});
        metricsDebugCounter0Reg <= metricsDebugCounter0Reg + 1;
    endrule

    rule checkQpcAndMrTable;
        let curFpDebugTime <- getSimulationTime;
        let pipelineEntryIn = checkQpcAndMrTablePipeQ.first;
        checkQpcAndMrTablePipeQ.deq;

        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let bth = rdmaPacketMeta.header.bth;
        let reth = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);
        let packetStatus = pipelineEntryIn.packetStatus;
        let isNeedQueryMrTable = pipelineEntryIn.isNeedQueryMrTable;
        let isFirstPacket = pipelineEntryIn.isFirstPacket;
        let isZeroPayload = pipelineEntryIn.isZeroPayload;

        let isSendReq            = isSendReqRdmaOpCode(bth.opcode);
        let isWriteReq           = isWriteReqRdmaOpCode(bth.opcode);
        let isReadReq            = isReadReqRdmaOpCode(bth.opcode);
        let isAtomicReq          = isAtomicReqRdmaOpCode(bth.opcode);
        let isReadResp           = isReadRespRdmaOpCode(bth.opcode);

        Bool                            isQpKeyCheckPass            = False;
        Bool                            isQpAccCheckPass            = False; 
        Bool                            isMrKeyCheckPass            = False;
        Bool                            isMrAccCheckPass            = False; 
        Bool                            isMrLowerAddrBoundOk        = False;
        MemRegionTableEntry             mrEntryUnwraped             = ?;
        PktFragNum                      zerobasedExpectedPayloadBeatNum      = ?;
        Length                          packetLen                   = ?;
        TruncatedAddrForMrBoundCheck    deltaLen                    = ?;

        let qpcMaybe <- qpcQueryCltInst.getResp;
        if (qpcMaybe matches tagged Valid .qpc) begin
            if (getKeyQP(bth.dqpn) == qpc.qpnKeyPart) begin
                isQpKeyCheckPass = True;
            end

            if (isNeedQueryMrTable) begin
                case ({ pack(isSendReq || isWriteReq), pack(isReadReq), pack(isAtomicReq), pack(isReadResp) })
                    4'b1000: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_REMOTE_WRITE);
                    end
                    4'b0100: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_REMOTE_READ);
                    end
                    4'b0010: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_REMOTE_ATOMIC);
                    end
                    4'b0001: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_LOCAL_WRITE);
                    end
                    default: begin
                        immFail(
                            "unreachible case @ mkReqHandleRQ",
                            $format(
                                "isSendReq=", fshow(isSendReq),
                                ", isWriteReq=", fshow(isWriteReq),
                                ", isReadReq=", fshow(isReadReq),
                                ", isAtomicReq=", fshow(isAtomicReq),
                                ", bth=", fshow(bth)
                            )
                        );
                    end
                endcase
            end
            else begin
                isQpAccCheckPass = True;
            end

            // Note: For "Only" type packet the reth.len is also the packet len, only the "First" type packet has to calculate.
            ChunkAlignLogValue pmtuAlignLogVal = getPmtuSizeByPmtuEnum(qpc.pmtu);
            Length pmtuByteSize = 1 << pmtuAlignLogVal;
            Length addrALignToPmtuMask = pmtuByteSize - 1;
            let startAddrOffsetAlignedToPmtu = reth.va & (signExtend(addrALignToPmtuMask));
            Length calculatedFirstPacketLen = pmtuByteSize - truncate(startAddrOffsetAlignedToPmtu);
            packetLen = isFirstPacket ? calculatedFirstPacketLen : reth.dlen;

            ADDR rethEndAddrForBeatCountCalc = reth.va + zeroExtend(packetLen) - 1;
            // Since each packet is at most 4kB, which use 13 bit, a Word is 16 bit, which is big enough.
            Word startAddrAsDwordOffset = truncate(reth.va >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
            Word endAddrAsDwordOffset = truncate(rethEndAddrForBeatCountCalc >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM));
            Word zeroBasedDwordCntInThisPacket = endAddrAsDwordOffset - startAddrAsDwordOffset;
            Word zeroBasedBeatCntInThisPacket = zeroBasedDwordCntInThisPacket >> (valueOf(TLog#(DWORD_CNT_PER_DATA_BUS_BEAT)));
            zerobasedExpectedPayloadBeatNum = truncate(zeroBasedBeatCntInThisPacket);

            if (isNeedQueryMrTable) begin
                let mrEntryMaybe <- mrTableQueryCltInst.getResp;
                if (mrEntryMaybe matches tagged Valid .mrEntry) begin
                    mrEntryUnwraped = mrEntry;
                    if (rkey2KeyPartMR(reth.rkey) == mrEntry.keyPart) begin
                        isMrKeyCheckPass = True;
                    end

                    case ({pack(isSendReq), pack(isReadReq), pack(isWriteReq || isReadResp), pack(isAtomicReq)})
                        4'b1000: begin  // Send
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_LOCAL_WRITE);
                        end
                        4'b0100: begin  // Read
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_REMOTE_READ);
                        end
                        4'b0010: begin  // Write
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_REMOTE_WRITE);
                        end
                        4'b0001: begin  // Atomic
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_REMOTE_ATOMIC);
                        end
                        default: begin
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_LOCAL_WRITE);
                        end
                    endcase

                    isMrLowerAddrBoundOk = reth.va >= mrEntry.baseVA;
                    
                    // The MR boundary check is a little trick. The straightforward way to check is to compare
                    //     (req.addr + req.len <= mr.startAddr + mr.len)
                    //
                    // But this way has many issues, first, we don't want to do many 64-bit add and compare;
                    // second, this can't handle overflow, unless we use a 65 bit to do the math.
                    // So, we use substruct instead of addition, we only care the the requests memory access span.
                    // The ( req.addr + req.len ) is the access upper memory boundary
                    // The ( req.addr + req.len - mr.startAddr ) is the span between MR's start address to  
                    // access request's upper boundary. ** The length of this span must not exceed MR's length **.
                    // 
                    // On the other hand, Since the access length is 32 bits, and to handle overflow, 
                    // we only need to care 33 bits. Like handling a ringbuf's address, we can think those 
                    // add and sub math is moving a point on a circle, and the substract result is the arc 
                    // on this circle.
                    // 
                    // Last, for the queation ( req.addr + req.len - mr.startAddr ),
                    // req.len is calucated in this beat, so it can't meet timing. So we have to change the
                    // operation order to ( (req.addr - mr.startAddr) + req.len ).
                    // In this beat, only calculate (req.addr - mr.startAddr)
                    TruncatedAddrForMrBoundCheck shortMrStartVa = truncate(mrEntry.baseVA);
                    TruncatedAddrForMrBoundCheck shortReqStartVa = truncate(reth.va);
                    deltaLen = shortReqStartVa - shortMrStartVa;
                end
            end
            else begin
                isMrKeyCheckPass = True;
                isMrAccCheckPass = True;
            end
        end

        if (isRecvPacketStatusNormal(packetStatus)) begin
            if (!isQpKeyCheckPass) begin
                packetStatus = RdmaRecvPacketStatusInvalidQpContext;
            end
            else if (!isQpAccCheckPass) begin
                packetStatus = RdmaRecvPacketStatusInvalidQpAccessFlag;
            end
            else if (!isMrKeyCheckPass) begin
                packetStatus = RdmaRecvPacketStatusInvalidMrKey;
            end
            else if (!isMrAccCheckPass) begin
                packetStatus = RdmaRecvPacketStatusInvalidMrAccessFlag;
            end
        end

        let pipelineEntryOut = CheckMrTableStep2PipelineEntry{
            rdmaPacketMeta          : rdmaPacketMeta,
            packetStatus            : packetStatus,
            isNeedQueryMrTable      : isNeedQueryMrTable,
            isZeroPayload           : isZeroPayload,
            mrEntry                 : mrEntryUnwraped,
            qpc                     : unwrapMaybe(qpcMaybe),
            isMrLowerAddrBoundOk    : isMrLowerAddrBoundOk,
            zerobasedExpectedPayloadBeatNum  : zerobasedExpectedPayloadBeatNum,
            packetLen               : packetLen,
            deltaLen                : deltaLen,
            peerMacIpUdpMeta        : pipelineEntryIn.peerMacIpUdpMeta,
            fpDebugTime             : curFpDebugTime
        };
        checkMrTableStep2PipeQ.enq(pipelineEntryOut);

        $display(
            "time=%0t:", $time, toGreen(" mkRQ checkQpcAndMrTable"),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
        // QPC and MR Table need 11 beat for worst case to generate resp.
        // For QPC, packte without payload can occur, which is 3 beats, then the arbiter's keep order queue depth should be at least 4
        // For MR Table, packet must have payload, which is at least 4 beats, then the arbiter's keep order queue depth should be at least 3
        checkFullyPipeline(pipelineEntryIn.fpDebugTime, 11, 2000, DebugConf{name: "mkRQ checkQpcAndMrTable", enableDebug: True});
        metricsDebugCounter1Reg <= metricsDebugCounter1Reg + 1;
    endrule
    

    rule checkMrTableStep2;
        let curFpDebugTime <- getSimulationTime;
        let pipelineEntryIn = checkMrTableStep2PipeQ.first;
        checkMrTableStep2PipeQ.deq;

        let deltaLen = pipelineEntryIn.deltaLen;
        let packetLen = pipelineEntryIn.packetLen;

        deltaLen = deltaLen + zeroExtend(packetLen);

        let pipelineEntryOut = CheckMrTableStep3PipelineEntry{
            rdmaPacketMeta          : pipelineEntryIn.rdmaPacketMeta,
            packetStatus            : pipelineEntryIn.packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            isZeroPayload           : pipelineEntryIn.isZeroPayload,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            isMrLowerAddrBoundOk    : pipelineEntryIn.isMrLowerAddrBoundOk,
            zerobasedExpectedPayloadBeatNum  : pipelineEntryIn.zerobasedExpectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen,
            deltaLen                : deltaLen,
            peerMacIpUdpMeta        : pipelineEntryIn.peerMacIpUdpMeta,
            fpDebugTime         : curFpDebugTime
        };
        checkMrTableStep3PipeQ.enq(pipelineEntryOut);
        $display(
            "time=%0t:", $time, toGreen(" mkRQ checkMrTableStep2"),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
        checkFullyPipeline(pipelineEntryIn.fpDebugTime, 1, 2000, DebugConf{name: "mkRQ checkMrTableStep2", enableDebug: True});
        metricsDebugCounter2Reg <= metricsDebugCounter2Reg + 1;
    endrule

    rule checkMrTableStep3;
        let curFpDebugTime <- getSimulationTime;

        let pipelineEntryIn = checkMrTableStep3PipeQ.first;
        checkMrTableStep3PipeQ.deq;

        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let zerobasedExpectedPayloadBeatNum = pipelineEntryIn.zerobasedExpectedPayloadBeatNum;
        let isNeedQueryMrTable = pipelineEntryIn.isNeedQueryMrTable;
        let deltaLen = pipelineEntryIn.deltaLen;
        let packetLen = pipelineEntryIn.packetLen;
        let mrEntry = pipelineEntryIn.mrEntry;

        Bool isMrUpperAddrBoundOk = deltaLen <= zeroExtend(mrEntry.len);

        Bool isAccessRangeCheckPass = False;
        Bool isPacketBeatCountCheckPass = False;
        let packetTailMeta = ?;

        if (rdmaPacketMeta.hasPayload) begin
            packetParser.rdmaPacketTailMetaPipeOut.deq;
        end

        if (isRecvPacketStatusNormal(packetStatus)) begin
            if (rdmaPacketMeta.hasPayload) begin
                packetTailMeta = packetParser.rdmaPacketTailMetaPipeOut.first;
                if (packetTailMeta.beatCnt - 1 == zerobasedExpectedPayloadBeatNum) begin
                    isPacketBeatCountCheckPass = True;
                end
            end
            else begin
                isPacketBeatCountCheckPass = True;
            end

            if (isNeedQueryMrTable) begin
                // if we reach here, then mrEntry must be a valid value, so we can safely use isMrUpperAddrBoundOk.
                isAccessRangeCheckPass = pipelineEntryIn.isMrLowerAddrBoundOk && isMrUpperAddrBoundOk;

                if (!isAccessRangeCheckPass) begin
                    packetStatus = RdmaRecvPacketStatusMemAccessOutOfBound;
                end
                else if (!isPacketBeatCountCheckPass) begin
                    packetStatus = RdmaRecvPacketStatusCorruptPktLength;
                end
            end
        end


        let pipelineEntryOut = IssuePayloadConReqOrDiscardPipelineEntry{
            rdmaPacketMeta          : rdmaPacketMeta,
            packetStatus            : packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            isZeroPayload           : pipelineEntryIn.isZeroPayload,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            zerobasedExpectedPayloadBeatNum  : pipelineEntryIn.zerobasedExpectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen,
            peerMacIpUdpMeta        : pipelineEntryIn.peerMacIpUdpMeta,
            fpDebugTime             : curFpDebugTime
        };
        issuePayloadConReqOrDiscardPipeQ.enq(pipelineEntryOut);
        $display(
            "time=%0t:", $time, toGreen(" mkRQ checkMrTableStep3"),
            toBlue(", packetTailMeta="), fshow(packetTailMeta),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
        metricsDebugCounter3Reg <= metricsDebugCounter3Reg + 1;
    endrule



    rule issuePayloadConReqOrDiscard;
        let curFpDebugTime <- getSimulationTime;

        let pipelineEntryIn = issuePayloadConReqOrDiscardPipeQ.first;
        issuePayloadConReqOrDiscardPipeQ.deq;
        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let bth = rdmaPacketMeta.header.bth;
        let reth = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);
        let mrEntry = pipelineEntryIn.mrEntry;

        Bool discardDebugFlag = True;
        if (rdmaPacketMeta.hasPayload) begin
            let isDiscard = !isRecvPacketStatusNormal(packetStatus);
            filterCmdQ.enq(isDiscard);
            if (!isDiscard) begin
                let payloadConReq = PayloadConReq{
                    addr        : reth.va,
                    len         : pipelineEntryIn.packetLen,
                    baseVA      : mrEntry.baseVA,    
                    pgtOffset   : mrEntry.pgtOffset,
                    fpDebugTime : curFpDebugTime
                };
                conReqPipeOutQ.enq(payloadConReq);
                discardDebugFlag = False;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkRQ issuePayloadConReqOrDiscard"),
                //     toBlue(", payloadConReq="), fshow(payloadConReq)
                // );
            end
        end
        else begin
            discardDebugFlag = False;
        end

        let pipelineEntryOut = HandleConRespPipelineEntry{
            rdmaPacketMeta          : pipelineEntryIn.rdmaPacketMeta,
            packetStatus            : pipelineEntryIn.packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            isZeroPayload           : pipelineEntryIn.isZeroPayload,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            zerobasedExpectedPayloadBeatNum  : pipelineEntryIn.zerobasedExpectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen,
            peerMacIpUdpMeta        : pipelineEntryIn.peerMacIpUdpMeta,
            fpDebugTime         : curFpDebugTime
        };
        handleConRespPipeQ.enq(pipelineEntryOut);


        case (packetStatus)
            RdmaRecvPacketStatusInvalidQpAccessFlag : metricsInvalidQpAccessCntReg      <= metricsInvalidQpAccessCntReg     + 1;
            RdmaRecvPacketStatusInvalidOpcode       : metricsInvalidOpcodeCntReg        <= metricsInvalidOpcodeCntReg       + 1;
            RdmaRecvPacketStatusInvalidMrKey        : metricsInvalidMrKeyCntReg         <= metricsInvalidMrKeyCntReg        + 1;
            RdmaRecvPacketStatusMemAccessOutOfBound : metricsMemAccessOutOfBoundCntReg  <= metricsMemAccessOutOfBoundCntReg + 1;
            RdmaRecvPacketStatusInvalidMrAccessFlag : metricsInvalidMrAccessFlagCntReg  <= metricsInvalidMrAccessFlagCntReg + 1;
            RdmaRecvPacketStatusInvalidHeader       : metricsInvalidHeaderCntReg        <= metricsInvalidHeaderCntReg       + 1;
            RdmaRecvPacketStatusInvalidQpContext    : metricsInvalidQpContextCntReg     <= metricsInvalidQpContextCntReg    + 1;
            RdmaRecvPacketStatusCorruptPktLength    : metricsCorruptPktLengthCntReg     <= metricsCorruptPktLengthCntReg    + 1;
            RdmaRecvPacketStatusUnknown             : metricsUnknownErrorCntReg         <= metricsUnknownErrorCntReg        + 1;
        endcase

        $display(
            "time=%0t:", $time, toGreen(" mkRQ issuePayloadConReqOrDiscard"),
            discardDebugFlag ? toRed(" Discard!") : " keeped",
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
        checkFullyPipeline(pipelineEntryIn.fpDebugTime, 1, 2000, DebugConf{name: "mkRQ issuePayloadConReqOrDiscard", enableDebug: True});
        metricsDebugCounter4Reg <= metricsDebugCounter4Reg + 1;
    endrule

    rule handleConResp;

        function Bool isOnlyWithImm(RdmaOpCode opCode);
            case(opCode)
                SEND_ONLY_WITH_IMMEDIATE,
                RDMA_WRITE_ONLY_WITH_IMMEDIATE: return True;
                default: return False;
            endcase
        endfunction

        let curFpDebugTime <- getSimulationTime;

        let pipelineEntryIn = handleConRespPipeQ.first;
        handleConRespPipeQ.deq;
        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let isDiscard = !isRecvPacketStatusNormal(packetStatus);

        let bth             = rdmaPacketMeta.header.bth;

        if (rdmaPacketMeta.hasPayload) begin
            if (!isDiscard) begin
                let resp = conRespPipeInQ.first;
                conRespPipeInQ.deq;
                $display("mkRQ[%d] payload con resp = ", channelIdx, fshow(resp));
            end
        end

        if (!isDiscard) begin
            let pipelineEntryOut = GenMetaReportQueueDescPipelineEntry{
                rdmaPacketMeta      : pipelineEntryIn.rdmaPacketMeta,
                fpDebugTime         : curFpDebugTime
            };
            handleGenMetaReportQueueDescPipeQ.enq(pipelineEntryOut);

            let needUpdatePsnBitmap = isOnlyWithImm(bth.opcode) || rdmaPacketMeta.hasPayload;
            if (needUpdatePsnBitmap) begin
                let autoAckReq = AutoAckGeneratorReq{
                    psn: bth.psn,
                    qpn: bth.dqpn,
                    qpc: pipelineEntryIn.qpc
                };
                autoAckGenReqPipeOutQueue.enq(autoAckReq);
                $display("mkRQ[%d] enq autoAckReq = ", channelIdx, fshow(autoAckReq));
            end

            // need to check packet type to avoid cpn packet looping
            if (rdmaPacketMeta.isEcnMarked && bth.trans != TRANS_TYPE_CNP) begin
                genCnpReqPipeOutQueue.enq(CnpPacketGenReq {
                    peerAddrInfo    : pipelineEntryIn.peerMacIpUdpMeta,
                    peerQpn         : pipelineEntryIn.qpc.peerQPN,
                    peerMsn         : bth.msn,
                    localUdpPort    : pipelineEntryIn.qpc.localUdpPort
                });
            end
            
        end

        $display(
            "time=%0t:", $time, toGreen(" mkRQ[%d] handleConResp"), channelIdx
        );
        metricsDebugCounter5Reg <= metricsDebugCounter5Reg + 1;
    endrule
   

    rule genMetaReportQueueDesc;
        let curFpDebugTime <- getSimulationTime;

        // write them in a function to make sure they are all comb logic.
        function Tuple3#(Vector#(NUMERIC_TYPE_TWO, Maybe#(RingbufRawDescriptor)), Bool, Bool) genDescVector();
            let pipelineEntryIn = handleGenMetaReportQueueDescPipeQ.first;
            let rdmaPacketMeta  = pipelineEntryIn.rdmaPacketMeta;

            let bth             = rdmaPacketMeta.header.bth;
            let opcode          = {pack(bth.trans), pack(bth.opcode)};
            let reth            = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);
            let rreth           = extractRRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans, bth.opcode);
            let aeth            = extractAETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans, bth.opcode);
            let immDT           = extractImmDt(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans, bth.opcode);

            let commonHeader = RingbufDescCommonHead {
                valid           : True,
                hasNextFrag     : False,
                reserved0       : unpack(0),
                isExtendOpcode  : False,
                opCode          : opcode
            };

            Maybe#(RingbufRawDescriptor) rawDescToEnqueueMaybe0 = tagged Invalid;
            Maybe#(RingbufRawDescriptor) rawDescToEnqueueMaybe1 = tagged Invalid;
            Bool decodeSuccess = True;
            Bool noNeedToGenDesc = False;
            case (opcode)
                fromInteger(valueOf(RC_SEND_FIRST)),
                fromInteger(valueOf(RC_SEND_LAST)),
                fromInteger(valueOf(RC_SEND_LAST_WITH_IMMEDIATE)),
                fromInteger(valueOf(RC_SEND_ONLY)),
                fromInteger(valueOf(RC_SEND_ONLY_WITH_IMMEDIATE)),
                fromInteger(valueOf(RC_RDMA_WRITE_FIRST)),
                fromInteger(valueOf(RC_RDMA_WRITE_LAST)),
                fromInteger(valueOf(RC_RDMA_WRITE_LAST_WITH_IMMEDIATE)),
                fromInteger(valueOf(RC_RDMA_WRITE_ONLY)),
                fromInteger(valueOf(RC_RDMA_WRITE_ONLY_WITH_IMMEDIATE)),
                fromInteger(valueOf(RC_RDMA_READ_REQUEST)),
                fromInteger(valueOf(RC_RDMA_READ_RESPONSE_FIRST)),
                fromInteger(valueOf(RC_RDMA_READ_RESPONSE_LAST)),
                fromInteger(valueOf(RC_RDMA_READ_RESPONSE_ONLY)):
                begin
                    let desc0 = MetaReportQueuePacketBasicInfoDesc{
                        immData     :   immDT,
                        rkey        :   reth.rkey,
                        raddr       :   reth.va,
                        totalLen    :   reth.dlen,
                        reserved1   :   unpack(0),
                        dqpn        :   bth.dqpn,
                        reserved0   :   unpack(0),
                        ackReq      :   bth.ackReq,
                        solicited   :   bth.solicited,
                        ecnMarked   :   ?,
                        isRetry     :   bth.isRetry,
                        psn         :   bth.psn,
                        msn         :   bth.msn,
                        commonHeader:   commonHeader
                    };
                    

                    if (opcode == fromInteger(valueOf(RC_RDMA_READ_REQUEST))) begin
                        desc0.commonHeader.hasNextFrag = True;
                        let desc1 = MetaReportQueueReadReqExtendInfoDesc{
                            reserved2   :   unpack(0),
                            reserved1   :   unpack(0),
                            lkey        :   rreth.lkey,
                            laddr       :   rreth.va,
                            totalLen    :   reth.dlen,
                            reserved0   :   unpack(0),
                            commonHeader:   commonHeader
                        };
                        rawDescToEnqueueMaybe1 = tagged Valid unpack(pack(desc1));
                    end
                    rawDescToEnqueueMaybe0 = tagged Valid unpack(pack(desc0));
                end
                fromInteger(valueOf(RC_SEND_MIDDLE)),
                fromInteger(valueOf(RC_RDMA_WRITE_MIDDLE)),
                fromInteger(valueOf(RC_RDMA_READ_RESPONSE_MIDDLE)):
                begin
                    if (bth.isRetry) begin
                        let desc0 = MetaReportQueuePacketBasicInfoDesc{
                            immData     :   immDT,
                            rkey        :   reth.rkey,
                            raddr       :   reth.va,
                            totalLen    :   reth.dlen,
                            reserved1   :   unpack(0),
                            dqpn        :   bth.dqpn,
                            reserved0   :   unpack(0),
                            ackReq      :   bth.ackReq,
                            solicited   :   bth.solicited,
                            ecnMarked   :   ?,
                            isRetry     :   bth.isRetry,
                            psn         :   bth.psn,
                            msn         :   bth.msn,
                            commonHeader:   commonHeader
                        };
                        rawDescToEnqueueMaybe0 = tagged Valid unpack(pack(desc0));
                    end
                    else begin
                        noNeedToGenDesc = True;
                    end
                end
                fromInteger(valueOf(RC_ACKNOWLEDGE)):
                begin
                    let desc0 = MetaReportQueueAckDesc{
                        nowBitmap       : aeth.newBitmap,
                        msn             : bth.msn,
                        qpn             : bth.dqpn,       
                        psnNow          : bth.psn,
                        reserved2       : unpack(0),
                        psnBeforeSlide  : aeth.preBitmapPsn,
                        reserved1       : unpack(0),
                        isPacketLost    : aeth.isPacketLost,
                        isWindowSlided  : aeth.isWindowSlided,
                        isSendByDriver  : aeth.isSendByDriver,
                        isSendByLocalHw : False,
                        reserved0       : unpack(0),
                        commonHeader    : commonHeader
                    };

                    if (aeth.isWindowSlided) begin
                        desc0.commonHeader.hasNextFrag = True;
                        let desc1 = MetaReportQueueAckExtraDesc{
                            preBitmap   :   aeth.preBitmap,
                            reserved2   :   unpack(0),
                            reserved1   :   unpack(0),
                            reserved0   :   unpack(0),
                            commonHeader:   commonHeader
                        };
                        rawDescToEnqueueMaybe1 = tagged Valid unpack(pack(desc1));
                    end
                    rawDescToEnqueueMaybe0 = tagged Valid unpack(pack(desc0));
                end


                default: begin
                    decodeSuccess = False;
                end
            endcase
            return tuple3(vec(rawDescToEnqueueMaybe0, rawDescToEnqueueMaybe1), decodeSuccess, noNeedToGenDesc);
        endfunction

        let {vecToEnqMaybe, decodeSuccess, noNeedToGenDesc} = genDescVector;

        if (!decodeSuccess) begin
            $display("Warn: Received Not Supported Packet, Will not report to software.");
            handleGenMetaReportQueueDescPipeQ.deq;
        end
        else begin
            let vecToEnq = vec(fromMaybe(?, vecToEnqMaybe[0]), fromMaybe(?, vecToEnqMaybe[1]));

            // Becareful of the useless guard of MIMO when processing more than one element.
            if (isValid(vecToEnqMaybe[0]) && isValid(vecToEnqMaybe[1])) begin
                if (metaReportMimoQueue.enqReadyN(2)) begin
                    metaReportMimoQueue.enq(2, vecToEnq);
                    handleGenMetaReportQueueDescPipeQ.deq;
                end
            end
            else if (isValid(vecToEnqMaybe[0])) begin
                if (metaReportMimoQueue.enqReadyN(1)) begin
                    metaReportMimoQueue.enq(1, vecToEnq);
                    handleGenMetaReportQueueDescPipeQ.deq;
                end
            end
            else begin
                if (noNeedToGenDesc) begin
                    handleGenMetaReportQueueDescPipeQ.deq;
                end
                else begin
                    // metaReportMimoQueue doesn't have enough space, so nothing to do, and no need to deq;
                end
            end
        end


        $display(
            "time=%0t:", $time, toGreen(" mkRQ[%d] genMetaReportQueueDesc"), channelIdx,
            toBlue(", vecToEnqMaybe="), fshow(vecToEnqMaybe)
        );
        metricsDebugCounter6Reg <= metricsDebugCounter6Reg + 1;
    endrule

    rule forwardMetaReportDescToOutput;
        let curFpDebugTime <- getSimulationTime;
        if (metaReportMimoQueue.deqReadyN(1)) begin
            metaReportMimoQueue.deq(1);
            let desc = metaReportMimoQueue.first[0];
            metaReportDescPipeOutQueue.enq(desc);

            $display(
                "time=%0t:", $time, toGreen(" mkRQ[%d] forwardMetaReportDescToOutput"), channelIdx,
                toBlue(", desc="), fshow(desc)
            );
        end
    endrule

    rule filterDiscardedPayloadStream;
        let curFpDebugTime <- getSimulationTime;
        let isDiscard = filterCmdQ.first;
        let ds = payloadStorage.first;
        payloadStorage.deq;

        if (!isDiscard) begin
            filteredDataStreamForConsumeQ.enq(ds);
        end

        if (ds.isLast) begin
            filterCmdQ.deq;
        end

        $display(
            "time=%0t:", $time, toGreen(" mkRQ[%d] filterDiscardedPayloadStream"), channelIdx,
            isDiscard ? toRed(" Discard!") : " keeped",
            toBlue(", ds="), fshow(ds)
        );
        metricsDebugCounter7Reg <= metricsDebugCounter7Reg + 1;
    endrule

    interface csrUpStreamPort           = csrNode.upStreamPort;
    interface qpcQueryClt               = qpcQueryCltInst.clt;
    interface mrTableQueryClt           = mrTableQueryCltInst.clt;

    interface ethernetFramePipeIn       = packetParser.ethernetFramePipeIn;
    interface otherRawPacketPipeOut     = packetParser.otherRawPacketPipeOut;

    interface payloadConReqPipeOut      = toPipeOut(conReqPipeOutQ);
    interface payloadConStreamPipeOut   = toPipeOut(filteredDataStreamForConsumeQ);
    interface payloadConRespPipeIn      = toPipeIn(conRespPipeInQ);

    method setLocalNetworkSettings      = packetParser.setLocalNetworkSettings; 

    interface metaReportDescPipeOut     = toPipeOut(metaReportDescPipeOutQueue);
    interface autoAckGenReqPipeOut      = toPipeOut(autoAckGenReqPipeOutQueue);
    interface genCnpReqPipeOut          = toPipeOut(genCnpReqPipeOutQueue);
endmodule


