import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 

import PrimUtils :: *;
import RdmaUtils :: *;
import Utils4Test :: *;
import EthernetTypes :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;
import StreamShifterG :: *;


typedef enum {
    TestBiDirectionStreamShifterStateGenInput = 0,
    TestBiDirectionStreamShifterStateForwardShift = 1,
    TestBiDirectionStreamShifterStateBackwardShift = 2,
    TestBiDirectionStreamShifterStateChecck = 3
} TestBiDirectionStreamShifterState deriving(Bits, Eq);


typedef DtldStreamData#(DATA) DataStreamForTest;
(* doc = "testcase" *)
module mkTestBiDirectionStreamShifterG(Empty);
    let inputBeatCountRandomGenPipeOut <- mkRandomLenPipeOut(0, 2);
    PipeOut#(DATA) inputBeatDataRandomGenPipeOut <- mkGenericRandomPipeOut;
    let inputBeatLengthRandomGenPipeOut <- mkRandomLenPipeOut(1, 32);
    let startByteIdxRandomGenPipeOut <- mkRandomLenPipeOut(0, 31);
    let forwardShiftOffsetRandomGenPipeOut <- mkRandomLenPipeOut(0, 63); // 6 bits signed number

    Reg#(Length) inputBeatGenBeatCounterReg <- mkReg(0);
    Reg#(Bool) inputBeatGenIsFirstBeatReg <- mkReg(True);

    FIFOF#(DataStreamForTest) checkerExpectedResultQ <- mkSizedFIFOF(10);
    FIFOF#(DataStreamForTest) dutInputQ <- mkSizedFIFOF(10);
    FIFOF#(DataStreamForTest) forwardToBackwardQ <- mkSizedFIFOF(10);

    StreamShifterG#(DATA) forwardShifter <- mkBiDirectionStreamShifterLsbRightG;
    StreamShifterG#(DATA) backwardShifter <- mkBiDirectionStreamShifterLsbRightG;


    Reg#(TestBiDirectionStreamShifterState) stateReg <- mkReg(TestBiDirectionStreamShifterStateGenInput);
    Reg#(Bit#(32)) exitCounterReg <- mkReg(10000000);

    rule genRandomInputStream if (stateReg == TestBiDirectionStreamShifterStateGenInput);
        let isFirst = inputBeatGenIsFirstBeatReg;
        let isLast = inputBeatGenBeatCounterReg == 0;

        let generateBeatAcceptable = False;

        let data = inputBeatDataRandomGenPipeOut.first;
        inputBeatDataRandomGenPipeOut.deq;

        Length byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        BusByteIdx startByteIdx = 0;
        if (isFirst || isLast) begin
            byteNum = inputBeatLengthRandomGenPipeOut.first;
            inputBeatLengthRandomGenPipeOut.deq;
            if (isFirst && isLast) begin
                startByteIdx = truncate(startByteIdxRandomGenPipeOut.first);
                startByteIdxRandomGenPipeOut.deq;
                if (zeroExtend(startByteIdx) + byteNum <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH))) begin
                    data = data >> (fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - byteNum - zeroExtend(startByteIdx)) * 8;
                    // clear lower bytes to zero to match startByteIdx;
                    Length tmpShiftCnt = zeroExtend(startByteIdx) * 8;
                    data = data >> tmpShiftCnt;
                    data = data << tmpShiftCnt; 
                    generateBeatAcceptable = True;
                end
            end
            else if (isFirst) begin
                data = data << (fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - byteNum) * 8;
                startByteIdx = truncate(fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - byteNum);
                generateBeatAcceptable = True;
            end
            else if (isLast) begin
                data = data >> (fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - byteNum) * 8;
                generateBeatAcceptable = True;
            end
        end
        else begin
            generateBeatAcceptable = True;
        end

        if (generateBeatAcceptable) begin
            if (isLast) begin
                inputBeatGenBeatCounterReg <= inputBeatCountRandomGenPipeOut.first;
                inputBeatCountRandomGenPipeOut.deq;
                inputBeatGenIsFirstBeatReg <= True;
            end 
            else begin
                inputBeatGenBeatCounterReg <= inputBeatGenBeatCounterReg - 1;
                inputBeatGenIsFirstBeatReg <= False;
            end

            DataStreamForTest ds = DataStreamForTest{
                data: data,
                byteNum: truncate(byteNum),
                startByteIdx: startByteIdx,
                isFirst: isFirst,
                isLast: isLast
            };
            checkerExpectedResultQ.enq(ds);
            dutInputQ.enq(ds);
            // $display(
            //     "time=%0t: ", $time, toGreen("genRandomInputStream"),
            //     toBlue(", ds="), fshow(ds)
            // );

            if (isLast) begin
                // $display("=====gen data finished=======");
                stateReg <= TestBiDirectionStreamShifterStateForwardShift;
            end
        end
    endrule

    rule doForwardShift if (stateReg == TestBiDirectionStreamShifterStateForwardShift);
        if (dutInputQ.notEmpty) begin
            let ds = dutInputQ.first;
            if (ds.isFirst) begin
                DataBusSignedByteShiftOffset offset = truncate(forwardShiftOffsetRandomGenPipeOut.first);
                forwardShiftOffsetRandomGenPipeOut.deq;
                let absOffset = getAbsValue(offset); 
                Bool offsetAcceptable = False;
                if (msb(offset) == 0) begin
                    // this is a positive number, means shift right.
                    Length maxAvailableShiftNum = zeroExtend(ds.startByteIdx);
                    offsetAcceptable = maxAvailableShiftNum >= zeroExtend(absOffset);

                    // $display("right shift maxAvailableShiftNum=", fshow(maxAvailableShiftNum), ", offset=", fshow(offset), ", absOffset=", fshow(absOffset), ", offsetAcceptable=", fshow(offsetAcceptable));
                end
                else begin
                    // this is a negative number, means shift left.
                    Length maxAvailableShiftNum =  fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - zeroExtend(ds.startByteIdx) - 1;
                    // can not shift "negative zero", only "postive zero" can be handled by right shifter
                    offsetAcceptable = maxAvailableShiftNum >= zeroExtend(absOffset) && absOffset != 0;
                    // $display("left shift maxAvailableShiftNum=", fshow(maxAvailableShiftNum), ", offset=", fshow(offset), ", absOffset=", fshow(absOffset), ", offsetAcceptable=", fshow(offsetAcceptable));
                end

                if (offsetAcceptable) begin
                    // we have found an legal offset to shift;
                    dutInputQ.deq;
                    forwardShifter.offsetPipeIn.enq(offset);
                    forwardShifter.streamPipeIn.enq(ds);
                    backwardShifter.offsetPipeIn.enq(-offset);
                    // $display(
                    //     "time=%0t: ", $time, toGreen("doForwardShift"),
                    //     toBlue(", offset="), fshow(offset)
                    // );
                end
            end
            else begin
                dutInputQ.deq;
                forwardShifter.streamPipeIn.enq(ds);
            end
        end
        if (forwardShifter.streamPipeOut.notEmpty) begin
            forwardToBackwardQ.enq(forwardShifter.streamPipeOut.first);
            forwardShifter.streamPipeOut.deq;
            if (forwardShifter.streamPipeOut.first.isLast) begin
                // $display("=====forward shift finished=======");
                stateReg <= TestBiDirectionStreamShifterStateBackwardShift;
            end
        end
    endrule

    rule doBackwardShift if (stateReg == TestBiDirectionStreamShifterStateBackwardShift);
        if (forwardToBackwardQ.notEmpty) begin
            let ds = forwardToBackwardQ.first;
            forwardToBackwardQ.deq;
            backwardShifter.streamPipeIn.enq(ds);
        end

        if (backwardShifter.streamPipeOut.notEmpty) begin
            let got = backwardShifter.streamPipeOut.first;
            backwardShifter.streamPipeOut.deq;
            let expected = checkerExpectedResultQ.first;
            checkerExpectedResultQ.deq;
            immAssert(
                expected == got,
                "expected != got,",
                $format("expected=", fshow(expected), "got=", fshow(got))
            );
            
            if (got.isLast) begin
                // $display("============= pass =============");
                stateReg <= TestBiDirectionStreamShifterStateGenInput;
                exitCounterReg <= exitCounterReg - 1;
                if (exitCounterReg == 0) begin
                    $display("Pass");
                    $finish;
                end 
                if (exitCounterReg % 100000 == 0) begin
                    $display("exitCounterReg = %d", exitCounterReg);
                end
            end
        end
    endrule
endmodule