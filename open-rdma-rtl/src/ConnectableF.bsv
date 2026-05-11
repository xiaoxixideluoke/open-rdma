import PAClib :: *;
import FIFOF :: *;
import Clocks :: *;
import CommitIfc :: * ;
import Connectable :: *;
import FullyPipelineChecker :: *;

// re-export PAAClib's PipeOut
export PipeOut;

export PipeIn(..);
export PipeInB0(..);
// export PipeInB1(..);
// export PipeInB2(..);
export PipeInAdapterB0(..);
// export PipeInAdapterB1(..);
// export PipeInAdapterB2(..);
export mkPipeInAdapterB0;
export mkPipeInAdapterB1;
export mkPipeInAdapterB2;
export mkPipeInB0Debug;
export toPipeInB0;
export mkPipeInB0ToPipeIn;
export mkPipeInB0ToPipeInWithDebug;
export mkFifofToPipeInB0;
export mkPipeInToPipeInB0;
export GetF(..);
export PutF(..);
export ServerF(..);
export ClientF(..);
export ServerP(..);
export ClientP(..);
export f_FIFOF_to_PipeIn;
export f_UGFIFOF_to_PipeIn;
export f_UGFIFOF_to_PipeOut;
export f_Sync_FIFOF_to_FIFOF;
export f_Sync_FIFOF_to_PipeIn;
export f_Sync_FIFOF_to_PipeOut;
export toPipeOut;
export toPipeIn;
export toPipeOutSync;
export toPipeInSync;
export ugToPipeOut;
export ugToPipeIn;
export toGPServerP;
export toGPClientP;
export Connectable;


interface PipeIn#(type tData);
    method Action enq(tData data);
    method Bool notFull;
endinterface

// B0 means Buffer 0, which directly pass through
interface PipeInB0#(type tData);
    method Action firstIn(tData dataIn);
    method Action notEmptyIn(Bool val);
    method Bool deqSignalOut;
endinterface

interface GetF#(type tData);
    method Bool ready;
    method ActionValue#(tData) get;
endinterface

interface PutF#(type tData);
    method Bool ready;
    method Action put(tData value);
endinterface

interface ServerF#(type tReq, type tResp);
    interface PutF#(tReq) request;
    interface GetF#(tResp) response;
endinterface

interface ClientF#(type tReq, type tResp);
    interface GetF#(tReq) request;
    interface PutF#(tResp) response;
endinterface

interface ServerP#(type tReq, type tResp);
    interface PipeInB0#(tReq) request;
    interface PipeOut#(tResp) response;
endinterface

interface ClientP#(type tReq, type tResp);
    interface PipeOut#(tReq) request;
    interface PipeInB0#(tResp) response;
endinterface


instance Connectable#(ServerP#(tReq, tResp), ClientP#(tReq, tResp));
    module mkConnection#(ServerP#(tReq, tResp) srv, ClientP#(tReq, tResp) clt)(Empty);
        mkConnection(srv.request, clt.request);
        mkConnection(srv.response, clt.response);
    endmodule
endinstance

instance Connectable#(ClientP#(tReq, tResp), ServerP#(tReq, tResp));
    module mkConnection#(ClientP#(tReq, tResp) clt, ServerP#(tReq, tResp) srv)(Empty);
        mkConnection(srv, clt);
    endmodule
endinstance

function ServerP#(tReq, tResp) toGPServerP(PipeInB0#(tReq) request, PipeOut#(tResp) response);
    return (interface ServerP;
        interface request = request;
        interface response = response;
    endinterface);
endfunction

function ClientP#(tReq, tResp) toGPClientP(PipeOut#(tReq) request, PipeInB0#(tResp) response);
    return (interface ClientP;
        interface request = request;
        interface response = response;
    endinterface);
endfunction

function PipeIn#(tData) f_FIFOF_to_PipeIn(FIFOF#(tData) fifof);
    return (interface PipeIn;
               method Action enq (tData data);
                  fifof.enq(data);
               endmethod
               method Bool notFull;
                  return fifof.notFull;
               endmethod
            endinterface);
endfunction

function PipeIn#(tData) f_UGFIFOF_to_PipeIn(FIFOF#(tData) fifof);
    return (interface PipeIn;
               method Action enq (tData data) if (fifof.notFull);
                  fifof.enq(data);
               endmethod
               method Bool notFull;
                  return fifof.notFull;
               endmethod
            endinterface);
endfunction

function PipeOut #(tData)  f_UGFIFOF_to_PipeOut  (FIFOF #(tData) fifof);
    return (interface PipeOut;
               method tData first if (fifof.notEmpty);
                  return fifof.first;
               endmethod
               method Action deq if (fifof.notEmpty);
                  fifof.deq;
               endmethod
               method Bool notEmpty;
                  return fifof.notEmpty;
               endmethod
            endinterface);
 endfunction

 function FIFOF#(tData) f_Sync_FIFOF_to_FIFOF(SyncFIFOIfc#(tData) syncFifo);
    return (interface FIFOF;
                method enq = syncFifo.enq;
                method notFull = syncFifo.notFull;
                method first = syncFifo.first;
                method deq = syncFifo.deq;
                method notEmpty = syncFifo.notEmpty;

                method Action clear;
                    $display("clear not supported on sync fifo converted FIFOF interface");
                    $finish(1);
                endmethod
            endinterface);
endfunction

 function PipeIn#(tData) f_Sync_FIFOF_to_PipeIn(SyncFIFOIfc#(tData) syncFifo);
    return (interface PipeIn;
                method enq = syncFifo.enq;
                method notFull = syncFifo.notFull;
            endinterface);
endfunction

function PipeOut#(tData) f_Sync_FIFOF_to_PipeOut(SyncFIFOIfc#(tData) syncFifo);
    return (interface PipeOut;      
                method first = syncFifo.first;
                method deq = syncFifo.deq;
                method notEmpty = syncFifo.notEmpty;
            endinterface);
endfunction



instance Connectable#(PipeOut#(t), PipeIn#(t));
    module mkConnection#(PipeOut#(t) fo, PipeIn#(t) fi)(Empty);
        rule connect;
            fi.enq(fo.first);
            fo.deq;
        endrule
    endmodule
endinstance

instance Connectable#(PipeIn#(t), PipeOut#(t));
    module mkConnection#(PipeIn#(t) fi, PipeOut#(t) fo)(Empty);
        rule connect;
            fi.enq(fo.first);
            fo.deq;
        endrule
    endmodule
endinstance

// PipeOut related

function PipeOut#(anytype) toPipeOut(FIFOF#(anytype) queue);
    return f_FIFOF_to_PipeOut(queue);
endfunction

function PipeIn#(anytype) toPipeIn(FIFOF#(anytype) queue);
    return f_FIFOF_to_PipeIn(queue);
endfunction

function PipeOut#(anytype) toPipeOutSync(SyncFIFOIfc#(anytype) queue);
    return f_Sync_FIFOF_to_PipeOut(queue);
endfunction

function PipeIn#(anytype) toPipeInSync(SyncFIFOIfc#(anytype) queue);
    return f_Sync_FIFOF_to_PipeIn(queue);
endfunction

function PipeOut#(anytype) ugToPipeOut(FIFOF#(anytype) queue);
    return f_UGFIFOF_to_PipeOut(queue);
endfunction

function PipeIn#(anytype) ugToPipeIn(FIFOF#(anytype) queue);
    return f_UGFIFOF_to_PipeIn(queue);
endfunction


interface PipeInAdapterB0#(type tData);
    method tData first;
    method Action deq;
    method Bool notEmpty;
    interface PipeInB0#(tData) pipeInIfc;
endinterface


module mkPipeInAdapterB0(PipeInAdapterB0#(tData)) provisos (Bits#(tData, szData));

    Wire#(tData) dataWire <- mkWire;
    Wire#(Bool)  notEmptyWire <- mkDWire(False);
    PulseWire deqSignalWire <- mkPulseWire;

    interface PipeInB0 pipeInIfc;
        method Action firstIn(tData dataIn);
            dataWire <= dataIn;
        endmethod
        
        method Action notEmptyIn(Bool val);
            notEmptyWire <= val;
        endmethod

        method Bool deqSignalOut;
            return deqSignalWire;
        endmethod
    endinterface

    method tData first if (notEmptyWire);
        return dataWire;
    endmethod

    method Action deq if (notEmptyWire);
        deqSignalWire.send;
    endmethod

    method Bool notEmpty;
        return notEmptyWire;
    endmethod
endmodule



module mkPipeInB0Debug#(DebugConf dbgConf)(PipeInAdapterB0#(tData)) provisos (Bits#(tData, szData));

    Wire#(tData) dataWire <- mkWire;
    Wire#(Bool)  notEmptyWire <- mkWire;
    PulseWire deqSignalWire <- mkPulseWire;

    interface PipeInB0 pipeInIfc;
        method Action firstIn(tData dataIn);
            dataWire <= dataIn;
        endmethod
        
        method Action notEmptyIn(Bool val);
            notEmptyWire <= val;
        endmethod

        method Bool deqSignalOut;
            return deqSignalWire;
        endmethod
    endinterface

    method tData first if (notEmptyWire);
        return dataWire;
    endmethod

    method Action deq if (notEmptyWire);
        deqSignalWire.send;
        $display(
            "time=%0t:", $time, " mkPipeInB0Debug deq is called",
            ", name=", fshow(dbgConf.name)
        );
    endmethod

    method Bool notEmpty;
        return notEmptyWire;
    endmethod
endmodule



instance Connectable#(PipeOut#(t), PipeInB0#(t));
    module mkConnection#(PipeOut#(t) fo, PipeInB0#(t) fi)(Empty);
        mkConnection(fo.first, fi.firstIn);
        mkConnection(fo.notEmpty, fi.notEmptyIn);
        rule handleDeq;
            if (fi.deqSignalOut) begin
                fo.deq;
            end
        endrule
    endmodule
endinstance

instance Connectable#(PipeInB0#(t), PipeOut#(t));
    module mkConnection#(PipeInB0#(t) fi, PipeOut#(t) fo)(Empty);
        mkConnection(fo, fi);
    endmodule
endinstance

function PipeInB0#(anytype) toPipeInB0(PipeInAdapterB0#(anytype) queue);
    return queue.pipeInIfc;
endfunction

module mkPipeInB0ToPipeInWithDebug#(PipeInB0#(tData) pipeInNr, Integer bufferDepth, DebugConf dbgConf)(PipeIn#(tData)) provisos(Bits#(tData, szData), FShow#(tData));

    FIFOF#(tData) innerQ <- (bufferDepth == 1 ? mkLFIFOF : mkSizedFIFOF(bufferDepth));
    mkConnection(toPipeOut(innerQ), pipeInNr);

    if (dbgConf.enableDebug) begin
        rule debugA;
            if (!innerQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkPipeInB0ToPipeInWithDebug [%s]", dbgConf.name);
        endrule

        rule debugB;
            if (!innerQ.notEmpty) $display("time=%0t, ", $time, "EmptyQueue: mkPipeInB0ToPipeInWithDebug [%s]", dbgConf.name);
        endrule

        rule debugC;
            if (innerQ.notEmpty && pipeInNr.deqSignalOut) begin
                // if deq handshake success, then print debug info
                $display(
                    "time=%0t:", $time, " mkPipeInB0ToPipeInWithDebug forward",
                    ", name=", fshow(dbgConf.name),
                    ", data=", fshow(innerQ.first)
                );
            end
        endrule
    end
    return toPipeIn(innerQ);
endmodule


module mkPipeInB0ToPipeIn#(PipeInB0#(tData) pipeInNr, Integer bufferDepth)(PipeIn#(tData)) provisos(Bits#(tData, szData), FShow#(tData));

    let inst <- mkPipeInB0ToPipeInWithDebug(pipeInNr, bufferDepth, DebugConf{name:"", enableDebug: False});
    return inst;
endmodule

module mkFifofToPipeInB0#(FIFOF#(tData) fifo)(PipeInB0#(tData)) provisos (Bits#(tData, szData));
    let b0Adapter <- mkPipeInAdapterB0;
    rule forward;
        b0Adapter.deq;
        fifo.enq(b0Adapter.first);
    endrule
    return b0Adapter.pipeInIfc;
endmodule

module mkPipeInToPipeInB0#(PipeIn#(tData) fifo)(PipeInB0#(tData)) provisos (Bits#(tData, szData));
    let b0Adapter <- mkPipeInAdapterB0;
    rule forward;
        b0Adapter.deq;
        fifo.enq(b0Adapter.first);
    endrule
    return b0Adapter.pipeInIfc;
endmodule


// // B1 means Buffer 1,
// interface PipeInB1#(type tData);
//     method Action enq(tData data);
//     method Bool notFull;
// endinterface

// interface PipeInAdapterB1#(type tData);
//     method tData first;
//     method Action deq;
//     method Bool notEmpty;
//     interface PipeInB1#(tData) pipeInIfc;
// endinterface


module mkPipeInAdapterB1(PipeInAdapterB0#(tData)) provisos (Bits#(tData, szData));

    FIFOF#(tData) innerFifo <- mkLFIFOF;

    Wire#(tData) dataWire <- mkWire;
    Wire#(Bool)  notEmptyWire <- mkWire;
    PulseWire deqSignalWire <- mkPulseWire;

    rule doEnq;
        if (notEmptyWire) begin
            innerFifo.enq(dataWire);
            deqSignalWire.send;
        end
    endrule

    method first = innerFifo.first;
    method deq = innerFifo.deq;
    method notEmpty = innerFifo.notEmpty;

    interface PipeInB0 pipeInIfc;
        method Action firstIn(tData dataIn);
            dataWire <= dataIn;
        endmethod
        
        method Action notEmptyIn(Bool val);
            notEmptyWire <= val;
        endmethod

        method Bool deqSignalOut;
            return deqSignalWire;
        endmethod
    endinterface
endmodule

// instance Connectable#(PipeOut#(t), PipeInB1#(t));
//     module mkConnection#(PipeOut#(t) fo, PipeInB1#(t) fi)(Empty);
//         rule handleForward;
//             fi.enq(fo.first);
//             fo.deq;
//         endrule
//     endmodule
// endinstance

// instance Connectable#(PipeInB1#(t), PipeOut#(t));
//     module mkConnection#(PipeInB1#(t) fi, PipeOut#(t) fo)(Empty);
//         mkConnection(fo, fi);
//     endmodule
// endinstance




// B2 means Buffer21,
// interface PipeInB2#(type tData);
//     method Action enq(tData data);
//     method Bool notFull;
// endinterface

// interface PipeInAdapterB2#(type tData);
//     method tData first;
//     method Action deq;
//     method Bool notEmpty;
//     interface PipeInB2#(tData) pipeInIfc;
// endinterface

module mkPipeInAdapterB2(PipeInAdapterB0#(tData)) provisos (Bits#(tData, szData));

    FIFOF#(tData) innerFifo <- mkFIFOF;

    Wire#(tData) dataWire <- mkWire;
    Wire#(Bool)  notEmptyWire <- mkWire;
    PulseWire deqSignalWire <- mkPulseWire;

    rule doEnq;
        if (notEmptyWire) begin
            innerFifo.enq(dataWire);
            deqSignalWire.send;
        end
    endrule

    method first = innerFifo.first;
    method deq = innerFifo.deq;
    method notEmpty = innerFifo.notEmpty;

    interface PipeInB0 pipeInIfc;
        method Action firstIn(tData dataIn);
            dataWire <= dataIn;
        endmethod
        
        method Action notEmptyIn(Bool val);
            notEmptyWire <= val;
        endmethod

        method Bool deqSignalOut;
            return deqSignalWire;
        endmethod
    endinterface
endmodule

// instance Connectable#(PipeOut#(t), PipeInB2#(t));
//     module mkConnection#(PipeOut#(t) fo, PipeInB2#(t) fi)(Empty);
//         rule handleForward;
//             fi.enq(fo.first);
//             fo.deq;
//         endrule
//     endmodule
// endinstance

// instance Connectable#(PipeInB2#(t), PipeOut#(t));
//     module mkConnection#(PipeInB2#(t) fi, PipeOut#(t) fo)(Empty);
//         mkConnection(fo, fi);
//     endmodule
// endinstance

instance ToSendCommit#(PipeOut#(a), a);
   // Assumes fifo has proper implicit conditions
   module mkSendCommit #(PipeOut#(a) p) (SendCommit#(a));
      PulseWire doAck <- mkPulseWire;
      (*fire_when_enabled*)
      rule doDeq (doAck /*&& p.notEmpty*/);
         p.deq;
      endrule
      method a dataout /*if (p.notEmpty)*/;
        return p.first;
      endmethod
      method Action ack = doAck.send;
   endmodule
endinstance


instance ToRecvCommit#(PipeIn#(a), a)
   provisos(Bits#(a,sa));
   // Assumes fifo has proper implicit conditions
   module mkRecvCommit #(PipeIn#(a) p) (RecvCommit#(a));
      RWire#(a) d <- mkRWire;
      (*fire_when_enabled*)
      rule doEnq (/*p.notFull &&& */ d.wget matches tagged Valid .data);
         p.enq(data);
      endrule
      method Action datain (a din);
         d.wset(din);
      endmethod
      method Bool accept = p.notFull;
   endmodule
endinstance