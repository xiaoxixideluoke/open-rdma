import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;
import Printf :: *;

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
import FullyPipelineChecker :: *;


typedef 2048    SIMPLE_NIC_SLOT_BYTE_SIZE;
typedef 2097152 SIMPLE_NIC_BUFFER_BYTE_SIZE;
typedef 512     SIMPLE_NIC_RX_PER_CHANNEL_BUFFER_DEPTH;

typedef TDiv#(SIMPLE_NIC_BUFFER_BYTE_SIZE, SIMPLE_NIC_SLOT_BYTE_SIZE) SIMPLE_NIC_SLOT_CNT;
typedef TLog#(SIMPLE_NIC_SLOT_CNT) SIMPLE_NIC_SLOT_INDEX_WITDH;
typedef TAdd#(1, SIMPLE_NIC_SLOT_INDEX_WITDH)  SIMPLE_NIC_SLOT_COUNT_WITDH;
typedef Bit#(SIMPLE_NIC_SLOT_INDEX_WITDH) SimpleNicSlotIdx;
typedef Bit#(SIMPLE_NIC_SLOT_COUNT_WITDH) SimpleNicSlotCnt;
typedef TDiv#(SIMPLE_NIC_SLOT_BYTE_SIZE, TLog#(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE)) SIMPLE_NIC_STREAM_ALIGN_BLOCK_CNT_PER_SLOT;
typedef Bit#(TAdd#(1, TLog#(SIMPLE_NIC_STREAM_ALIGN_BLOCK_CNT_PER_SLOT))) AlignBlockCntInSimpleNicSlot;

interface SimpleNic;
    interface PipeIn#(IoChannelEthDataStream)                                   rawEthernetPacketPipeIn;
    interface PipeOut#(IoChannelEthDataStream)                                  rawEthernetPacketPipeOut;
    
    interface PipeIn#(RingbufRawDescriptor)                                     simpleNicTxDescPipeIn;
    interface PipeOut#(RingbufRawDescriptor)                                    simpleNicRxDescPipeOut;
    interface IoChannelMemoryMasterPipeB0In                                     simpleNicPacketDmaMasterPipeIfc;
endinterface

(* synthesize *)
module mkSimpleNic(SimpleNic);
    Reg#(SimpleNicSlotIdx) curSlotIdxReg <- mkReg(0);
    Reg#(ADDR) rxBufferBaseAddrReg <- mkReg(0);
    
    FIFOF#(IoChannelEthDataStream) rawEthernetPacketPipeInQueue <- mkLFIFOF;

    FIFOF#(Word) rawEthernetPacketLengthQueue <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_EIGHT));
    Reg#(Word) rawEthernetPacketLengthReg <- mkReg(0);

    FIFOF#(IoChannelEthDataStream) rawEthernetPacketPipeOutQueue <- mkFIFOF;



    FIFOF#(RingbufRawDescriptor) simpleNicDescPipeInQueue <- mkLFIFOF;
    FIFOF#(RingbufRawDescriptor) simpleNicDescPipeOutQueue <- mkFIFOF;

    FIFOF#(IoChannelMemoryAccessMeta)           dmaWriteMetaPipeOutQueue    <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream)     dmaWriteDataPipeOutQueue    <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessMeta)           dmaReadMetaPipeOutQueue     <- mkFIFOF;
    // FIFOF#(IoChannelMemoryAccessDataStream)     dmaReadDataPipeInQueue      <- mkSizedFIFOF(2);

    AddressChunker#(ADDR, Length, ChunkAlignLogValue) rxAddrChunker <- mkAddressChunker;
    AddressChunker#(ADDR, Length, ChunkAlignLogValue) txAddrChunker <- mkAddressChunker;

    let rxAddrChunkerRequestPipeInAdapter <- mkPipeInB0ToPipeIn(rxAddrChunker.requestPipeIn, 1);
    let txAddrChunkerRequestPipeInAdapter <- mkPipeInB0ToPipeIn(txAddrChunker.requestPipeIn, 1);

    DtldStreamConcator#(DATA, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) txConcator <- mkDtldStreamConcator(DebugConf{name: "mkSimpleNic txConcator", enableDebug: True});
    DtldStreamSplitor#(DATA, AlignBlockCntInSimpleNicSlot, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) rxSplitor <- mkDtldStreamSplitor(DebugConf{name: "mkSimpleNic rxSplitor", enableDebug: True});

    // Pipeline FIFO
    FIFOF#(AddressChunkResp#(ADDR, Length)) forwardRxChunkedDataStreamToDmaPipelineQ <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_FOUR));
    FIFOF#(Tuple2#(SimpleNicSlotIdx, Word)) rxDescMetaPipelineQ <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_FOUR));


    // mkConnection(toPipeOut(dmaReadDataPipeInQueue), txConcator.dataPipeIn);
    mkConnection(txConcator.dataPipeOut, toPipeIn(rawEthernetPacketPipeOutQueue));

    let rxSplitorDataPipeInPipeInConverter <- mkPipeInB0ToPipeIn(rxSplitor.dataPipeIn, 128);
    let rxSplitorStreamAlignBlockCountPipeInConverter <- mkPipeInB0ToPipeIn(rxSplitor.streamAlignBlockCountPipeIn, 1);
    let txConcatorIsLastStreamFlagPipeInConverter <- mkPipeInB0ToPipeIn(txConcator.isLastStreamFlagPipeIn, 1);
    

    rule calcPacketLenAndPutToBuffer;
        let ds = rawEthernetPacketPipeInQueue.first;
        rawEthernetPacketPipeInQueue.deq;
        rxSplitorDataPipeInPipeInConverter.enq(ds);

        let newLength = rawEthernetPacketLengthReg + zeroExtend(ds.byteNum);

        if (ds.isLast) begin
            rawEthernetPacketLengthReg <= 0;
            rawEthernetPacketLengthQueue.enq(newLength);
        end
        else begin
            rawEthernetPacketLengthReg <= newLength;
        end
    endrule


    rule forwardRxDsLengthToChunkCalc;


        let totalLen = rawEthernetPacketLengthQueue.first;
        rawEthernetPacketLengthQueue.deq;

        ADDR writeAddr = rxBufferBaseAddrReg + (zeroExtend(curSlotIdxReg) << valueOf(TLog#(SIMPLE_NIC_SLOT_BYTE_SIZE)));
        curSlotIdxReg <= curSlotIdxReg + 1;

        rxAddrChunkerRequestPipeInAdapter.enq(AddressChunkReq{
            startAddr: writeAddr,
            len: zeroExtend(totalLen),
            chunk: fromInteger(valueOf(TLog#(PCIE_MAX_BYTE_IN_BURST)))
        });
        rxDescMetaPipelineQ.enq(tuple2(curSlotIdxReg, totalLen));
    endrule

    rule forwardRxDmaChunkSplitReq;
        let chunkInfo = rxAddrChunker.responsePipeOut.first;
        rxAddrChunker.responsePipeOut.deq;
        let alignBlockCntForDmaBurst = (chunkInfo.len + fromInteger(valueOf(TExp#(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE)) - 1)) >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE);
        rxSplitorStreamAlignBlockCountPipeInConverter.enq(truncate(alignBlockCntForDmaBurst));
        forwardRxChunkedDataStreamToDmaPipelineQ.enq(chunkInfo);
    endrule

    rule forwardRxChunkedDataStreamToDma;
        let ds = rxSplitor.dataPipeOut.first;
        rxSplitor.dataPipeOut.deq;
        let chunkInfo = forwardRxChunkedDataStreamToDmaPipelineQ.first;
        if (ds.isFirst) begin
            let wm = IoChannelMemoryAccessMeta{
                addr        : chunkInfo.startAddr,
                totalLen    : chunkInfo.len,
                accessType  : MemAccessTypeNormalReadWrite,
                operand_1   : 0,
                operand_2   : 0,
                noSnoop     : False
            };
            dmaWriteMetaPipeOutQueue.enq(wm);
        end
        if (ds.isLast) begin
            forwardRxChunkedDataStreamToDmaPipelineQ.deq;

            if (chunkInfo.isLast) begin
                let {slotIdx, totalLen} = rxDescMetaPipelineQ.first;
                rxDescMetaPipelineQ.deq;
                
                let commonHeader = RingbufDescCommonHead {
                    valid           : True,
                    hasNextFrag     : False,
                    reserved0       : unpack(0),
                    isExtendOpcode  : True,  // since it's not standard rdma opcode
                    opCode          : fromInteger(valueOf(SIMPLE_NIC_RX_QUEUE_DESC_OPCODE_NEW_PACKET))
                };

                simpleNicDescPipeOutQueue.enq(pack(SimpleNicRxQueueDesc {
                    reserved3   : unpack(0),
                    reserved2   : unpack(0),
                    reserved1   : unpack(0),
                    slotIdx     : zeroExtend(slotIdx),
                    len         : zeroExtend(totalLen),
                    reserved0   : unpack(0),
                    commonHeader: commonHeader   
                }));

            end
        end
        dmaWriteDataPipeOutQueue.enq(ds);
    endrule


    rule handleTxReq;
        SimpleNicTxQueueDesc desc = unpack(pack(simpleNicDescPipeInQueue.first));
        simpleNicDescPipeInQueue.deq;

        let chunkReq = AddressChunkReq {
            startAddr: desc.addr,
            len: desc.len,
            chunk: fromInteger(valueOf(TLog#(PCIE_MAX_BYTE_IN_BURST)))
        };
        txAddrChunkerRequestPipeInAdapter.enq(chunkReq);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkSimpleNic handleTxReq"),
        //     toBlue(", desc="), fshow(desc),
        //     toBlue(", chunkReq="), fshow(chunkReq)
        // );
    endrule

    rule handleTxAddrChunkResp;
        let chunkInfo = txAddrChunker.responsePipeOut.first;
        txAddrChunker.responsePipeOut.deq;

        let dmaReadReq = IoChannelMemoryAccessMeta{
            addr: chunkInfo.startAddr,
            totalLen: chunkInfo.len,
            accessType  : MemAccessTypeNormalReadWrite,
            operand_1   : 0,
            operand_2   : 0,
            noSnoop     : False
        };
        dmaReadMetaPipeOutQueue.enq(dmaReadReq);
        txConcatorIsLastStreamFlagPipeInConverter.enq(chunkInfo.isLast);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkSimpleNic handleTxAddrChunkResp"),
        //     toBlue(", chunkInfo="), fshow(chunkInfo),
        //     toBlue(", dmaReadReq="), fshow(dmaReadReq)
        // );
    endrule


    // let fifoToPipeInB0Bridge <- mkFifofToPipeInB0(dmaReadDataPipeInQueue);


    interface rawEthernetPacketPipeIn = toPipeIn(rawEthernetPacketPipeInQueue);
    interface rawEthernetPacketPipeOut = toPipeOut(rawEthernetPacketPipeOutQueue);
    interface simpleNicTxDescPipeIn = toPipeIn(simpleNicDescPipeInQueue);
    interface simpleNicRxDescPipeOut = toPipeOut(simpleNicDescPipeOutQueue);

    interface IoChannelMemoryMasterPipeB0In simpleNicPacketDmaMasterPipeIfc;
        interface DtldStreamMasterWritePipes  writePipeIfc;
            interface writeMetaPipeOut  = toPipeOut(dmaWriteMetaPipeOutQueue);
            interface writeDataPipeOut  = toPipeOut(dmaWriteDataPipeOutQueue);
        endinterface
        interface DtldStreamMasterReadPipesB0In  readPipeIfc;
            interface readMetaPipeOut   = toPipeOut(dmaReadMetaPipeOutQueue);
            interface readDataPipeIn    = txConcator.dataPipeIn;
        endinterface
    endinterface
endmodule