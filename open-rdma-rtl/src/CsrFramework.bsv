import GetPut :: *;
import ClientServer :: *;
import Vector :: *;
import SpecialFIFOs :: *;
import Connectable :: *;
import FIFOF :: *;
import PrimUtils :: *;

typedef struct {
    tAddr addr;
    tValue value;
    Bool isWrite;
} CsrReadWriteReq#(type tAddr, type tValue) deriving(Bits, FShow);

typedef struct {
    tValue value;
} CsrReadWriteResp#(type tValue) deriving(Bits, FShow);


typedef Client#(CsrReadWriteReq#(tAddr, tValue), CsrReadWriteResp#(tValue)) CsrNodeDownStreamPort#(type tAddr, type tValue);
typedef Server#(CsrReadWriteReq#(tAddr, tValue), CsrReadWriteResp#(tValue)) CsrNodeUpStreamPort#(type tAddr, type tValue);


typedef union tagged {
    void                         CsrNodeResultWriteHandled;
    CsrReadWriteResp#(tValue)    CsrNodeResultReadHandled;
    tDownStreamPordIdx           CsrNodeResultForward;
    void                         CsrNodeResultNotMatched;
} CsrNodeResult#(type tDownStreamPordIdx, type tValue) deriving (FShow, Bits, Eq);

interface CsrNode#(type tAddr, type tValue, numeric type nDownStreamPortCnt);
    interface CsrNodeUpStreamPort#(tAddr, tValue) upStreamPort;
    interface Vector#(nDownStreamPortCnt, CsrNodeDownStreamPort#(tAddr, tValue)) downStreamPortsVec;
endinterface

module mkCsrNode#(
        function ActionValue#(CsrNodeResult#(tDownStreamPordIdx, tValue)) matchFunc(CsrReadWriteReq#(tAddr, tValue) req),
        Integer queueDepth,
        String debugName
    )(CsrNode#(tAddr, tValue, nDownStreamPortCnt)) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tValue, szValue),
        NumAlias#(TLog#(TMax#(1, nDownStreamPortCnt)), szDownStreamPordIdx),
        Bits#(tDownStreamPordIdx, szDownStreamPordIdx),
        FShow#(CsrFramework::CsrReadWriteResp#(tValue)),
        Literal#(tValue),
        PrimIndex#(tDownStreamPordIdx, a__),
        FShow#(tAddr),
        FShow#(tDownStreamPordIdx)
    );

    Vector#(nDownStreamPortCnt, Wire#(CsrReadWriteReq#(tAddr, tValue))) reqWireVec <- replicateM(mkWire);
    Vector#(nDownStreamPortCnt, FIFOF#(CsrReadWriteReq#(tAddr, tValue))) reqRelayQueueVec <- replicateM(mkLFIFOF);
    Vector#(nDownStreamPortCnt, FIFOF#(CsrReadWriteResp#(tValue))) respRelayQueueVec <- replicateM(mkLFIFOF);

    FIFOF#(CsrReadWriteResp#(tValue)) selfRespQueue <- mkLFIFOF;
    FIFOF#(Tuple2#(Bool, tDownStreamPordIdx)) keepOrderQueue <- mkSizedFIFOF(queueDepth);

    Vector#(nDownStreamPortCnt, CsrNodeDownStreamPort#(tAddr, tValue)) downStreamPortsVecInst = newVector;
    for (Integer idx = 0; idx < valueOf(nDownStreamPortCnt); idx = idx + 1) begin
        downStreamPortsVecInst[idx] = toGPClient(reqRelayQueueVec[idx], respRelayQueueVec[idx]);
    end

    interface CsrNodeUpStreamPort upStreamPort;
        interface Put request;
            method Action put(CsrReadWriteReq#(tAddr, tValue) req);
                let matchResult <- matchFunc(req);
                case (matchResult) matches
                    tagged CsrNodeResultWriteHandled: begin
                        // nothing to do
                    end
                    tagged CsrNodeResultReadHandled .resp: begin
                        selfRespQueue.enq(resp);
                        let isSelfResp = True;
                        keepOrderQueue.enq(tuple2(isSelfResp, ?));
                    end
                    tagged CsrNodeResultForward .portIdx: begin
                        reqRelayQueueVec[portIdx].enq(req);
                        let isSelfResp = False;
                        if (!req.isWrite) begin
                            keepOrderQueue.enq(tuple2(isSelfResp, portIdx));
                        end
                    end
                    tagged CsrNodeResultNotMatched: begin
                        selfRespQueue.enq(unpack('hAAAAAAAA));
                        let isSelfResp = True;
                        keepOrderQueue.enq(tuple2(isSelfResp, ?));
                        immFail(
                            "CSR routing found an unknown address",
                            $format("req=", fshow(req))
                        );
                    end
                endcase

                // $display(
                //     "time=%0t:", $time, toGreen(" mkCsrNode upStreamPort put request [%s]"), debugName,
                //     toBlue(", req="), fshow(req),
                //     toBlue(", matchResult="), fshow(matchResult)
                // );
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(CsrReadWriteResp#(tValue)) get;
                let {isSelfResp, portIdx} = keepOrderQueue.first;
                keepOrderQueue.deq;
                if (isSelfResp) begin
                    selfRespQueue.deq;
                    // $display(
                    //     "time=%0t:", $time, toGreen(" mkCsrNode upStreamPort get read resp [%s]"), debugName,
                    //     toBlue(", isSelfResp="), fshow(isSelfResp),
                    //     toBlue(", result="), fshow(selfRespQueue.first)
                    // );
                    return selfRespQueue.first;
                end
                else begin
                    respRelayQueueVec[portIdx].deq;
                    // $display(
                    //     "time=%0t:", $time, toGreen(" mkCsrNode upStreamPort get read resp [%s]"), debugName,
                    //     toBlue(", isSelfResp="), fshow(isSelfResp),
                    //     toBlue(", portIdx="), fshow(portIdx),
                    //     toBlue(", result="), fshow(respRelayQueueVec[portIdx].first)
                    // );
                    return respRelayQueueVec[portIdx].first;
                end
            endmethod

        endinterface
    endinterface

    interface downStreamPortsVec = downStreamPortsVecInst;
endmodule