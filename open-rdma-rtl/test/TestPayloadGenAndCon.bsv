import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import PayloadGenAndCon :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;
import NapWrapper :: *;
import StreamShifterG :: *;
import MemRegionAndAddressTranslate :: *;
import IoChannels :: *;


typedef enum {
    TestPayloadGenAndConStateGenWriteReq = 0,
    TestPayloadGenAndConStateWaitWriteFinish = 1,
    TestPayloadGenAndConStateCheckReadResp = 2
} TestPayloadGenAndConState deriving(FShow, Bits, Eq);



interface TestCocotbPayloadGenAndCon;
    interface IoChannelMemoryMasterPipe ioChannelMemoryMasterPipeIfc;
endinterface

(* doc = "testcase" *)
module mkTestCocotbPayloadGenAndCon(TestCocotbPayloadGenAndCon);

    Reg#(Bit#(32)) quitCounterReg <- mkReg(1000000);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    PayloadGenAndCon dut <- mkPayloadGenAndCon(clk, rst);

    let fakeAddrTranslatorForGen <- mkBypassAddressTranslateForTest;
    let fakeAddrTranslatorForCon <- mkBypassAddressTranslateForTest;
    mkConnection(dut.genAddrTranslateClt, fakeAddrTranslatorForGen.translateSrv);
    mkConnection(dut.conAddrTranslateClt, fakeAddrTranslatorForCon.translateSrv);

    let payloadStreamGen <- mkFixedLengthDateStreamRandomGen;
    let writeStreamShifter <- mkLsbRightStreamLeftShifterG;
    // mkConnection(payloadStreamGen.streamPipeOut, writeStreamShifter.streamPipeIn);

    rule debug;
        let ds = payloadStreamGen.streamPipeOut.first;
        payloadStreamGen.streamPipeOut.deq;
        writeStreamShifter.streamPipeIn.enq(ds);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkTestCocotbPayloadGenAndCon debug"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    FIFOF#(PayloadGenReq) payloadGenReqQ <- mkFIFOF;
    FIFOF#(DataStream) expectedStreamQ <- mkSizedFIFOF(1024);

    // Vector#(2, PipeOut#(DataStream)) rdmaPayloadDataStreamPipeOutForkedVec <- mkForkVector(writeStreamShifter.streamPipeOut);
    // mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[0], dut.payloadConStreamPipeIn);
    // mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[1], toPipeIn(expectedStreamQ));

    rule forkShiftResult;
        let ds = writeStreamShifter.streamPipeOut.first;
        writeStreamShifter.streamPipeOut.deq;
        dut.payloadConStreamPipeIn.enq(ds);
        expectedStreamQ.enq(ds);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkTestCocotbPayloadGenAndCon forkShiftResult"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    PipeOut#(Length) payloadLenRandPipeOut <- mkRandomLenPipeOut(1, 2048);//fromInteger(valueOf(MAX_PMTU)));
    PipeOut#(Length) payloadAddrRandPipeOut <- mkRandomLenPipeOut(0, 1 << (valueOf(MOCK_HOST_ADDR_WIDTH)-1) );


    Reg#(TestPayloadGenAndConState) stateReg <- mkReg(TestPayloadGenAndConStateGenWriteReq);


    rule genWriteReq if (stateReg == TestPayloadGenAndConStateGenWriteReq);
       
        let rdmaPayloadLen = payloadLenRandPipeOut.first;
        payloadLenRandPipeOut.deq;

        ADDR rdmaPayloadStartAddr = zeroExtend(payloadAddrRandPipeOut.first);
        payloadAddrRandPipeOut.deq;


        payloadStreamGen.reqPipeIn.enq(zeroExtend(rdmaPayloadLen));

        ByteIdxInDword startByteOffset = truncate(rdmaPayloadStartAddr);
        BusByteIdx signedShiftOffset = zeroExtend(startByteOffset);
        writeStreamShifter.offsetPipeIn.enq(signedShiftOffset);

        let conReq = PayloadConReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen,
            baseVA: dontCareValue,    // since we use a fake addr translator in test.
            pgtOffset: dontCareValue  // since we use a fake addr translator in test.
        };
        dut.conReqPipeIn.enq(conReq);


        let genReq = PayloadGenReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen,
            baseVA: dontCareValue,    // since we use a fake addr translator in test.
            pgtOffset: dontCareValue  // since we use a fake addr translator in test.
        };
        payloadGenReqQ.enq(genReq);

        stateReg <= TestPayloadGenAndConStateWaitWriteFinish;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkTestCocotbPayloadGenAndCon genWriteReq"),
        //     toBlue(", conReq="), fshow(conReq)
        // );
    endrule

    rule waitWriteFinished if (stateReg == TestPayloadGenAndConStateWaitWriteFinish);
        let writeFinishResp = dut.conRespPipeOut.first;
        dut.conRespPipeOut.deq;
        immAssert(
            writeFinishResp,
            "writeFinishResp should be True, which means no error occured",
            $format("")
        );

        let genReq = payloadGenReqQ.first;
        payloadGenReqQ.deq;
        dut.genReqPipeIn.enq(genReq);

        stateReg <= TestPayloadGenAndConStateCheckReadResp;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkTestCocotbPayloadGenAndCon waitWriteFinished"),
        //     toBlue(", genReq="), fshow(genReq)
        // );
    endrule

    rule checkReadResp if (stateReg == TestPayloadGenAndConStateCheckReadResp);
        let ds = dut.payloadGenStreamPipeOut.first;
        dut.payloadGenStreamPipeOut.deq;

        let expectedDs = expectedStreamQ.first;
        expectedStreamQ.deq;

        // mask out non-valid bytes.
        if (ds.isFirst) begin
            // only first beat is right aligned.
            BusBitCnt shiftOffset = zeroExtend(ds.startByteIdx) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            DATA maskForStartByteIdx = ~((1 << shiftOffset) - 1);

            shiftOffset = (zeroExtend(ds.startByteIdx) + zeroExtend(ds.byteNum)) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            DATA maskForByteNum = (1 << shiftOffset) - 1;

            ds.data = ds.data & maskForStartByteIdx & maskForByteNum;
            expectedDs.data = expectedDs.data & maskForStartByteIdx & maskForByteNum;
        end
        else if (ds.isLast) begin
            BusBitCnt shiftOffset = zeroExtend(ds.byteNum) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            DATA maskForByteNum = (1 << shiftOffset) - 1;
            ds.data = ds.data & maskForByteNum;
            expectedDs.data = expectedDs.data & maskForByteNum;
        end
        

        immAssert(
            ds == expectedDs,
            "read datastream not match write datastream",
            $format("ds=", fshow(ds), ", expectedDs=", fshow(expectedDs))
        );

        if (ds.isLast) begin
            stateReg <= TestPayloadGenAndConStateGenWriteReq;

            // $display("----------one check finished ----------------\n\n\n");

            quitCounterReg <= quitCounterReg - 1;
            if (quitCounterReg % 50 == 0) begin
                $display(quitCounterReg);
            end
            if (quitCounterReg == 0) begin
                $display("PASS");
                $finish;
            end
        end
    endrule

    interface ioChannelMemoryMasterPipeIfc = dut.ioChannelMemoryMasterPipeIfc;
endmodule



interface TestPayloadGenAndConTiming;
    method Bit#(32) getOutput;
endinterface


(* doc = "testcase" *)
(* synthesize *)
module mkTestPayloadGenAndConTiming(TestPayloadGenAndConTiming);

    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    PayloadGenAndCon dut <- mkPayloadGenAndCon(clk, rst);

    ForceKeepWideSignals#(Bit#(512), Bit#(32)) signalKeeperForGen <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(512), Bit#(32)) signalKeeperForDma <- mkForceKeepWideSignals; 

    ForceKeepWideSignals#(Bool, Bool) signalKeeperForCon <- mkForceKeepWideSignals; 
    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    Reg#(Bit#(32)) outReg <- mkRegU;

    let fakeAddrTranslatorForGen <- mkBypassAddressTranslateForTest;
    let fakeAddrTranslatorForCon <- mkBypassAddressTranslateForTest;
    mkConnection(dut.genAddrTranslateClt, fakeAddrTranslatorForGen.translateSrv);
    mkConnection(dut.conAddrTranslateClt, fakeAddrTranslatorForCon.translateSrv);

    rule handleDmaAccess;
        IoChannelMemoryAccessMeta metaA = ?;
        IoChannelMemoryAccessMeta metaB = ?;
        IoChannelMemoryAccessDataStream ds = ?;
        if (dut.ioChannelMemoryMasterPipeIfc.writePipeIfc.writeMetaPipeOut.notEmpty) begin
            dut.ioChannelMemoryMasterPipeIfc.writePipeIfc.writeMetaPipeOut.deq;
            metaA = dut.ioChannelMemoryMasterPipeIfc.writePipeIfc.writeMetaPipeOut.first;
        end

        if (dut.ioChannelMemoryMasterPipeIfc.readPipeIfc.readMetaPipeOut.notEmpty) begin
            dut.ioChannelMemoryMasterPipeIfc.readPipeIfc.readMetaPipeOut.deq;
            metaB = dut.ioChannelMemoryMasterPipeIfc.readPipeIfc.readMetaPipeOut.first;
        end

        if (dut.ioChannelMemoryMasterPipeIfc.writePipeIfc.writeDataPipeOut.notEmpty) begin
            dut.ioChannelMemoryMasterPipeIfc.writePipeIfc.writeDataPipeOut.deq;
            ds = dut.ioChannelMemoryMasterPipeIfc.writePipeIfc.writeDataPipeOut.first;
        end

        metaA = unpack(pack(metaA) ^ pack(metaB));
        signalKeeperForDma.bitsPipeIn.enq(zeroExtend({pack(metaA), pack(ds)}));
    endrule

    rule injectReadData;
        let randData512 <- randSource3.get;
        dut.ioChannelMemoryMasterPipeIfc.readPipeIfc.readDataPipeIn.enq(unpack(truncate(randData512)));
    endrule

    rule genWriteReq;
        
        let randData512 <- randSource1.get;

        Length rdmaPayloadLen = truncate(randData512 >> 2);
        ADDR rdmaPayloadStartAddr = truncate(randData512 >> 12);

        let conReq = PayloadConReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen,
            baseVA: dontCareValue,    // since we use a fake addr translator in test.
            pgtOffset: dontCareValue  // since we use a fake addr translator in test.
        };
        dut.conReqPipeIn.enq(conReq);


        let genReq = PayloadGenReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen,
            baseVA: dontCareValue,    // since we use a fake addr translator in test.
            pgtOffset: dontCareValue  // since we use a fake addr tr
        };
        dut.genReqPipeIn.enq(genReq);

    endrule

    rule genWriteData;
        let randData512 <- randSource2.get;
        dut.payloadConStreamPipeIn.enq(unpack(truncate(randData512)));
    endrule

    rule getConResult;
        let writeFinishResp = dut.conRespPipeOut.first;
        dut.conRespPipeOut.deq;
        signalKeeperForCon.bitsPipeIn.enq(writeFinishResp);
    endrule

    rule getGenResult;
        let ds = dut.payloadGenStreamPipeOut.first;
        dut.payloadGenStreamPipeOut.deq;
        signalKeeperForGen.bitsPipeIn.enq(zeroExtend(pack(ds)));
    endrule

    rule gatherKeptSignals;
        outReg <= zeroExtend(pack(signalKeeperForCon.out)) ^ signalKeeperForGen.out ^ signalKeeperForDma.out;
    endrule

    method getOutput = outReg;
endmodule

