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

import AutoAckGenerator :: *;






interface TestAutoAckGeneratorTiming;
    method Bit#(32) getOutput;
endinterface

(* doc = "testcase" *)
module mkTestAutoAckGeneratorTiming(TestAutoAckGeneratorTiming);
 
    let dut <- mkAutoAckGenerator;

    ForceKeepWideSignals#(Bit#(512), Bit#(32)) signalKeeperForResp1 <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(512), Bit#(32)) signalKeeperForResp2 <- mkForceKeepWideSignals; 
    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);

    Reg#(Bit#(32)) outReg <- mkRegU;
    rule injectData;
        let rndData1 <- randSource1.get;
        let rndData2 <- randSource2.get;
        let rndData3 <- randSource3.get;
        let rndData4 <- randSource4.get;

        dut.reqPipeInVec[0].enq(unpack(truncate(rndData1)));
        dut.reqPipeInVec[1].enq(unpack(truncate(rndData2)));
        dut.reqPipeInVec[2].enq(unpack(truncate(rndData3)));
        dut.reqPipeInVec[3].enq(unpack(truncate(rndData4)));
        
        if (rndData1[20] == 1) begin
            dut.resetReqPipeIn.enq(unpack(truncate(rndData1[100: 10])));
        end
    endrule

    rule getResp;
        let resp1 = dut.respPipeOutVec[0].first;
        dut.respPipeOutVec[0].deq;
        let resp2 = dut.respPipeOutVec[1].first;
        dut.respPipeOutVec[1].deq;

        signalKeeperForResp1.bitsPipeIn.enq(zeroExtend(pack(resp1)));
        signalKeeperForResp2.bitsPipeIn.enq(zeroExtend(pack(resp2)));
    endrule

    rule getResetResp;
        dut.resetRespPipeOut.deq;
    endrule

    rule gatherKeptSignals;
        outReg <= signalKeeperForResp1.out ^ signalKeeperForResp2.out;
    endrule

    method getOutput = outReg;
endmodule