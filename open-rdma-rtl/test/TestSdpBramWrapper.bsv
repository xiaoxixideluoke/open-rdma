import GetPut :: *;
import ClientServer :: *;
import FIFOF :: *;

import PrimUtils :: *;
import Utils4Test :: *;

import SdpBramWrapper :: *;
import Randomizable :: * ;

interface TestSdpBramWrapperTimingTest;
    method Bit#(144) _read;
endinterface

// (*synthesize*)
// module mkTestSdpBramWrapperTimingTest(TestSdpBramWrapperTimingTest);
//     SdpBram#(Bit#(9), Bit#(144)) bram <- mkSdpBram;

//     Reg#(Bit#(9)) addrReg <- mkReg(0);
//     Reg#(Bit#(144)) dataReg <- mkReg(0);
//     Reg#(Bit#(144)) outReg <- mkReg(0);

//     rule testWriteAndReadReq;
//         addrReg <= addrReg + 1;
//         dataReg <= dataReg + 1;
//         let x = truncate(dataReg) | addrReg;
//         if (lsb(addrReg) == 1) begin
//             bram.write.put(tuple2(x, dataReg));
//             bram.readSrv.request.put(x);
//         end 
//     endrule

//     rule testReadResp;
//         let resp <- bram.readSrv.response.get;
//         outReg <= resp;
//     endrule

//     method _read = outReg;
// endmodule

interface TestSdpBramWrapperConflictReadWriteTest;
    (* always_ready *)
    method Bit#(145) lastError;

    (* always_ready *)
    method Bit#(145) readResp;

    (* always_ready *)
    method Bit#(24) zeroErrorCnt;

    (* always_ready *)
    method Bit#(24) oneErrorCnt;

    (* always_ready *)
    method Bool keepConstRuleFired;

    (* always_ready *)
    method AcxBram72kAddr ra;

    (* always_ready *)
    method AcxBram72kAddr wa;

endinterface

(*synthesize*)
module mkTestSdpBramWrapperConflictReadWriteTest(TestSdpBramWrapperConflictReadWriteTest);

    // For this test, the write address is linear increase, while read address is a random value.
    // so, in the same cycle, there maybe chance that two port read and write the same address.
    // The write value is controlled by the msb of a 11-bit counter, the lower 10 bits is used as address.
    // So, the underlying BRAM will be flashed to all 0s, and then all 1s, then all 0s, and repeat forever.
    // This makes the content in the BRAM predictable, making the checker works easier.

    SdpBram#(Bit#(144)) bram <- mkSdpBram;

    Reg#(Bit#(10)) addrWriteReg <- mkReg(0);
    let addrReadRng <- mkSynthesizableRng32(11);

    FIFOF#(Tuple3#(Bool, AcxBram72kAddr, AcxBram72kAddr)) checkerExpectedResultQ <- mkSizedFIFOF(8);
    Reg#(Bit#(24)) readZeroErrorCntReg <- mkReg(0);
    Reg#(Bit#(24)) readOneErrorCntReg <- mkReg(0);

    Reg#(Bit#(145)) lastErrorReg <- mkReg(0);

    Reg#(Bool) errorOccuredReg <- mkReg(False); 

    Reg#(Bit#(64)) exitCounterReg <- mkReg(0);
    
    let exitThreshold = genVerilog ? -1 : 2048; 

    Reg#(Bit#(144)) constZeroReg <- mkReg('haaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa);
    Reg#(Bit#(144)) constOneReg <- mkReg('h555555555555555555555555555555555555);

    Reg#(Bit#(145)) readRespReg <- mkReg(0);
    
    FIFOF#(Tuple6#(Bool, Bool, Bool, Bit#(144), AcxBram72kAddr, AcxBram72kAddr)) resultCheckQ1 <- mkFIFOF;
    FIFOF#(Tuple6#(Bool, Bool, Bool, Bit#(144), AcxBram72kAddr, AcxBram72kAddr)) resultCheckQ2 <- mkFIFOF;
    FIFOF#(Tuple6#(Bool, Bool, Bool, Bit#(144), AcxBram72kAddr, AcxBram72kAddr)) resultCheckQ3 <- mkFIFOF;
    Reg#(Bool) keepConstRuleFiredReg <- mkReg(False);

    Reg#(AcxBram72kAddr) raReg <- mkRegU;
    Reg#(AcxBram72kAddr) waReg <- mkRegU;


    // use a non constant Reg to trick the backend tool to not optmise those 144 signals into 2 signal.
    rule keepCosnstReg if (msb(exitCounterReg) == 1);
        constZeroReg <= constZeroReg << 1;
        constOneReg <= constOneReg << 1;
        keepConstRuleFiredReg <= True;
        exitCounterReg <= exitCounterReg + 1;
    endrule
    
    rule testWriteAndReadReq;
        addrWriteReg <= addrWriteReg + 1;
        Bit#(9) writeAddr = truncate(addrWriteReg);
        let rawAddrRead <- addrReadRng.get;
        Bit#(9) readAddr = truncate(rawAddrRead);
        Bool writeOne = msb(addrWriteReg) == 1;

        AcxBram72kAddr ra = zeroExtend(readAddr);
        AcxBram72kAddr wa = zeroExtend(writeAddr);
        
        bram.write.put(tuple2(wa, writeOne ? constOneReg : constZeroReg));
        bram.readSrv.request.put(ra);
        // $display("read req @ %0t", $time);

        Bool expectedOne = ?;
        if (readAddr > writeAddr) begin
            // then the content in the BRAM should be different from the current write value
            expectedOne = !writeOne;
        end
        else begin
            // the content in the BRAM should be the updated value
            expectedOne = writeOne;
        end
        checkerExpectedResultQ.enq(tuple3(expectedOne, wa, ra));
    endrule

    rule testReadRespStep1 if (msb(exitCounterReg) != 1);
        // $display("read resp @ %0t", $time);
        Bit#(144) resp <- bram.readSrv.response.get;
        let {expectedOne, wa, ra} = checkerExpectedResultQ.first;
        checkerExpectedResultQ.deq;

        readRespReg <= {pack(expectedOne), resp};

        
        let expectOneNotMatch = resp[47:0] != constOneReg[47:0];
        let expectZeroNotMatch = resp[47:0] != constZeroReg[47:0];
        resultCheckQ1.enq(tuple6(expectedOne, expectOneNotMatch, expectZeroNotMatch, resp, wa, ra));
    endrule

    rule testReadRespStep2 if (msb(exitCounterReg) != 1);
        let {expectedOne, expectOneNotMatch, expectZeroNotMatch, resp, wa, ra} = resultCheckQ1.first;
        resultCheckQ1.deq;
        
        expectOneNotMatch = (resp[95:48] != constOneReg[95:48]) || expectOneNotMatch;
        expectZeroNotMatch = (resp[95:48] != constZeroReg[95:48]) || expectZeroNotMatch;
        resultCheckQ2.enq(tuple6(expectedOne, expectOneNotMatch, expectZeroNotMatch, resp, wa, ra));
    endrule

    rule testReadRespStep3 if (msb(exitCounterReg) != 1);
        let {expectedOne, expectOneNotMatch, expectZeroNotMatch, resp, wa, ra} = resultCheckQ2.first;
        resultCheckQ2.deq;
        
        expectOneNotMatch = (resp[143:96] != constOneReg[143:96]) || expectOneNotMatch;
        expectZeroNotMatch = (resp[143:96] != constZeroReg[143:96]) || expectZeroNotMatch;
        resultCheckQ3.enq(tuple6(expectedOne, expectOneNotMatch, expectZeroNotMatch, resp, wa, ra));
    endrule

    rule testReadRespStep4 if (msb(exitCounterReg) != 1);

        let {expectedOne, expectOneNotMatch, expectZeroNotMatch, resp, wa, ra} = resultCheckQ3.first;
        resultCheckQ3.deq;

        // The content of the BRAM is random in first 512 beat.
        if (exitCounterReg >= 512) begin
            if (expectedOne && expectOneNotMatch) begin
                readOneErrorCntReg <= readOneErrorCntReg + 1;
                lastErrorReg <= {pack(expectedOne), resp};
                raReg <= ra;
                waReg <= wa;
                errorOccuredReg <= True;
                $display("time=%t", $time, toRed("Error, expect all ones"));
            end 
            else if (!expectedOne && expectZeroNotMatch) begin
                readZeroErrorCntReg <= readZeroErrorCntReg + 1;
                lastErrorReg <= {pack(expectedOne), resp};
                raReg <= ra;
                waReg <= wa;
                errorOccuredReg <= True;
                $display("time=%t", $time, toRed("Error, expect all zeros"));
            end
        end

        exitCounterReg <= exitCounterReg + 1;
    endrule

    if (genC) begin
        rule checkSimEnd;    
            if (exitCounterReg == fromInteger(exitThreshold)) begin
                if (errorOccuredReg) begin
                    immFail("mkTestSdpBramWrapperConflictReadWriteTest", $format(""));
                end
                else begin
                    $display("Pass");
                    $finish;
                end
            end
        endrule
    end

    method lastError = lastErrorReg;

    method zeroErrorCnt = readZeroErrorCntReg;

    method oneErrorCnt = readOneErrorCntReg;

    method readResp = readRespReg;

    method keepConstRuleFired = keepConstRuleFiredReg;

    method ra = raReg;

    method wa = waReg;
endmodule






















































interface TestAcxBram72kSdpConflictRW;
    (* always_ready *)
    method Bit#(145) lastError;

    (* always_ready *)
    method Bit#(145) readResp;

    (* always_ready *)
    method Bit#(32) zeroErrorCnt;

    (* always_ready *)
    method Bit#(32) oneErrorCnt;

    (* always_ready *)
    method Bit#(32) correctCnt;

    (* always_ready *)
    method AcxBram72kAddr ra;
        
    (* always_ready *)
    method Bool errorOccured;


endinterface

(*synthesize*)
(* doc = "testcase" *)
module mkTestAcxBram72kSdpConflictRW(TestAcxBram72kSdpConflictRW);


    BRAM72K_SDP#(Bit#(144)) bram <- mkBRAM72K_SDP;

    Reg#(Bit#(144)) constZeroReg <- mkRegU;
    Reg#(Bit#(144)) constOneReg <- mkRegU;

    Reg#(Bit#(10)) addrWriteReg <- mkReg(0);
    Reg#(Bit#(10)) addrReadReg <- mkReg(0);

    Reg#(AcxBram72kAddr) raDelayReg1 <- mkRegU;
    Reg#(AcxBram72kAddr) raDelayReg2 <- mkRegU;

    Reg#(Bit#(32)) readZeroErrorCntReg <- mkReg(0);
    Reg#(Bit#(32)) readOneErrorCntReg <- mkReg(0);
    Reg#(Bit#(32)) correctCntReg <- mkReg(0);



    Reg#(Bit#(145)) lastErrorReg <- mkReg(0);
    Reg#(Bool) errorOccuredReg <- mkReg(False); 
    Reg#(Bit#(32)) exitCounterReg <- mkReg(0);
    

    Reg#(Bit#(145)) readRespReg <- mkReg(0);
    
    FIFOF#(Tuple4#(Bool, Bool, Bit#(144), AcxBram72kAddr)) resultCheckQ1 <- mkFIFOF;
    FIFOF#(Tuple4#(Bool, Bool, Bit#(144), AcxBram72kAddr)) resultCheckQ2 <- mkFIFOF;
    FIFOF#(Tuple4#(Bool, Bool, Bit#(144), AcxBram72kAddr)) resultCheckQ3 <- mkFIFOF;

    Reg#(AcxBram72kAddr) raReg <- mkRegU;


    // use a non constant Reg to trick the backend tool to not optmise those 144 signals into 2 signal.
    rule genConstRegValue;
        constZeroReg <= constZeroReg << 1;
        constOneReg <= (constOneReg << 1) | 'h1;
        exitCounterReg <= exitCounterReg + 1;
    endrule
    
    rule genBramContent if (exitCounterReg < 1024);
        addrWriteReg <= addrWriteReg + 1;
        Bit#(9) writeAddr = truncate(addrWriteReg);
        AcxBram72kAddr wa = zeroExtend(writeAddr) << 5;
       
        bram.putWriteReq(wa, lsb(writeAddr) == 1 ? constOneReg : constZeroReg);
        // bram.putWriteReq(wa, zeroExtend(wa));
    endrule

    rule genReadReq if (exitCounterReg >= 1024 );
        addrReadReg <= addrReadReg + 1;
        Bit#(9) readAddr = truncate(addrReadReg);
        AcxBram72kAddr ra = zeroExtend(readAddr);
        bram.putReadReq(ra << 5);
        raDelayReg1 <= ra;
        raDelayReg2 <= raDelayReg1;
    endrule

    rule testReadRespStep1 if (exitCounterReg >= 2048);
        
        Bit#(144) resp = bram.read;
        let ra = raDelayReg2;
        readRespReg <= {pack(lsb(ra) == 1), resp};
        // raReg <= ra;
                
        let expectOneNotMatch = resp[47:0] != constOneReg[47:0];
        let expectZeroNotMatch = resp[47:0] != constZeroReg[47:0];
        resultCheckQ1.enq(tuple4(expectOneNotMatch, expectZeroNotMatch, resp, ra));
    endrule

    rule testReadRespStep2;
        let {expectOneNotMatch, expectZeroNotMatch, resp, ra} = resultCheckQ1.first;
        resultCheckQ1.deq;
        
        expectOneNotMatch = (resp[95:48] != constOneReg[95:48]) || expectOneNotMatch;
        expectZeroNotMatch = (resp[95:48] != constZeroReg[95:48]) || expectZeroNotMatch;
        resultCheckQ2.enq(tuple4(expectOneNotMatch, expectZeroNotMatch, resp, ra));
    endrule

    rule testReadRespStep3;
        let {expectOneNotMatch, expectZeroNotMatch, resp, ra} = resultCheckQ2.first;
        resultCheckQ2.deq;
        
        expectOneNotMatch = (resp[143:96] != constOneReg[143:96]) || expectOneNotMatch;
        expectZeroNotMatch = (resp[143:96] != constZeroReg[143:96]) || expectZeroNotMatch;
        resultCheckQ3.enq(tuple4(expectOneNotMatch, expectZeroNotMatch, resp, ra));
    endrule

    rule testReadRespStep4;

        let {expectOneNotMatch, expectZeroNotMatch, resp, ra} = resultCheckQ3.first;
        resultCheckQ3.deq;


        if ((lsb(ra) == 1) && expectOneNotMatch) begin
            readOneErrorCntReg <= readOneErrorCntReg + 1;
            lastErrorReg <= {pack(lsb(ra) == 1), resp};
            raReg <= ra;
            errorOccuredReg <= !errorOccuredReg;
            $display("time=%t", $time, toRed("Error, expect all ones"));
        end 
        else if ((lsb(ra) == 0) && expectZeroNotMatch) begin
            readZeroErrorCntReg <= readZeroErrorCntReg + 1;
            lastErrorReg <= {pack(lsb(ra) == 1), resp};
            raReg <= ra;
            errorOccuredReg <= !errorOccuredReg;
            $display("time=%t", $time, toRed("Error, expect all zeros"));
        end
        else begin
            correctCntReg <= correctCntReg + 1;
        end

    endrule

    method lastError = lastErrorReg;
    method zeroErrorCnt = readZeroErrorCntReg;
    method oneErrorCnt = readOneErrorCntReg;
    method correctCnt = correctCntReg;
    method readResp = readRespReg;
    method ra = raReg;
    method errorOccured = errorOccuredReg;
endmodule