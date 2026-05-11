import Vector :: *;
import FIFOF :: *;
import PrimUtils :: *;
import Arbiter :: *;

import ConnectableF :: *;
import BasicDataTypes :: *;

// Common ==================
typedef 8 AXI_AXLEN_WIDTH;
typedef Bit#(AXI_AXLEN_WIDTH) AxiAxlen;


// AW channel ==============
typedef 8 AXI_AWID_WIDTH;
typedef Bit#(AXI_AWID_WIDTH) AxiAwid;

typedef 64 AXI_AWADDR_WIDTH;
typedef Bit#(AXI_AWADDR_WIDTH) AxiAwaddr;

typedef AXI_AXLEN_WIDTH AXI_AWLEN_WIDTH;
typedef Bit#(AXI_AWLEN_WIDTH) AxiAwlen;

typedef 3 AXI_AWSIZE_WIDTH;
typedef Bit#(AXI_AWSIZE_WIDTH) AxiAwsize;

typedef 2 AXI_AWBURST_WIDTH;
typedef Bit#(AXI_AWBURST_WIDTH) AxiAwburst;

typedef 4 AXI_AWQOS_WIDTH;
typedef Bit#(AXI_AWQOS_WIDTH) AxiAwqos;

typedef 3 AXI_PROT_WIDTH;
typedef Bit#(AXI_PROT_WIDTH) AxiProt;

// W channel ==============
    // defined in common part above.

// B channel ==============
typedef 8 AXI_BID_WIDTH;
typedef Bit#(AXI_BID_WIDTH) AxiBid;

typedef 2 AXI_BRESP_WIDTH;
typedef Bit#(AXI_BRESP_WIDTH) AxiBresp;

// AR channel ==============
typedef 8 AXI_ARID_WIDTH;
typedef Bit#(AXI_ARID_WIDTH) AxiArid;

typedef 64 AXI_ARADDR_WIDTH;
typedef Bit#(AXI_ARADDR_WIDTH) AxiAraddr;

typedef AXI_AXLEN_WIDTH AXI_ARLEN_WIDTH;
typedef Bit#(AXI_ARLEN_WIDTH) AxiArlen;

typedef 3 AXI_ARSIZE_WIDTH;
typedef Bit#(AXI_ARSIZE_WIDTH) AxiArsize;

typedef 2 AXI_ARBURST_WIDTH;
typedef Bit#(AXI_ARBURST_WIDTH) AxiArburst;

typedef 4 AXI_ARQOS_WIDTH;
typedef Bit#(AXI_ARQOS_WIDTH) AxiArqos;

// R channel ==============
typedef 8 AXI_RID_WIDTH;
typedef Bit#(AXI_RID_WIDTH) AxiRid;

typedef 2 AXI_RRESP_WIDTH;
typedef Bit#(AXI_RRESP_WIDTH) AxiRresp;

typedef enum {
    AxiSize1B   = 0,
    AxiSize2B   = 1,
    AxiSize4B   = 2,
    AxiSize8B   = 3,
    AxiSize16B  = 4,
    AxiSize32B  = 5,
    AxiSize64B  = 6,
    AxiSize128B = 7
} AxiSize deriving(Bits, FShow, Eq);

typedef enum {
    AxiBurstFixed  = 0,
    AxiBurstIncr   = 1,
    AxiBurstWrap   = 2
} AxiBurst deriving(Bits, FShow, Eq);

typedef struct {
    AxiAwid awid;
    AxiAwaddr awaddr;
    AxiAwlen awlen;
    AxiAwsize awsize;
    AxiAwburst awburst;
    Bool awlock;  
    AxiAwqos awqos;
} AxiMmBeatAw deriving(Bits, FShow);

typedef struct {
    tAxiWdata wdata;
    Bit#(TDiv#(SizeOf#(tAxiWdata), BYTE_WIDTH)) wstrb;
    Bool wlast;
} AxiMmBeatW#(type tAxiWdata) deriving(Bits, FShow);

typedef struct {
    AxiBid bid;
    AxiBresp bresp;
} AxiMmBeatB deriving(Bits, FShow);

typedef struct {
    AxiArid arid;
    AxiAraddr araddr;
    AxiArlen arlen;
    AxiArsize arsize;
    AxiArburst arburst;
    Bool arlock;
    AxiArqos arqos;
} AxiMmBeatAr deriving(Bits, FShow);

typedef struct {
    AxiRid rid;
    tAxiRdata rdata;
    AxiRresp rresp;
    Bool rlast;
} AxiMmBeatR#(type tAxiRdata) deriving(Bits, FShow);



interface AxiMasterWritePipes#(type tAxiWdata);
    interface PipeOut#(AxiMmBeatAw)              writeAddrPipeOut;
    interface PipeOut#(AxiMmBeatW#(tAxiWdata))   writeDataPipeOut;
    interface PipeIn#(AxiMmBeatB)                writeRespPipeIn;
endinterface

interface AxiMasterReadPipes#(type tAxiRdata);
    interface PipeOut#(AxiMmBeatAr)              readAddrPipeOut;
    interface PipeIn#(AxiMmBeatR#(tAxiRdata))    readRespPipeIn;
endinterface

interface AxiMasterPipes#(type tAxiData);
    interface AxiMasterWritePipes#(tAxiData)  writePipeIfc;
    interface AxiMasterReadPipes#(tAxiData)   readPipeIfc;
endinterface


interface AxiSlaveWritePipes#(type tAxiWdata);
    interface PipeIn#(AxiMmBeatAw)              writeAddrPipeIn;
    interface PipeIn#(AxiMmBeatW#(tAxiWdata))   writeDataPipeIn;
    interface PipeOut#(AxiMmBeatB)              writeRespPipeOut;
endinterface

interface AxiSlaveReadPipes#(type tAxiRdata);
    interface PipeIn#(AxiMmBeatAr)              readAddrPipeIn;
    interface PipeOut#(AxiMmBeatR#(tAxiRdata))  readRespPipeOut;
endinterface

interface AxiSlavePipes#(type tAxiData);
    interface AxiSlaveWritePipes#(tAxiData)  writePipeIfc;
    interface AxiSlaveReadPipes#(tAxiData)   readPipeIfc;
endinterface


// AXI stream

(* always_ready, always_enabled *)
interface AxiRawBusMaster#(type tRawData);
    (* result = "data" *) method tRawData  data;
    (* result = "valid"*) method Bool       valid;
    (* prefix = "" *) method Action ready((* port = "ready" *) Bool rdy);
endinterface

(* always_ready, always_enabled *)
interface AxiRawBusSlave#(type tRawData);
    (* prefix = "" *) method Action validData(
        (* port = "valid"   *) Bool     valid,
        (* port = "data"    *) tRawData data
    );
    (* result = "ready" *) method Bool ready;
endinterface


module mkPipeOutToRawBusMaster#(PipeOut#(tRawData) pipe)(AxiRawBusMaster#(tRawData)) provisos(Bits#(tRawData, dSz));
    RWire#(tRawData) dataW <- mkRWire;
    Wire#(Bool) readyW <- mkBypassWire;

    rule passWire if (pipe.notEmpty);
        dataW.wset(pipe.first);
    endrule

    rule passReady if (pipe.notEmpty && readyW);
        pipe.deq;
    endrule

    method Bool valid = pipe.notEmpty;
    method tRawData data = fromMaybe(?, dataW.wget);
    method Action ready(Bool rdy);
        readyW <= rdy;
    endmethod
endmodule

// Note: the output ready signal is valid during reset
module mkPipeInToRawBusSlave#(PipeIn#(tRawData) pipe)(AxiRawBusSlave#(tRawData)) provisos(Bits#(tRawData, dSz));
    Wire#(Bool)  validW <- mkBypassWire;
    Wire#(tRawData) dataW <- mkBypassWire;

    rule passData if (validW);
        pipe.enq(dataW);
    endrule

    method Action validData(Bool valid, tRawData data);
        validW <= valid;
        dataW <= data;
    endmethod
    method Bool ready = pipe.notFull;
endmodule




function RawAxiStreamMaster#(tData, tKeep, tUser) convertRawBusToRawAxiStreamMaster(
        AxiRawBusMaster#(AxiStream#(tData, tKeep, tUser)) rawBus
    ) provisos (Bits#(tData, szData));
    return (
        interface RawAxiStreamMaster;
            method Bool axisValid = rawBus.valid;
            method tData axisData = rawBus.data.axisData;
            method tKeep axisKeep = rawBus.data.axisKeep;
            method Bool axisLast = rawBus.data.axisLast;
            method tUser axisUser = rawBus.data.axisUser;
            method Action axisReady(Bool rdy);
                rawBus.ready(rdy);
            endmethod
        endinterface
    );
endfunction

function RawAxiStreamSlave#(tData, tKeep, tUser) convertRawBusToRawAxiStreamSlave(
        AxiRawBusSlave#(AxiStream#(tData, tKeep, tUser)) rawBus
    ) provisos (Bits#(tData, szData));
    return (
        interface RawAxiStreamSlave;
            method Bool axisReady = rawBus.ready;
            method Action axisValid(
                Bool valid, 
                tData axisData, 
                tKeep axisKeep, 
                Bool axisLast, 
                tUser axisUser
            );
                AxiStream#(tData, tKeep, tUser) axiStream = AxiStream {
                    axisData: axisData,
                    axisKeep: axisKeep,
                    axisLast: axisLast,
                    axisUser: axisUser
                };
                rawBus.validData(valid, axiStream);
            endmethod
        endinterface
    );
endfunction





typedef struct {
    tData                                   axisData;
    tKeep                                   axisKeep;
    Bool                                    axisLast;
    tUser                                   axisUser;
} AxiStream#(type tData, type tKeep, type tUser) deriving(Bits, FShow, Eq, Bounded);

(*always_ready, always_enabled*)
interface RawAxiStreamMaster#(type tData, type tKeep, type tUser);
    (* result = "tvalid" *) method Bool                                     axisValid;
    (* result = "tdata"  *) method tData                                    axisData;
    (* result = "tkeep"  *) method tKeep                                    axisKeep;
    (* result = "tlast"  *) method Bool                                     axisLast;
    (* result = "tuser"  *) method tUser                                    axisUser;
    (* always_enabled, prefix = "" *) method Action axisReady((* port="tready" *) Bool ready);
endinterface

(* always_ready, always_enabled *)
interface RawAxiStreamSlave#(type tData, type tKeep, type tUser);
   (* prefix = "" *)
   method Action axisValid (
        (* port="tvalid" *) Bool                                    axisValid,
		(* port="tdata"  *) tData                                   axisData,
		(* port="tkeep"  *) tKeep                                   axisKeep,
		(* port="tlast"  *) Bool                                    axisLast,
        (* port="tuser"  *) tUser                                   axisUser
    );
   (* result="tready" *) method Bool    axisReady;
endinterface


module mkPipeOutToRawAxiStreamMaster#(
        PipeOut#(AxiStream#(tData, tKeep, tUser)) pipe
    )(RawAxiStreamMaster#(tData, tKeep, tUser)) provisos (
        Bits#(tData, szData),
        Bits#(tKeep, szKeep),
        Bits#(tUser, szUser)
    );

    let rawBus <- mkPipeOutToRawBusMaster(pipe);
    return convertRawBusToRawAxiStreamMaster(rawBus);
endmodule


module mkPipeInToRawAxiStreamSlave#(
        PipeIn#(AxiStream#(tData, tKeep, tUser)) pipe
    )(RawAxiStreamSlave#(tData, tKeep, tUser)) provisos (
        Bits#(tData, szData),
        Bits#(tUser, szUser),
        Bits#(tKeep, szKeep)
    );

    let rawBus <- mkPipeInToRawBusSlave(pipe);
    return convertRawBusToRawAxiStreamSlave(rawBus);
endmodule



// Write Address channel
typedef struct {
    tAddr       awAddr;
    AxiProt     awProt;
} Axi4LiteWrAddr#(type tAddr) deriving(Bits, FShow);

// Write Data channel
typedef struct {
    tData       wData;
    tStrb       wStrb;
} Axi4LiteWrData#(type tData, type tStrb) deriving(Bits, FShow);

// Write Response channel
typedef AxiBresp Axi4LiteWrResp;

// Read Address channel
typedef struct {
    tAddr       arAddr;
    AxiProt     arProt;
} Axi4LiteRdAddr#(type tAddr) deriving(Bits, FShow);

// Read Data channel
typedef struct {
    AxiBresp    rResp;
    tData       rData;
} Axi4LiteRdData#(type tData) deriving(Bits, FShow);



(* always_ready, always_enabled *)
interface RawAxi4LiteWrSlave#(type tAddr, type tData, type tStrb);
    // Wr Addr channel
    (* prefix = "" *)
    method Action awValidData(
         (* port = "awvalid"*) Bool                  awValid, // in
         (* port = "awaddr" *) tAddr                 awAddr,  // in
         (* port = "awprot" *) AxiProt               awProt   // in
     );
    (* result = "awready" *) method Bool awReady; // out
 
    // Wr Data channel
    (* prefix = "" *)
    method Action wValidData(
         (* port = "wvalid"*) Bool    wValid, // in
         (* port = "wdata" *) tData   wData,  // in
         (* port = "wstrb" *) tStrb   wStrb
     );
    (* result = "wready" *) method Bool wReady;
 
    // Wr Response channel
    (* result = "bvalid"*) method Bool                  bValid;    // out
    (* result = "bresp" *) method AxiBresp              bResp;     // out
    (* prefix = "" *) method Action bReady((* port = "bready" *) Bool rdy); // in
 endinterface
 
 (* always_ready, always_enabled *)
 interface RawAxi4LiteRdSlave#(type tAddr, type tData, type tStrb);
    // Rd Addr channel
    (* prefix = "" *)
    method Action arValidData(
         (* port = "arvalid"*) Bool                  arValid, // in
         (* port = "araddr" *) tAddr                 arAddr,  // in
         (* port = "arprot" *) AxiProt               arProt   // in
     );
    (* result = "arready" *) method Bool arReady; // out
 
    // Rd Data channel
    (* result = "rvalid"*) method Bool          rValid; // out
    (* result = "rresp" *) method AxiBresp      rResp;  // out
    (* result = "rdata" *) method tData         rData;  // out
    (* prefix = "" *) method Action rReady((* port = "rready" *) Bool rdy);         // in
 endinterface
 
 
 interface RawAxi4LiteSlave#(type tAddr, type tData, type tStrb);
     (* prefix = "" *) interface RawAxi4LiteWrSlave#(tAddr, tData, tStrb) wrSlave;
     (* prefix = "" *) interface RawAxi4LiteRdSlave#(tAddr, tData, tStrb) rdSlave;
 endinterface
 


 module mkRawAxi4LiteSlave#(
        PipeIn#(Axi4LiteWrAddr#(tAddr)) wrAddr,
        PipeIn#(Axi4LiteWrData#(tData, tStrb)) wrData,
        PipeOut#(AxiBresp) wrResp,

        PipeIn#(Axi4LiteRdAddr#(tAddr)) rdAddr,
        PipeOut#(Axi4LiteRdData#(tData)) rdData
    )(RawAxi4LiteSlave#(tAddr, tData, tStrb)) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tData, szData),
        Bits#(tStrb, szStrb)
    );
    let rawWrAddrBus <- mkPipeInToRawBusSlave(wrAddr);
    let rawWrDataBus <- mkPipeInToRawBusSlave(wrData);
    let rawWrRespBus <- mkPipeOutToRawBusMaster(wrResp);

    let rawRdAddrBus <- mkPipeInToRawBusSlave(rdAddr);
    let rawRdDataBus <- mkPipeOutToRawBusMaster(rdData);

    interface wrSlave = parseRawBusToRawAxi4LiteWrSlave(rawWrAddrBus, rawWrDataBus, rawWrRespBus);
    interface rdSlave = parseRawBusToRawAxi4LiteRdSlave(rawRdAddrBus, rawRdDataBus);
endmodule



function RawAxi4LiteWrSlave#(tAddr, tData, tStrb) parseRawBusToRawAxi4LiteWrSlave(
        AxiRawBusSlave#(Axi4LiteWrAddr#(tAddr)) rawWrAddrBus,
        AxiRawBusSlave#(Axi4LiteWrData#(tData, tStrb)) rawWrDataBus,
        AxiRawBusMaster#(Axi4LiteWrResp) rawWrRespBus
    ) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tData, szData),
        Bits#(tStrb, szStrb)
    );
    return (
        interface RawAxi4LiteWrSlave;
            // Wr Addr channel
            method Action awValidData(
                Bool awValid, 
                tAddr awAddr, 
                AxiProt awProt
            );
                Axi4LiteWrAddr#(tAddr) wrAddr = Axi4LiteWrAddr {
                    awAddr: awAddr,
                    awProt: awProt
                };
                rawWrAddrBus.validData(awValid, wrAddr);
            endmethod
            method Bool awReady = rawWrAddrBus.ready;

            // Wr Data channel
            method Action wValidData(
                Bool wValid, 
                tData wData, 
                tStrb wStrb
            );
                Axi4LiteWrData#(tData, tStrb) wrData = Axi4LiteWrData {
                    wData: wData,
                    wStrb: wStrb
                };
                rawWrDataBus.validData(wValid, wrData);
            endmethod
            method Bool wReady = rawWrDataBus.ready;

            // Wr Response channel
            method Bool                  bValid = rawWrRespBus.valid;
            method AxiBresp              bResp  = rawWrRespBus.data;
            method Action bReady(Bool rdy);
                rawWrRespBus.ready(rdy);
            endmethod
        endinterface
    );
endfunction

function RawAxi4LiteRdSlave#(tAddr, tData, tStrb) parseRawBusToRawAxi4LiteRdSlave(
        AxiRawBusSlave#(Axi4LiteRdAddr#(tAddr)) rawRdAddrBus,
        AxiRawBusMaster#(Axi4LiteRdData#(tData)) rawRdDataBus
    ) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tData, szData),
        Bits#(tStrb, szStrb)
    );
    return (
        interface RawAxi4LiteRdSlave;
            // Rd Addr channel
            method Action arValidData(
                Bool arValid, 
                tAddr arAddr, 
                AxiProt arProt
            );
                Axi4LiteRdAddr#(tAddr) rdAddr = Axi4LiteRdAddr {
                    arAddr: arAddr,
                    arProt: arProt
                };
                rawRdAddrBus.validData(arValid, rdAddr);
            endmethod
            method Bool arReady = rawRdAddrBus.ready;

            // Rd Data channel
            method Bool                               rValid = rawRdDataBus.valid;
            method AxiBresp                           rResp  = rawRdDataBus.data.rResp;
            method tData                              rData  = rawRdDataBus.data.rData;
            method Action rReady(Bool rdy);
                rawRdDataBus.ready(rdy);
            endmethod
        endinterface
    );
endfunction