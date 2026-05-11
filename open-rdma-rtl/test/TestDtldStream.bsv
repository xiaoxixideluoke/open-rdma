import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;
import StmtFSM :: *;
import Cntrs :: *;

import Utils4Test :: *;

import PrimUtils :: *;
import RdmaUtils :: *;
import Utils4Test :: *;
import EthernetTypes :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;
import DtldStream :: *;


interface TestDtldStreamConcatorTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestDtldStreamConcatorTimingTest(TestDtldStreamConcatorTimingTest);
    Reg#(Bit#(128)) outReg <- mkReg(0);
    Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
    Reg#(Bit#(2))  rotReg <- mkReg(0);


    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

    ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeper          <- mkForceKeepWideSignals; 

    DtldStreamConcator#(DATA, NUMERIC_TYPE_TWO) dut <- mkDtldStreamConcator;

    rule test;
        let randValue1 <- randSource1.get;
        
        dut.dataPipeIn.enq(unpack(truncate(randValue1)));
        dut.isLastStreamFlagPipeIn.enq(unpack(truncateLSB(randValue1)));
    endrule



    rule handleOutput;
        let out = dut.dataPipeOut.first;
        dut.dataPipeOut.deq;

        signalKeeper.bitsPipeIn.enq(zeroExtend(pack(out)));
        outReg <= zeroExtend({signalKeeper.out});
    endrule

    method getOutput = outReg;
endmodule




typedef Bit#(10) SpliterSubStreamAlignBlockCnt;

interface TestDtldStreamSpliterTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestDtldStreamSpliterTimingTest(TestDtldStreamSpliterTimingTest);
    Reg#(Bit#(128)) outReg <- mkReg(0);
    Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
    Reg#(Bit#(2))  rotReg <- mkReg(0);


    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

    ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeper          <- mkForceKeepWideSignals; 

    DtldStreamSplitor#(DATA, SpliterSubStreamAlignBlockCnt, NUMERIC_TYPE_TWO) dut <- mkDtldStreamSplitor;

    rule test;
        let randValue1 <- randSource1.get;
        
        dut.dataPipeIn.enq(unpack(truncate(randValue1)));
        dut.streamAlignBlockCountPipeIn.enq(unpack(truncateLSB(randValue1)));
    endrule



    rule handleOutput;
        let out = dut.dataPipeOut.first;
        dut.dataPipeOut.deq;

        signalKeeper.bitsPipeIn.enq(zeroExtend(pack(out)));
        outReg <= zeroExtend({signalKeeper.out});
    endrule

    method getOutput = outReg;
endmodule



module mkTestDtldStreamSpliterAndConcator(Empty);
    
    Reg#(Length) testCounterReg <- mkReg(1000000);
    Reg#(Bool) genNewTestReg <- mkReg(True);
    Reg#(Bool) runCheckerReg[2] <- mkCReg(2, False);

    Count#(Length) originDsCounter <- mkCount(0);

    Length minBatchCnt = 2;

    DtldStreamConcator#(DATA, NUMERIC_TYPE_TWO) concator <- mkDtldStreamConcator;
    DtldStreamSplitor#(DATA, SpliterSubStreamAlignBlockCnt, NUMERIC_TYPE_TWO) splitor <- mkDtldStreamSplitor;

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);

    let originStreamTotalByteNumRandomGenPipeOut <- mkRandomLenPipeOut(1, 512);
    let originStreamStartByteIdxRandomGenPipeOut <- mkRandomLenPipeOut(0,3);
    let splitFirstStreamAlignBlockCntRandomGenPipeOut <- mkRandomLenPipeOut(1,24);
    let splitOtherStreamAlignBlockCntRandomGenPipeOut <- mkRandomLenPipeOut(8,24);

    Reg#(Length) targetOriginDsTotalByteNumReg <- mkRegU;
    Reg#(Length) targetOriginDsStartByteIdxReg <- mkRegU;
    Reg#(Length) curOriginDsTotalByteNumReg <- mkRegU;
    Reg#(Bool)   originDsIsFirstReg <- mkReg(True);

    Reg#(Length) leftAlignBlockCntForSubDsReg <- mkReg(0);
    Reg#(Bool)   firstSubDsLenHasSelectedReg <- mkReg(False);
    Reg#(Length) checkerBatchCounterReg <- mkReg(0);
    

    FIFOF#(DtldStreamData#(DATA)) originDsQueue <- mkSizedFIFOF(1000);
    FIFOF#(Tuple2#(Length, Length)) originDsInfoQueue <- mkSizedFIFOF(1000);
    FIFOF#(Tuple2#(SpliterSubStreamAlignBlockCnt, Bool)) splitAlignBlockCntQueue <- mkSizedFIFOF(1000);

    FIFOF#(DtldStreamData#(DATA)) checkerExpectedDsQueue <- mkSizedFIFOF(1000);


    function DtldStreamData#(DATA) maskOutUnusedBytes(DtldStreamData#(DATA) dsIn);
        DATA mask = -1;
        BusBitCnt shiftCnt = zeroExtend(dsIn.startByteIdx) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        mask = mask >> (shiftCnt);
        mask = mask << (shiftCnt);

        if (dsIn.isLast) begin
            BusByteCnt emptyByteCntAtTail = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx);
            shiftCnt = zeroExtend(emptyByteCntAtTail) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            mask = mask << shiftCnt;
            mask = mask >> shiftCnt;
        end

        dsIn.data = dsIn.data & mask;
        return dsIn;
    endfunction


    rule connectSplitorAndConcator;
        splitor.dataPipeOut.deq;
        concator.dataPipeIn.enq(splitor.dataPipeOut.first);
        // $display("froward from S to C: ds=", fshow(splitor.dataPipeOut.first));
    endrule
    
    rule forkOriginDsToCheckerAndDut;
        let ds = originDsQueue.first;
        originDsQueue.deq;
        splitor.dataPipeIn.enq(ds);
        checkerExpectedDsQueue.enq(ds);
    endrule

    rule forkOriginDsMetaToCheckerAndDut;
        let {subDsAlignCnt, isSubDsLast} = splitAlignBlockCntQueue.first;
        splitAlignBlockCntQueue.deq;
        splitor.streamAlignBlockCountPipeIn.enq(subDsAlignCnt);
        concator.isLastStreamFlagPipeIn.enq(isSubDsLast);
    endrule

    rule checkOutput if (originDsCounter == minBatchCnt);
        let expectedDs = checkerExpectedDsQueue.first;
        checkerExpectedDsQueue.deq;

        let gotDs = concator.dataPipeOut.first;
        concator.dataPipeOut.deq;

        // if (expectedDs.isFirst) begin
        //     $display("======================================================");
        //     $display("===============Start Check New Stream=================");
        //     $display("======================================================");
        // end


        
        if (expectedDs.isLast) begin
            if (checkerBatchCounterReg + 1 == minBatchCnt) begin
                checkerBatchCounterReg <= 0;
                originDsCounter.decr(minBatchCnt);
            end
            else begin
                checkerBatchCounterReg <= checkerBatchCounterReg + 1;
            end
        end

        // $display("expectedDs=", fshow(expectedDs));
        // $display("     gotDs=", fshow(gotDs));

        expectedDs = maskOutUnusedBytes(expectedDs);
        gotDs = maskOutUnusedBytes(gotDs);
        // $display("time=%t", $time);
        // $display("masked expectedDs=", fshow(expectedDs));
        // $display("     masked gotDs=", fshow(gotDs));

        immAssert(
            pack(expectedDs) == pack(gotDs),
            "not match",
            $format("")
        );
    endrule

    Stmt genOriginStream = (seq
        repeat(minBatchCnt)
        seq
            action
                targetOriginDsTotalByteNumReg <= originStreamTotalByteNumRandomGenPipeOut.first;
                originStreamTotalByteNumRandomGenPipeOut.deq;

                targetOriginDsStartByteIdxReg <= originStreamStartByteIdxRandomGenPipeOut.first;
                originStreamStartByteIdxRandomGenPipeOut.deq;

                curOriginDsTotalByteNumReg <= 0;

                originDsInfoQueue.enq(tuple2(originStreamTotalByteNumRandomGenPipeOut.first, originStreamStartByteIdxRandomGenPipeOut.first));
            endaction

            while (curOriginDsTotalByteNumReg != targetOriginDsTotalByteNumReg)
            seq
                action

                    BusByteCnt byteCntCanHoldInThisBeat = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - truncate(targetOriginDsStartByteIdxReg);

                    let isFirst = originDsIsFirstReg;
                    let isLast = (targetOriginDsTotalByteNumReg - curOriginDsTotalByteNumReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH))) && (truncate(targetOriginDsTotalByteNumReg - curOriginDsTotalByteNumReg) <= byteCntCanHoldInThisBeat);
                    originDsIsFirstReg <= isLast;
                    targetOriginDsStartByteIdxReg <= 0;

                    // $display("targetOriginDsStartByteIdxReg=", fshow(targetOriginDsStartByteIdxReg), ", curOriginDsTotalByteNumReg=", fshow(curOriginDsTotalByteNumReg), ", targetOriginDsTotalByteNumReg=", fshow(targetOriginDsTotalByteNumReg));
                    BusByteCnt byteNum;
                    BusByteIdx    startByteIdx;

                    if (isFirst && isLast) begin
                        byteNum = truncate(targetOriginDsTotalByteNumReg);
                        startByteIdx = truncate(targetOriginDsStartByteIdxReg);
                    end
                    else if (isFirst) begin
                        byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                        byteNum = byteNum - truncate(targetOriginDsStartByteIdxReg);
                        startByteIdx = truncate(targetOriginDsStartByteIdxReg);
                    end
                    else if (isLast) begin
                        byteNum = truncate(targetOriginDsTotalByteNumReg - curOriginDsTotalByteNumReg);
                        startByteIdx = 0;
                    end
                    else begin
                        byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                        startByteIdx = 0;
                    end

                    let tmpData <- randSource1.get;
                    DtldStreamData#(DATA) ds = DtldStreamData {
                        data: truncate(tmpData),
                        byteNum: byteNum,
                        startByteIdx: startByteIdx,
                        isFirst: isFirst,
                        isLast: isLast
                    };
                    originDsQueue.enq(ds);
                    // $display("original DS: ds=", fshow(ds));

                    curOriginDsTotalByteNumReg <= curOriginDsTotalByteNumReg + zeroExtend(byteNum);
                    
                endaction
            endseq
        endseq
    endseq);


    Stmt splitMetaGen = (seq
        repeat(minBatchCnt)
        seq
            while (!firstSubDsLenHasSelectedReg)
            seq
                action
                    if (originDsInfoQueue.notFull) begin
                        let {originDsLen, startIdx} = originDsInfoQueue.first;
                        let firstStreamAlignBlockCnt = splitFirstStreamAlignBlockCntRandomGenPipeOut.first;
                        splitFirstStreamAlignBlockCntRandomGenPipeOut.deq;
                        let originDsALignBlockCnt = ((originDsLen + startIdx - 1) >> valueOf(NUMERIC_TYPE_TWO)) + 1;
                        if (firstStreamAlignBlockCnt <= originDsALignBlockCnt) begin
                            originDsInfoQueue.deq;
                            let isLastSubDs = firstStreamAlignBlockCnt == originDsALignBlockCnt;
                            splitAlignBlockCntQueue.enq(tuple2(truncate(firstStreamAlignBlockCnt), isLastSubDs));
                            leftAlignBlockCntForSubDsReg <= originDsALignBlockCnt - firstStreamAlignBlockCnt;
                            firstSubDsLenHasSelectedReg <= True;
                            // $display("org ds meta = ", fshow(originDsInfoQueue.first));
                            // $display("split plan: subDsAlignCnt=", fshow(firstStreamAlignBlockCnt), ", isLastSubDs=", fshow(isLastSubDs));
                        end
                    end
                endaction
            endseq

            firstSubDsLenHasSelectedReg <= False;

            while (leftAlignBlockCntForSubDsReg != 0)
            seq
                action
                    if (leftAlignBlockCntForSubDsReg >= 8) begin
                        let t = splitOtherStreamAlignBlockCntRandomGenPipeOut.first;
                        splitOtherStreamAlignBlockCntRandomGenPipeOut.deq;
                        Length otherStreamAlignBlockCnt = 8 * (1 + zeroExtend(pack(t)[1:0]));

                        if (otherStreamAlignBlockCnt > leftAlignBlockCntForSubDsReg) begin
                            // nothing to do
                        end
                        else begin
                            let isLastSubDs = leftAlignBlockCntForSubDsReg == otherStreamAlignBlockCnt;
                            splitAlignBlockCntQueue.enq(tuple2(truncate(otherStreamAlignBlockCnt), isLastSubDs));
                            // $display("split plan: subDsAlignCnt=", fshow(otherStreamAlignBlockCnt), ", isLastSubDs=", fshow(isLastSubDs));
                            leftAlignBlockCntForSubDsReg <= leftAlignBlockCntForSubDsReg - otherStreamAlignBlockCnt;
                        end
                    end
                    else begin
                        splitAlignBlockCntQueue.enq(tuple2(truncate(leftAlignBlockCntForSubDsReg), True));
                        // $display("split plan: subDsAlignCnt=", fshow(leftAlignBlockCntForSubDsReg), ", isLastSubDs=", fshow(True));
                        leftAlignBlockCntForSubDsReg <= 0;
                    end
                endaction
            endseq
        endseq
    endseq);




    FSM originDsGenFSM <- mkFSM(genOriginStream);
    FSM genSplitMetaFSM  <- mkFSM(splitMetaGen);


    Stmt runTest = (seq
        // action
        //     $display("======================================================");
        //     $display("=====================New Batch=======================");
        //     $display("======================================================");
        // endaction
        originDsGenFSM.start;
        // $display("step 1---------------");
        await(originDsGenFSM.done);
        // $display("step 2---------------");
        genSplitMetaFSM.start;
        // $display("step 3---------------");
        await(genSplitMetaFSM.done);
        // $display("step 4---------------");
        originDsCounter.incr(minBatchCnt);
        // $display("step 5---------------");
        await(originDsCounter == 0);
        // $display("step 6---------------");
    endseq);

    FSM runTestFSM  <- mkFSM(runTest);
    
    // rule debug;
    //     $display(fshow(originDsGenFSM.done), " ", fshow(genSplitMetaFSM.done), " ", fshow(originDsInfoQueue.notEmpty), " ", fshow(splitAlignBlockCntQueue.notFull), " originDsCounter=", fshow(originDsCounter));
    // endrule

    rule runTestRule;
        testCounterReg <= testCounterReg - 1;
        if (testCounterReg == 0) begin
            $display("Pass");
            $finish;
        end
        if (testCounterReg % 10000 == 0) begin
            $display("testCounterReg=%d", testCounterReg);
        end
        runTestFSM.start;
    endrule
endmodule

// module mkTestDtldStreamSpliterAndConcator(Empty);
//     DtldStreamConcator#(DATA, NUMERIC_TYPE_TWO) concator <- mkDtldStreamConcator;

//     Stmt runTest = (
//         par
//         seq
//             concator.isLastStreamFlagPipeIn.enq(False);
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000f8e80000f8e40000f8e00000f8dc0000f8d80000f8d40000f8d00000f8cc, byteNum: 'h1e, startByteIdx: 'h02, isFirst: True, isLast: False});
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000f9080000f9040000f9000000f8fc0000f8f80000f8f40000f8f00000f8ec, byteNum: 'h20, startByteIdx: 'h00, isFirst: False, isLast: False});
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000f9280000f9240000f9200000f91c0000f9180000f9140000f9100000f90c, byteNum: 'h20, startByteIdx: 'h00, isFirst: False, isLast: False});
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000000000000000000000000000f93c0000f9380000f9340000f9300000f92c, byteNum: 'h14, startByteIdx: 'h00, isFirst: False, isLast: True});
//             concator.isLastStreamFlagPipeIn.enq(True);
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000f95c0000f9580000f9540000f9500000f94c0000f9480000f9440000f940, byteNum: 'h20, startByteIdx: 'h00, isFirst: True, isLast: False});
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000f97c0000f9780000f9740000f9700000f96c0000f9680000f9640000f960, byteNum: 'h20, startByteIdx: 'h00, isFirst: False, isLast: False});
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000f99c0000f9980000f9940000f9900000f98c0000f9880000f9840000f980, byteNum: 'h20, startByteIdx: 'h00, isFirst: False, isLast: False});
//             concator.dataPipeIn.enq(DtldStreamData {data: 'h0000000000000000000000000000000000000000000000000000f9a40000f9a0, byteNum: 'h07, startByteIdx: 'h00, isFirst: False, isLast: True});
            
//         endseq
//         seq
//             action
//                 concator.dataPipeOut.deq;
//                 $display(fshow(concator.dataPipeOut.first));
//             endaction
//             action
//                 concator.dataPipeOut.deq;
//                 $display(fshow(concator.dataPipeOut.first));
//             endaction
//             action
//                 concator.dataPipeOut.deq;
//                 $display(fshow(concator.dataPipeOut.first));
//             endaction
//             action
//                 concator.dataPipeOut.deq;
//                 $display(fshow(concator.dataPipeOut.first));
//             endaction
//             action
//                 concator.dataPipeOut.deq;
//                 $display(fshow(concator.dataPipeOut.first));
//             endaction
//             action
//                 concator.dataPipeOut.deq;
//                 $display(fshow(concator.dataPipeOut.first));
//             endaction
//             action
//                 concator.dataPipeOut.deq;
//                 $display(fshow(concator.dataPipeOut.first));
//             endaction
            
//         endseq
//         endpar
//     );

//     FSM runTestFSM  <- mkFSM(runTest);

//     Reg#(Bool) runReg <- mkReg(True);

//     rule r if (runReg);
//         runReg <= False;
//         runTestFSM.start;
//     endrule

// endmodule