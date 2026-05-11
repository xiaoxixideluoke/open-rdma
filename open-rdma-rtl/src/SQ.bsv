import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

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

interface SQ;
    interface PipeInB0#(WorkQueueElem) wqePipeIn;

    interface PipeOut#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeOut;
    interface PipeOut#(RdmaSendPacketMeta)          rdmaPacketMetaPipeOut;
    interface PipeOut#(DataStream)                  rdmaPayloadPipeOut;

    interface ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

    interface PipeOut#(PayloadGenReq) payloadGenReqPipeOut;
    interface PipeIn#(DataStream) payloadGenRespPipeIn;
endinterface

(* synthesize *)
module mkSQ(SQ);

    let packetGen <- mkPacketGen;
    
    interface wqePipeIn = packetGen.wqePipeIn;
    
    interface macIpUdpMetaPipeOut = packetGen.macIpUdpMetaPipeOut;
    interface rdmaPacketMetaPipeOut = packetGen.rdmaPacketMetaPipeOut;
    interface rdmaPayloadPipeOut = packetGen.rdmaPayloadPipeOut;

    interface mrTableQueryClt = packetGen.mrTableQueryClt;

    interface payloadGenReqPipeOut = packetGen.genReqPipeOut;
    interface payloadGenRespPipeIn = packetGen.genRespPipeIn;
endmodule