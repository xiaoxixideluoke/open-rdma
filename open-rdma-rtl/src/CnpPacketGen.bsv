import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;

import Settings :: *;
import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import AddressChunker :: *;
import RdmaHeaders :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import Ringbuf :: *;
import Descriptors :: *;
import EthernetTypes :: *;
import EthernetFrameIO256 :: *;

typedef struct {
    ThinMacIpUdpMetaDataForRecv peerAddrInfo;
    QPN                         peerQpn;
    MSN                         peerMsn;
    UdpPort                     localUdpPort;
} CnpPacketGenReq deriving(Bits, FShow);

typedef 32 CNP_PAUSE_COUNTER_WIDTH;
typedef Bit#(CNP_PAUSE_COUNTER_WIDTH) CnpPauseCounter;

typedef 8192 CNP_PAUSE_TICK_CNT;

typedef struct {
    CnpPauseCounter cnpPauseCounter;
} CnpGenContextEntry deriving(Bits, FShow);

interface CnpPacketGenerator;
    interface PipeInB0#(CnpPacketGenReq)            genReqPipeIn;

    interface PipeOut#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeOut;
    interface PipeOut#(RdmaSendPacketMeta)          rdmaPacketMetaPipeOut;
    interface PipeOut#(DataStream)                  rdmaPayloadPipeOut;
endinterface

(* synthesize *)
module mkCnpPacketGenerator(CnpPacketGenerator);
    PipeInAdapterB0#(CnpPacketGenReq) genReqPipeInQueue <- mkPipeInAdapterB0;

    FIFOF#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeOutQueue <- mkSizedFIFOF(4);
    FIFOF#(RdmaSendPacketMeta) rdmaPacketMetaPipeOutQueue <- mkSizedFIFOF(4);
    FIFOF#(DataStream) rdmaPayloadPipeOutQueue <- mkFIFOF;  // dummy one, not used

    AutoInferBramQueuedOutput#(IndexQP, CnpGenContextEntry) storage <- mkAutoInferBramQueuedOutput(False, "", "mkCnpPacketGenerator");

    FIFOF#(CnpPacketGenReq) genPacketPipelineQueue <- mkSizedFIFOF(4);

    Reg#(CnpPauseCounter) cnpPauseCounterNowReg <- mkReg(0);

    rule incrCounter;
        cnpPauseCounterNowReg <= cnpPauseCounterNowReg + 1;
    endrule

    rule genContextReadReq;
        let req = genReqPipeInQueue.first;
        genReqPipeInQueue.deq;
        storage.putReadReq(getIndexQP(req.peerQpn));
        genPacketPipelineQueue.enq(req);
    endrule

    rule genPacket;
        
        let req = genPacketPipelineQueue.first;
        genPacketPipelineQueue.deq;

        let cnpCtx = storage.readRespPipeOut.first;
        storage.readRespPipeOut.deq;

        if (cnpPauseCounterNowReg - cnpCtx.cnpPauseCounter > fromInteger(valueOf(CNP_PAUSE_TICK_CNT))) begin
            let thinMacIpUdpMetaDataForSend = ThinMacIpUdpMetaDataForSend {
                dstMacAddr      : req.peerAddrInfo.srcMacAddr,
                ipDscp          : 0,
                ipEcn           : pack(IpHeaderEcnFlagEnabled),
                dstIpAddr       : req.peerAddrInfo.srcIpAddr,
                srcPort         : req.localUdpPort,
                dstPort         : fromInteger(valueOf(UDP_PORT_RDMA)),
                udpPayloadLen   : fromInteger(valueOf(RDMA_FIXED_HEADER_BYTE_NUM)),
                ethType         : fromInteger(valueOf(ETH_TYPE_IP))
            };

            let rdmaSendPacketMeta = RdmaSendPacketMeta {
                header:RdmaBthAndExtendHeader{
                    bth: BTH {
                        trans    : TRANS_TYPE_CNP,
                        opcode   : unpack(0),
                        solicited: False,
                        isRetry  : False,
                        padCnt   : unpack(0),
                        tver     : unpack(0),
                        msn      : req.peerMsn,
                        fecn     : unpack(0),
                        becn     : unpack(0),
                        resv6    : unpack(0),
                        dqpn     : req.peerQpn,
                        ackReq   : False,
                        resv7    : unpack(0),
                        psn      : unpack(0)
                    },
                    rdmaExtendHeaderBuf: unpack(0)
                },
                hasPayload: False
            };
            macIpUdpMetaPipeOutQueue.enq(thinMacIpUdpMetaDataForSend);
            rdmaPacketMetaPipeOutQueue.enq(rdmaSendPacketMeta);
            storage.write(getIndexQP(req.peerQpn), CnpGenContextEntry{cnpPauseCounter: cnpPauseCounterNowReg});
        end

    endrule
    
    interface genReqPipeIn = toPipeInB0(genReqPipeInQueue);
    interface macIpUdpMetaPipeOut = toPipeOut(macIpUdpMetaPipeOutQueue);
    interface rdmaPacketMetaPipeOut = toPipeOut(rdmaPacketMetaPipeOutQueue);
    interface rdmaPayloadPipeOut = toPipeOut(rdmaPayloadPipeOutQueue);
    
endmodule