import ClientServer :: *;
import GetPut :: *;
import Vector :: *;

import PrimUtils :: *;
import Utils4Test :: *;

import ButterflyMerge :: *;
import SdpBramWrapper :: *;



function Tuple2#(Bit#(15), Bit#(128)) mergeFuncBitOr(Bit#(15) oldTag, Bit#(128) oldData, Bit#(15) newTag, Bit#(128) newData);
    if (oldTag == newTag) begin
        return tuple2(oldTag, oldData | newData);
    end 
    else begin
        return tuple2(newTag, newData);
    end
endfunction

(* doc = "testcase" *)
module mkTestFourChannelButterflyMergeCreateInstance(Empty);
    FourChannelButterflyMerge#(Bit#(5), Bit#(2), Bit#(128), Bit#(15), Bram72kEntry144) instWithFourBank <- mkFourChannelButterflyMerge(mergeFuncBitOr, mergeFuncBitOr);

    // The following instance has a bankAddr type of `Bit#(0)`, which is of zero size, make sure it works.
    FourChannelButterflyMerge#(Bit#(5), Bit#(0), Bit#(128), Bit#(15), Bram72kEntry144) instWithOneBank <- mkFourChannelButterflyMerge(mergeFuncBitOr, mergeFuncBitOr);

    rule exit;
        $finish;
    endrule
endmodule

(* doc = "testcase" *)
module mkTestFourChannelButterflyMergeSingleBeatTest(Empty);

    let stopCounter <- mkSimulationCycleLimitCounter(200);

    FourChannelButterflyMerge#(Bit#(5), Bit#(2), Bit#(128), Bit#(15), Bram72kEntry144) instWithFourBank <- mkFourChannelButterflyMerge(mergeFuncBitOr, mergeFuncBitOr);

    // The boundary case, every 2 beat comes a packet
    rule sendOneBeatReq if (stopCounter % 2 == 0);
        $display("$time=%0t, Enq req", $time);
        for (Integer idx = 0; idx < 4; idx = idx + 1) begin
            instWithFourBank.mergeSrvs[idx].request.put(ButterflyMergeReq{
                rowAddr: 0,
                bankAddr: 0,
                data: 1 << idx,
                tag: 0
            });
        end
    endrule

    for (Integer idx = 0; idx < 4; idx = idx + 1) begin
        rule displayResp;
            let resp <- instWithFourBank.mergeSrvs[idx].response.get;
            Bit#(128) expectedData = 'hF;
            immAssert(resp.data == expectedData, "Butterfly merge error, expected 'hF, got", fshow(resp));
        endrule
    end

endmodule



interface TestFourChannelButterflyMergeTimingTest;
    method Bit#(150) getOutput;
endinterface



(* doc = "testcase" *)
(* synthesize *)
module mkTestFourChannelButterflyMergeTimingTest(TestFourChannelButterflyMergeTimingTest);

    let stopCounter <- mkSimulationCycleLimitCounter(200);

    FourChannelButterflyMerge#(Bit#(5), Bit#(2), Bit#(128), Bit#(15), Bram72kEntry144) instWithFourBank <- mkFourChannelButterflyMerge(mergeFuncBitOr, mergeFuncBitOr);

    Vector#(4, Get#(Bit#(32))) randGenVec = newVector;
    randGenVec[0] <- mkSynthesizableRng32(11);
    randGenVec[1] <- mkSynthesizableRng32(13);
    randGenVec[2] <- mkSynthesizableRng32(17);
    randGenVec[3] <- mkSynthesizableRng32(19);

    Vector#(4, Reg#(Bit#(128))) inputDataRegVec <- replicateM(mkRegU);

    Reg#(Bit#(10)) tagCounterReg <- mkRegU;

    Reg#(Bit#(150)) outputReg <- mkRegU;

    // The boundary case, every 2 beat comes a packet
    rule sendOneBeatReq if (stopCounter % 2 == 0);
        $display("$time=%0t, Enq req", $time);
        tagCounterReg <= tagCounterReg + 1;

        // tag shouldn't change so fast, otherwise the bank will be evicted too fast. so, use a counter's higher bits as tag.
        let tag = zeroExtend(tagCounterReg[9:5]);

        for (Integer idx = 0; idx < 4; idx = idx + 1) begin

            let randVal <- randGenVec[idx].get;

            instWithFourBank.mergeSrvs[idx].request.put(ButterflyMergeReq{
                rowAddr: truncate(randVal),
                bankAddr: truncateLSB(randVal),
                data: inputDataRegVec[idx],
                tag: tag
            });
        end
    endrule

    
    rule outputResp;
        Bit#(150) xorResult = 0;
        for (Integer idx = 0; idx < 4; idx = idx + 1) begin
            let resp <- instWithFourBank.mergeSrvs[idx].response.get;
            xorResult = xorResult ^ pack(resp);
        end
        outputReg <= xorResult;
    endrule
    
    method getOutput = outputReg;
endmodule

