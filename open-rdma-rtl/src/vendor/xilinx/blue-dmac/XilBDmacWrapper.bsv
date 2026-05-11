import Vector :: *;
import FIFOF :: *;

import SemiFifo::*;

import XilBdmaPcieTypes :: *;
import XilBdmaDmaTypes :: *;
import XilBdmaDmaWrapper :: *;
import XilBdmaPrimUtils :: *;

import BasicDataTypes :: *;
import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;
import RdmaHeaders :: *;

import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import StreamShifterG :: *;



interface XilBdmacWrapper;
    // to hardware IP
    (* prefix = "" *)       interface   RawXilinxPcieIp         rawPcie;
    (* prefix = "" *)       method      TlpSizeCfg              tlpSizeDebugPort;
    (* prefix = "" *)       method      Bool                    sys_reset;

    // to UserLogic DMA Channel
    interface Vector#(NUMERIC_TYPE_TWO, IoChannelMemorySlavePipeB0In)   dmaSlavePipeIfcVec;

    // to Userlogic CSR Access
    interface IoChannelMemoryMasterPipe dmaMasterPipeIfc;
endinterface

(* synthesize *)
module mkXilBdmacWrapper(XilBdmacWrapper);
    DmaController innerDmac       <- mkDmaController;

    FIFOF#(IoChannelMemoryAccessMeta)        csrWriteMetaPipeOutQueue    <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream)  csrWriteDataPipeOutQueue    <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessMeta)        csrReadMetaPipeOutQueue     <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream)  csrReadDataPipeInQueue      <- mkFIFOF;

    Vector#(NUMERIC_TYPE_TWO, PipeInAdapterB0#(IoChannelMemoryAccessMeta))         dmaWriteMetaPipeInQueueVec   <- replicateM(mkPipeInAdapterB2);
    Vector#(NUMERIC_TYPE_TWO, PipeInAdapterB0#(IoChannelMemoryAccessMeta))         dmaReadMetaPipeInQueueVec    <- replicateM(mkPipeInAdapterB2);

    Vector#(NUMERIC_TYPE_TWO, PipeIn#(Bit#(TLog#(TDiv#(SizeOf#(DATA), BYTE_WIDTH))))) rightShifterOffsetPipeInConverterVec = newVector;
    Vector#(NUMERIC_TYPE_TWO, PipeIn#(Bit#(TLog#(TDiv#(SizeOf#(DATA), BYTE_WIDTH))))) leftShifterOffsetPipeInConverterVec = newVector;
    Vector#(NUMERIC_TYPE_TWO, PipeIn#(StreamDataTypes::DataStream)) leftShifterStreamPipeInConverterVec = newVector;

    Vector#(NUMERIC_TYPE_TWO, IoChannelMemorySlavePipeB0In)   dmaSlavePipeIfcVecInst;

    FIFOF#(DmaCsrAddr) csrReadRespKeepOrderQueue <- mkFIFOF;

    Vector#(NUMERIC_TYPE_TWO, UniDirStreamShifter#(DATA)) rightShifterVec    <- replicateM(mkLsbRightStreamRightShifterG);
    Vector#(NUMERIC_TYPE_TWO, UniDirStreamShifter#(DATA)) leftShifterVec     <- replicateM(mkLsbRightStreamLeftShifterG);

    Reg#(Bit#(16)) sysResetCounterReg <- mkReg(0);

    for (Integer channelIdx = 0; channelIdx < valueOf(NUMERIC_TYPE_TWO); channelIdx = channelIdx + 1) begin

        rightShifterOffsetPipeInConverterVec[channelIdx] <- mkPipeInB0ToPipeIn(rightShifterVec[channelIdx].offsetPipeIn, 64);
        leftShifterOffsetPipeInConverterVec[channelIdx] <- mkPipeInB0ToPipeIn(leftShifterVec[channelIdx].offsetPipeIn, 64);
        leftShifterStreamPipeInConverterVec[channelIdx] <- mkPipeInB0ToPipeIn(leftShifterVec[channelIdx].streamPipeIn, 2);

        rule forwardDmaReadWriteMeta;
            // Write has high priority
            if (dmaWriteMetaPipeInQueueVec[channelIdx].notEmpty) begin
                dmaWriteMetaPipeInQueueVec[channelIdx].deq;
                let req = dmaWriteMetaPipeInQueueVec[channelIdx].first;

                ByteIdxInDword addrOffsetInDword = truncate(req.addr);
                rightShifterOffsetPipeInConverterVec[channelIdx].enq(zeroExtend(addrOffsetInDword));
                
                let writeReq = DmaRequest{
                    startAddr:unpack(req.addr),
                    length: unpack(req.totalLen),
                    isWrite: True,
                    attr: unpack(0)
                };
                innerDmac.c2hReqFifoIn[channelIdx].enq(writeReq);
                $display(
                    "time=%0t:", $time, toGreen(" mkXilBdmacWrapper forwardDmaReadWriteMeta channel[%0d] Write"), channelIdx,
                    toBlue(", writeReq="), fshow(writeReq)
                );
            end
            else begin
                dmaReadMetaPipeInQueueVec[channelIdx].deq;
                let req = dmaReadMetaPipeInQueueVec[channelIdx].first;

                ByteIdxInDword addrOffsetInDword = truncate(req.addr);
                leftShifterOffsetPipeInConverterVec[channelIdx].enq(zeroExtend(addrOffsetInDword));

                let readReq = DmaRequest{
                    startAddr:unpack(req.addr),
                    length: unpack(req.totalLen),
                    isWrite: False,
                    attr: unpack(0)
                };
                innerDmac.c2hReqFifoIn[channelIdx].enq(readReq);

                $display(
                    "time=%0t:", $time, toGreen(" mkXilBdmacWrapper forwardDmaReadWriteMeta channel[%0d] Read"), channelIdx,
                    toBlue(", readReq="), fshow(readReq)
                );
            end
        endrule

        rule forwardDmaWriteData;
            rightShifterVec[channelIdx].streamPipeOut.deq;
            let ds = rightShifterVec[channelIdx].streamPipeOut.first;

            let dsDma = XilBdmaDmaTypes::DataStream {
                data    : ds.data,
                byteEn  : convertBytePtr2ByteEn(truncate(ds.byteNum)),
                isFirst: ds.isFirst,
                isLast: ds.isLast
            };
            innerDmac.c2hDataFifoIn[channelIdx].enq(dsDma);


            $display(
                "time=%0t:", $time, toGreen(" mkXilBdmacWrapper forwardDmaWriteData channel[%0d]"), channelIdx,
                toBlue(", ds="), fshow(ds)
            );
        endrule



        rule forwardDmaReadResp;
            innerDmac.c2hDataFifoOut[channelIdx].deq;
            let ds = innerDmac.c2hDataFifoOut[channelIdx].first;
            leftShifterStreamPipeInConverterVec[channelIdx].enq(IoChannelMemoryAccessDataStream{
                data: unpack(pack(ds.data)),
                startByteIdx: 0,
                byteNum: unpack(pack(convertByteEn2BytePtr(ds.byteEn))),
                isFirst: ds.isFirst,
                isLast: ds.isLast
            });

            $display(
                "time=%0t:", $time, toGreen(" mkXilBdmacWrapper forwardDmaReadResp channel[%0d]"), channelIdx,
                toBlue(", ds="), fshow(ds)
            );
        endrule

        

        dmaSlavePipeIfcVecInst[channelIdx] = (
            interface DtldStreamBiDirSlavePipesB0In;
                interface DtldStreamSlaveWritePipesB0In writePipeIfc;
                    interface  writeMetaPipeIn  = toPipeInB0(dmaWriteMetaPipeInQueueVec[channelIdx]);
                    interface  writeDataPipeIn  = rightShifterVec[channelIdx].streamPipeIn;
                endinterface

                interface DtldStreamSlaveReadPipesB0In readPipeIfc;
                    interface  readMetaPipeIn  = toPipeInB0(dmaReadMetaPipeInQueueVec[channelIdx]);
                    interface  readDataPipeOut = leftShifterVec[channelIdx].streamPipeOut;
                endinterface
            endinterface);

    end



    rule handleCsrAccessReq;
        let req = innerDmac.h2cReqFifoOut.first;
        innerDmac.h2cReqFifoOut.deq;
        if (req.isWrite) begin
            csrWriteMetaPipeOutQueue.enq(IoChannelMemoryAccessMeta{
                addr: unpack(zeroExtend(req.addr)),
                totalLen: fromInteger(valueOf(TDiv#(DWORD_WIDTH, BYTE_WIDTH)))});
            csrWriteDataPipeOutQueue.enq(IoChannelMemoryAccessDataStream{
                data: unpack(zeroExtend(req.value)),
                startByteIdx: 0,
                byteNum: fromInteger(valueOf(TDiv#(DWORD_WIDTH, BYTE_WIDTH))),
                isFirst: True,
                isLast: True
            });
        end
        else begin
            csrReadMetaPipeOutQueue.enq(IoChannelMemoryAccessMeta {
                addr: unpack(zeroExtend(req.addr)),
                totalLen: fromInteger(valueOf(TDiv#(DWORD_WIDTH, BYTE_WIDTH)))
            });
            csrReadRespKeepOrderQueue.enq(req.addr);
        end

    endrule

    rule handleCsrAccessResp;
        csrReadDataPipeInQueue.deq;
        csrReadRespKeepOrderQueue.deq;
        let resp = CsrResponse {
            addr: csrReadRespKeepOrderQueue.first,
            value: unpack(truncate(pack(csrReadDataPipeInQueue.first.data)))
        };
        innerDmac.h2cRespFifoIn.enq(resp);
    endrule


    rule sysResetHandler;
        if (sysResetCounterReg < 1000) begin
            sysResetCounterReg <= sysResetCounterReg + 1;
        end
    endrule


    interface rawPcie               = innerDmac.rawPcie;
    method    tlpSizeDebugPort      = innerDmac.tlpSizeDebugPort;
    method    sys_reset             = sysResetCounterReg == 1000;


    interface dmaSlavePipeIfcVec = dmaSlavePipeIfcVecInst;


    interface DtldStreamBiDirMasterPipes dmaMasterPipeIfc;
        interface DtldStreamMasterWritePipes writePipeIfc;
            interface  writeMetaPipeOut  = toPipeOut(csrWriteMetaPipeOutQueue);
            interface  writeDataPipeOut  = toPipeOut(csrWriteDataPipeOutQueue);
        endinterface

        interface DtldStreamMasterReadPipes readPipeIfc;
            interface  readMetaPipeOut  = toPipeOut(csrReadMetaPipeOutQueue);
            interface  readDataPipeIn   = toPipeIn(csrReadDataPipeInQueue);
        endinterface
    endinterface


endmodule