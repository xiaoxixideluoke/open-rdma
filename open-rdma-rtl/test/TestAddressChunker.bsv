import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;


(* doc = "testcase" *)
module mkTestAddressChunker(Empty);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);



    AddressChunker#(ADDR, Length, ChunkAlignLogValue) dutAddrChunkerNoOutputAlign <- mkAddressChunker;
    
    // TODO: the function for this should be fixed. Or this function should be removed.
    // AddressChunker#(ADDR, Length, ChunkAlignLogValue) dutAddrChunkerWithOutputAlign <- mkAddressChunker;

    PipeOut#(Length) withOutputAlignOrNotRandPipeOut <- mkRandomLenPipeOut(1, 2);
    PipeOut#(Length) pmtuRandPipeOut <- mkRandomLenPipeOut(1, 5);
    PipeOut#(Length) lengthRandPipeOut <- mkRandomLenPipeOut(1, 1024 * 16);
    PipeOut#(ADDR) addrRandPipeOut <- mkGenericRandomPipeOut;

    FIFOF#(Tuple3#(AddressChunkReq#(ADDR, Length, ChunkAlignLogValue), PMTU, Bool)) originReqForCheckerQ <- mkFIFOF;
    Reg#(Length) totalLenSumReg <- mkRegU;
    Reg#(Bool) canGenReqReg <- mkReg(True);



    rule reqGen if (canGenReqReg);
        canGenReqReg <= False;

        
        PMTU pmtu = unpack(truncate(pack(pmtuRandPipeOut.first)));
        pmtuRandPipeOut.deq;

        // random value is 1~5, after plus 7, it is between 8~12, which means 2^8 ~ 2^12, which is 256 ~ 4096
        ChunkAlignLogValue pmtuSizeInLog = getPmtuSizeByPmtuEnum(pmtu);

        Length len = lengthRandPipeOut.first;
        lengthRandPipeOut.deq;

        ADDR addr = addrRandPipeOut.first;
        addrRandPipeOut.deq;

        let isAccepted = True;

        Bit#(TAdd#(1, SizeOf#(ADDR))) addrPlusLen = zeroExtend(addr) + zeroExtend(len);
        
        if (msb(addrPlusLen) == 1) begin
            isAccepted = False;
        end

        if (isAccepted) begin

            // TODO: the function for this should be fixed. Or this function should be removed.
            // Bool withOutputAlign = withOutputAlignOrNotRandPipeOut.first == 1;
            // withOutputAlignOrNotRandPipeOut.deq;
            Bool withOutputAlign = False;

            let req = AddressChunkReq{
                startAddr: addr,
                len: len,
                chunk: pmtuSizeInLog 
            };

            
            if (withOutputAlign) begin
                // dutAddrChunkerWithOutputAlign.requestPipeIn.enq(req);
            end
            else begin
                dutAddrChunkerNoOutputAlign.requestPipeIn.enq(req);
            end
            originReqForCheckerQ.enq(tuple3(req, pmtu, withOutputAlign));
        end
    endrule

    rule checkResp if (!canGenReqReg);

        let {expectedReq, pmtuExpected, withOutputAlign} = originReqForCheckerQ.first;

        let chunk;
        if (withOutputAlign) begin
            // chunk = dutAddrChunkerWithOutputAlign.responsePipeOut.first;
            // dutAddrChunkerWithOutputAlign.responsePipeOut.deq;
        end
        else begin
            chunk =dutAddrChunkerNoOutputAlign.responsePipeOut.first;
            dutAddrChunkerNoOutputAlign.responsePipeOut.deq;
        end

        
        let totalLenSum = totalLenSumReg;
        if (chunk.isFirst) begin
            totalLenSum = chunk.len;
        end
        else begin
            totalLenSum = totalLenSum + chunk.len;
        end
        totalLenSumReg <= totalLenSum;


        Length expectedFullChunkSize = 1 << pack(expectedReq.chunk);

        if (chunk.isFirst && chunk.isLast) begin
            immAssert(
                chunk.len == expectedReq.len,
                "For ONLY chunk, expect chunk.len == expectedReq.len",
                $format("Got chunk=", fshow(chunk), ", expectedReq=", fshow(expectedReq))
            );
        end

        if (chunk.isFirst) begin
            immAssert(
                chunk.startAddr == expectedReq.startAddr,
                "For first chunk, the start address must match the request's start address",
                $format("Got chunk=", fshow(chunk), ", expectedReq=", fshow(expectedReq))
            );
        end

        if (!chunk.isFirst && !chunk.isLast) begin
            immAssert(
                chunk.len == expectedFullChunkSize,
                "middle chunk shoud have full length",
                $format(
                    "chunk=", fshow(chunk), 
                    ", expectedFullChunkSize=", fshow(expectedFullChunkSize)
                ) 
            );
        end

        immAssert(
            chunk.len != 0,
            "resp chunk len must not be zero",
            $format("Got chunk=", fshow(chunk))
        );

        immAssert(
            chunk.len <= expectedFullChunkSize,
            "resp chunk len must not greater than req chunk size",
            $format("Got chunk=", fshow(chunk), ", expectedFullChunkSize=", fshow(expectedFullChunkSize))
        );


        if (chunk.isLast) begin
            immAssert(
                totalLenSum == expectedReq.len,
                "totalLenSum should match expectedReq.len",
                $format(
                    "totalLenSum=", fshow(totalLenSum), 
                    ", expectedReq=", fshow(expectedReq)
                ) 
            );
            originReqForCheckerQ.deq;
        end

        if (!withOutputAlign) begin
            let {devidedLen, lenRemainderTmp} = devideLengthByPMTU(chunk.len, pmtuExpected);
            let {alignedAddr, addrRemainderTmp} = alignAddrByPMTU(chunk.startAddr, pmtuExpected);
            immAssert(
                lenRemainderTmp + truncate(addrRemainderTmp) <= expectedFullChunkSize,
                "a split should not across align boundary.",
                $format(
                    "lenRemainderTmp=", fshow(lenRemainderTmp), 
                    ", addrRemainderTmp=", fshow(addrRemainderTmp),
                    ", expectedFullChunkSize=", fshow(expectedFullChunkSize)
                ) 
            );

            if (!chunk.isFirst) begin
                immAssert(
                    addrRemainderTmp == 0,
                    "address not aligned",
                    $format(
                        ", addrRemainderTmp=", fshow(addrRemainderTmp)
                    ) 
                );
            end
        end
        else begin
            if (chunk.isFirst && !chunk.isLast) begin
                let invalidByteCnt = expectedFullChunkSize - chunk.len;
                immAssert(
                    invalidByteCnt <= 3,
                    "since output is aligned to 4 byte, no more than 3 invalid byte is allowed",
                    $format(
                        ", chunk=", fshow(chunk),
                        ", expectedFullChunkSize=", fshow(expectedFullChunkSize)
                    )
                );
            end
            if (!chunk.isFirst) begin
                immAssert(
                    chunk.startAddr[1:0] == 2'b0,
                    "output address not aligned",
                    $format(
                        ", chunk=", fshow(chunk)
                    ) 
                );
            end
            
        end


        if (chunk.isLast) begin
            quitCounterReg <= quitCounterReg - 1;
            canGenReqReg <= True;
            if (quitCounterReg % 100000 == 0) begin
                $display("quitCounterReg=%d",quitCounterReg);
            end
            if (quitCounterReg == 0) begin
                $display("Pass");
                $finish;
            end
        end

    endrule
endmodule




function Tuple2#(ADDR, ADDR) alignAddrByPMTU(ADDR addr, PMTU pmtu);
    return case (pmtu)
        IBV_MTU_256 : begin
            // 8 = log2(256)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 8], 8'b0 }, zeroExtend(addr[7 : 0]));
        end
        IBV_MTU_512 : begin
            // 9 = log2(512)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 9], 9'b0 }, zeroExtend(addr[8 : 0]));
        end
        IBV_MTU_1024: begin
            // 10 = log2(1024)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 10], 10'b0 }, zeroExtend(addr[9 : 0]));
        end
        IBV_MTU_2048: begin
            // 11 = log2(2048)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 11], 11'b0 }, zeroExtend(addr[10 : 0]));
        end
        IBV_MTU_4096: begin
            // 12 = log2(4096)
            tuple2({ addr[valueOf(ADDR_WIDTH)-1 : 12], 12'b0 }, zeroExtend(addr[11 : 0]));
        end
    endcase;
endfunction


function Tuple2#(Length, Length) devideLengthByPMTU(Length len, PMTU pmtu);
    return case (pmtu)
        IBV_MTU_256 : begin
            // 8 = log2(256)
            tuple2({ 8'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 8] }, zeroExtend(len[7 : 0]));
        end
        IBV_MTU_512 : begin
            // 9 = log2(512)
            tuple2({ 9'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 9] }, zeroExtend(len[8 : 0]));
        end
        IBV_MTU_1024: begin
            // 10 = log2(1024)
            tuple2({ 10'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 10] }, zeroExtend(len[9 : 0]));
        end
        IBV_MTU_2048: begin
            // 11 = log2(2048)
            tuple2({ 11'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 11] }, zeroExtend(len[10 : 0]));
        end
        IBV_MTU_4096: begin
            // 12 = log2(4096)
            tuple2({ 12'b0, len[valueOf(RDMA_MAX_LEN_WIDTH)-1 : 12] }, zeroExtend(len[11 : 0]));
        end
    endcase;
endfunction



interface TestAddressChunkerTiming;
    method Byte getOutput;
endinterface



(* synthesize *)
(* doc = "testcase" *)
module mkTestAddressChunkerTiming(TestAddressChunkerTiming);
    
    AddressChunker#(ADDR, Length, ChunkAlignLogValue) dutAddrChunkerNoOutputAlign <- mkAddressChunker;


    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    ForceKeepWideSignals#(Bit#(256), Byte) signalKeeper1 <- mkForceKeepWideSignals; 


    rule injectInput1;
        let randValue1 <- randSource1.get;
        dutAddrChunkerNoOutputAlign.requestPipeIn.enq(unpack(truncate(randValue1)));
    endrule

    rule handleOutput;
        let t1 = dutAddrChunkerNoOutputAlign.responsePipeOut.first;
        dutAddrChunkerNoOutputAlign.responsePipeOut.deq;

        signalKeeper1.bitsPipeIn.enq(zeroExtend(pack(t1)));
    endrule

    method getOutput = signalKeeper1.out;
endmodule