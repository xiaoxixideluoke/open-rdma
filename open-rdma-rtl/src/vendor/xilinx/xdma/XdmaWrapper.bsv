import FIFOF :: *;
import SpecialFIFOs :: *;
import ClientServer :: * ;
import GetPut :: *;
import Clocks :: * ;
import Vector :: *;
import BRAM :: *;

import Settings :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import RdmaHeaders :: *;
import StreamShifterG :: *;

import RdmaUtils :: *;


import PrimUtils :: *;
import ConnectableF :: * ;

import AxiBus :: *;


typedef 1 XDMA_AXIS_TUSER_WIDTH;
typedef Bit#(XDMA_AXIS_TUSER_WIDTH) XdmaAxisTuser;
typedef Bit#(DATA_BUS_BYTE_WIDTH) XdmaAxisTkeep;
typedef AxiStream#(DATA, XdmaAxisTkeep, XdmaAxisTuser) XdmaAxiStream;


typedef Bit#(64) XdmaDescBypAddr;
typedef Bit#(28) XdmaDescBypLength;
typedef struct {
    Bool eop;
    Bit#(2) _rsv;
    Bool completed;
    Bool stop;
} XdmaDescBypCtl deriving(Bits);


typedef struct {
    Bit#(1) _rsv;
    Bool running;
    Bool irqPending;
    Bool packetDone;
    Bool descDone;
    Bool descStop;
    Bool descCplt;
    Bool busy;
} XdmaChannelStatus deriving(Bits);

(* always_ready, always_enabled *)
interface XdmaDescriptorBypass;
    (* prefix = "" *)     method Action ready((* port = "ready" *) Bool rdy);
    (* result = "load" *) method Bool   load;
    (* result = "src_addr" *) method XdmaDescBypAddr  srcAddr;
    (* result = "dst_addr" *) method XdmaDescBypAddr  dstAddr;
    (* result = "len" *) method XdmaDescBypLength  len;
    (* result = "ctl" *) method XdmaDescBypCtl  ctl;
    (* prefix = "" *) method Action descDone((* port = "desc_done" *) Bool done) ;
endinterface

interface XdmaChannel#(type tData, type tKeep, type tUser);
    interface RawAxiStreamSlave#(tData, tKeep, tUser) rawH2cAxiStream;
    interface RawAxiStreamMaster#(tData, tKeep, tUser) rawC2hAxiStream;
    interface XdmaDescriptorBypass h2cDescByp;
    interface XdmaDescriptorBypass c2hDescByp;
endinterface

interface XdmaWrapper#(type tData, type tKeep, type tUser);
    interface IoChannelMemorySlavePipeB0In   dmaSlavePipeIfc;
    interface XdmaChannel#(tData, tKeep, tUser) xdmaChannel;
endinterface

(* synthesize *)
module mkXdmaWrapper(XdmaWrapper#(DATA, XdmaAxisTkeep, XdmaAxisTuser));

    FIFOF#(AxiStream#(DATA, XdmaAxisTkeep, XdmaAxisTuser)) xdmaH2cStFifo <- mkFIFOF;
    let rawH2cSt <- mkPipeInToRawAxiStreamSlave(toPipeIn(xdmaH2cStFifo));

    FIFOF#(AxiStream#(DATA, XdmaAxisTkeep, XdmaAxisTuser)) xdmaC2hStFifo <- mkFIFOF;
    let rawC2hSt <- mkPipeOutToRawAxiStreamMaster(toPipeOut(xdmaC2hStFifo));


    PipeInAdapterB0#(IoChannelMemoryAccessMeta)         dmaWriteMetaPipeInQueue   <- mkPipeInAdapterB0;
    // PipeInAdapterB0#(IoChannelMemoryAccessDataStream)   dmaWriteDataPipeInQueue   <- mkPipeInAdapterB0;
    PipeInAdapterB0#(IoChannelMemoryAccessMeta)         dmaReadMetaPipeInQueue    <- mkPipeInAdapterB0;
    // FIFOF#(IoChannelMemoryAccessDataStream)             dmaReadDataPipeOutQueue   <- mkFIFOF;

    Wire#(Bool) h2cDescBypRdyWire <- mkBypassWire;
    Reg#(Bool) h2cNextBeatIsFirstReg <- mkReg(True);

    Wire#(Bool) c2hDescBypRdyWire   <- mkBypassWire;
    Wire#(Bool) c2hDescBypDoneWire  <- mkBypassWire;
    
    Bool h2cDescHandshakeWillSuccess = h2cDescBypRdyWire && dmaReadMetaPipeInQueue.notEmpty;

    Wire#(IoChannelMemoryAccessMeta) c2hMetaWire <- mkDWire(unpack(0));
    Wire#(IoChannelMemoryAccessMeta) h2cMetaWire <- mkDWire(unpack(0));

    UniDirStreamShifter#(DATA) rightShifter    <- mkLsbRightStreamRightShifterG;
    UniDirStreamShifter#(DATA) leftShifter     <- mkLsbRightStreamLeftShifterG;

    let rightShifterOffsetPipeInConverter <- mkPipeInB0ToPipeIn(rightShifter.offsetPipeIn, 64);
    let leftShifterOffsetPipeInConverter <- mkPipeInB0ToPipeIn(leftShifter.offsetPipeIn, 64);
    // let rightShifterStreamPipeInConverter <- mkPipeInB0ToPipeIn(rightShifter.streamPipeIn, 1);
    let leftShifterStreamPipeInConverter <- mkPipeInB0ToPipeIn(leftShifter.streamPipeIn, 1);

    rule forwardH2cDesc;
        h2cMetaWire <= dmaReadMetaPipeInQueue.first;
        if (h2cDescHandshakeWillSuccess) begin
            dmaReadMetaPipeInQueue.deq;
            ByteIdxInDword addrOffsetInDword = truncate(dmaReadMetaPipeInQueue.first.addr);
            leftShifterOffsetPipeInConverter.enq(zeroExtend(addrOffsetInDword));
        end
    endrule

    rule forawrdH2cData;
        let newData = xdmaH2cStFifo.first;
        xdmaH2cStFifo.deq;
        leftShifterStreamPipeInConverter.enq(IoChannelMemoryAccessDataStream{
            data: unpack(pack(newData.axisData)),
            startByteIdx: 0,
            byteNum: newData.axisLast ? unpack(pack(countZerosLSB(~newData.axisKeep))) : fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)),
            isFirst: h2cNextBeatIsFirstReg,
            isLast: newData.axisLast
        });

        h2cNextBeatIsFirstReg <= newData.axisLast;
    endrule

    Bool c2hDescHandshakeWillSuccess = c2hDescBypRdyWire && dmaWriteMetaPipeInQueue.notEmpty;

    rule forwardC2hDesc;
        c2hMetaWire <= dmaWriteMetaPipeInQueue.first;
        if (c2hDescHandshakeWillSuccess) begin
            dmaWriteMetaPipeInQueue.deq;
            ByteIdxInDword addrOffsetInDword = truncate(dmaWriteMetaPipeInQueue.first.addr);
            rightShifterOffsetPipeInConverter.enq(zeroExtend(addrOffsetInDword));
        end
    endrule

    rule forwardC2hData;
        rightShifter.streamPipeOut.deq;
        let ds = rightShifter.streamPipeOut.first;
        xdmaC2hStFifo.enq(
            AxiStream {
                axisData: unpack(pack(ds.data)),
                axisKeep: ds.isLast ? (1 << ds.byteNum) - 1 : maxBound,
                axisUser: ?,
                axisLast: ds.isLast
            }
        );
    endrule


    interface DtldStreamBiDirSlavePipesB0In dmaSlavePipeIfc;
        interface DtldStreamSlaveWritePipesB0In writePipeIfc;
            interface  writeMetaPipeIn  = toPipeInB0(dmaWriteMetaPipeInQueue);
            interface  writeDataPipeIn  = rightShifter.streamPipeIn;
        endinterface

        interface DtldStreamSlaveReadPipesB0In readPipeIfc;
            interface  readMetaPipeIn  = toPipeInB0(dmaReadMetaPipeInQueue);
            interface  readDataPipeOut = leftShifter.streamPipeOut;
        endinterface
    endinterface

    interface XdmaChannel xdmaChannel;

        interface rawH2cAxiStream = rawH2cSt;
        interface rawC2hAxiStream = rawC2hSt;

        interface XdmaDescriptorBypass h2cDescByp;

            method Action ready(Bool rdy);
                h2cDescBypRdyWire <= rdy;
            endmethod

            method Bool load;
                return h2cDescHandshakeWillSuccess;
            endmethod

            method XdmaDescBypAddr  srcAddr;
                return h2cMetaWire.addr;
            endmethod

            method XdmaDescBypAddr  dstAddr;
                return 0;
            endmethod

            method XdmaDescBypLength len;
                return truncate(h2cMetaWire.totalLen);
            endmethod

            method XdmaDescBypCtl ctl;
                return XdmaDescBypCtl {
                    eop: True,
                    _rsv: 0,
                    completed: False,
                    stop: False
                };
            endmethod

            method Action descDone(Bool done);
            endmethod
        endinterface

        interface XdmaDescriptorBypass c2hDescByp;

            method Action ready(Bool rdy);
                c2hDescBypRdyWire <= rdy;
            endmethod

            method Bool load;
                return c2hDescHandshakeWillSuccess;
            endmethod

            method XdmaDescBypAddr  srcAddr;
                return 0;
            endmethod

            method XdmaDescBypAddr  dstAddr;
                return c2hMetaWire.addr;
            endmethod

            
            method XdmaDescBypLength  len;
                return truncate(c2hMetaWire.totalLen);
            endmethod

            method XdmaDescBypCtl  ctl;
                return XdmaDescBypCtl {
                    eop: True,
                    _rsv: 0,
                    completed: False,
                    stop: False
                };
            endmethod

            method Action descDone(Bool done);
                c2hDescBypDoneWire <= done;
            endmethod
        endinterface

    endinterface
endmodule


typedef Bit#(NUMERIC_TYPE_FOUR) XdmaAxiLiteStrb;
typedef Dword                   XdmaAxiLiteData;

interface XdmaAxiLiteBridgeWrapper;
    interface RawAxi4LiteSlave#(ADDR, XdmaAxiLiteData, XdmaAxiLiteStrb) cntrlAxil;
    interface IoChannelMemoryMasterPipe dmaMasterPipeIfc;
endinterface 

module mkXdmaAxiLiteBridgeWrapper(XdmaAxiLiteBridgeWrapper);

    FIFOF#(Axi4LiteWrAddr#(ADDR)) cntrlWrAddrFifo <- mkFIFOF;
    FIFOF#(Axi4LiteWrData#(XdmaAxiLiteData, XdmaAxiLiteStrb)) cntrlWrDataFifo <- mkFIFOF;
    FIFOF#(Axi4LiteWrResp) cntrlWrRespFifo <- mkFIFOF;
    FIFOF#(Axi4LiteRdAddr#(ADDR)) cntrlRdAddrFifo <- mkFIFOF;
    FIFOF#(Axi4LiteRdData#(XdmaAxiLiteData)) cntrlRdDataFifo <- mkFIFOF;




    FIFOF#(IoChannelMemoryAccessMeta) writeMetaPipeOutQueue <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream) writeDataPipeOutQueue <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessMeta) readMetaPipeOutQueue <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream) readDataPipeInQueue <- mkFIFOF;

    let cntrlAxilSlave <- mkRawAxi4LiteSlave(
        toPipeIn(cntrlWrAddrFifo),
        toPipeIn(cntrlWrDataFifo),
        toPipeOut(cntrlWrRespFifo),

        toPipeIn(cntrlRdAddrFifo),
        toPipeOut(cntrlRdDataFifo)
    );

    rule handleRead;
        cntrlRdAddrFifo.deq;
        readMetaPipeOutQueue.enq(IoChannelMemoryAccessMeta {
            addr: unpack(zeroExtend(cntrlRdAddrFifo.first.arAddr)),
            totalLen: fromInteger(valueOf(SizeOf#(XdmaAxiLiteStrb)))
        });
    endrule

    rule forwardReadResp;
        readDataPipeInQueue.deq;
        cntrlRdDataFifo.enq(Axi4LiteRdData{rResp: 0, rData: unpack(truncate(pack(readDataPipeInQueue.first.data)))});
    endrule

    rule handleWrite;
        cntrlWrAddrFifo.deq;
        cntrlWrDataFifo.deq;
        writeMetaPipeOutQueue.enq(IoChannelMemoryAccessMeta{
            addr: unpack(cntrlWrAddrFifo.first.awAddr),
            totalLen: 4});
        writeDataPipeOutQueue.enq(IoChannelMemoryAccessDataStream{
            data: unpack(zeroExtend(cntrlWrDataFifo.first.wData)),
            startByteIdx: 0,
            byteNum: fromInteger(valueOf(SizeOf#(XdmaAxiLiteStrb))),
            isFirst: True,
            isLast: True
        });
        cntrlWrRespFifo.enq(0);
    endrule

    interface cntrlAxil = cntrlAxilSlave;

    interface DtldStreamBiDirMasterPipes dmaMasterPipeIfc;
        interface DtldStreamMasterWritePipes writePipeIfc;
            interface  writeMetaPipeOut  = toPipeOut(writeMetaPipeOutQueue);
            interface  writeDataPipeOut  = toPipeOut(writeDataPipeOutQueue);
        endinterface

        interface DtldStreamMasterReadPipes readPipeIfc;
            interface  readMetaPipeOut  = toPipeOut(readMetaPipeOutQueue);
            interface  readDataPipeIn   = toPipeIn(readDataPipeInQueue);
        endinterface
    endinterface
endmodule
