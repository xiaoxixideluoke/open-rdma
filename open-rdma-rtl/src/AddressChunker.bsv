import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import BasicDataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;


typedef struct {
    tAddr startAddr;
    tLen len;
    tChunkAlignLog chunk;
} AddressChunkReq#(type tAddr, type tLen, type tChunkAlignLog) deriving(Bits, FShow);

typedef struct {
    tAddr       startAddr;
    tLen        len;
    Bool        isFirst;
    Bool        isLast;
} AddressChunkResp#(type tAddr, type tLen) deriving(Bits, FShow);

interface AddressChunker#(type tAddr, type tLen, type tChunkAlignLog);
    interface PipeInB0#(AddressChunkReq#(tAddr, tLen, tChunkAlignLog)) requestPipeIn;
    interface PipeOut#(AddressChunkResp#(tAddr, tLen)) responsePipeOut;
endinterface



module mkAddressChunker(AddressChunker#(tAddr, tLen, tChunkAlignLog)) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tLen, szLen),
        Bits#(tChunkAlignLog, szChunkAlignLog),
        Bitwise#(tAddr),
        Bitwise#(tLen),
        Eq#(tLen),
        Arith#(tLen),
        Arith#(tChunkAlignLog),
        Add#(b__, szLen, szAddr),
        Ord#(tLen),
        Arith#(tAddr), 
        Alias#(Bit#(TAdd#(1, szLen)), tInternalMathOp),
        Bits#(tInternalMathOp, szInternalMathOp),
        Add#(a__, szInternalMathOp, szAddr),
        FShow#(AddressChunkReq#(tAddr, tLen, tChunkAlignLog)),
        PrimShiftIndex#(tChunkAlignLog, c__)
    );

    PipeInAdapterB0#(AddressChunkReq#(tAddr, tLen, tChunkAlignLog)) reqQ <- mkPipeInAdapterB0;
    FIFOF#(AddressChunkResp#(tAddr, tLen)) respQ <- mkFIFOF;

    FIFOF#(Tuple5#(tLen, tLen, tLen, tAddr, tLen)) preCalcResultQueue <- mkLFIFOF;

    Reg#(Bool) busyReg <- mkReg(False);
    
    Reg#(tLen) remainingChunkNumReg <- mkRegU;
    Reg#(tAddr) nextAddrReg <- mkRegU;
    Reg#(tLen) remainingLenReg <- mkRegU;
    Reg#(tLen) chunkSizeReg <- mkRegU;

    rule preCalc;
        let chunkReq = reqQ.first;
        reqQ.deq;

        tLen chunkSize = unpack(1 << chunkReq.chunk);

        tLen zeroBasedOutputAlignChunkCnt;
        tLen zeroBasedChunkCnt;
        tLen nonValidByteCntInFirstChunk;

        zeroBasedOutputAlignChunkCnt = 0;
        zeroBasedChunkCnt = unpack(
            ((truncate(pack(chunkReq.startAddr)) + zeroExtend(pack(chunkReq.len) - 1)) >> chunkReq.chunk) -
            (truncate(pack(chunkReq.startAddr)) >> chunkReq.chunk)
        );
        tLen chunkRemainingMask = chunkSize - 1;
        nonValidByteCntInFirstChunk = unpack(truncate(pack(chunkReq.startAddr)) & pack(chunkRemainingMask));
        
        preCalcResultQueue.enq(tuple5(chunkSize, nonValidByteCntInFirstChunk, zeroBasedChunkCnt, chunkReq.startAddr, chunkReq.len));
    endrule

    rule doFirstBeat if (!busyReg);

        let {chunkSize, nonValidByteCntInFirstChunk, zeroBasedChunkCnt, reqStartAddr, reqLen} = preCalcResultQueue.first;
        preCalcResultQueue.deq;
        
        tLen outputLen = chunkSize - nonValidByteCntInFirstChunk;
        Bool isOnlyChunk = zeroBasedChunkCnt == 0;

        chunkSizeReg <= chunkSize;
        nextAddrReg <= reqStartAddr + unpack(zeroExtend(pack(outputLen)));
        busyReg <= !isOnlyChunk;
        remainingLenReg <= reqLen - outputLen;
        remainingChunkNumReg <= zeroBasedChunkCnt;

        tAddr startAddr = reqStartAddr;
        tLen len = isOnlyChunk ? reqLen : outputLen;
        let isFirst = True;
        let isLast = isOnlyChunk;

        let outEntry = AddressChunkResp {
            startAddr: startAddr,
            len: len, 
            isFirst: isFirst,
            isLast: isLast
        };

        respQ.enq(outEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressChunker doFirstBeat"),
        //     toBlue(", req="), fshow(req),
        //     toBlue(", remainingChunkNum="), fshow(remainingChunkNum),
        //     toBlue(", isOnlyChunk="), fshow(isOnlyChunk),
        //     toBlue(", chunkSize="), fshow(chunkSize),
        //     toBlue(", addrRemainder="), fshow(addrRemainder),
        //     toBlue(", nextAddr="), fshow(nextAddr),
        //     toBlue(", startAddr="), fshow(startAddr),
        //     toBlue(", len="), fshow(len),
        //     toBlue(", outEntry="), fshow(outEntry)
        // );

    endrule

    rule doOtherBeat if (busyReg);
        let isLast = isOneR(pack(remainingChunkNumReg));
        if (isLast) begin
            busyReg <= False;
        end
        else begin
            remainingChunkNumReg <= remainingChunkNumReg - 1;
        end

        let newNextAddr = nextAddrReg + unpack(zeroExtend(pack(chunkSizeReg)));
        nextAddrReg <= newNextAddr;
        let newRemainingLen = remainingLenReg - unpack(zeroExtend(pack(chunkSizeReg)));
        remainingLenReg <= newRemainingLen;

        let outEntry = AddressChunkResp {
            startAddr: nextAddrReg,
            len: isLast ? remainingLenReg : unpack(zeroExtend(pack(chunkSizeReg))), 
            isFirst: False,
            isLast: isLast
        };
        respQ.enq(outEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkAddressChunker doOtherBeat"),
        //     toBlue(", remainingChunkNumReg="), fshow(remainingChunkNumReg),
        //     toBlue(", nextAddrReg="), fshow(nextAddrReg),
        //     toBlue(", newNextAddr="), fshow(newNextAddr),
        //     toBlue(", remainingLenReg="), fshow(remainingLenReg),
        //     toBlue(", newRemainingLen="), fshow(newRemainingLen),
        //     toBlue(", outEntry="), fshow(outEntry)
        // );
    endrule
    
    interface requestPipeIn = toPipeInB0(reqQ);
    interface responsePipeOut = toPipeOut(respQ);
endmodule