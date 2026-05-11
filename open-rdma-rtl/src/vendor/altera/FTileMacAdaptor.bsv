import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import Cntrs :: *;
import BRAMCore :: *;
import Arbiter :: * ;
import Connectable :: *;
import ConfigReg :: *;
import MIMO :: *;
import Reserved :: *;

import Settings :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import PAClib :: *;
import ConnectableF :: *;
import PrimUtils :: *;
import PrioritySearchBuffer :: *;
import AxiBus :: *;
import DtldStream :: *;

import StreamShifterG :: *;


typedef 16                                      FTILE_MAC_SEGMENT_CNT;
typedef TLog#(FTILE_MAC_SEGMENT_CNT)            FTILE_MAC_SEGMENT_IDX_WIDTH;
typedef Bit#(FTILE_MAC_SEGMENT_IDX_WIDTH)       FtileMacSegmentIdx;
typedef TAdd#(1, FTILE_MAC_SEGMENT_IDX_WIDTH)   FTILE_MAC_SEGMENT_CNT_WIDTH;
typedef Bit#(FTILE_MAC_SEGMENT_CNT_WIDTH)       FtileMacSegmentCnt;

typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentInframeSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentSopSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentEopSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentFcsErrorSignalBundle;
typedef Bit#(FTILE_MAC_SEGMENT_CNT) SegmentSkipCrcSignalBundle;

typedef 3 FTILE_MAC_EOP_EMPTY_WIDTH;
typedef Bit#(FTILE_MAC_EOP_EMPTY_WIDTH) FtileMacEopEmpty;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileMacEopEmpty) SegmentEopEmptySignalBundle;

typedef 2 FTILE_RX_MAC_ERROR_WIDTH;
typedef Bit#(FTILE_RX_MAC_ERROR_WIDTH) FtileRxMacError;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileRxMacError) SegmentRxMacErrorSignalBundle;

typedef 3 FTILE_MAC_STATUS_DATA_WIDTH;
typedef Bit#(FTILE_MAC_STATUS_DATA_WIDTH) FtileMacStatusData;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileMacStatusData) SegmentStatusDataSignalBundle;

typedef 1 FTILE_TX_MAC_ERROR_WIDTH;
typedef Bit#(FTILE_TX_MAC_ERROR_WIDTH) FtileTxMacError;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileTxMacError) SegmentTxMacErrorSignalBundle;


typedef 1024 FTILE_MAC_DATA_BUNDLE_WIDTH;
typedef TDiv#(FTILE_MAC_DATA_BUNDLE_WIDTH, FTILE_MAC_SEGMENT_CNT)       FTILE_MAC_DATA_SEGMENT_WIDTH;    // 64
typedef TDiv#(FTILE_MAC_DATA_SEGMENT_WIDTH, BYTE_WIDTH)                 FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH;    // 8
typedef TLog#(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH)                    FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM; // 3
typedef Bit#(FTILE_MAC_DATA_SEGMENT_WIDTH)                              FtileMacDataSegment;
typedef Vector#(FTILE_MAC_SEGMENT_CNT, FtileMacDataSegment)             FtileMacDataBusSegBundle;


typedef Bit#(TLog#(HARDWARE_QP_CHANNEL_CNT)) DispatchChannelIdx;

typedef struct {
    FtileMacDataBusSegBundle        data;
    SegmentInframeSignalBundle      inframe;
    SegmentEopEmptySignalBundle     eop_empty;
    SegmentSopSignalBundle          sop;
    SegmentEopSignalBundle          eop;
    SegmentFcsErrorSignalBundle     fcs_error;
    SegmentRxMacErrorSignalBundle   error;
    SegmentStatusDataSignalBundle   status_data;
} FtileMacRxBeat deriving (Bits, FShow);

typedef struct {
    FtileMacDataBusSegBundle        data;
    SegmentInframeSignalBundle      inframe;
    SegmentEopEmptySignalBundle     eop_empty;
    SegmentTxMacErrorSignalBundle   error;
    SegmentSkipCrcSignalBundle      skip_crc;
} FtileMacTxBeat deriving (Bits, FShow);


interface FTileMacAdaptorRx;

    // input port
    (* prefix="" *)
    method Action setRxInputData(
        FtileMacDataBusSegBundle        data,
        Bool                            valid,
        SegmentInframeSignalBundle      inframe,
        SegmentEopEmptySignalBundle     eop_empty,
        SegmentFcsErrorSignalBundle     fcs_error,
        SegmentRxMacErrorSignalBundle   error,
        SegmentStatusDataSignalBundle   status_data
    );

    // output port
    method Bool                                 ready;
endinterface

interface FTileMacAdaptorTx;

    // input port
    (* prefix="" *)
    method Action setTxInputData(Bool ready);

    // output port
    method FtileMacDataBusSegBundle         data;
    method Bool                             valid;
    method SegmentInframeSignalBundle       inframe;
    method SegmentEopEmptySignalBundle      eop_empty;
    method SegmentTxMacErrorSignalBundle    error;
    method SegmentSkipCrcSignalBundle       skip_crc;
endinterface

interface FTileMacAdaptor;
    (* always_ready, always_enabled *)
    interface FTileMacAdaptorRx rx;

    (* always_ready, always_enabled *)
    interface FTileMacAdaptorTx tx;

    interface PipeOut#(FtileMacRxBeat) ftilemacRxPipeOut;
    interface PipeIn#(FtileMacTxBeat) ftilemacTxPipeIn;
endinterface

(* synthesize *)
module mkFTileMacAdaptor(FTileMacAdaptor);


    FIFOF#(FtileMacRxBeat) ftileMacRxPipeOutQueue <- mkUGFIFOF;
    FIFOF#(FtileMacTxBeat) ftileMacTxPipeInQueue <- mkUGLFIFOF;

    Reg#(Bool) txReadySignalOutputReg <- mkReg(False);

    Bool txValid = ftileMacTxPipeInQueue.notEmpty && txReadySignalOutputReg;

    Reg#(Bool) previousRxBeatLastInframeSignalReg <- mkReg(False);
    Reg#(Bool) previousTxBeatLastInframeSignalReg <- mkReg(False);

    rule deq;
        if (txValid && ftileMacTxPipeInQueue.notEmpty) begin
            ftileMacTxPipeInQueue.deq;
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFTileMacAdaptor handshake tx packet"),
            //     toBlue(", beat="), fshow(ftileMacTxPipeInQueue.first)
            // );
        end
    endrule


    interface FTileMacAdaptorRx rx;
        // input port
        method Action setRxInputData(
            FtileMacDataBusSegBundle        data,
            Bool                            valid,
            SegmentInframeSignalBundle      inframe,
            SegmentEopEmptySignalBundle     eop_empty,
            SegmentFcsErrorSignalBundle     fcs_error,
            SegmentRxMacErrorSignalBundle   error,
            SegmentStatusDataSignalBundle   status_data
        );


            let mergedInframeSignal = {pack(inframe), pack(previousRxBeatLastInframeSignalReg)};
            SegmentSopSignalBundle sop;
            SegmentEopSignalBundle eop;
            for (Integer idx = 0; idx < valueOf(FTILE_MAC_SEGMENT_CNT); idx = idx + 1) begin
                sop[idx] = pack(mergedInframeSignal[idx] == 0 && mergedInframeSignal[idx + 1] == 1);
                eop[idx] = pack(mergedInframeSignal[idx] == 1 && mergedInframeSignal[idx + 1] == 0);
            end

            if ( valid ) begin
                let beat = FtileMacRxBeat {
                    data                    : data,
                    inframe                 : inframe,
                    eop_empty               : eop_empty,
                    sop                     : sop,
                    eop                     : eop,
                    fcs_error               : fcs_error,
                    error                   : error,
                    status_data             : status_data
                };

                immAssert(
                    ftileMacRxPipeOutQueue.notFull,
                    "ftileMacRxPipeOutQueue is Full",
                    $format("")
                );

                ftileMacRxPipeOutQueue.enq(beat);
                previousRxBeatLastInframeSignalReg <= unpack(msb(inframe));
            end
        endmethod

        // output port
        method Bool                                 ready               = True;  
    endinterface

    interface FTileMacAdaptorTx tx;
        // input port
        method Action setTxInputData(Bool ready);
            txReadySignalOutputReg <= ready;
        endmethod

        // output port
        
        method FtileMacDataBusSegBundle         data        = txValid ? ftileMacTxPipeInQueue.first.data        : unpack(0);
        method SegmentInframeSignalBundle       inframe     = txValid ? ftileMacTxPipeInQueue.first.inframe     : unpack(0);
        method SegmentEopEmptySignalBundle      eop_empty   = txValid ? ftileMacTxPipeInQueue.first.eop_empty   : unpack(0);
        method SegmentTxMacErrorSignalBundle    error       = txValid ? ftileMacTxPipeInQueue.first.error       : unpack(0);
        method SegmentSkipCrcSignalBundle       skip_crc    = txValid ? ftileMacTxPipeInQueue.first.skip_crc    : unpack(0);
        method Bool                             valid       = txValid;
    endinterface

    interface ftilemacRxPipeOut = ugToPipeOut(ftileMacRxPipeOutQueue);
    interface ftilemacTxPipeIn = ugToPipeIn(ftileMacTxPipeInQueue);
endmodule



typedef 3 FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT;
typedef Bit#(TLog#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT)) FtileMacRxPingPongMetaOutputChannelIdx;

typedef 4 FTILE_MAC_USER_LOGIC_CHANNEL_CNT;
typedef 256 FTILE_MAC_USER_LOGIC_DATA_WIDTH;

typedef TLog#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT) FTILE_MAC_USER_LOGIC_CHANNEL_IDX_WIDTH;
typedef Bit#(FTILE_MAC_USER_LOGIC_CHANNEL_IDX_WIDTH) FtileMacUserLogicChannelIdx;

typedef 512 FTILE_MAC_RX_BRAM_BUFFER_DEPTH;
typedef TLog#(FTILE_MAC_RX_BRAM_BUFFER_DEPTH) FTILE_MAC_RX_BRAM_BUFFER_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_RX_BRAM_BUFFER_ADDR_WIDTH) FtileMacRxBramBufferAddr;



typedef struct {
    FtileMacRxBramBufferAddr        bufferAddr;         // 10
    SegmentEopEmptySignalBundle     eopEmpty;           // 48
    SegmentSopSignalBundle          sop;                // 16
    SegmentEopSignalBundle          eop;                // 16
    SegmentFcsErrorSignalBundle     fcsError;           // 16
    // SegmentRxMacErrorSignalBundle   error;          // 32
    // SegmentStatusDataSignalBundle   status_data;    // 48
} FtileMacRxPingPongSingleChannelProcessorInputMeta deriving(FShow, Bits);

typedef struct {
    FtileMacRxBramBufferAddr        bufferAddr;                // 10
    FtileMacSegmentIdx              startSegIdx;                // 4
    FtileMacSegmentIdx              zeroBasedValidSegCnt;       // 4
    FtileMacEopEmpty                lastSegEmptyByteCnt;        // 3
    Bool                            isFirst;                    // 1
    Bool                            isLast;                     // 1
    Bool                            isError;                    // 1
} FtileMacRxPacketChunkMeta deriving(FShow, Bits);

typedef struct {
    Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, Maybe#(FtileMacRxPacketChunkMeta))    packetChunkMetaVector;
    Bool                                                                                packetNumOverflowAffectNextBeat;
} FtileMacRxPingPongSingleChannelProcessorOutputMeta deriving(FShow, Bits);


interface FtileMacRxPingPongSingleChannelProcessor;
    interface PipeInB0#(FtileMacRxPingPongSingleChannelProcessorInputMeta)                      beatMetaPipeIn;
    interface PipeOut#(FtileMacRxPingPongSingleChannelProcessorOutputMeta)                      packetsChunkMetaPipeOut;
endinterface

(* synthesize *)
module mkFtileMacRxPingPongSingleChannelProcessor(FtileMacRxPingPongSingleChannelProcessor);
    PipeInAdapterB0#(FtileMacRxPingPongSingleChannelProcessorInputMeta)  beatMetaPipeInQueue          <- mkPipeInAdapterB0;
    FIFOF#(FtileMacRxPingPongSingleChannelProcessorOutputMeta) packetsChunkMetaPipeOutQueue <- mkFIFOF;

    Reg#(Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, Maybe#(FtileMacRxPacketChunkMeta))) outputMetaTmpBufferVecReg<- mkReg(replicate(tagged Invalid));


    Reg#(Bool)                                              isIdleReg                               <- mkReg(True);
    Reg#(FtileMacRxPingPongSingleChannelProcessorInputMeta) curProcessingMetaReg                    <- mkRegU;
    Reg#(Bool)                                              currentPacketHasErrorReg                <- mkReg(False);
    Reg#(FtileMacSegmentIdx)                                curProcessingSegIdxReg                  <- mkReg(0);
    Reg#(FtileMacSegmentIdx)                                curFirstSegIdxForThisPacketReg          <- mkReg(0);
    Reg#(FtileMacSegmentIdx)                                zeroBasedValidSegCntForPacketReg        <- mkReg(0);
    Reg#(FtileMacRxPingPongMetaOutputChannelIdx)            curOutChannelIdxReg                     <- mkReg(0);
    Reg#(Bool)                                              isPacketNotEndReg                       <- mkReg(False);
    Reg#(Bool)                                              isPacketNumOverflowReg                  <- mkReg(False);
    // since different ping-pong channel doesn't know the state of other ping-pong channel, the isFirstForOutputReg signal
    // is inited to False. Suppose a packet cross two beat, the sop is in the first beat, which is processed by the first ping-pong channel.
    // when the second beat is handled by the second ping-pong channel, it must output isFirst set to False.
    // So, the total rule is like this: the isPacketNumOverflowReg is turned to False at the start of each beat, then, when it meets a sop flag,
    // it keeps True until to the end of this beat.
    Reg#(Bool)                                              isFirstForOutputReg                     <- mkReg(False);
    Reg#(Bool)                                              hasMetEopButNotSopReg                   <- mkReg(False);
    rule handle;
        let currentMeta;
        let curProcessingSegIdx;
        let zeroBasedValidSegCntForPacket;
        let curOutChannelIdx;
        let isPacketNumOverflow;
        let startSegIdx;
        let isFirstForOutput;
        let hasMetEopButNotSop;
        let tmpMetaBufferVec;
        if (isIdleReg) begin
            isIdleReg <= False;
            currentMeta             = beatMetaPipeInQueue.first;
            beatMetaPipeInQueue.deq;
            curProcessingSegIdx     = 0;
            zeroBasedValidSegCntForPacket  = 0;
            curOutChannelIdx        = 0;
            isPacketNumOverflow     = False;
            startSegIdx             = 0;
            isFirstForOutput        = False;
            hasMetEopButNotSop      = False;
            tmpMetaBufferVec        = replicate(tagged Invalid);
        end
        else begin
            currentMeta                         = curProcessingMetaReg;
            curProcessingSegIdx                 = curProcessingSegIdxReg;
            zeroBasedValidSegCntForPacket       = zeroBasedValidSegCntForPacketReg;
            curOutChannelIdx                    = curOutChannelIdxReg;
            isPacketNumOverflow                 = isPacketNumOverflowReg;
            startSegIdx                         = curFirstSegIdxForThisPacketReg;
            isFirstForOutput                    = isFirstForOutputReg;
            hasMetEopButNotSop                  = hasMetEopButNotSopReg;
            tmpMetaBufferVec                    = outputMetaTmpBufferVecReg;
        end
            
        FtileMacEopEmpty                lastSegEmptyByteCnt         = truncate(pack(currentMeta.eopEmpty));    
        Bool                            sopFlag                     = unpack(lsb(currentMeta.sop));                    
        Bool                            eopFlag                     = unpack(lsb(currentMeta.eop));                     
        Bool                            isError                     = unpack(lsb(currentMeta.fcsError));                    
        

        
        case ({pack(eopFlag), pack(sopFlag)})
            2'b00: begin // middle or empty
                // Nothing to do
            end
            2'b01: begin // first
                zeroBasedValidSegCntForPacket = 0;
                startSegIdx = curProcessingSegIdx;
                isFirstForOutput = True;
                hasMetEopButNotSop = False;
            end
            2'b10: begin // last
                hasMetEopButNotSop = True;
            end
            2'b11: begin // only
                immFail(
                    "should not reach here. FTile can't output sop and eop in the same segment",
                    $format("")
                );
            end
        endcase

        let outPacketMeta = FtileMacRxPacketChunkMeta {
            bufferAddr                  : currentMeta.bufferAddr,
            startSegIdx                 : startSegIdx,
            zeroBasedValidSegCnt        : zeroBasedValidSegCntForPacket,
            lastSegEmptyByteCnt         : lastSegEmptyByteCnt,
            isFirst                     : isFirstForOutput,
            isLast                      : eopFlag,
            isError                     : isError
        };

        zeroBasedValidSegCntForPacket = zeroBasedValidSegCntForPacket + 1;

        Bool isLastSegInThisBeat = curProcessingSegIdxReg == fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT) - 1);
        Bool needOutputOutputMeta = (isLastSegInThisBeat && !hasMetEopButNotSop) || eopFlag;
        
        
        if (needOutputOutputMeta) begin
            if (curOutChannelIdx == fromInteger(valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT))) begin
                isPacketNumOverflow = True;
            end
            
            if (!isPacketNumOverflow) begin
                tmpMetaBufferVec[curOutChannelIdx] = tagged Valid outPacketMeta;
                curOutChannelIdx = curOutChannelIdx + 1;

                // $display(
                //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongSingleChannelProcessor handle output to meta buffer"),
                //     toBlue(", outPacketMeta="), fshow(outPacketMeta)
                // );
            end
        end

        if (isLastSegInThisBeat) begin
            // if this is the last segment of both the beat and the packet, 
            // then this overflow won't affact next beat in the next sibling ping-pong channel
            // another case is that, it already overflowed, but the last segment is not used 
            // (i.e., the last overflow packet end before the last segment). For example, for a 16-seg beat,
            // there are 4 eop in seg 2, 4, 6, 8, and seg 9-15 doesn't have data, in this case, the beat is 
            // overflowed, but the seg 15 is not eop. In this case, the error should not affact next beat.
            Bool packetNumOverflowAffectNextBeat = hasMetEopButNotSop ? False : isPacketNumOverflow;
            
            Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, 
                Maybe#(FtileMacRxPacketChunkMeta))    packetChunkMetaVector = newVector;

            for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT); idx = idx + 1) begin
                packetChunkMetaVector[idx] = tmpMetaBufferVec[idx];
            end

            let outputMeta = FtileMacRxPingPongSingleChannelProcessorOutputMeta {
                packetChunkMetaVector: packetChunkMetaVector,
                packetNumOverflowAffectNextBeat: packetNumOverflowAffectNextBeat
            }; 

            packetsChunkMetaPipeOutQueue.enq(outputMeta);
        end

        currentMeta.eopEmpty    = unpack(pack(currentMeta.eopEmpty)  >> valueOf(FTILE_MAC_EOP_EMPTY_WIDTH));
        currentMeta.sop         = unpack(pack(currentMeta.sop)       >> valueOf(SizeOf#(Bool)));        
        currentMeta.eop         = unpack(pack(currentMeta.eop)       >> valueOf(SizeOf#(Bool)));
        currentMeta.fcsError   = unpack(pack(currentMeta.fcsError) >> valueOf(SizeOf#(Bool)));

        if (curProcessingSegIdx == maxBound) begin
            isIdleReg <= True;
        end
        
        curProcessingSegIdxReg              <= curProcessingSegIdx + 1;
        curFirstSegIdxForThisPacketReg      <= startSegIdx;
        curProcessingMetaReg                <= currentMeta;
        zeroBasedValidSegCntForPacketReg    <= zeroBasedValidSegCntForPacket;
        curOutChannelIdxReg                 <= curOutChannelIdx;
        isPacketNumOverflowReg              <= isPacketNumOverflow;
        isFirstForOutputReg                 <= isFirstForOutput;
        hasMetEopButNotSopReg               <= hasMetEopButNotSop;
        outputMetaTmpBufferVecReg           <= tmpMetaBufferVec;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongSingleChannelProcessor handle"),
        //     toBlue(", curProcessingSegIdx="), fshow(curProcessingSegIdx),
        //     toBlue(", startSegIdx="), fshow(startSegIdx),
        //     toBlue(", curProcessingMeta="), fshow(currentMeta),
        //     toBlue(", zeroBasedValidSegCntForPacket="), fshow(zeroBasedValidSegCntForPacket),
        //     toBlue(", curOutChannelIdx="), fshow(curOutChannelIdx),
        //     toBlue(", isPacketNumOverflow="), fshow(isPacketNumOverflow),
        //     toBlue(", isFirstForOutput="), fshow(isFirstForOutput),
        //     toBlue(", hasMetEopButNotSop="), fshow(hasMetEopButNotSop)
        // );
    endrule



    interface beatMetaPipeIn = toPipeInB0(beatMetaPipeInQueue);
    interface packetsChunkMetaPipeOut = toPipeOut(packetsChunkMetaPipeOutQueue);
endmodule


typedef FTILE_MAC_SEGMENT_CNT FTILE_MAC_RX_PING_PONG_CHANNEL_CNT;
typedef Bit#(TLog#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT)) FtileMacRxPingPongChannelIdx;

typedef struct {
    FtileMacRxBramBufferAddr addr;
    FtileMacDataBusSegBundle data;
} FtileMacRxBramBufferWriteReq deriving (FShow, Bits);


interface FtileMacRxBeatFork;
    interface PipeIn#(FtileMacRxBeat)                                                           rxBetaPipeIn;
    interface Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
                      PipeOut#(FtileMacRxPingPongSingleChannelProcessorInputMeta))              rxPingPongChannelMetaPipeOutVec;
    interface PipeOut#(FtileMacRxBramBufferWriteReq)                                            rxBramWriteReqPipeOut;
endinterface


(* synthesize *)
module mkFtileMacRxBeatFork(FtileMacRxBeatFork);
    
    FIFOF#(FtileMacRxBeat)                                                  rxBetaPipeInQueue                   <- mkLFIFOF;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
            PipeOut#(FtileMacRxPingPongSingleChannelProcessorInputMeta))    rxPingPongChannelMetaPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
            FIFOF#(FtileMacRxPingPongSingleChannelProcessorInputMeta))      rxPingPongChannelMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    FIFOF#(FtileMacRxBramBufferWriteReq)                                    rxBramWriteReqPipeOutQueue          <- mkFIFOF;

    Reg#(FtileMacRxBramBufferAddr) addrPtrReg <- mkReg(0);

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        rxPingPongChannelMetaPipeOutVecInst[idx] = toPipeOut(rxPingPongChannelMetaPipeOutQueueVec[idx]);
    end

    Reg#(FtileMacRxPingPongChannelIdx) channelIdxReg <- mkReg(0);

    rule handleInputBeat;
        let rxBeat = rxBetaPipeInQueue.first;
        rxBetaPipeInQueue.deq;
        
        let outMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
            bufferAddr      : addrPtrReg,
            eopEmpty        : rxBeat.eop_empty,  
            sop             : rxBeat.sop,       
            eop             : rxBeat.eop,       
            fcsError        : rxBeat.fcs_error  
        };
        rxPingPongChannelMetaPipeOutQueueVec[channelIdxReg].enq(outMeta);
        

        let bramWriteReq = FtileMacRxBramBufferWriteReq {
            addr    : addrPtrReg,
            data    : rxBeat.data
        };
        rxBramWriteReqPipeOutQueue.enq(bramWriteReq);

        addrPtrReg      <= addrPtrReg    + 1;
        channelIdxReg   <= channelIdxReg + 1;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxBeatFork handleInputBeat"),
        //     toBlue(", channelIdxReg="), fshow(channelIdxReg)
        // );
    endrule
    

    interface rxBetaPipeIn                      = toPipeIn(rxBetaPipeInQueue);
    interface rxPingPongChannelMetaPipeOutVec   = rxPingPongChannelMetaPipeOutVecInst;
    interface rxBramWriteReqPipeOut             = toPipeOut(rxBramWriteReqPipeOutQueue);
endmodule



typedef Vector#(
    FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, 
    PipeInB0#(FtileMacRxPingPongSingleChannelProcessorOutputMeta)) FtileMacRxPingPongChannelMetaJoinInputIfc;


// each beat(packet chunk) is 128B, for 4kB packet, it uses about 32 chunk meta. To buffer about 4 4kB packet, use a 128 depth.
typedef 128 PACKET_CHUNK_META_OUTPUT_BUFFER_DEPTH;

// to select the most empty channel to dispatch, need to track the segment count in each output channel. Each 4kB packet has 512 8Byte segments,
// so, we decide to use a max counter value that can hold about four 4kB packets, that is 512 * 4 = 2048
typedef TLog#(2048) PACKET_BEAT_SEG_COUNTER_MAX_VALUE_WIDTH;
typedef Bit#(PACKET_BEAT_SEG_COUNTER_MAX_VALUE_WIDTH) PacketBeatSegCnt;

typedef struct {
    FtileMacUserLogicChannelIdx         targetChannelIdx;
    Maybe#(FtileMacRxPacketChunkMeta)   packetChunkMetaMaybe;
} FtileMacRxPacketChunkMetaDispatchPipelineQueueEntry deriving(Bits, FShow);

interface FtileMacRxPingPongChannelMetaJoin;
    interface FtileMacRxPingPongChannelMetaJoinInputIfc metaPipeInVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxPacketChunkMeta)) packetChunkMetaPipeOutVec;
endinterface

(* synthesize *)
module mkFtileMacRxPingPongChannelMetaJoin(FtileMacRxPingPongChannelMetaJoin);

    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, PipeInAdapterB0#(FtileMacRxPingPongSingleChannelProcessorOutputMeta)) metaPipeInQueueVec <- replicateM(mkPipeInAdapterB0);
    FtileMacRxPingPongChannelMetaJoinInputIfc metaPipeInVecInst = newVector; 

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacRxPacketChunkMeta))    packetChunkMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxPacketChunkMeta))  packetChunkMetaPipeOutVecInst  = newVector; 

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        metaPipeInVecInst[idx] = toPipeInB0(metaPipeInQueueVec[idx]);
    end

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        packetChunkMetaPipeOutVecInst[idx] = toPipeOut(packetChunkMetaPipeOutQueueVec[idx]);
    end

    Reg#(FtileMacUserLogicChannelIdx)  currentOutputChannelIdxReg       <- mkReg(0);
    Reg#(Bool)                         isCurrentPacketNotEndReg         <- mkReg(False);
    Reg#(Bool)                         isCurrentPacketShouldSkipReg     <- mkReg(False);
    Reg#(FtileMacRxPingPongChannelIdx) pingPongChannelIdxReg            <- mkReg(0);

    // use ConfigReg to solve conflict
    Reg#(Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FtileMacUserLogicChannelIdx)) curUserLogicChannelDispatchOrderReg <- mkConfigReg(vec(0, 1, 2, 3));


    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacRxPacketChunkMeta)) packetChunkMetaOutputBufferVec <- replicateM(mkSizedFIFOF(valueOf(PACKET_CHUNK_META_OUTPUT_BUFFER_DEPTH)));
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Count#(PacketBeatSegCnt)) outputChannelBufferUsedSegCounterVec <- replicateM(mkCount(0));

    // Pipeline FIFOs and Regs
    FIFOF#(FtileMacRxPingPongSingleChannelProcessorOutputMeta) selectedPingPongOutputChannelMetaPipelineQ <- mkLFIFOF;
    FIFOF#(Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, FtileMacRxPacketChunkMetaDispatchPipelineQueueEntry)) dispatchPacketChunkMetaPipelineQ <- mkLFIFOF;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(Bool)) discardOrOutputSignalPipelineQueueVec <- replicateM(mkFIFOF);   // change to LFIFO will block

    Reg#(Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)))  bitonicSortPipelineReg <- mkRegU;

    rule generateNextDispatchOrderByBufferUsageStage1;
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep1Vec = vec (
            tuple2(0, outputChannelBufferUsedSegCounterVec[0]),
            tuple2(1, outputChannelBufferUsedSegCounterVec[1]),
            tuple2(2, outputChannelBufferUsedSegCounterVec[2]),
            tuple2(3, outputChannelBufferUsedSegCounterVec[3])
        );

        // first swap
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep2Vec = newVector;
        if (tpl_2(bitonicSortStep1Vec[0]) > tpl_2(bitonicSortStep1Vec[1])) begin
            bitonicSortStep2Vec[1] = bitonicSortStep1Vec[0];
            bitonicSortStep2Vec[0] = bitonicSortStep1Vec[1];
        end
        else begin
            bitonicSortStep2Vec[0] = bitonicSortStep1Vec[0];
            bitonicSortStep2Vec[1] = bitonicSortStep1Vec[1];
        end

        if (tpl_2(bitonicSortStep1Vec[2]) > tpl_2(bitonicSortStep1Vec[3])) begin
            bitonicSortStep2Vec[2] = bitonicSortStep1Vec[2];
            bitonicSortStep2Vec[3] = bitonicSortStep1Vec[3];
        end
        else begin
            bitonicSortStep2Vec[3] = bitonicSortStep1Vec[2];
            bitonicSortStep2Vec[2] = bitonicSortStep1Vec[3];
        end

        bitonicSortPipelineReg <= bitonicSortStep2Vec;
    endrule

    rule generateNextDispatchOrderByBufferUsageStage2;
        // second swap
        let bitonicSortStep2Vec = bitonicSortPipelineReg;
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep3Vec = newVector;
        if (tpl_2(bitonicSortStep2Vec[0]) > tpl_2(bitonicSortStep2Vec[2])) begin
            bitonicSortStep3Vec[2] = bitonicSortStep2Vec[0];
            bitonicSortStep3Vec[0] = bitonicSortStep2Vec[2];
        end
        else begin
            bitonicSortStep3Vec[0] = bitonicSortStep2Vec[0];
            bitonicSortStep3Vec[2] = bitonicSortStep2Vec[2];
        end

        if (tpl_2(bitonicSortStep2Vec[1]) > tpl_2(bitonicSortStep2Vec[3])) begin
            bitonicSortStep3Vec[3] = bitonicSortStep2Vec[1];
            bitonicSortStep3Vec[1] = bitonicSortStep2Vec[3];
        end
        else begin
            bitonicSortStep3Vec[1] = bitonicSortStep2Vec[1];
            bitonicSortStep3Vec[3] = bitonicSortStep2Vec[3];
        end

        // third swap
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Tuple2#(FtileMacUserLogicChannelIdx, PacketBeatSegCnt)) bitonicSortStep4Vec = newVector;
        if (tpl_2(bitonicSortStep3Vec[0]) > tpl_2(bitonicSortStep3Vec[1])) begin
            bitonicSortStep4Vec[1] = bitonicSortStep3Vec[0];
            bitonicSortStep4Vec[0] = bitonicSortStep3Vec[1];
        end
        else begin
            bitonicSortStep4Vec[0] = bitonicSortStep3Vec[0];
            bitonicSortStep4Vec[1] = bitonicSortStep3Vec[1];
        end

        if (tpl_2(bitonicSortStep3Vec[2]) > tpl_2(bitonicSortStep3Vec[3])) begin
            bitonicSortStep4Vec[3] = bitonicSortStep3Vec[2];
            bitonicSortStep4Vec[2] = bitonicSortStep3Vec[3];
        end
        else begin
            bitonicSortStep4Vec[2] = bitonicSortStep3Vec[2];
            bitonicSortStep4Vec[3] = bitonicSortStep3Vec[3];
        end

        curUserLogicChannelDispatchOrderReg <= vec(
            tpl_1(bitonicSortStep4Vec[0]),
            tpl_1(bitonicSortStep4Vec[1]),
            tpl_1(bitonicSortStep4Vec[2]),
            tpl_1(bitonicSortStep4Vec[3])
        );

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongChannelMetaJoin generateNextDispatchOrderByBufferUsage"),
        //     toBlue(", bitonicSortStep1Vec="), fshow(bitonicSortStep1Vec), 
        //     toBlue(", bitonicSortStep4Vec="), fshow(bitonicSortStep4Vec)
        // );

    endrule

    rule selectAndForwardPingPongChannel;
        pingPongChannelIdxReg <= pingPongChannelIdxReg + 1;

        let pingPongOutputMeta = metaPipeInQueueVec[pingPongChannelIdxReg].first;
        metaPipeInQueueVec[pingPongChannelIdxReg].deq;

        selectedPingPongOutputChannelMetaPipelineQ.enq(pingPongOutputMeta);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongChannelMetaJoin selectAndForwardPingPongChannel"),
        //     toBlue(", pingPongOutputMeta="), fshow(pingPongOutputMeta)
        // );
    endrule

    rule forwardPacketsInOnePingPongChannelToFourOutputChannels;

        Vector#(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT, FtileMacRxPacketChunkMetaDispatchPipelineQueueEntry) outputEntryVec = newVector;

        let inputPingPongMeta = selectedPingPongOutputChannelMetaPipelineQ.first;
        selectedPingPongOutputChannelMetaPipelineQ.deq;

        immAssert(
            isValid(inputPingPongMeta.packetChunkMetaVector[0]),
            "the input Vector's first element should not be Invalid",
            $format("")
        );

        for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT); idx = idx + 1) begin
            outputEntryVec[idx].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[idx];
        end

        let isCurrentPacketNotEnd       = isCurrentPacketNotEndReg;
        let isCurrentPacketShouldSkip   = isCurrentPacketShouldSkipReg;
        let currentOutputChannelIdx     = currentOutputChannelIdxReg;

        Vector#(TSub#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, 1), FtileMacUserLogicChannelIdx) dispatchOrderWithoutCurrentChannel = case (currentOutputChannelIdx)
            curUserLogicChannelDispatchOrderReg[0]: vec(curUserLogicChannelDispatchOrderReg[1], curUserLogicChannelDispatchOrderReg[2], curUserLogicChannelDispatchOrderReg[3]);
            curUserLogicChannelDispatchOrderReg[1]: vec(curUserLogicChannelDispatchOrderReg[0], curUserLogicChannelDispatchOrderReg[2], curUserLogicChannelDispatchOrderReg[3]);
            curUserLogicChannelDispatchOrderReg[2]: vec(curUserLogicChannelDispatchOrderReg[0], curUserLogicChannelDispatchOrderReg[1], curUserLogicChannelDispatchOrderReg[3]);
            curUserLogicChannelDispatchOrderReg[3]: vec(curUserLogicChannelDispatchOrderReg[0], curUserLogicChannelDispatchOrderReg[1], curUserLogicChannelDispatchOrderReg[2]);
        endcase;
        
        let isFirstPacketUseNewChannel  = False;

        // There is at most 3 packet to handle here.
        // Now handle the first one.
        let firstInputMeta = fromMaybe(?, inputPingPongMeta.packetChunkMetaVector[0]);
        if (isCurrentPacketNotEnd) begin
            if (isCurrentPacketShouldSkip) begin
                outputEntryVec[0].packetChunkMetaMaybe = tagged Invalid;
            end
            else begin
                outputEntryVec[0].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[0];
                outputEntryVec[0].targetChannelIdx = currentOutputChannelIdx;
            end
            if (firstInputMeta.isLast) begin
                isCurrentPacketShouldSkip   = False;
                isCurrentPacketNotEnd       = False;
            end
        end
        else begin
            immAssert(
                firstInputMeta.isFirst && !isCurrentPacketShouldSkip,
                "if the packet has finished in previous beat, then this must be first. And for a first beat, isCurrentPacketShouldSkip must already be set to False in previous beat",
                $format("firstInputMeta=", fshow(firstInputMeta), "isCurrentPacketShouldSkip=", fshow(isCurrentPacketShouldSkip))
            );

            currentOutputChannelIdx = dispatchOrderWithoutCurrentChannel[0];
            isFirstPacketUseNewChannel = True;
            outputEntryVec[0].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[0];
            outputEntryVec[0].targetChannelIdx = currentOutputChannelIdx;
            if (firstInputMeta.isLast) begin
                isCurrentPacketNotEnd       = False;
            end
            else begin
                isCurrentPacketNotEnd       = True;
            end
        end

        // Now handle the second one.
        if (inputPingPongMeta.packetChunkMetaVector[1] matches tagged Valid .secondInputMeta) begin
            immAssert(
                !isCurrentPacketNotEnd,
                "since the second meta is valid, the previous packet must be eop",
                $format("firstInputMeta=", fshow(firstInputMeta), "secondInputMeta=", fshow(secondInputMeta))
            );

            currentOutputChannelIdx = isFirstPacketUseNewChannel ? dispatchOrderWithoutCurrentChannel[1] : dispatchOrderWithoutCurrentChannel[0];
            outputEntryVec[1].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[1];
            outputEntryVec[1].targetChannelIdx = currentOutputChannelIdx;
            if (secondInputMeta.isLast) begin
                isCurrentPacketNotEnd       = False;
            end
            else begin
                isCurrentPacketNotEnd       = True;
            end
        end

        // Now handle the third one.
        if (inputPingPongMeta.packetChunkMetaVector[2] matches tagged Valid .thirdInputMeta) begin
            immAssert(
                !isCurrentPacketNotEnd,
                "since the third meta is valid, the previous packet must be eop",
                $format("thirdInputMeta=", fshow(thirdInputMeta))
            );

            currentOutputChannelIdx = isFirstPacketUseNewChannel ? dispatchOrderWithoutCurrentChannel[2] : dispatchOrderWithoutCurrentChannel[1];
            outputEntryVec[2].packetChunkMetaMaybe = inputPingPongMeta.packetChunkMetaVector[2];
            outputEntryVec[2].targetChannelIdx = currentOutputChannelIdx;
            if (thirdInputMeta.isLast) begin
                isCurrentPacketNotEnd       = False;
            end
            else begin
                isCurrentPacketNotEnd       = True;
            end
        end
        
        if (inputPingPongMeta.packetNumOverflowAffectNextBeat) begin
            isCurrentPacketShouldSkip = True;
            isCurrentPacketNotEnd     = True;
        end


        currentOutputChannelIdxReg <= currentOutputChannelIdx;
        isCurrentPacketNotEndReg <= isCurrentPacketNotEnd;
        isCurrentPacketShouldSkipReg <= isCurrentPacketShouldSkip;

        dispatchPacketChunkMetaPipelineQ.enq(outputEntryVec);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongChannelMetaJoin forwardPacketsInOnePingPongChannelToFourOutputChannels"),
        //     toBlue(", inputPingPongMeta="), fshow(inputPingPongMeta), 
        //     toBlue(", outputEntryVec="), fshow(outputEntryVec),
        //     toBlue(", isCurrentPacketNotEndReg="), fshow(isCurrentPacketNotEndReg),
        //     toBlue(", isCurrentPacketNotEnd="), fshow(isCurrentPacketNotEnd)
        // );
    endrule

    rule dispatchToOutputBuffer;
        let pipelineInputEntry = dispatchPacketChunkMetaPipelineQ.first;
        dispatchPacketChunkMetaPipelineQ.deq;

        for (Integer userChannelIdx = 0; userChannelIdx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); userChannelIdx = userChannelIdx + 1) begin
            Maybe#(FtileMacRxPacketChunkMeta) metaToOutputMaybe = tagged Invalid;
            
            for (Integer srcIdx = 0; srcIdx < valueOf(FTILE_MAC_RX_MAX_PACKET_CNT_PER_BEAT); srcIdx = srcIdx + 1) begin
                let dispatchTargetInfo = pipelineInputEntry[srcIdx];
                if (dispatchTargetInfo.targetChannelIdx == fromInteger(userChannelIdx)) begin
                    metaToOutputMaybe = dispatchTargetInfo.packetChunkMetaMaybe;
                end
            end

            if (metaToOutputMaybe matches tagged Valid .metaToOutput) begin
                packetChunkMetaOutputBufferVec[userChannelIdx].enq(metaToOutput);
                outputChannelBufferUsedSegCounterVec[userChannelIdx].incr(zeroExtend(metaToOutput.zeroBasedValidSegCnt)+1);
                if (metaToOutput.isLast) begin
                    let needDiscard = metaToOutput.isError;
                    discardOrOutputSignalPipelineQueueVec[userChannelIdx].enq(needDiscard);
                    // $display(
                    //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongChannelMetaJoin dispatchToOutputBuffer reach packet tail"),
                    //     toBlue(", userChannelIdx="), $format("%d", userChannelIdx),
                    //     toBlue(", pipelineInputEntry="), fshow(pipelineInputEntry),
                    //     toBlue(", needDiscard="), fshow(needDiscard)
                    // );
                end
            end            
        end 

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPingPongChannelMetaJoin dispatchToOutputBuffer"),
        //     toBlue(", pipelineInputEntry="), fshow(pipelineInputEntry)
        // );
    endrule

    for (Integer userChannelIdx = 0; userChannelIdx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); userChannelIdx = userChannelIdx + 1) begin
        rule forwardFromOutputBufferToOutputIfc;
            let needDiscard = discardOrOutputSignalPipelineQueueVec[userChannelIdx].first;

            let metaToForward = packetChunkMetaOutputBufferVec[userChannelIdx].first;
            packetChunkMetaOutputBufferVec[userChannelIdx].deq;

            if (!needDiscard) begin
                packetChunkMetaPipeOutQueueVec[userChannelIdx].enq(metaToForward);
            end
            if (metaToForward.isLast) begin
                discardOrOutputSignalPipelineQueueVec[userChannelIdx].deq;
            end

            outputChannelBufferUsedSegCounterVec[userChannelIdx].decr(zeroExtend(metaToForward.zeroBasedValidSegCnt)+1);
        endrule
    end

    interface metaPipeInVec             = metaPipeInVecInst;
    interface packetChunkMetaPipeOutVec = packetChunkMetaPipeOutVecInst;
endmodule


typedef DtldStreamData#(DATA) FtileMacRxUserStream;
typedef FtileMacRxUserStream FtileMacTxUserStream;
typedef TDiv#(SizeOf#(FtileMacDataBusSegBundle), SizeOf#(DATA)) RTILE_RX_BRAM_BLOCK_CNT;   // 4
typedef TDiv#(SizeOf#(DATA), FTILE_MAC_DATA_SEGMENT_WIDTH) RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT;  // 4

typedef struct {
    Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT))    startBramBlockIdx;
    Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT))    endBramBlockIdx;
    FtileMacSegmentIdx                      firstOutputBeatShiftSegCnt;
    BusByteCnt                            firstOutputBeatByteNum;
    BusByteCnt                            lastOutputBeatByteNum;
    Bool                                    isFirst;             
    Bool                                    isLast;                    
} FtileMacRxGearBoxMeta deriving(Bits, FShow);

interface FtileMacRxPayloadStorageAndGearBox;
    interface PipeIn#(FtileMacRxBramBufferWriteReq)     rxBramWriteReqPipeIn;
    interface PipeInB0#(FtileMacRxPacketChunkMeta)        packetChunkMetaPipeIn;
    interface PipeOut#(FtileMacRxUserStream)            streamPipeOut;
endinterface

module mkFtileMacRxPayloadStorageAndGearBox(FtileMacRxPayloadStorageAndGearBox);
    FIFOF#(FtileMacRxBramBufferWriteReq)    rxBramWriteReqPipeInQ   <- mkLFIFOF;
    PipeInAdapterB0#(FtileMacRxPacketChunkMeta)       packetChunkMetaPipeInQ  <- mkPipeInAdapterB0;

    Vector#(RTILE_RX_BRAM_BLOCK_CNT, AutoInferBramQueuedOutput#(FtileMacRxBramBufferAddr, DATA))  dataStreamStorageVec  <- replicateM(mkAutoInferBramQueuedOutput(False, "", "mkFtileMacRxPayloadStorageAndGearBox dataStreamStorageVec"));

    UniDirStreamShifter#(DATA) outputShifter <- mkLsbRightStreamRightShifterG;

    Reg#(FtileMacRxBramBufferAddr)                  curReadAddrReg          <- mkRegU;
    Reg#(Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT)))      curReadBramBlockIdxReg  <- mkRegU;
    Reg#(Bool)                                      isReadIdleReg           <- mkReg(True);

    Reg#(Vector#(RTILE_RX_BRAM_BLOCK_CNT, DATA)) readBackDataVecReg <- mkRegU;

    // Pipeline Queue
    FIFOF#(FtileMacRxGearBoxMeta)           packetChunkMetaPipelineQ  <- mkSizedFIFOF(4); 

    let outputShifterStreamPipeInConverter <- mkPipeInB0ToPipeIn(outputShifter.streamPipeIn, 1);
    let outputShifterOffsetPipeInConverter <- mkPipeInB0ToPipeIn(outputShifter.offsetPipeIn, 1);

    // rule debug;
    //     $display(
    //         "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox debug"),
    //         toBlue(", dataStreamStorageVec[0].notEmpty="), fshow(dataStreamStorageVec[0].readRespPipeOut.notEmpty),
    //         toBlue(", packetChunkMetaPipelineQ.notEmpty="), fshow(packetChunkMetaPipelineQ.notEmpty)
    //     );
    // endrule

    rule handleWriteReq;
        let req = rxBramWriteReqPipeInQ.first;
        rxBramWriteReqPipeInQ.deq;

        for (Integer idx = 0; idx < valueOf(RTILE_RX_BRAM_BLOCK_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].write(req.addr, {req.data[idx * 4 + 3], req.data[idx * 4 + 2], req.data[idx * 4 + 1], req.data[idx * 4 + 0]});
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox handleWriteReq"),
        //     toBlue(", req="), fshow(req)
        // );
    endrule

    rule handleReadReq;
        let rawReq = packetChunkMetaPipeInQ.first;
        packetChunkMetaPipeInQ.deq;
        

        for (Integer idx = 0; idx < valueOf(RTILE_RX_BRAM_BLOCK_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].putReadReq(rawReq.bufferAddr);
        end

        let endSegIdx                                            = rawReq.startSegIdx + rawReq.zeroBasedValidSegCnt;
        Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT)) startBramBlockIdx   = truncateLSB(rawReq.startSegIdx);
        Bit#(TLog#(RTILE_RX_BRAM_BLOCK_CNT)) endBramBlockIdx     = truncateLSB(endSegIdx);

        BusByteCnt lastOutputBeatByteNum = ?;
        BusByteCnt firstOutputBeatByteNum = ?;

        if (startBramBlockIdx == endBramBlockIdx) begin
            lastOutputBeatByteNum = ((zeroExtend(rawReq.zeroBasedValidSegCnt) + 1) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM)) - (rawReq.isLast ? zeroExtend(rawReq.lastSegEmptyByteCnt) : 0);
            firstOutputBeatByteNum = lastOutputBeatByteNum;
        end
        else begin
            Bit#(TLog#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)) zeroBasedSegCntInFirstBlock = maxBound - truncate(rawReq.startSegIdx);
            Bit#(TLog#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)) zeroBasedSegCntInLastBlock = truncate(endSegIdx);
    
            firstOutputBeatByteNum = ((zeroExtend(zeroBasedSegCntInFirstBlock) + 1) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM));
            lastOutputBeatByteNum = ((zeroExtend(zeroBasedSegCntInLastBlock) + 1) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM)) - (rawReq.isLast ? zeroExtend(rawReq.lastSegEmptyByteCnt) : 0);        
        end

        let meta = FtileMacRxGearBoxMeta {
            startBramBlockIdx           : startBramBlockIdx,
            endBramBlockIdx             : endBramBlockIdx,
            firstOutputBeatShiftSegCnt  : rawReq.startSegIdx,
            firstOutputBeatByteNum      : firstOutputBeatByteNum,
            lastOutputBeatByteNum       : lastOutputBeatByteNum,
            isFirst                     : rawReq.isFirst,
            isLast                      : rawReq.isLast
        };
        packetChunkMetaPipelineQ.enq(meta);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox handleReadReq"),
        //     toBlue(", meta="), fshow(meta)
        // );
    endrule

    rule handleReadResp;
        let meta = packetChunkMetaPipelineQ.first;

        if (isReadIdleReg) begin
            Vector#(RTILE_RX_BRAM_BLOCK_CNT, DATA) readBackDataVec = newVector;
            for (Integer idx = 0; idx < valueOf(RTILE_RX_BRAM_BLOCK_CNT); idx = idx + 1) begin
                readBackDataVec[idx] = dataStreamStorageVec[idx].readRespPipeOut.first;
                dataStreamStorageVec[idx].readRespPipeOut.deq;
            end


            let isLastBlock = meta.startBramBlockIdx == meta.endBramBlockIdx;
            let isFirst     = meta.isFirst;
            let isLast      = isLastBlock && meta.isLast;

            let byteNum = ?;
            if (isFirst) begin
                byteNum = meta.firstOutputBeatByteNum;
            end
            else if (isLast) begin
                byteNum = meta.lastOutputBeatByteNum;
            end
            else begin
                byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
            end

            let startByteIdx = isFirst ? zeroExtend(meta.firstOutputBeatShiftSegCnt) << valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM) : 0;
            let ds = FtileMacRxUserStream {
                data        : readBackDataVec[meta.startBramBlockIdx],
                byteNum     : byteNum,
                startByteIdx: startByteIdx,
                isFirst     : isFirst,
                isLast      : isLast
            };
            
            readBackDataVecReg <= readBackDataVec;
            curReadBramBlockIdxReg <= meta.startBramBlockIdx + 1;

            outputShifterStreamPipeInConverter.enq(ds);

            if (isFirst) begin
                outputShifterOffsetPipeInConverter.enq(startByteIdx);
            end

            if (!isLastBlock) begin
                isReadIdleReg <= False;
            end
            else begin
                packetChunkMetaPipelineQ.deq;
            end
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox handleReadResp - FIRST"),
            //     toBlue(", ds="), fshow(ds),
            //     toBlue(", meta="), fshow(meta)
            // );
        end
        else begin
            let isLastBlock = curReadBramBlockIdxReg == meta.endBramBlockIdx;
            let isLast      = isLastBlock && meta.isLast;

            let byteNum = ?;
            if (isLast) begin
                byteNum = meta.lastOutputBeatByteNum;
            end
            else begin
                byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
            end

            let ds = FtileMacRxUserStream {
                data        : readBackDataVecReg[curReadBramBlockIdxReg],
                byteNum     : byteNum,
                startByteIdx: 0,
                isFirst     : False,
                isLast      : isLast
            };
            outputShifterStreamPipeInConverter.enq(ds);

            curReadBramBlockIdxReg <= curReadBramBlockIdxReg + 1;

            if (isLastBlock) begin
                isReadIdleReg <= True;
                packetChunkMetaPipelineQ.deq;
            end
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacRxPayloadStorageAndGearBox handleReadResp - MORE"),
            //     toBlue(", ds="), fshow(ds),
            //     toBlue(", isLastBlock="), fshow(isLastBlock)
            // );
        end
    endrule


    interface rxBramWriteReqPipeIn = toPipeIn(rxBramWriteReqPipeInQ);
    interface packetChunkMetaPipeIn = toPipeInB0(packetChunkMetaPipeInQ);
    interface streamPipeOut = outputShifter.streamPipeOut;
endmodule



typedef 512 FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH;
typedef TLog#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_DEPTH) FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH) FtileMacTxChannelBufferAddr;

// input DATA is buffered in a BRAM, each BRAM row has an address, and we further divide one row into segemnts, and give each segment and index.
// in this way, the higher part of the address is BRAM row address, and the lower part of the address is the segment index inside a row;
typedef TDiv#(SizeOf#(DATA), FTILE_MAC_DATA_SEGMENT_WIDTH) FTILE_MAC_TX_SEG_CNT_PER_USER_INPUT_BEAT;
typedef TLog#(FTILE_MAC_TX_SEG_CNT_PER_USER_INPUT_BEAT) FTILE_MAC_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH;
typedef Bit#(FTILE_MAC_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH) FtileMacTxChannelBufferRowSegIdx;
typedef FTILE_MAC_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH   FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET;

typedef TAdd#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_ADDR_WIDTH, FTILE_MAC_TX_SEG_INDEX_IN_BUFFER_ROW_WIDTH) FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_SEG_ADDR_WIDTH;
typedef Bit#(FTILE_MAC_TX_SINGLE_USER_CHANNEL_BUFFER_SEG_ADDR_WIDTH) FtileMacTxChannelBufferSegAddr;
typedef FtileMacTxChannelBufferSegAddr FtileMacTxChannelBufferSegCnt;  // infact, we can redefine it to a shorter type to just hold a 4kB packte and addtional header part.

// BRAM width is 32 bytes, a 4kB packet need 128 beat, and we need to add some beat for headers, so next 2^n value is 256.
typedef 256 FTILE_MAC_TX_MAX_STORAGE_ROW_CNT_PER_PACKET;
typedef Bit#(TLog#(FTILE_MAC_TX_MAX_STORAGE_ROW_CNT_PER_PACKET)) FtileMacTxBufRowCntPerPacket;

typedef struct {
    FtileMacTxChannelBufferSegAddr startSegAddr;
    FtileMacTxChannelBufferSegCnt  segCnt;
    Bool                           isStorageRowCountSmall;  // To improve timing
    FtileMacEopEmpty               eopEmpty;
} FtileMacTxBufferRange deriving(Bits, FShow);

typedef struct {
    FtileMacUserLogicChannelIdx         srcChannelIdx;
    FtileMacTxChannelBufferSegAddr      startSegAddr;
    FtileMacTxChannelBufferSegCnt       segCnt;
    Bool                                isStorageRowCountSmall;
    FtileMacEopEmpty                    eopEmpty;
    FtileMacTxChannelBufferRowSegIdx    destSegOffset;
    ReservedZero#(2)                    reserved;           // make this struct's size is power of two, or the MIMO FIFO will use dsp block to implement multiply operation. cause very bad timing.
} FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset deriving(Bits, FShow);

typedef struct {
    FtileMacUserLogicChannelIdx         srcChannelIdx;
    FtileMacTxChannelBufferAddr         startRowAddr;
    FtileMacSegmentIdx                  zeroBasedSegCnt;
    FtileMacEopEmpty                    eopEmpty;
    FtileMacTxChannelBufferRowSegIdx    destSegOffset;
    Bool                                isLast;
    // Bool                                isOutputBeatLast;
} FtileMacTxPingPongChannelMetaEntry deriving(Bits, FShow);


interface FtileMacTxUserInputGearboxStorageAndMetaExtractor;
    interface PipeInB0#(FtileMacTxUserStream)       streamPipeIn;
    interface PipeOut#(FtileMacTxBufferRange)       packetMetaPipeOut;

    interface Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(FtileMacTxBramBufferReadReq))  bramReadReqPipeInVec;
    interface Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeOut#(DATA))  bramReadRespPipeOutVec;
endinterface

// (* synthesize *)
module mkFtileMacTxUserInputGearboxStorageAndMetaExtractor(FtileMacTxUserInputGearboxStorageAndMetaExtractor);
    PipeInAdapterB0#(FtileMacTxUserStream)    streamPipeInQueue       <- mkPipeInAdapterB0;
    FIFOF#(FtileMacTxBufferRange)           packetMetaPipeOutQueue  <- mkFIFOF;

    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(FtileMacTxBramBufferReadReq)) bramReadReqPipeInVecInst = newVector;
    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeInAdapterB0#(FtileMacTxBramBufferReadReq)) bramReadReqPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeOut#(DATA)) bramReadRespPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, FIFOF#(DATA)) bramReadRespPipeOutQueueVec <- replicateM(mkFIFOF);

    for (Integer idx=0; idx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        bramReadReqPipeInVecInst[idx] = toPipeInB0(bramReadReqPipeInQueueVec[idx]);
        bramReadRespPipeOutVecInst[idx] = toPipeOut(bramReadRespPipeOutQueueVec[idx]);
    end

    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, AutoInferBramQueuedOutput#(FtileMacTxChannelBufferAddr, DATA))  dataStreamStorageVec  <- replicateM(mkAutoInferBramQueuedOutput(False, "", "mkFtileMacTxUserInputGearboxStorageAndMetaExtractor dataStreamStorageVec"));
    
    Reg#(FtileMacTxChannelBufferAddr)    curRowAddrReg      <- mkReg(0);
    Reg#(FtileMacTxChannelBufferAddr)    startRowAddrReg    <- mkReg(0);
    Reg#(FtileMacTxChannelBufferSegCnt)  curSegCntReg       <- mkReg(0);

    // rule debug;
    //     if (!streamPipeInQueue.notFull) begin
    //         $display("time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor debug"),  toBlue(", streamPipeInQueue is Full"));
    //     end

    //     if (!packetMetaPipeOutQueue.notFull) begin
    //         $display("time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor debug"),  toBlue(", packetMetaPipeOutQueue is Full"));
    //     end
    //     for (Integer idx=0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
    //         if (!bramReadReqPipeInQueueVec[idx].notFull) begin
    //             $display("time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor debug [idx=%d]"), idx, toBlue(", bramReadReqPipeInQueueVec is Full"));
    //         end
    //         if (!bramReadRespPipeOutQueueVec[idx].notFull) begin
    //             $display("time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor debug [idx=%d]"), idx, toBlue(", bramReadRespPipeOutQueueVec is Full"));
    //         end
    //     end
    // endrule


    for (Integer idx=0; idx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        rule handleStorageReadReq;
            let req = bramReadReqPipeInQueueVec[idx].first;
            bramReadReqPipeInQueueVec[idx].deq;
            dataStreamStorageVec[idx].putReadReq(req.addr);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor handleStorageReadReq [idx=%d]"), idx,
            //     toBlue(", req="), fshow(req)
            // );
        endrule

        // TODO Should we remove this stage?
        rule handleStorageReadResp;
            let resp = dataStreamStorageVec[idx].readRespPipeOut.first;
            dataStreamStorageVec[idx].readRespPipeOut.deq;
            bramReadRespPipeOutQueueVec[idx].enq(resp);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor handleStorageReadResp [idx=%d]"), idx,
            //     toBlue(", resp="), fshow(resp)
            // );
        endrule
    end

    rule handleMetaCalc;
        let ds = streamPipeInQueue.first;
        streamPipeInQueue.deq;

        let curSegCnt = curSegCntReg;
        if (!ds.isLast) begin
            curSegCnt = curSegCnt + fromInteger(valueOf(FTILE_MAC_TX_SEG_CNT_PER_USER_INPUT_BEAT));
        end
        else begin

            let zeroBasedByteNum = ds.byteNum - 1;
            curSegCnt = curSegCnt + zeroExtend(zeroBasedByteNum >> valueOf(FTILE_MAC_SEGMENT_CNT_TO_BYTE_CNT_CONVERT_SHIFT_NUM)) + 1;

            FtileMacEopEmpty byteNumLowerBits = truncate(zeroBasedByteNum);

            let outputEntry = FtileMacTxBufferRange {
                startSegAddr: zeroExtend(startRowAddrReg) << valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET),
                segCnt: curSegCnt, 
                isStorageRowCountSmall: (curSegCnt >> valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)),
                eopEmpty: fromInteger(valueOf(FTILE_MAC_TLP_DATA_SEGMENT_BYTE_WIDTH)-1) - byteNumLowerBits
            };
            packetMetaPipeOutQueue.enq(outputEntry);
            curSegCnt = 0;
            startRowAddrReg <= curRowAddrReg + 1;
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor handleMetaCalc"),
            //     toBlue(", outputEntry="), fshow(outputEntry)
            // );
        end

        for (Integer idx = 0; idx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
            dataStreamStorageVec[idx].write(curRowAddrReg, ds.data);
        end
        curRowAddrReg <= curRowAddrReg + 1;
        curSegCntReg  <= curSegCnt;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacTxUserInputGearboxStorageAndMetaExtractor handleMetaCalc BRAMwrite"),
        //     toBlue(", curRowAddrReg="), fshow(curRowAddrReg),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface streamPipeIn              = toPipeInB0(streamPipeInQueue);
    interface packetMetaPipeOut         = toPipeOut(packetMetaPipeOutQueue);
    interface bramReadReqPipeInVec      = bramReadReqPipeInVecInst;
    interface bramReadRespPipeOutVec    = bramReadRespPipeOutVecInst;
endmodule



typedef 2 FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT;  // since the beta width is 1024 bits(128 bytes), and min eth packet is 64 bytes.
typedef 3 FTILE_MAC_TX_MAX_PACKET_PER_BEAT;
typedef TDiv#(FTILE_MAC_DATA_BUNDLE_WIDTH, SizeOf#(DATA)) FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT;  // 4
// typedef TSub#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT, 1) FTILE_MAC_TX_MAX_OVERFLOW_SEG_CNT_PER_BEAT;
typedef FTILE_MAC_USER_LOGIC_CHANNEL_CNT                    FTILE_MAC_TX_PING_PONG_CHANNEL_CNT;
typedef Bit#(TLog#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT))     FtileMacTxPingPongChannelIdx;
typedef Bit#(TLog#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT))   FtileMacTxOutputBeatNewPacketIndex;

typedef Bit#(TLog#(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) FtileMacTxBramRowIndexInOutputBeat;
typedef TAdd#(1, TLog#(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) FTILE_MAC_TX_SMALL_BRAM_ROW_COUNT_WIDTH;
typedef TAdd#(1, FTILE_MAC_TX_SMALL_BRAM_ROW_COUNT_WIDTH) FTILE_MAC_TX_SMALL_BRAM_ROW_COUNT_SUM_RESULT_WIDTH;
typedef Bit#(FTILE_MAC_TX_SMALL_BRAM_ROW_COUNT_WIDTH) FtileMacTxSmallBramRowCnt;
typedef Bit#(FTILE_MAC_TX_SMALL_BRAM_ROW_COUNT_SUM_RESULT_WIDTH) FtileMacTxSmallBramRowCntSumResult;


typedef Vector#(FTILE_MAC_TX_MAX_PACKET_PER_BEAT, Maybe#(FtileMacTxPingPongChannelMetaEntry)) FtileMacTxPingPongChannelMetaBundle;

interface FtileMacTxPingPongFork;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInB0#(FtileMacTxBufferRange)) packetMetaPipeInVec;
    interface Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeOut#(FtileMacTxPingPongChannelMetaBundle))  pingpongChannelMetaPipeOutVec;
endinterface

(* synthesize *)
module mkFtileMacTxPingPongFork(FtileMacTxPingPongFork);
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInB0#(FtileMacTxBufferRange)) packetMetaPipeInVecInst = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInAdapterB0#(FtileMacTxBufferRange)) packetMetaPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeOut#(FtileMacTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, FIFOF#(FtileMacTxPingPongChannelMetaBundle)) pingpongChannelMetaPipeOutQueueVec <- replicateM(mkFIFOF);
    

    for (Integer idx=0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        packetMetaPipeInVecInst[idx] = toPipeInB0(packetMetaPipeInQueueVec[idx]);
    end

    for (Integer idx=0; idx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        pingpongChannelMetaPipeOutVecInst[idx] = toPipeOut(pingpongChannelMetaPipeOutQueueVec[idx]);
    end


    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Reg#(Maybe#(FtileMacTxBufferRange))) curDataRangeRegVec <- replicateM(mkReg(tagged Invalid));
    Reg#(FtileMacUserLogicChannelIdx)       curInputRoundRobinIdxReg <- mkReg(0);
    Reg#(FtileMacTxPingPongChannelIdx)      curOutputRoundRobinIdxReg <- mkReg(0);
    Reg#(FtileMacTxChannelBufferRowSegIdx)  prevDestSegOffsetReg <- mkReg(0);

    let mimoCfg = MIMOConfiguration {
        unguarded: False,
        bram_based: False
    };
    MIMO#(
        FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT,
            FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT,
            TMul#(2, FTILE_MAC_USER_LOGIC_CHANNEL_CNT),
            FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset
    ) selectedInputChannelMetaMIMO <- mkMIMO(mimoCfg);
    

    Reg#(Maybe#(FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset)) curMetaMaybeReg <- mkReg(tagged Invalid);

    // Pipeline Queues
    FIFOF#(Tuple2#(
        Vector#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT, FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset),
        LUInt#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT)
    ))  mimoInputPipelineQueue <- mkLFIFOF;

    FIFOF#(Tuple2#(FtileMacTxPingPongChannelIdx, FtileMacTxPingPongChannelMetaBundle)) outputTimingFixPipelineQueue <- mkLFIFOF;

    rule guard;
        immAssert(
            valueOf(SizeOf#(FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset)) == valueOf(TExp#(TLog#(SizeOf#(FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset)))),
            "the size of FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset must be 2's power",
            $format("")
        );
    endrule

    rule prepareRoundRobinChannelOrder;
        Vector#(FTILE_MAC_TX_MAX_NEW_PACKET_PER_BEAT, FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset) vecToEnq = newVector;
        Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, Bool) needDeqFlagVec = replicate(False);
        let curInputRoundRobinIdx = curInputRoundRobinIdxReg;
        let prevDestSegOffset = prevDestSegOffsetReg;
        let enqCnt = 0;
        case ({ pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].notEmpty),
                pack(packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].notEmpty)
            }) matches
            4'b0000: begin
            end
            4'b0001: begin
                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 1;
            end
            4'b0010: begin
                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty, 
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 1;
            end
            4'b0011: begin
                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b0100: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall, 
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 1;
            end
            4'b0101: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b011?: begin
                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b1000: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt,
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty, 
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);
                curInputRoundRobinIdx = curInputRoundRobinIdx + 1;
                enqCnt = 1;
            end
            4'b1001: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+3] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+3].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+3,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 0;
                enqCnt = 2;
            end
            4'b101?: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+2] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+2].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+2,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 3;
                enqCnt = 2;
            end
            4'b11??: begin
                needDeqFlagVec[curInputRoundRobinIdx+0] = True;
                let inMeta0 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+0].first;
                vecToEnq[0] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+0,
                    startSegAddr    : inMeta0.startSegAddr, 
                    segCnt          : inMeta0.segCnt, 
                    isStorageRowCountSmall : inMeta0.isStorageRowCountSmall,
                    eopEmpty        : inMeta0.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta0.segCnt);

                needDeqFlagVec[curInputRoundRobinIdx+1] = True;
                let inMeta1 = packetMetaPipeInQueueVec[curInputRoundRobinIdx+1].first;
                vecToEnq[1] = FtileMacTxBufferRangeWithSrcChannelIdxAndDestSegOffset {
                    srcChannelIdx   : curInputRoundRobinIdx+1,
                    startSegAddr    : inMeta1.startSegAddr, 
                    segCnt          : inMeta1.segCnt, 
                    isStorageRowCountSmall : inMeta1.isStorageRowCountSmall,
                    eopEmpty        : inMeta1.eopEmpty,
                    destSegOffset   : prevDestSegOffset,
                    reserved        : unpack(0)
                };
                prevDestSegOffset = prevDestSegOffset + truncate(inMeta1.segCnt);
                
                curInputRoundRobinIdx = curInputRoundRobinIdx + 2;
                enqCnt = 2;
            end
        endcase

        
        // IMPORTANT!!!!
        // since MIMO's enq doesn't have guard (infact, it has guard, but the guard only check if it can enq at least one element), to make sure 
        // there are enough space for `enqCnt`, we can't relay on enq's guard to block the rule from being fired.
        // so, we need to move all the "Actions"(i.e., code that will change the state) into the following IF block. And only leave combinational logic
        // out of the IF block
        if (enqCnt != 0 && selectedInputChannelMetaMIMO.enqReadyN(enqCnt)) begin
            curInputRoundRobinIdxReg <= curInputRoundRobinIdx;
            prevDestSegOffsetReg <= prevDestSegOffset;

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

            selectedInputChannelMetaMIMO.enq(enqCnt, vecToEnq);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongFork prepareRoundRobinChannelOrder"),
            //     toBlue(", enqCnt="), fshow(enqCnt),
            //     toBlue(", vecToEnq="), fshow(vecToEnq)
            // );
        end

        // mimoInputPipelineQueue.enq(tuple2(vecToEnq, enqCnt));
    endrule

    // rule forwardRoundRobinResultToMimoBuffer;
    //     let {vecToEnq, enqCnt} = mimoInputPipelineQueue.first;
    //     mimoInputPipelineQueue.deq;
    //     if (enqCnt != 0) begin
    //         selectedInputChannelMetaMIMO.enq(enqCnt, vecToEnq);
    //     end
    // endrule


    rule dispatch;
        FtileMacTxPingPongChannelMetaBundle outputMetaBundle = replicate(tagged Invalid);

        if (curMetaMaybeReg matches tagged Valid .curMeta) begin

            let onePacketMetaAvailable      = True;
            let twoPacketMetaAvailable      = selectedInputChannelMetaMIMO.deqReadyN(1);
            let threePacketMetaAvailable    = selectedInputChannelMetaMIMO.deqReadyN(2);

            let packetOneMeta   = curMeta;
            let packetTwoMeta   = twoPacketMetaAvailable ? selectedInputChannelMetaMIMO.first[0] : ?;
            let packetThreeMeta = threePacketMetaAvailable ? selectedInputChannelMetaMIMO.first[1] : ?;

            FtileMacTxSmallBramRowCnt packetOneSmallBramRowCnt   = truncate((packetOneMeta.segCnt - 1) >> valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) + 1;
            FtileMacTxSmallBramRowCnt packetTwoSmallBramRowCnt   = truncate((packetTwoMeta.segCnt - 1)  >> valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) + 1;
            FtileMacTxSmallBramRowCnt packetThreeSmallBramRowCnt = truncate((packetThreeMeta.segCnt - 1) >> valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) + 1;

            FtileMacTxSmallBramRowCntSumResult onePacketSmallBramRowCntSum   =                               zeroExtend(packetOneSmallBramRowCnt);
            FtileMacTxSmallBramRowCntSumResult twoPacketSmallBramRowCntSum   = onePacketSmallBramRowCntSum + zeroExtend(packetTwoSmallBramRowCnt);
            FtileMacTxSmallBramRowCntSumResult threePacketSmallBramRowCntSum = twoPacketSmallBramRowCntSum + zeroExtend(packetThreeSmallBramRowCnt);

            let packetOneWillEndInThisBeat   = packetOneMeta.isStorageRowCountSmall   && onePacketSmallBramRowCntSum   <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            let packetTwoWillEndInThisBeat   = packetTwoMeta.isStorageRowCountSmall   && twoPacketSmallBramRowCntSum   <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            let packetThreeWillEndInThisBeat = packetThreeMeta.isStorageRowCountSmall && threePacketSmallBramRowCntSum <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            
            let beatWillHoldOnePacket   = onePacketMetaAvailable;
            let beatWillHoldTwoPacket   = twoPacketMetaAvailable   && packetOneMeta.isStorageRowCountSmall && onePacketSmallBramRowCntSum < fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            let beatWillHoldThreePacket = threePacketMetaAvailable && packetOneMeta.isStorageRowCountSmall && packetTwoMeta.isStorageRowCountSmall && twoPacketSmallBramRowCntSum < fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));

            FtileMacTxSmallBramRowCnt smallStorgeRowCntLeftForPacketOne     = fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
            FtileMacTxSmallBramRowCnt smallStorgeRowCntLeftForPacketTwo     = fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) - truncate(onePacketSmallBramRowCntSum);
            FtileMacTxSmallBramRowCnt smallStorgeRowCntLeftForPacketThree   = fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)) - truncate(twoPacketSmallBramRowCntSum);

            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongFork dispatch"),
            //     toBlue(", beatWillHoldPacket="), fshow(beatWillHoldThreePacket ? 3 : beatWillHoldTwoPacket ? 2 : 1),
            //     toBlue(", packetOneSmallBramRowCnt="), fshow(packetOneSmallBramRowCnt),
            //     toBlue(", packetTwoSmallBramRowCnt="), fshow(packetTwoSmallBramRowCnt),
            //     toBlue(", packetThreeSmallBramRowCnt="), fshow(packetThreeSmallBramRowCnt),
            //     toBlue(", onePacketSmallBramRowCntSum="), fshow(onePacketSmallBramRowCntSum),
            //     toBlue(", twoPacketSmallBramRowCntSum="), fshow(twoPacketSmallBramRowCntSum),
            //     toBlue(", threePacketSmallBramRowCntSum="), fshow(threePacketSmallBramRowCntSum),
            //     toBlue(", smallStorgeRowCntLeftForPacketOne="), fshow(smallStorgeRowCntLeftForPacketOne),
            //     toBlue(", smallStorgeRowCntLeftForPacketTwo="), fshow(smallStorgeRowCntLeftForPacketTwo),
            //     toBlue(", smallStorgeRowCntLeftForPacketThree="), fshow(smallStorgeRowCntLeftForPacketThree)
            // );

            if (beatWillHoldThreePacket) begin
                outputMetaBundle[0] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetOneMeta.segCnt-1),
                    eopEmpty        : packetOneMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : True
                    // isOutputBeatLast: 
                };
                outputMetaBundle[1] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetTwoMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetTwoMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetTwoMeta.segCnt-1),
                    eopEmpty        : packetTwoMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : True
                    // isOutputBeatLast: 
                };
                outputMetaBundle[2] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetThreeMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetThreeMeta.startSegAddr),
                    zeroBasedSegCnt : packetThreeWillEndInThisBeat ? truncate(packetThreeMeta.segCnt-1) : ((zeroExtend(smallStorgeRowCntLeftForPacketThree) << valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) - 1),
                    eopEmpty        : packetThreeMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : packetThreeWillEndInThisBeat
                    // isOutputBeatLast: 
                };

                immAssert(selectedInputChannelMetaMIMO.deqReadyN(2), "MIMO Queue doesn't have enough element", $format(""));
                selectedInputChannelMetaMIMO.deq(2);

                if (packetThreeWillEndInThisBeat) begin
                    curMetaMaybeReg <= tagged Invalid;
                    immFail("should not reach here, each packet is at least 64 Byte, 3 packet can't end in single 128 Byte", $format(""));
                end
                else begin
                    let nextCurMeta                     = packetThreeMeta;
                    let segCntDelta                     = zeroExtend(smallStorgeRowCntLeftForPacketThree) << valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET);
                    nextCurMeta.startSegAddr            = nextCurMeta.startSegAddr + segCntDelta;
                    nextCurMeta.segCnt                  = nextCurMeta.segCnt - segCntDelta;
                    nextCurMeta.isStorageRowCountSmall  = (nextCurMeta.segCnt >> valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
                    curMetaMaybeReg <= tagged Valid nextCurMeta;
                end
            end
            else if (beatWillHoldTwoPacket) begin
                outputMetaBundle[0] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : truncate(packetOneMeta.segCnt-1),
                    eopEmpty        : packetOneMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : True
                    // isOutputBeatLast: 
                };
                outputMetaBundle[1] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetTwoMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetTwoMeta.startSegAddr),
                    zeroBasedSegCnt : packetTwoWillEndInThisBeat ? truncate(packetTwoMeta.segCnt-1) : ((zeroExtend(smallStorgeRowCntLeftForPacketTwo) << valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) - 1),
                    eopEmpty        : packetTwoMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : packetTwoWillEndInThisBeat
                    // isOutputBeatLast: 
                };

                immAssert(selectedInputChannelMetaMIMO.deqReadyN(1), "MIMO Queue doesn't have enough element", $format(""));
                selectedInputChannelMetaMIMO.deq(1);

                if (packetTwoWillEndInThisBeat) begin
                    curMetaMaybeReg <= tagged Invalid;
                end
                else begin
                    let nextCurMeta                     = packetTwoMeta;
                    let segCntDelta                     = zeroExtend(smallStorgeRowCntLeftForPacketTwo) << valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET);
                    nextCurMeta.startSegAddr            = nextCurMeta.startSegAddr + segCntDelta;
                    nextCurMeta.segCnt                  = nextCurMeta.segCnt - segCntDelta;
                    nextCurMeta.isStorageRowCountSmall  = (nextCurMeta.segCnt >> valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
                    curMetaMaybeReg <= tagged Valid nextCurMeta;
                end
            end
            else if (beatWillHoldOnePacket) begin
                outputMetaBundle[0] = tagged Valid FtileMacTxPingPongChannelMetaEntry {
                    srcChannelIdx   : packetOneMeta.srcChannelIdx,
                    startRowAddr    : truncateLSB(packetOneMeta.startSegAddr),
                    zeroBasedSegCnt : packetOneWillEndInThisBeat ? truncate(packetOneMeta.segCnt - 1) : ((zeroExtend(smallStorgeRowCntLeftForPacketOne) << valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) - 1),
                    eopEmpty        : packetOneMeta.eopEmpty,
                    destSegOffset   : ?,
                    isLast          : packetOneWillEndInThisBeat
                    // isOutputBeatLast: 
                };

                if (packetOneWillEndInThisBeat) begin
                    if (selectedInputChannelMetaMIMO.deqReadyN(1)) begin
                        curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[0];
                        selectedInputChannelMetaMIMO.deq(1);
                    end
                    else begin
                        curMetaMaybeReg <= tagged Invalid;
                    end
                end
                else begin
                    let nextCurMeta                     = packetOneMeta;
                    let segCntDelta                     = fromInteger(valueOf(FTILE_MAC_SEGMENT_CNT));
                    nextCurMeta.startSegAddr            = nextCurMeta.startSegAddr + segCntDelta;
                    nextCurMeta.segCnt                  = nextCurMeta.segCnt - segCntDelta;
                    nextCurMeta.isStorageRowCountSmall  = (nextCurMeta.segCnt >> valueOf(FTILE_MAC_TX_SEG_ADDR_TO_ROW_ADDR_CONVERT_SHIFT_OFFSET)) <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT));
                    curMetaMaybeReg <= tagged Valid nextCurMeta;
                end
            end
            else begin
                immFail("should not reach here", $format(""));
            end

            outputTimingFixPipelineQueue.enq(tuple2(curOutputRoundRobinIdxReg, outputMetaBundle));
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongFork dispatch final output"),
            //     toBlue(", curOutputRoundRobinIdxReg="), fshow(curOutputRoundRobinIdxReg),
            //     toBlue(", outputMetaBundle="), fshow(outputMetaBundle)
            // );

            curOutputRoundRobinIdxReg <= curOutputRoundRobinIdxReg + 1;
        end
        else begin
            if (selectedInputChannelMetaMIMO.deqReadyN(1)) begin
                curMetaMaybeReg <= tagged Valid selectedInputChannelMetaMIMO.first[0];
                selectedInputChannelMetaMIMO.deq(1);
                // $display(
                //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongFork dispatch IDLE"),
                //     toBlue(", selectedInputChannelMetaMIMO.first[0]="), fshow(selectedInputChannelMetaMIMO.first[0])
                // );
            end
            else begin
                // $display(
                //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongFork dispatch IDLE and not new packet")
                // );
            end
        end
    endrule

    rule forwardOutput;
        let {curOutputRoundRobinIdx, outputMetaBundle} = outputTimingFixPipelineQueue.first;
        outputTimingFixPipelineQueue.deq;
        pingpongChannelMetaPipeOutQueueVec[curOutputRoundRobinIdx].enq(outputMetaBundle);
    endrule

    
    interface packetMetaPipeInVec = packetMetaPipeInVecInst;
    interface pingpongChannelMetaPipeOutVec = pingpongChannelMetaPipeOutVecInst;
endmodule

typedef struct {
    FtileMacTxChannelBufferAddr addr;
} FtileMacTxBramBufferReadReq deriving (FShow, Bits);

typedef struct {
    FtileMacUserLogicChannelIdx         srcChannelIdx;
    FtileMacTxChannelBufferRowSegIdx    zeroBasedValidSegCnt;
    FtileMacEopEmpty                    eopEmpty;
    Bool                                isLast;
    Bool                                isOutputBeatLast;
} FtileMacTxPingPongChannelBramReadPipelineEntry deriving (FShow, Bits);


typedef struct {
    FtileMacDataBusSegBundle            dataBuf;
    SegmentInframeSignalBundle          inFrameSignal;
    SegmentEopEmptySignalBundle         eopEmptySignal;
} FtileMacTxPingPongChannelOutputEntry deriving (FShow, Bits);

interface FtileMacTxPingPongSingleChannel;
    interface PipeInB0#(FtileMacTxPingPongChannelMetaBundle)      metaPipeIn;
    interface PipeOut#(FtileMacTxPingPongChannelOutputEntry)    beatPipeOut;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacTxBramBufferReadReq))  bramReadReqPipeOutVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInB0#(DATA))  bramReadRespPipeInVec;
endinterface

(* synthesize *)
module mkFtileMacTxPingPongSingleChannel(FtileMacTxPingPongSingleChannel);
    PipeInAdapterB0#(FtileMacTxPingPongChannelMetaBundle)  metaPipeInQueue <- mkPipeInAdapterB0;
    FIFOF#(FtileMacTxPingPongChannelOutputEntry) beatPipeOutQueue <- mkFIFOF;

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacTxBramBufferReadReq))  bramReadReqPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FIFOF#(FtileMacTxBramBufferReadReq))    bramReadReqPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInB0#(DATA))   bramReadRespPipeInVecInst = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInAdapterB0#(DATA))    bramReadRespPipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    for (Integer idx=0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        bramReadReqPipeOutVecInst[idx] = toPipeOut(bramReadReqPipeOutQueueVec[idx]);
        bramReadRespPipeInVecInst[idx] = toPipeInB0(bramReadRespPipeInQueueVec[idx]);
    end

    
    Reg#(Maybe#(FtileMacTxPingPongChannelMetaEntry)) curMetaEntryMaybeReg <- mkReg(tagged Invalid);
    Reg#(FtileMacTxPingPongChannelMetaBundle) curInputMetaBundleReg <- mkRegU;

    Reg#(FtileMacTxBramRowIndexInOutputBeat) outputBeatEmptyStorageRowCntReg <- mkReg(fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)-1));


    Reg#(FtileMacTxPingPongChannelOutputEntry) outputEntryReg <- mkReg(unpack(0));

    // Pipeline FIFOs
    FIFOF#(FtileMacTxPingPongChannelBramReadPipelineEntry) bramReadPipelineQueue <- mkSizedFIFOF(8);
    FIFOF#(Tuple2#(FtileMacTxBramRowIndexInOutputBeat, FtileMacTxPingPongChannelOutputEntry))  finalShiftPipelineQueue <- mkLFIFOF;

    rule sendBramReadReq;
        let zeroBasedValidSegCnt = ?;

        if (curMetaEntryMaybeReg matches tagged Valid .curMetaEntry) begin
            let metaBundle = metaPipeInQueue.first;

            let isCurMetaEntryLast = (curMetaEntry.zeroBasedSegCnt <= fromInteger(valueOf(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)-1));
            let isPacketLast = isCurMetaEntryLast && curMetaEntry.isLast;
            let haveNextValidPacketMeta = isValid(curInputMetaBundleReg[0]);
            let isOutputBeatLast = isCurMetaEntryLast && !haveNextValidPacketMeta;

            if (!isPacketLast) begin
                zeroBasedValidSegCnt = fromInteger(valueOf(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT)-1);
            end
            else begin
                zeroBasedValidSegCnt = truncate(curMetaEntry.zeroBasedSegCnt);
            end

            bramReadReqPipeOutQueueVec[curMetaEntry.srcChannelIdx].enq(FtileMacTxBramBufferReadReq{addr: curMetaEntry.startRowAddr});
            bramReadPipelineQueue.enq(FtileMacTxPingPongChannelBramReadPipelineEntry {
                srcChannelIdx       : curMetaEntry.srcChannelIdx,
                zeroBasedValidSegCnt: zeroBasedValidSegCnt,
                eopEmpty            : curMetaEntry.eopEmpty,
                isLast              : isPacketLast,
                isOutputBeatLast    : isOutputBeatLast
            });

            let nextCurMetaEntryMaybe;
            if (!isCurMetaEntryLast) begin
                let nextCurMetaEntry = curMetaEntry;
                nextCurMetaEntry.zeroBasedSegCnt = nextCurMetaEntry.zeroBasedSegCnt - fromInteger(valueOf(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT));
                nextCurMetaEntry.startRowAddr = nextCurMetaEntry.startRowAddr + 1;
                nextCurMetaEntryMaybe = tagged Valid nextCurMetaEntry;
            end
            else begin
                if (haveNextValidPacketMeta) begin
                    curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, curInputMetaBundleReg, 1);
                    nextCurMetaEntryMaybe = curInputMetaBundleReg[0];
                end
                else begin
                    if (metaPipeInQueue.notEmpty) begin
                        curInputMetaBundleReg <= shiftOutFrom0(tagged Invalid, metaPipeInQueue.first, 1);
                        nextCurMetaEntryMaybe = metaPipeInQueue.first[0];
                        metaPipeInQueue.deq;
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
            // $display(
            //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongSingleChannel sendBramReadReq IDLE"),
            //     toBlue(", metaPipeInQueue.first="), fshow(metaPipeInQueue.first)
            // );
        end
    endrule


    rule handleBramReadResp;
        let bramReadBeatMeta = bramReadPipelineQueue.first;
        bramReadPipelineQueue.deq;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongSingleChannel handleBramReadResp"),
        //     toBlue(", bramReadBeatMeta="), fshow(bramReadBeatMeta)
        // );

        let readResp = bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].first;
        bramReadRespPipeInQueueVec[bramReadBeatMeta.srcChannelIdx].deq;

        let outputEntry                     = outputEntryReg;
        let outputBeatEmptyStorageRowCnt    = outputBeatEmptyStorageRowCntReg;

        Vector#(RTILE_GEAR_BOX_SEG_CNT_PER_USER_LOGIC_BEAT, FtileMacDataSegment) readRespAsSegBundle = unpack(readResp);
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[0]);
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[1]);
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[2]);
        outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, readRespAsSegBundle[3]);

        case (bramReadBeatMeta.zeroBasedValidSegCnt)
            0: begin
                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 4'b0000: 4'b1111, truncateLSB(outputEntry.inFrameSignal)};
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, bramReadBeatMeta.isLast ? bramReadBeatMeta.eopEmpty : unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
            end
            1: begin
                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 4'b0001: 4'b1111, truncateLSB(outputEntry.inFrameSignal)};
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, bramReadBeatMeta.isLast ? bramReadBeatMeta.eopEmpty : unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
            end
            2: begin
                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 4'b0011: 4'b1111, truncateLSB(outputEntry.inFrameSignal)};
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, bramReadBeatMeta.isLast ? bramReadBeatMeta.eopEmpty : unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
            end
            3: begin
                outputEntry.inFrameSignal = {bramReadBeatMeta.isLast ? 4'b0111: 4'b1111, truncateLSB(outputEntry.inFrameSignal)};
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, bramReadBeatMeta.isLast ? bramReadBeatMeta.eopEmpty : unpack(0));
            end
        endcase
    

        if (bramReadBeatMeta.isOutputBeatLast) begin
            finalShiftPipelineQueue.enq(tuple2(outputBeatEmptyStorageRowCnt, outputEntry));
            outputBeatEmptyStorageRowCntReg <= fromInteger(valueOf(FTILE_MAC_TX_INPUT_BRAM_ROW_CNT_PER_OUTPUT_BEAT)-1);
        end
        else begin
            outputBeatEmptyStorageRowCntReg <= outputBeatEmptyStorageRowCnt - 1;
        end
        outputEntryReg <= outputEntry;
    endrule

    rule finalShift;
        FtileMacTxBramRowIndexInOutputBeat      outputBeatEmptyStorageRowCnt;
        FtileMacTxPingPongChannelOutputEntry    outputEntry;

        {outputBeatEmptyStorageRowCnt, outputEntry} = finalShiftPipelineQueue.first;
        finalShiftPipelineQueue.deq;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkFtileMacTxPingPongSingleChannel finalShift"),
        //     toBlue(", outputBeatEmptyStorageRowCnt="), fshow(outputBeatEmptyStorageRowCnt),
        //     toBlue(", outputEntry="), fshow(outputEntry)
        // );

        case (outputBeatEmptyStorageRowCnt)
            0: begin
                // nothing to do
            end
            1: begin
                for (Integer idx = 0; idx < 4; idx = idx + 1) begin
                    outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, unpack(0));
                    outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                    outputEntry.inFrameSignal = {1'b0, truncateLSB(outputEntry.inFrameSignal)};
                end
                
            end
            2: begin
                for (Integer idx = 0; idx < 8; idx = idx + 1) begin
                    outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, unpack(0));
                    outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                    outputEntry.inFrameSignal = {1'b0, truncateLSB(outputEntry.inFrameSignal)};
                end
            end
            3: begin
                for (Integer idx = 0; idx < 12; idx = idx + 1) begin
                    outputEntry.dataBuf = shiftInAtN(outputEntry.dataBuf, unpack(0));
                    outputEntry.eopEmptySignal = shiftInAtN(outputEntry.eopEmptySignal, unpack(0));
                    outputEntry.inFrameSignal = {1'b0, truncateLSB(outputEntry.inFrameSignal)};
                end
            end
        endcase
        beatPipeOutQueue.enq(outputEntry);
    endrule

   

    interface metaPipeIn            = toPipeInB0(metaPipeInQueue);
    interface beatPipeOut           = toPipeOut(beatPipeOutQueue);
    interface bramReadReqPipeOutVec = bramReadReqPipeOutVecInst;
    interface bramReadRespPipeInVec = bramReadRespPipeInVecInst;
endmodule

interface FtileMacTxPingPongJoin;
    interface Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(FtileMacTxPingPongChannelOutputEntry))    pingpongBeatPipeInVec;
    interface PipeOut#(FtileMacTxBeat)                                                                      ftilemacTxPipeOut;
endinterface

(* synthesize *)
module mkFtileMacTxPingPongJoin(FtileMacTxPingPongJoin);
    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeInAdapterB0#(FtileMacTxPingPongChannelOutputEntry))     pingpongBeatPipeInQueueVec <- replicateM(mkPipeInAdapterB0);
    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, PipeInB0#(FtileMacTxPingPongChannelOutputEntry))    pingpongBeatPipeInVecInst  = newVector;
    FIFOF#(FtileMacTxBeat) ftilemacTxPipeOutQueue <- mkFIFOF;

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        pingpongBeatPipeInVecInst[idx] = toPipeInB0(pingpongBeatPipeInQueueVec[idx]);
    end

    Reg#(FtileMacTxPingPongChannelIdx) curChannelIdxReg <- mkReg(0);

    rule doJoin;
        let inputBeat = pingpongBeatPipeInQueueVec[curChannelIdxReg].first;
        pingpongBeatPipeInQueueVec[curChannelIdxReg].deq;
        curChannelIdxReg <= curChannelIdxReg + 1;

        ftilemacTxPipeOutQueue.enq(FtileMacTxBeat{
            data        : inputBeat.dataBuf,
            inframe     : inputBeat.inFrameSignal,
            eop_empty   : inputBeat.eopEmptySignal,
            error       : unpack(0),
            skip_crc    : unpack(0)
        });
    endrule

    interface pingpongBeatPipeInVec = pingpongBeatPipeInVecInst;
    interface ftilemacTxPipeOut     = toPipeOut(ftilemacTxPipeOutQueue);
endmodule

interface FTileMac;
    interface PipeIn#(FtileMacRxBeat) ftilemacRxPipeIn;
    interface PipeOut#(FtileMacTxBeat) ftilemacTxPipeOut;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInB0#(FtileMacTxUserStream)) ftilemacTxStreamPipeInVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxUserStream))  ftilemacRxStreamPipeOutVec;
endinterface


(* synthesize *)
module mkFTileMac(FTileMac);
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxUserStream))  ftilemacRxStreamPipeOutVecInst = newVector;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInB0#(FtileMacTxUserStream)) ftilemacTxStreamPipeInVecInst = newVector;

    let ftileMacRxBeatFork <- mkFtileMacRxBeatFork;
    Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FtileMacRxPingPongSingleChannelProcessor) pingPongChannelVec <- replicateM(mkFtileMacRxPingPongSingleChannelProcessor); 
    let ftileMacRxBeatJoin <- mkFtileMacRxPingPongChannelMetaJoin;
    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FtileMacRxPayloadStorageAndGearBox) storageAndGearBoxVec <- replicateM(mkFtileMacRxPayloadStorageAndGearBox);

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(ftileMacRxBeatFork.rxPingPongChannelMetaPipeOutVec[idx], pingPongChannelVec[idx].beatMetaPipeIn);   // already Nr
        mkConnection(pingPongChannelVec[idx].packetsChunkMetaPipeOut, ftileMacRxBeatJoin.metaPipeInVec[idx]);  // already Nr
    end

    for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx], storageAndGearBoxVec[idx].packetChunkMetaPipeIn);  // already Nr
        ftilemacRxStreamPipeOutVecInst[idx] = storageAndGearBoxVec[idx].streamPipeOut;
    end

    Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FtileMacTxUserInputGearboxStorageAndMetaExtractor) txInputChannelVec <- replicateM(mkFtileMacTxUserInputGearboxStorageAndMetaExtractor);
    let ftileMacTxBeatFork <- mkFtileMacTxPingPongFork;
    Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, FtileMacTxPingPongSingleChannel) txPingPongChannelVec <- replicateM(mkFtileMacTxPingPongSingleChannel);
    let ftileMacTxBeatJoin <- mkFtileMacTxPingPongJoin;

    for (Integer inputChannelIdx = 0; inputChannelIdx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); inputChannelIdx = inputChannelIdx + 1) begin
        for (Integer pingpongChannelIdx = 0; pingpongChannelIdx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); pingpongChannelIdx = pingpongChannelIdx + 1) begin
            mkConnection(txPingPongChannelVec[pingpongChannelIdx].bramReadReqPipeOutVec[inputChannelIdx], txInputChannelVec[inputChannelIdx].bramReadReqPipeInVec[pingpongChannelIdx]);  // already Nr
            mkConnection(txInputChannelVec[inputChannelIdx].bramReadRespPipeOutVec[pingpongChannelIdx], txPingPongChannelVec[pingpongChannelIdx].bramReadRespPipeInVec[inputChannelIdx]);  // already Nr
        end
    end


    for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
        ftilemacTxStreamPipeInVecInst[idx] = txInputChannelVec[idx].streamPipeIn;
        mkConnection(txInputChannelVec[idx].packetMetaPipeOut, ftileMacTxBeatFork.packetMetaPipeInVec[idx]);  // already Nr
        mkConnection(ftileMacTxBeatFork.pingpongChannelMetaPipeOutVec[idx], txPingPongChannelVec[idx].metaPipeIn); // already Nr
        mkConnection(txPingPongChannelVec[idx].beatPipeOut, ftileMacTxBeatJoin.pingpongBeatPipeInVec[idx]);  // already Nr
    end
    

    rule forwardBramWriteReq;
        for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
           storageAndGearBoxVec[idx].rxBramWriteReqPipeIn.enq(ftileMacRxBeatFork.rxBramWriteReqPipeOut.first);
        end
        ftileMacRxBeatFork.rxBramWriteReqPipeOut.deq;
    endrule
    


    interface ftilemacTxStreamPipeInVec     = ftilemacTxStreamPipeInVecInst;
    interface ftilemacTxPipeOut             = ftileMacTxBeatJoin.ftilemacTxPipeOut;
    interface ftilemacRxPipeIn              = ftileMacRxBeatFork.rxBetaPipeIn;
    interface ftilemacRxStreamPipeOutVec    = ftilemacRxStreamPipeOutVecInst;
endmodule



