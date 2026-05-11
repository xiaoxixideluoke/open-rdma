import BuildVector :: *;
import ClientServer :: *;
import Connectable :: *;
import ConnectableF :: *;
import FIFOF :: *;
import GetPut :: *;
import PAClib :: *;
import Vector :: *;

import PrimUtils :: *;
import RdmaUtils :: *;

import Arbiter :: * ;

import FullyPipelineChecker :: *;






module mkTwoWayFixedPriorityStreamMux#(
    Vector#(2, PipeOut#(reqType)) inVec,
    function Bool isReqFinished(reqType request),
    DebugConf dbgConf
)(Get#(Tuple2#(Bool, reqType))) provisos(
    FShow#(reqType), 
    Bits#(reqType, reqSz)
);

    Reg#(Bool) isIdleReg <- mkReg(True);
    Reg#(Bool) isForwardingCh0Reg <- mkReg(False);


    FIFOF#(Tuple2#(Bool, reqType))   reqQ <- mkLFIFOF;

    rule handleIdle if (isIdleReg);
        let hasReq = inVec[0].notEmpty || inVec[1].notEmpty;
        let data = ?;
        let isForwardingCh0 = ?;
        if (inVec[0].notEmpty) begin
            data = inVec[0].first;
            inVec[0].deq;
            isForwardingCh0 = True;
        end
        else if (inVec[1].notEmpty) begin
            data = inVec[1].first;
            inVec[1].deq;
            isForwardingCh0 = False;
        end
        isForwardingCh0Reg <= isForwardingCh0;

        if (hasReq) begin
            reqQ.enq(tuple2(isForwardingCh0, data));
            if (!isReqFinished(data)) begin
                isIdleReg <= False;
            end
        end
    endrule

    rule handleForward if (!isIdleReg);
        let data = ?;
        if (isForwardingCh0Reg) begin
            data = inVec[0].first;
            inVec[0].deq;
        end
        else begin
            data = inVec[1].first;
            inVec[1].deq;
        end
        reqQ.enq(tuple2(isForwardingCh0Reg, data));
        if (isReqFinished(data)) begin
            isIdleReg <= True;
        end
    endrule

    return toGet(reqQ);
endmodule





module mkClientArbiter#(
    Integer keepOrderQueueLen,
    Vector#(portSz, Client#(reqType, respType)) clientVec,
    function Bool isReqFinished(reqType request),
    function Bool isRespFinished(respType response),
    DebugConf dbgConf
)(Client#(reqType, respType)) provisos(
    Bits#(reqType, reqSz),
    Bits#(respType, respSz),
    Add#(1, anysize, portSz),
    FShow#(reqType)
);

    Arbiter_IFC#(portSz) arbiter <- mkArbiter(False);
    Reg#(Bool) canSubmitArbitReqReg <- mkReg(True);

    Vector#(portSz, FIFOF#(reqType)) clientReqFifoVec <- replicateM(mkLFIFOF);

    // A trick here. This fifo's size must be small, and it should be smaller than portSz, or it will
    // queue too many granted requests ahead of time (mkArbiter will do arbit every clock cycle)
    FIFOF#(Bit#(TLog#(portSz))) grantReqKeepOrderQ <- mkLFIFOF;
    // This Fifo can be larger since receive response may take some time and there can be many outstanding requests.
    FIFOF#(Bit#(TLog#(portSz))) grantRespKeepOrderQ <- mkSizedFIFOF(keepOrderQueueLen);

    FIFOF#(reqType)   reqQ <- mkLFIFOF;
    FIFOF#(respType) respQ <- mkLFIFOF;

    // convert input Get interface to a FIFOF since we need full/empty signal
    // THIS QUEUE MUST BE SIZE OF 2, SO WHEN IT FULL IT MEANS THAT WE HAVE TO ELEMENTS IN QUEUE NOW.
    for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin
        mkConnection(clientVec[idx].request, toPut(clientReqFifoVec[idx]));
    end



    rule forwardRequest if (!canSubmitArbitReqReg);
        let idx = grantReqKeepOrderQ.first;
        let req = clientReqFifoVec[idx].first;
        clientReqFifoVec[idx].deq;
        reqQ.enq(req);

        let reqFinished = isReqFinished(req);
        if (reqFinished) begin
            canSubmitArbitReqReg <= True;
            grantReqKeepOrderQ.deq;
        end
        

        if (dbgConf.enableDebug) begin
            $display(
                "time=%0t: ", $time,
                fshow(dbgConf.name),
                " arbitrate request, reqIdx=%0d", idx,
                ", reqFinished=", fshow(reqFinished)
            );
        end
        
        
    endrule

    for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin
        rule sendArbitReq;
            if (dbgConf.enableDebug) begin
                $display(
                    "time=%0t: ", $time,
                    fshow(dbgConf.name),
                    " arbitrate sendArbitReq debug, reqIdx=%0d", idx,
                    " canSubmitArbitReqReg = ", fshow(canSubmitArbitReqReg),
                    " clientReqFifoVec[idx].notEmpty = ", fshow(clientReqFifoVec[idx].notEmpty)
                );
            end
            
            if (canSubmitArbitReqReg) begin
                arbiter.clients[idx].request;
                if (dbgConf.enableDebug) begin
                    $display(
                        "time=%0t: ", $time,
                        fshow(dbgConf.name),
                        " arbitrate submit req, reqIdx=%0d", idx
                    );
                end
            end
        endrule

        

        rule forwardResponse if (grantRespKeepOrderQ.first == fromInteger(idx));
            let resp = respQ.first;
            respQ.deq;
            clientVec[idx].response.put(resp);
            let respFinished = isRespFinished(resp);
            if (respFinished) begin
                grantRespKeepOrderQ.deq;
            end

            if (dbgConf.enableDebug) begin
                $display(
                    "time=%0t: ", $time,
                    fshow(dbgConf.name),
                    " dispatch response, idx=%0d", idx,
                    ", respFinished=", fshow(respFinished)
                );
            end
        endrule
    end

    rule recvArbitResp if (canSubmitArbitReqReg);

        Vector#(portSz, Bool) arbiterRespVec;
        for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin
            arbiterRespVec[idx] = arbiter.clients[idx].grant;
        end
        if (dbgConf.enableDebug) begin
            $display(
                "time=%0t: ", $time,
                fshow(dbgConf.name),
                " arbit result=", fshow(arbiterRespVec)
            );
        end
        if (pack(arbiterRespVec) != 0) begin
            let idx = arbiter.grant_id;
            let req = clientReqFifoVec[idx].first;

            reqQ.enq(req);
            clientReqFifoVec[idx].deq;
            grantRespKeepOrderQ.enq(idx);

            if (!isReqFinished(req)) begin
                grantReqKeepOrderQ.enq(idx);
                canSubmitArbitReqReg <= False;
                if (dbgConf.enableDebug) begin
                    $display(
                        "time=%0t: ", $time,
                        fshow(dbgConf.name),
                        " grant new single beat request, client idx=%0d", idx
                    );
                end
            end
            
            if (dbgConf.enableDebug) begin
                $display(
                    "time=%0t: ", $time,
                    fshow(dbgConf.name),
                    ", grant new request, client idx=%0d", idx, 
                    ", req=", fshow(req)
                );
            end
        end

    endrule

    rule debug if (dbgConf.enableDebug);
        if (!reqQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " reqQ");
        end
        if (!respQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " respQ");
        end

        // if (!reqQ.notEmpty) begin
        //     $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " reqQ");
        // end
        // if (!respQ.notEmpty) begin
        //     $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " respQ");
        // end

        // if (!grantReqKeepOrderQ.notEmpty) begin
        //     $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " grantReqKeepOrderQ");
        // end

        if (!grantReqKeepOrderQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " grantReqKeepOrderQ");
        end

        if (!grantRespKeepOrderQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " grantRespKeepOrderQ");
        end

        for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin

            if (!clientReqFifoVec[idx].notFull) begin
                $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " clientReqFifoVec[%0d]", idx);
            end

            // if (!clientReqFifoVec[idx].notEmpty) begin
            //     $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(dbgConf.name) , " clientReqFifoVec[%0d]", idx);
            // end
            
        end
    endrule

    return toGPClient(reqQ, respQ);
endmodule


















interface ServerToClientArbitP#(numeric type channelCnt, type tReq, type tResp);
    interface Vector#(channelCnt, ServerP#(tReq, tResp))        srvIfcVec;
    interface ClientP#(tReq, tResp)                             cltIfc;
endinterface


module mkServerToClientArbitP#(
        Integer depth, 
        Bool needReadResp,
        function Bool isReqFinished(tReq request),
        function Bool isRespFinished(tResp response),
        DebugConf dbgConf
    )(ServerToClientArbitP#(channelCnt, tReq, tResp)) provisos (
        Bits#(tReq, szReq),
        Bits#(tResp, szResp),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
        FShow#(tReq),
        FShow#(tResp)
    );

    Vector#(channelCnt, ServerP#(tReq, tResp))     srvIfcVecInst = newVector;

    Vector#(channelCnt, PipeInAdapterB0#(tReq))                         srvSideReqQueueVec      <- replicateM(mkPipeInAdapterB0);
    Vector#(channelCnt, FIFOF#(tResp))                                   srvSideRespQueueVec     <- replicateM(mkFIFOF);

    FIFOF#(tReq)                           cltSideReqQueue   <-  mkFIFOF;
    PipeInAdapterB0#(tResp)                 cltSideRespQueue  <-  mkPipeInAdapterB0;


    Arbiter_IFC#(channelCnt) innerArbiter <- mkArbiter(False);
    Reg#(Bool) isReqFirstBeatReg <- mkReg(True);
    Reg#(tChannelIdx) curReqChannelIdxReg <- mkRegU;
    FIFOF#(tChannelIdx) respKeepOrderQueue  <- mkSizedFIFOFWithFullAssert(depth, concatDebugName (dbgConf, "mkServerToClientArbitFixPriorityP respKeepOrderQueue"));

    // rule debug;
    //     $display(
    //         "time=%0t, ", $time, "DEBUG", 
    //         ", isWriteFirstBeatReg=", fshow(isWriteFirstBeatReg),
    //         ", masterSideQueueWm.notFull=", fshow(masterSideQueueWm.notFull),
    //         ", masterSideQueueWd.notFull=", fshow(masterSideQueueWd.notFull),
    //         ", writeSourceChannelIdPipeOutQueue.notFull=", fshow(writeSourceChannelIdPipeOutQueue.notFull)
    //     );
    // endrule

    rule sendWriteArbitReq if (isReqFirstBeatReg);
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (srvSideReqQueueVec[channelIdx].notEmpty) begin
                innerArbiter.clients[channelIdx].request;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkServerToClientArbitP sendWriteArbitReq"),
                //     toBlue(", channelIdx=%d"), channelIdx
                // );
            end
        end
    endrule

    rule recvReqArbitResult if (isReqFirstBeatReg);
        Maybe#(tReq) reqMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (innerArbiter.clients[channelIdx].grant) begin
                reqMaybe = tagged Valid srvSideReqQueueVec[channelIdx].first;
                srvSideReqQueueVec[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (reqMaybe matches tagged Valid .req) begin
            cltSideReqQueue.enq(req);
            isReqFirstBeatReg <= isReqFinished(req);
            curReqChannelIdxReg <= curChannelIdx;
            if (needReadResp) begin
                respKeepOrderQueue.enq(curChannelIdx);
            end
            $display(
                "time=%0t:", $time, toGreen(" mkServerToClientArbitP forward request first beat"),
                toBlue(", req="), fshow(req)
            );
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkServerToClientArbitP recvReqArbitResult"),
        //     toBlue(", wmMaybe="), fshow(wmMaybe),
        //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
        // );
    endrule

    rule forwardMoreReqBeat if (!isReqFirstBeatReg);
        let req  = srvSideReqQueueVec[curReqChannelIdxReg].first;
        srvSideReqQueueVec[curReqChannelIdxReg].deq;
        cltSideReqQueue.enq(req);
        isReqFirstBeatReg <= isReqFinished(req);

        $display(
            "time=%0t:", $time, toGreen(" mkServerToClientArbitP forward request more beat"),
            toBlue(", req="), fshow(req)
        );
    endrule


    if (needReadResp) begin
        rule forwardReadResp;
            let resp = cltSideRespQueue.first;
            cltSideRespQueue.deq;

            let channelIdx = respKeepOrderQueue.first;
            srvSideRespQueueVec[channelIdx].enq(resp);

            if (isRespFinished(resp)) begin
                respKeepOrderQueue.deq;
            end
            $display(
                "time=%0t:", $time, toGreen(" mkServerToClientArbitP forwardReadResp"),
                toBlue(", channelIdx="), fshow(channelIdx),
                toBlue(", resp="), fshow(resp)
            );
        endrule
    end


    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        srvIfcVecInst[channelIdx] = toGPServerP(toPipeInB0(srvSideReqQueueVec[channelIdx]), toPipeOut(srvSideRespQueueVec[channelIdx]));
    end

    interface srvIfcVec = srvIfcVecInst;
    interface cltIfc = toGPClientP(toPipeOut(cltSideReqQueue), toPipeInB0(cltSideRespQueue));
endmodule







// channel 0 has highest priority, and last channel has lowest priority.
interface ServerToClientArbitFixPriorityP#(numeric type channelCnt, type tReq, type tResp);
    interface Vector#(channelCnt, ServerP#(tReq, tResp))        srvIfcVec;
    interface ClientP#(tReq, tResp)                             cltIfc;
endinterface


module mkServerToClientArbitFixPriorityP#(
        Integer depth, 
        Bool needReadResp,
        function Bool isReqFinished(tReq request),
        function Bool isRespFinished(tResp response),
        DebugConf dbgConf
    )(ServerToClientArbitFixPriorityP#(channelCnt, tReq, tResp)) provisos (
        Bits#(tReq, szReq),
        Bits#(tResp, szResp),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
        FShow#(tReq),
        FShow#(tResp)
    );

    Vector#(channelCnt, ServerP#(tReq, tResp))     srvIfcVecInst = newVector;

    Vector#(channelCnt, PipeInAdapterB0#(tReq))                         srvSideReqQueueVec      <- replicateM(mkPipeInAdapterB0);
    Vector#(channelCnt, FIFOF#(tResp))                                   srvSideRespQueueVec     <- replicateM(mkFIFOF);

    FIFOF#(tReq)                           cltSideReqQueue   <-  mkFIFOF;
    PipeInAdapterB0#(tResp)                 cltSideRespQueue  <-  mkPipeInAdapterB0;

    Reg#(Bool) isReqFirstBeatReg <- mkReg(True);
    Reg#(tChannelIdx) curReqChannelIdxReg <- mkRegU;
    FIFOF#(tChannelIdx) respKeepOrderQueue  <- mkSizedFIFOFWithFullAssert(depth, concatDebugName(dbgConf, "mkServerToClientArbitFixPriorityP respKeepOrderQueue"));   // TODO: check why use mkRegisteredSizedFIFOF will deadlock here

    // rule debug;
    //     $display(
    //         "time=%0t, ", $time, "DEBUG", 
    //         ", isWriteFirstBeatReg=", fshow(isWriteFirstBeatReg),
    //         ", masterSideQueueWm.notFull=", fshow(masterSideQueueWm.notFull),
    //         ", masterSideQueueWd.notFull=", fshow(masterSideQueueWd.notFull),
    //         ", writeSourceChannelIdPipeOutQueue.notFull=", fshow(writeSourceChannelIdPipeOutQueue.notFull)
    //     );
    // endrule


    rule recvReqArbitResult if (isReqFirstBeatReg);
        Maybe#(tReq) reqMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        
        Bit#(TAdd#(1, TLog#(channelCnt))) conflictCounter = 0;

        for (Integer channelIdx = valueOf(channelCnt) - 1; channelIdx >= 0 ; channelIdx = channelIdx - 1) begin
            if (srvSideReqQueueVec[channelIdx].notEmpty) begin
                reqMaybe = tagged Valid srvSideReqQueueVec[channelIdx].first;
                curChannelIdx = fromInteger(channelIdx);
                conflictCounter = conflictCounter + 1;
            end
        end

        if (conflictCounter > 1) begin
            $display("mkServerToClientArbitFixPriorityP multi input ready.");
        end

        if (reqMaybe matches tagged Valid .req) begin
            cltSideReqQueue.enq(req);
            isReqFirstBeatReg <= isReqFinished(req);
            curReqChannelIdxReg <= curChannelIdx;
            srvSideReqQueueVec[curChannelIdx].deq;
            if (needReadResp) begin
                respKeepOrderQueue.enq(curChannelIdx);
            end
            $display(
                "time=%0t:", $time, toGreen(" mkServerToClientArbitFixPriorityP forward request first beat"),
                toBlue(", req="), fshow(req)
            );
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkServerToClientArbitFixPriorityP recvReqArbitResult"),
        //     toBlue(", wmMaybe="), fshow(wmMaybe),
        //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
        // );
    endrule

    rule forwardMoreReqBeat if (!isReqFirstBeatReg);
        let req  = srvSideReqQueueVec[curReqChannelIdxReg].first;
        srvSideReqQueueVec[curReqChannelIdxReg].deq;
        cltSideReqQueue.enq(req);
        isReqFirstBeatReg <= isReqFinished(req);

        $display(
            "time=%0t:", $time, toGreen(" mkServerToClientArbitFixPriorityP forward request more beat"),
            toBlue(", req="), fshow(req)
        );
    endrule


    if (needReadResp) begin
        rule forwardReadResp;
            let resp = cltSideRespQueue.first;
            cltSideRespQueue.deq;

            let channelIdx = respKeepOrderQueue.first;
            srvSideRespQueueVec[channelIdx].enq(resp);

            if (isRespFinished(resp)) begin
                respKeepOrderQueue.deq;
            end
            $display(
                "time=%0t:", $time, toGreen(" mkServerToClientArbitFixPriorityP forwardReadResp"),
                toBlue(", channelIdx="), fshow(channelIdx),
                toBlue(", resp="), fshow(resp)
            );
        endrule
    end


    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        srvIfcVecInst[channelIdx] = toGPServerP(toPipeInB0(srvSideReqQueueVec[channelIdx]), toPipeOut(srvSideRespQueueVec[channelIdx]));
    end

    interface srvIfcVec = srvIfcVecInst;
    interface cltIfc = toGPClientP(toPipeOut(cltSideReqQueue), toPipeInB0(cltSideRespQueue));
endmodule







interface SimpleRoundRobinPipeArbiter#(type nChannel, type tElement);
    interface Vector#(nChannel, PipeInB0#(tElement)) pipeInVec;
    interface PipeOut#(tElement) pipeOut;
endinterface


module mkSimpleRoundRobinPipeArbiter#(Integer bufferDepth)(SimpleRoundRobinPipeArbiter#(nChannel, tElement)) provisos (
        Bits#(tElement, szElement)
    );
    Vector#(nChannel, PipeInB0#(tElement)) pipeInVecInst = newVector;
    
    Vector#(nChannel, PipeInAdapterB0#(tElement)) pipeInQueueVec <- replicateM(mkPipeInAdapterB0);

    
    FIFOF#(tElement) pipeOutQueue <- mkSizedFIFOF(bufferDepth);


    Arbiter_IFC#(nChannel) arbiter <- mkArbiter(False);

    for (Integer channelIdx = 0; channelIdx < valueOf(nChannel); channelIdx = channelIdx + 1) begin
        pipeInVecInst[channelIdx] = pipeInQueueVec[channelIdx].pipeInIfc;
    end

    rule sendArbitReq;
        for (Integer channelIdx = 0; channelIdx < valueOf(nChannel); channelIdx = channelIdx + 1) begin
            if (pipeInQueueVec[channelIdx].notEmpty) begin
                arbiter.clients[channelIdx].request;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkSimpleRoundRobinPipeArbiter sendArbitReq"),
                //     toBlue(", channelIdx=%d"), channelIdx
                // );
            end
        end
    endrule


    rule recvArbitResp;
        Maybe#(tElement) elementMaybe = tagged Invalid;
        Bit#(TLog#(nChannel)) curChannelIdx = 0;

        for (Integer channelIdx = 0; channelIdx < valueOf(nChannel); channelIdx = channelIdx + 1) begin
            if (arbiter.clients[channelIdx].grant) begin
                elementMaybe = tagged Valid pipeInQueueVec[channelIdx].first;
                pipeInQueueVec[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (elementMaybe matches tagged Valid .element) begin
            pipeOutQueue.enq(element);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkSimpleRoundRobinPipeArbiter forward"),
            //     toBlue(", element="), fshow(element),
            //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
            // );
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkSimpleRoundRobinPipeArbiter recvArbitResp"),
        //     toBlue(", elementMaybe="), fshow(elementMaybe)
        // );
    endrule



    interface pipeInVec     = pipeInVecInst;
    interface pipeOut       = toPipeOut(pipeOutQueue);
endmodule



interface SimpleRoundRobinPipeDispatcher#(type nChannel, type tElement);
    interface PipeIn#(tElement)                     pipeIn;
    interface Vector#(nChannel, PipeOut#(tElement)) pipeOutVec;
endinterface


module mkSimpleRoundRobinPipeDispatcher#(Integer bufferDepth)(SimpleRoundRobinPipeDispatcher#(nChannel, tElement)) provisos (
        Bits#(tElement, szElement)
    );
    Vector#(nChannel, PipeOut#(tElement)) pipeOutVecInst = newVector;
    
    Vector#(nChannel, FIFOF#(tElement)) pipeOutQueueVec <- replicateM(mkFIFOF);

    
    FIFOF#(tElement) pipeInQueue <- mkSizedFIFOF(bufferDepth);


    Arbiter_IFC#(nChannel) arbiter <- mkArbiter(False);

    for (Integer channelIdx = 0; channelIdx < valueOf(nChannel); channelIdx = channelIdx + 1) begin
        pipeOutVecInst[channelIdx] = toPipeOut(pipeOutQueueVec[channelIdx]);
    end

    rule sendArbitReq;
        for (Integer channelIdx = 0; channelIdx < valueOf(nChannel); channelIdx = channelIdx + 1) begin
            if (pipeOutQueueVec[channelIdx].notFull) begin
                arbiter.clients[channelIdx].request;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkSimpleRoundRobinPipeDispatcher sendArbitReq"),
                //     toBlue(", channelIdx=%d"), channelIdx
                // );
            end
        end
    endrule


    rule recvArbitResp;
        Bool successDispatched = False;
        Bit#(TLog#(nChannel)) curChannelIdx = 0;

        for (Integer channelIdx = 0; channelIdx < valueOf(nChannel); channelIdx = channelIdx + 1) begin
            if (arbiter.clients[channelIdx].grant) begin
                
                pipeOutQueueVec[channelIdx].enq(pipeInQueue.first);
                curChannelIdx = fromInteger(channelIdx);
                successDispatched = True;
            end
        end

        if (successDispatched) begin
            pipeInQueue.deq;
            // $display(
            //     "time=%0t:", $time, toGreen(" mkSimpleRoundRobinPipeDispatcher forward"),
            //     toBlue(", element="), fshow(pipeInQueue.first),
            //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
            // );
        end
    endrule



    interface pipeIn            = toPipeIn(pipeInQueue);
    interface pipeOutVec        = pipeOutVecInst;
endmodule








interface MultiBeatRoundRobinPipeArbiter#(type channelCnt, type tReq, type tResp);
    interface Vector#(channelCnt, PipeInB0#(tReq)) reqPipeInVec;
    interface PipeOut#(tReq) reqPipeOut;

    interface PipeInB0#(tResp) respPipeIn;
    interface Vector#(channelCnt, PipeOut#(tResp)) respPipeOutVec;

    interface PipeOut#(Bit#(TLog#(channelCnt))) channelIdxPipeOut;

endinterface


module mkMultiBeatRoundRobinPipeArbiter#(
        Integer bufferDepth,
        Bool needReadResp,
        Bool needChannelIdxPipeOut,
        function Bool isReqFinished(tReq request),
        function Bool isRespFinished(tResp response),
        DebugConf dbgConf
    )(MultiBeatRoundRobinPipeArbiter#(channelCnt, tReq, tResp)) provisos (
        Bits#(tReq, szReq),
        Bits#(tResp, szResp),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
        FShow#(tReq),
        FShow#(tResp)
    );

    Vector#(channelCnt, PipeInB0#(tReq))  reqPipeInVecInst    = newVector;
    PipeInAdapterB0#(tResp)               respPipeInQueue     <-  mkPipeInAdapterB0;
    Vector#(channelCnt, PipeOut#(tResp))  respPipeOutVecInst  = newVector;
    
    
    Vector#(channelCnt, PipeInAdapterB0#(tReq)) reqPipeInQueueVec   <- replicateM(mkPipeInAdapterB0);
    Vector#(channelCnt, FIFOF#(tResp))          respPipeOutQueueVec <- replicateM(mkFIFOF);

    FIFOF#(tReq)                                reqPipeOutQueue     <- mkSizedFIFOF(bufferDepth);
    Arbiter_IFC#(channelCnt)                    innerArbiter        <- mkArbiter(False);
    Reg#(Bool) isReqFirstBeatReg <- mkReg(True);
    Reg#(tChannelIdx) curReqChannelIdxReg <- mkRegU;
    FIFOF#(tChannelIdx) respKeepOrderQueue  <- mkSizedFIFOFWithFullAssert(bufferDepth, concatDebugName (dbgConf, "mkMultiBeatRoundRobinPipeArbiter respKeepOrderQueue"));
    FIFOF#(tChannelIdx) channelIdxPipeOutQueue  <- mkSizedFIFOFWithFullAssert(bufferDepth, concatDebugName (dbgConf, "mkMultiBeatRoundRobinPipeArbiter channelIdxPipeOutQueue"));

    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        reqPipeInVecInst[channelIdx] = reqPipeInQueueVec[channelIdx].pipeInIfc;
        respPipeOutVecInst[channelIdx] = toPipeOut(respPipeOutQueueVec[channelIdx]);
    end

    rule sendWriteArbitReq if (isReqFirstBeatReg);
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (reqPipeInQueueVec[channelIdx].notEmpty) begin
                innerArbiter.clients[channelIdx].request;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkMultiBeatRoundRobinPipeArbiter sendWriteArbitReq"),
                //     toBlue(", channelIdx=%d"), channelIdx
                // );
            end
        end
    endrule


    rule recvReqArbitResult if (isReqFirstBeatReg);
        Maybe#(tReq) reqMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (innerArbiter.clients[channelIdx].grant) begin
                reqMaybe = tagged Valid reqPipeInQueueVec[channelIdx].first;
                reqPipeInQueueVec[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (reqMaybe matches tagged Valid .req) begin
            reqPipeOutQueue.enq(req);
            isReqFirstBeatReg <= isReqFinished(req);
            curReqChannelIdxReg <= curChannelIdx;
            if (needReadResp) begin
                respKeepOrderQueue.enq(curChannelIdx);
            end
            if (needChannelIdxPipeOut) begin
                channelIdxPipeOutQueue.enq(curChannelIdx);
            end
            $display(
                "time=%0t:", $time, toGreen(" mkMultiBeatRoundRobinPipeArbiter forward request first beat"),
                toBlue(", req="), fshow(req)
            );
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkMultiBeatRoundRobinPipeArbiter recvReqArbitResult"),
        //     toBlue(", wmMaybe="), fshow(wmMaybe),
        //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
        // );
    endrule

    rule forwardMoreReqBeat if (!isReqFirstBeatReg);
        let req  = reqPipeInQueueVec[curReqChannelIdxReg].first;
        reqPipeInQueueVec[curReqChannelIdxReg].deq;
        reqPipeOutQueue.enq(req);
        isReqFirstBeatReg <= isReqFinished(req);

        $display(
            "time=%0t:", $time, toGreen(" mkMultiBeatRoundRobinPipeArbiter forward request more beat"),
            toBlue(", req="), fshow(req)
        );
    endrule

    if (needReadResp) begin
        rule forwardReadResp;
            let resp = respPipeInQueue.first;
            respPipeInQueue.deq;

            let channelIdx = respKeepOrderQueue.first;
            respPipeOutQueueVec[channelIdx].enq(resp);

            if (isRespFinished(resp)) begin
                respKeepOrderQueue.deq;
            end
            $display(
                "time=%0t:", $time, toGreen(" mkMultiBeatRoundRobinPipeArbiter forwardReadResp"),
                toBlue(", channelIdx="), fshow(channelIdx),
                toBlue(", resp="), fshow(resp)
            );
        endrule
    end

    interface reqPipeInVec = reqPipeInVecInst;
    interface reqPipeOut = toPipeOut(reqPipeOutQueue);

    interface respPipeIn = toPipeInB0(respPipeInQueue);
    interface respPipeOutVec = respPipeOutVecInst;

    interface channelIdxPipeOut = toPipeOut(channelIdxPipeOutQueue);
endmodule