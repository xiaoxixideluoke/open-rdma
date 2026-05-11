import Vector :: *;
import FIFOF :: *;
import GetPut :: *;

import StmtFSM :: * ;

import PrimUtils :: *;
import Utils4Test :: *;
import EthernetFrameIO :: *;

import NapWrapper :: *;

interface TestEthernetNapLoopBack;
    method Bit#(16) recvPacketCnt;
    method Bit#(5) getStateReg;
    method Action run;
endinterface

typedef 4 ETH_NAP_COUNT;

typedef struct {
    Bit#(2) channelIdx;
    Bit#(32) data;
} EthFrame deriving(Bits);



(*synthesize*)
(* doc = "testcase" *)
module mkTestEthernetNapLoopBack(TestEthernetNapLoopBack);

    Vector#(ETH_NAP_COUNT, AcxNapEthernetWrapper) ethNapVec = newVector;

    Vector#(ETH_NAP_COUNT, FIFOF#(VerticalNapBeatEntry)) inflightBeatVec <- replicateM(mkSizedFIFOF(10));
    Vector#(ETH_NAP_COUNT, FIFOF#(VerticalNapBeatEntry)) recvBeatVec <- replicateM(mkFIFOF);

    Vector#(ETH_NAP_COUNT, Reg#(Bool)) nextIsFirstRegVec <- replicateM(mkRegU);
    Vector#(ETH_NAP_COUNT, Reg#(Bit#(3))) lengthCounterRegVec <- replicateM(mkRegU);

    Vector#(4, Get#(Bit#(32))) randGenVec = newVector;
    randGenVec[0] <- mkSynthesizableRng32(11);
    randGenVec[1] <- mkSynthesizableRng32(13);
    randGenVec[2] <- mkSynthesizableRng32(17);
    randGenVec[3] <- mkSynthesizableRng32(19);

    Reg#(Bool) loopbackSetReg <- mkReg(False);

    AcxNapSlaveWrapper napSlave <- mkAcxNapSlaveWrapper;

    Reg#(AxiMmNapBeatR) controlRegValReg <- mkRegU;

    Reg#(Bit#(5)) stateReg <- mkReg(0);
    

    Stmt driversMonitors =
    (seq
        // stateReg <= 1;
        // napSlave.sendReadAddr(AxiMmNapBeatAr{
        //     arid:0, 
        //     araddr: 'h081B1000000,
        //     arlen: 0,
        //     arsize: pack(NapAxiSize4B),
        //     arburst: pack(NapAxiBurstFixed),
        //     arlock: False,
        //     arqos: 0
        // });
        // stateReg <= 2;
        // action
        //     AxiMmNapBeatR readResult <- napSlave.recvReadResp;
        //     readResult.rdata = readResult.rdata | 'h4000;
        //     controlRegValReg <= readResult;
        // endaction
        stateReg <= 3;

        napSlave.sendWriteAddr(AxiMmNapBeatAw{
            awid: 0,
            awaddr: 'h081B1000000,
            awlen: 0,
            awsize: pack(NapAxiSize4B),
            awburst: pack(NapAxiBurstFixed),
            awlock: False,
            awqos: 0
        });
        stateReg <= 4;

        napSlave.sendWriteData(AxiMmNapBeatW{
            wdata: controlRegValReg.rdata,
            wstrb: 'hF,
            wlast: True
        });
        stateReg <= 5;
        action
            AxiMmNapBeatB readResult <- napSlave.recvWriteResp;
           
        endaction
        stateReg <= 6;
    endseq);

    FSM test <- mkFSM(driversMonitors);
    Reg#(Bool) going <- mkReg(False);
    Reg#(Bool) runReg <- mkReg(False);

    rule ssss if (!going && runReg);
        going <= True;
        test.start;
    endrule

    // for (Integer idx = 0; idx < valueOf(ETH_NAP_COUNT); idx = idx + 1) begin
    //     let txEiuChannelNum = idx * 2;
    //     let rxEiuChannelNum = txEiuChannelNum + 1;

    //     ethNapVec[idx] <- mkAcxNapEthernetWrapper(fromInteger(txEiuChannelNum), fromInteger(rxEiuChannelNum));

    //     rule genData;
    //         let randData <- randGenVec[idx].get;

    //         let data = EthFrame{
    //             channelIdx: fromInteger(idx),
    //             data: randData
    //         };

    //         Bool eop = False;
    //         Bool sop = nextIsFirstRegVec[idx];

    //         if (lengthCounterRegVec[idx] == 0) begin
    //             eop = True;
    //             nextIsFirstRegVec[idx] <= True;
    //             lengthCounterRegVec[idx] <= truncate(randData);
    //         end
    //         else begin
    //             nextIsFirstRegVec[idx] <= False;
    //             lengthCounterRegVec[idx] <= lengthCounterRegVec[idx] - 1;
    //         end

    //         let beat = VerticalNapBeatEntry{
    //             srcOrDstNodeId: fromInteger(valueOf(ETHERNET_NAP_NODE_ID)),
    //             data: zeroExtend(pack(data)),
    //             sop: sop,
    //             eop: eop
    //         };

    //         inflightBeatVec[idx].enq(beat);
    //         ethNapVec[idx].send(beat);
    //     endrule

    //     rule recvData; 
    //         let d <- ethNapVec[idx].recv;
    //         recvBeatVec[idx].enq(d);
    //     endrule
    // end

    
    method getStateReg = stateReg;
    method recvPacketCnt = truncate(pack(recvBeatVec[0].first) | pack(recvBeatVec[1].first) | pack(recvBeatVec[2].first) | pack(recvBeatVec[3].first));
    method Action run;
        runReg <= True;
    endmethod
endmodule