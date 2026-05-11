import Connectable :: *;
import GetPut :: *;
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

import PsnContinousChecker :: *;





(* doc = "testcase" *)
module mkTestCocotbPsnPerMergeAndStorage(PsnPerMergeAndStorage);
    let dut <- mkPsnPerMergeAndStorage;
    return dut;
endmodule




interface TestBitmapWindowStorageTiming;
    method Bit#(32) getOutput;
endinterface

(* doc = "testcase" *)
module mkTestBitmapWindowStorageTiming(TestBitmapWindowStorageTiming);
 
    BitmapWindowStorage#(IndexQP, AckBitmap, PsnMergeWindowBoundary, ACK_WINDOW_STRIDE) dut <- mkBitmapWindowStorage;

    ForceKeepWideSignals#(Maybe#(BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary)), Bit#(32)) signalKeeperForResp1 <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Maybe#(BitmapWindowStorageUpdateResp#(IndexQP, AckBitmap, PsnMergeWindowBoundary)), Bit#(32)) signalKeeperForResp2 <- mkForceKeepWideSignals; 
    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);

    Reg#(Bit#(32)) outReg <- mkRegU;
    rule injectData;
        let rndData <- randSource1.get;
        dut.reqPipeInVec[0].enq(unpack(truncate(rndData)));
        dut.reqPipeInVec[1].enq(unpack(truncate(rndData[511:256])));
        if (rndData[20] == 1) begin
            dut.resetReqPipeIn.enq(unpack(truncate(rndData[100: 10])));
        end
    endrule

    rule getResp;
        let resp1 = dut.respPipeOutVec[0].first;
        dut.respPipeOutVec[0].deq;
        let resp2 = dut.respPipeOutVec[1].first;
        dut.respPipeOutVec[1].deq;

        signalKeeperForResp1.bitsPipeIn.enq(resp1);
        signalKeeperForResp2.bitsPipeIn.enq(resp2);
    endrule

    rule getResetResp;
        dut.resetRespPipeOut.deq;
    endrule

    rule gatherKeptSignals;
        outReg <= signalKeeperForResp1.out ^ signalKeeperForResp2.out;
    endrule

    method getOutput = outReg;
endmodule