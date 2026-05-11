import PrimUtils :: *;
import Vector :: *;
import PAClib :: *;
import ClientServer :: *;
import GetPut :: *;

import Utils4Test :: *;
import BluerdmaConsts :: *;
import FullyPipelinedUpdateBram :: *;
import RdmaHeaders :: *;


function Tuple2#(Bit#(144), Bool) mergeFuncBitOr(Bit#(144) oldData, Bit#(144) newData);
    let oldTag = oldData[15:0];
    let newTag = newData[15:0];
    if (oldTag == newTag) begin
        return tuple2({oldData[143:16] | newData[143:16], oldTag}, False);
    end 
    else begin
        return tuple2({newData[143:16], newTag}, True);
    end
endfunction


function Tuple2#(Bit#(144), Bool) mergeFuncIncCounter(Bit#(144) oldData, Bit#(144) newData);
    let oldTag = oldData[15:0];
    let newTag = newData[15:0];
    if (oldTag == newTag) begin
        let data = oldData[143:16];
        data = data + 1;
        return tuple2({data, oldTag}, False);
    end 
    else begin
        return tuple2({1, newTag}, True);
    end
endfunction

function Tuple2#(Bit#(144), Bool) mergeFuncIncCounterForFunctionalTest(Bit#(144) oldData, Bit#(144) newData);
    let oldTag = oldData[15:0];
    let newTag = newData[15:0];
    if (oldTag == newTag) begin
        let data = oldData[47:16];
        data = data + 1;
        return tuple2({0, data, oldTag}, False);
    end 
    else begin
        return tuple2({1, newTag}, True);
    end
endfunction


function Tuple2#(Bit#(144), Bool) mergeFuncShiftAndBitOr(Bit#(144) oldData, Bit#(144) newData);
    let oldTag = oldData[20:0];
    let newTag = newData[20:0];
    let delta = oldTag - newTag;
    if (delta < 'hFF) begin
        Bit#(3) offset = truncate(delta);
        Bit#(7) offsetExt = zeroExtend(offset);
        let outData = oldData << (offsetExt << 4);
        outData[127:0] = outData[127:0] | newData[127:0];
        return tuple2(outData, False);
    end
    else if (delta > 'h100000) begin
        return tuple2(oldData, True);
    end
    else begin
        return tuple2(newData, False);
    end


endfunction

(* doc = "testcase" *)
module mkTestFullyPipelinedUpdateBram(Empty);
    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(2), Bit#(144)) instWithFourBank <- mkFullyPipelinedUpdateBram2(False, mergeFuncIncCounter);

    // The following instance has a bankAddr type of `Bit#(0)`, which is of zero size, make sure it works.
    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(0), Bit#(144)) instWithOneBank <- mkFullyPipelinedUpdateBram2(True, mergeFuncBitOr);

    Reg#(Long) cycleCounterReg <- mkReg(0);
    Reg#(Long) cycleCounterStopReg <- mkReg(10000000);

    Reg#(Long) lastEnqCycleReg <- mkReg(-1);

    Vector#(1, PipeOut#(Bit#(7))) oneHotRandomGen <-
        mkRandomValueInRangePipeOut(0, 127);

    Vector#(4, Reg#(Long)) expectedCounterVec <- replicateM(mkReg(0));

    rule incCounter;
        cycleCounterReg <= cycleCounterReg + 1;
        if (cycleCounterReg % 100000 == 0) begin
            $display(cycleCounterStopReg - cycleCounterReg);
        end
    endrule

    rule checkFullyPipeline if (cycleCounterReg > 1 && cycleCounterReg <= cycleCounterStopReg - 3); // random generator need one cycle to start.
        immAssert(
            cycleCounterReg - lastEnqCycleReg <= 1,
            "mkTestFullyPipelinedUpdateBram Error",
            $format("pipeline paused, cycleCounterReg=%d, lastEnqCycleReg=%d", cycleCounterReg, lastEnqCycleReg)
        );
    endrule

    rule testEnq if (cycleCounterReg <= cycleCounterStopReg - 3);
        lastEnqCycleReg <= cycleCounterReg;

        Bit#(2) bankAddr = truncate(oneHotRandomGen[0].first);
        oneHotRandomGen[0].deq;

        expectedCounterVec[bankAddr] <= expectedCounterVec[bankAddr] + 1;


        instWithOneBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: True,
                address:      0,
                bankAddress:  0,
                data:       {0, 16'h0}
            }
        );
        instWithFourBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: True,
                address:      0,
                bankAddress:  bankAddr,
                data:       {0, 14'h0, bankAddr}
            }
        );

    endrule

    rule fetchUpdateResp;

        let resp1 <- instWithOneBank.updateSrv.response.get;
        let resp2 <- instWithFourBank.updateSrv.response.get;

        if (cycleCounterReg == cycleCounterStopReg) begin

            Long expected = expectedCounterVec[resp2.bankAddress];
            Long got = truncate(resp2.data[143:16]);
            if ( expected == got) begin
                $display("PASS");
                $finish;
            end
            else begin
                let now <- $time;
                immFail(
                    "mkTestFullyPipelinedUpdateBram Failed", 
                    $format("time=%0t", now, ", got=", fshow(got), ", expected=", fshow(expected), ", resp2=", fshow(resp2))
                );
            end
        end
    endrule
endmodule




interface TestFullyPipelinedBackendTimingTest;
    method Bit#(155) _read;
endinterface

(*synthesize*)
module mkTestFullyPipelinedBackendTimingTest(TestFullyPipelinedBackendTimingTest);

    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(2), Bit#(144)) instWithFourBank <- mkFullyPipelinedUpdateBram2(False, mergeFuncShiftAndBitOr);

    // The following instance has a bankAddr type of `Bit#(0)`, which is of zero size, make sure it works.
    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(0), Bit#(144)) instWithOneBank <- mkFullyPipelinedUpdateBram2(False, mergeFuncShiftAndBitOr);

    Reg#(Bit#(9)) addrReg1 <- mkReg(0);

    Reg#(Bit#(144)) bitmapInputReg <- mkReg(123);
    Reg#(Bit#(155)) outputReg <- mkReg(0);


    rule testEnq;
        bitmapInputReg <= rotateBitsBy(bitmapInputReg, 2) ^ bitmapInputReg;
        let bankAddr = truncate(addrReg1);

        instWithOneBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: lsb(addrReg1) == 0,
                address:      addrReg1,
                bankAddress:  0,
                data:       bitmapInputReg
            }
        );
        instWithFourBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: lsb(addrReg1) == 0,
                address:      addrReg1,
                bankAddress:  bankAddr,
                data:       bitmapInputReg
            }
        );
        addrReg1 <= addrReg1 + 1;
    endrule

    rule fetchUpdateResp;
        let resp1 <- instWithOneBank.updateSrv.response.get;
        let resp2 <- instWithFourBank.updateSrv.response.get;
        outputReg <=  truncate(pack(resp1)) ^ truncate(pack(resp2));
    endrule

    method _read = outputReg;
endmodule



interface TestFullyPipelinedUpdateBramFunctionalTest;
    method Bool getSuccess;
    method Bool getFinished;
endinterface


(* doc = "testcase" *)
module mkTestFullyPipelinedUpdateBramFunctionalTest(TestFullyPipelinedUpdateBramFunctionalTest);
    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(2), Bit#(144)) instWithFourBank <- mkFullyPipelinedUpdateBram2(False, mergeFuncIncCounterForFunctionalTest);

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);

    Reg#(Length) cycleCounterReg <- mkReg(0);
    Reg#(Length) cycleCounterStopReg <- mkReg(10000000);

    Vector#(4, Reg#(Length)) expectedCounterVec <- replicateM(mkReg(0));

    Reg#(Bool) finishedReg <- mkReg(False);
    Reg#(Bool) successReg <- mkReg(False);



    rule incCounter;
        cycleCounterReg <= cycleCounterReg + 1;
    endrule


    rule testEnq if (cycleCounterReg <= cycleCounterStopReg - 3);

        let randValue1 <- randSource1.get;

        Bit#(2) bankAddr = truncate(randValue1);

        expectedCounterVec[bankAddr] <= expectedCounterVec[bankAddr] + 1;

        instWithFourBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: True,
                address:      0,
                bankAddress:  bankAddr,
                data:       {0, 14'h0, bankAddr}
            }
        );

    endrule

    rule fetchUpdateResp;

        let resp2 <- instWithFourBank.updateSrv.response.get;

        if (cycleCounterReg == cycleCounterStopReg) begin
            finishedReg <= True;
            Length expected = expectedCounterVec[resp2.bankAddress];
            Length got = truncate(resp2.data[143:16]);
            if ( expected == got) begin
                successReg <= True;
            end
        end
    endrule

    method getSuccess = successReg;
    method getFinished = finishedReg;
endmodule