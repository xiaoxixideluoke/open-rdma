import ClientServer :: *;
import GetPut :: *;
import FIFOF :: *;
import Connectable :: *;
import ConnectableF :: *;

import BasicDataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import Vector :: *;

import Settings :: *;
import PrimUtils :: *;

import Arbitration :: *;
import FullyPipelineChecker :: *;


interface QpContext;
    interface ServerP#(ReadReqQPC, Maybe#(EntryQPC)) querySrv;
    interface ServerP#(WriteReqQPC, Bool) updateSrv;
endinterface

(* synthesize *)
module mkQpContext(QpContext);
    QueuedServerP#(ReadReqQPC, Maybe#(EntryQPC)) qpcQuerySrvInst <- mkQueuedServerP(DebugConf{name: "qpcQuerySrvInst", enableDebug: False});
    QueuedServerP#(WriteReqQPC, Bool) qpcUpdateSrvInst <- mkQueuedServerP(DebugConf{name: "qpcUpdateSrvInst", enableDebug: False});

    AutoInferBram#(IndexQP, Maybe#(EntryQPC)) qpcEntryCommonStorage <- mkAutoInferBramUG(False, "", "qpcEntryCommonStorage");

    FIFOF#(Tuple3#(IndexQP, KeyQP, Bool)) pipeQ <- mkLFIFOF;

    rule handleReadReq;
        let req <- qpcQuerySrvInst.getReq;
        IndexQP idx = getIndexQP(req.qpn);
        KeyQP key   = getKeyQP(req.qpn);
        qpcEntryCommonStorage.putReadReq(idx);
        pipeQ.enq(tuple3(idx, key, req.needCheckKey));
    endrule

    rule handleReadResp;
        let {idx, key, needCheckKey} = pipeQ.first;
        pipeQ.deq;
        let qpcEntryMaybe <- qpcEntryCommonStorage.getReadResp;

        if (qpcEntryMaybe matches tagged Valid .resp) begin
            if (needCheckKey) begin
                if (resp.qpnKeyPart == key) begin
                    qpcQuerySrvInst.putResp(tagged Valid resp);
                end
                else begin
                    qpcQuerySrvInst.putResp(tagged Invalid);
                end
            end
            else begin
                qpcQuerySrvInst.putResp(tagged Valid resp);
            end
        end 
        else begin
            qpcQuerySrvInst.putResp(tagged Invalid);
        end
        $display("read BRAM idx=", fshow(idx), "qpcEntryMaybe=", fshow(qpcEntryMaybe));
    endrule

    rule handleWriteReq;
        let req <- qpcUpdateSrvInst.getReq;
        IndexQP idx = getIndexQP(req.qpn);

        qpcEntryCommonStorage.write(idx, req.ent);
        qpcUpdateSrvInst.putResp(True);

        $display("write BRAM idx=", fshow(idx), "req=", fshow(req.ent));
    endrule

    interface querySrv = qpcQuerySrvInst.srv;
    interface updateSrv = qpcUpdateSrvInst.srv;
endmodule



interface QpContextTwoWayQuery;
    interface Vector#(NUMERIC_TYPE_TWO, ServerP#(ReadReqQPC, Maybe#(EntryQPC))) querySrvVec;
    interface ServerP#(WriteReqQPC, Bool) updateSrv;
endinterface



(* synthesize *)
module mkQpContextTwoWayQuery(QpContextTwoWayQuery);
    
    function Bool alwaysTrue(anytype resp);
        return True;
    endfunction

    QpContext qpContext <- mkQpContext;
    // QPC Table need 10 beat for worst case to generate resp.
    // For QPC, packte without payload can occur, which is 3 beats, then the arbiter's keep order queue depth should be at least 4
    let arbiter <- mkServerToClientArbitFixPriorityP(
        4,
        True,
        alwaysTrue,
        alwaysTrue,
        DebugConf{name: "QpContextTwoWayQuery", enableDebug: False}
    );

    mkConnection(arbiter.cltIfc, qpContext.querySrv);

    interface querySrvVec = arbiter.srvIfcVec;
    interface updateSrv = qpContext.updateSrv;
endmodule



interface QpContextFourWayQuery;
    interface Vector#(NUMERIC_TYPE_FOUR, ServerP#(ReadReqQPC, Maybe#(EntryQPC))) querySrvVec;
    interface ServerP#(WriteReqQPC, Bool) updateSrv;
endinterface

(* synthesize *)
module mkQpContextFourWayQuery(QpContextFourWayQuery);
    

    Vector#(NUMERIC_TYPE_TWO, QpContextTwoWayQuery) twoWayQpContextVec <- replicateM(mkQpContextTwoWayQuery);
    Vector#(NUMERIC_TYPE_FOUR, ServerP#(ReadReqQPC, Maybe#(EntryQPC))) querySrvVecInst = newVector;

    querySrvVecInst[0] = twoWayQpContextVec[0].querySrvVec[0];
    querySrvVecInst[1] = twoWayQpContextVec[0].querySrvVec[1];
    querySrvVecInst[2] = twoWayQpContextVec[1].querySrvVec[0];
    querySrvVecInst[3] = twoWayQpContextVec[1].querySrvVec[1];
    
    interface querySrvVec = querySrvVecInst;

    interface ServerP updateSrv;
        interface PipeInB0 request;
            method Action firstIn(WriteReqQPC dataIn);
                twoWayQpContextVec[0].updateSrv.request.firstIn(dataIn);
                twoWayQpContextVec[1].updateSrv.request.firstIn(dataIn);
            endmethod

            method Action notEmptyIn(Bool val);
                twoWayQpContextVec[0].updateSrv.request.notEmptyIn(val);
                twoWayQpContextVec[1].updateSrv.request.notEmptyIn(val);
            endmethod

            // two QpContextTwoWayQuery should be in sync, so only care one's response is enough.
            method deqSignalOut = twoWayQpContextVec[0].updateSrv.request.deqSignalOut;
        endinterface

        interface PipeOut response;
            // two QpContextTwoWayQuery should be in sync, so only care one's response is enough.
            method first = twoWayQpContextVec[0].updateSrv.response.first;
            method Bool notEmpty = twoWayQpContextVec[0].updateSrv.response.notEmpty;
              
            method Action deq;
                twoWayQpContextVec[0].updateSrv.response.deq;
                twoWayQpContextVec[1].updateSrv.response.deq;
            endmethod
        endinterface
    endinterface
endmodule