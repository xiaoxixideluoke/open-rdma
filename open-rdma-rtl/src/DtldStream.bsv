import Vector :: *;
import Printf :: *;
import FIFOF :: *;
import PrimUtils :: *;
import Arbiter :: *;
import Connectable :: *;
import ConnectableF :: *;
import BasicDataTypes :: *;
import FullyPipelineChecker :: *;

typedef enum {
    MemAccessTypeNormalReadWrite = 0,
    MemAccessTypeFetchAdd  = 1,
    MemAccessTypeSwap = 2,
    MemAccessTypeCAS  = 3
} MemAccessType deriving (Eq, Bits, FShow);

typedef enum {
    ONE_DW = 0,
    TWO_DW = 1 //only support this now
} OperandSize deriving (Eq, Bits, FShow);

typedef Bit#(2) OperandNum;

typedef TMul#(2,DWORD_WIDTH) ATOMIC_OPERAND_WIDTH;
typedef Bit#(ATOMIC_OPERAND_WIDTH) AtomicOperand;

typedef struct {
    tAddr                                               addr;
    tLen                                                totalLen;
    MemAccessType                                       accessType;
    AtomicOperand                                       operand_1;
    AtomicOperand                                       operand_2;
    Bool                                                noSnoop;
} DtldStreamMemAccessMeta#(type tAddr, type tLen) deriving(Bits, FShow);

typedef struct {
    tData                                                       data;
    Bit#(TAdd#(1, TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH))))    byteNum;
    Bit#(TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH)))              startByteIdx;
    Bool                                                        isFirst;
    Bool                                                        isLast;
} DtldStreamData#(type tData) deriving (FShow, Bits, Eq);



// instance ConnectableWithFullyPipelineCheck#(PipeOut#(DtldStreamData#(t)), PipeInB0#(DtldStreamData#(t)));
//     module mkConnectionFpCheck#(PipeOut#(DtldStreamData#(t)) fo, PipeInB0#(DtldStreamData#(t)) fi, String name,  Bool enableFpCheck)(Empty);
//         let fpChecker <- mkStreamFullyPipelineChecker(name);
//         mkConnection(fo.notEmpty, fi.notEmptyIn);

//         rule connect;
//             fi.firstIn(fo.first);
//             fpChecker.putStreamBeatInfo(fo.first.isFirst, fo.first.isLast);
//         endrule

//         rule handleDeq;
//             if (fi.deqSignalOut) begin
//                 fo.deq;
//             end
//         endrule
//     endmodule
// endinstance

// instance ConnectableWithFullyPipelineCheck#(PipeInB0#(DtldStreamData#(t)), PipeOut#(DtldStreamData#(t)));
//     module mkConnectionFpCheck#(PipeInB0#(DtldStreamData#(t)) fi, PipeOut#(DtldStreamData#(t)) fo, String name,  Bool enableFpCheck)(Empty);
//         mkConnectionFpCheck(fo, fi);
//     endmodule
// endinstance


// instance ConnectableWithFullyPipelineCheck#(PipeOut#(DtldStreamData#(t)), PipeIn#(DtldStreamData#(t)));
//     module mkConnectionFpCheck#(PipeOut#(DtldStreamData#(t)) fo, PipeIn#(DtldStreamData#(t)) fi, String name, Bool enableFpCheck)(Empty);
//         let fpChecker <- mkStreamFullyPipelineChecker(name);
//         rule connect;
//             fi.enq(fo.first);
//             fo.deq;
//             fpChecker.putStreamBeatInfo(fo.first.isFirst, fo.first.isLast);
//         endrule
//     endmodule
// endinstance

// instance ConnectableWithFullyPipelineCheck#(PipeIn#(DtldStreamData#(t)), PipeOut#(DtldStreamData#(t)));
//     module mkConnectionFpCheck#(PipeIn#(DtldStreamData#(t)) fi, PipeOut#(DtldStreamData#(t)) fo, String name,  Bool enableFpCheck)(Empty);
//         mkConnectionFpCheck(fo, fi, name, enableFpCheck);
//     endmodule
// endinstance




module mkDsConnectionFpCheckB0#(PipeOut#(DtldStreamData#(t)) fo, PipeInB0#(DtldStreamData#(t)) fi, DebugConf dbgConf)(Empty);
    let fpChecker <- mkStreamFullyPipelineChecker(dbgConf);
    mkConnection(fo.notEmpty, fi.notEmptyIn);

    rule connect;
        fi.firstIn(fo.first);
        let _ <- fpChecker.putStreamBeatInfo(fo.first.isFirst, fo.first.isLast);
    endrule

    rule handleDeq;
        if (fi.deqSignalOut) begin
            fo.deq;
        end
    endrule
endmodule




module mkDsConnectionFpCheck#(PipeOut#(DtldStreamData#(t)) fo, PipeIn#(DtldStreamData#(t)) fi, DebugConf dbgConf)(Empty);
    let fpChecker <- mkStreamFullyPipelineChecker(dbgConf);
    rule connect;
        fi.enq(fo.first);
        fo.deq;
        let _ <- fpChecker.putStreamBeatInfo(fo.first.isFirst, fo.first.isLast);
    endrule
endmodule






interface DtldStreamMasterWritePipes#(type tData, type tAddr, type tLen);
    interface PipeOut#(DtldStreamMemAccessMeta#(tAddr, tLen))   writeMetaPipeOut;
    interface PipeOut#(DtldStreamData#(tData))                  writeDataPipeOut;
endinterface


interface DtldStreamMasterReadPipes#(type tData, type tAddr, type tLen);
    interface PipeOut#(DtldStreamMemAccessMeta#(tAddr, tLen))   readMetaPipeOut;
    interface PipeIn#(DtldStreamData#(tData))                   readDataPipeIn;
endinterface
interface DtldStreamMasterReadPipesB0In#(type tData, type tAddr, type tLen);
    interface PipeOut#(DtldStreamMemAccessMeta#(tAddr, tLen))   readMetaPipeOut;
    interface PipeInB0#(DtldStreamData#(tData))                 readDataPipeIn;
endinterface
// interface DtldStreamMasterReadPipesB2In#(type tData, type tAddr, type tLen);
//     interface PipeOut#(DtldStreamMemAccessMeta#(tAddr, tLen))   readMetaPipeOut;
//     interface PipeInB2#(DtldStreamData#(tData))                 readDataPipeIn;
// endinterface



interface DtldStreamBiDirMasterPipes#(type tData, type tAddr, type tLen);
    interface DtldStreamMasterWritePipes#(tData, tAddr, tLen)  writePipeIfc;
    interface DtldStreamMasterReadPipes#(tData, tAddr, tLen)   readPipeIfc;
endinterface
interface DtldStreamBiDirMasterPipesB0In#(type tData, type tAddr, type tLen);
    interface DtldStreamMasterWritePipes#(tData, tAddr, tLen)  writePipeIfc;
    interface DtldStreamMasterReadPipesB0In#(tData, tAddr, tLen)   readPipeIfc;
endinterface
// interface DtldStreamBiDirMasterPipesB2In#(type tData, type tAddr, type tLen);
//     interface DtldStreamMasterWritePipes#(tData, tAddr, tLen)  writePipeIfc;
//     interface DtldStreamMasterReadPipesB2In#(tData, tAddr, tLen)   readPipeIfc;
// endinterface


interface DtldStreamSlaveWritePipes#(type tData, type tAddr, type tLen);
    interface PipeIn#(DtldStreamMemAccessMeta#(tAddr, tLen))    writeMetaPipeIn;
    interface PipeIn#(DtldStreamData#(tData))                   writeDataPipeIn;
endinterface
interface DtldStreamSlaveWritePipesB0In#(type tData, type tAddr, type tLen);
    interface PipeInB0#(DtldStreamMemAccessMeta#(tAddr, tLen))    writeMetaPipeIn;
    interface PipeInB0#(DtldStreamData#(tData))                   writeDataPipeIn;
endinterface
// interface DtldStreamSlaveWritePipesB2In#(type tData, type tAddr, type tLen);
//     interface PipeInB2#(DtldStreamMemAccessMeta#(tAddr, tLen))    writeMetaPipeIn;
//     interface PipeInB2#(DtldStreamData#(tData))                   writeDataPipeIn;
// endinterface

interface DtldStreamSlaveReadPipes#(type tData, type tAddr, type tLen);
    interface PipeIn#(DtldStreamMemAccessMeta#(tAddr, tLen))     readMetaPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                   readDataPipeOut;
endinterface
interface DtldStreamSlaveReadPipesB0In#(type tData, type tAddr, type tLen);
    interface PipeInB0#(DtldStreamMemAccessMeta#(tAddr, tLen))      readMetaPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                      readDataPipeOut;
endinterface
// interface DtldStreamSlaveReadPipesB2In#(type tData, type tAddr, type tLen);
//     interface PipeInB2#(DtldStreamMemAccessMeta#(tAddr, tLen))      readMetaPipeIn;
//     interface PipeOut#(DtldStreamData#(tData))                      readDataPipeOut;
// endinterface

interface DtldStreamBiDirSlavePipes#(type tData, type tAddr, type tLen);
    interface DtldStreamSlaveWritePipes#(tData, tAddr, tLen)  writePipeIfc;
    interface DtldStreamSlaveReadPipes#(tData, tAddr, tLen)   readPipeIfc;
endinterface
interface DtldStreamBiDirSlavePipesB0In#(type tData, type tAddr, type tLen);
    interface DtldStreamSlaveWritePipesB0In#(tData, tAddr, tLen)  writePipeIfc;
    interface DtldStreamSlaveReadPipesB0In#(tData, tAddr, tLen)   readPipeIfc;
endinterface
// interface DtldStreamBiDirSlavePipesB2In#(type tData, type tAddr, type tLen);
//     interface DtldStreamSlaveWritePipesB2In#(tData, tAddr, tLen)  writePipeIfc;
//     interface DtldStreamSlaveReadPipesB2In#(tData, tAddr, tLen)   readPipeIfc;
// endinterface





interface DtldStreamNoMetaBiDirPipes#(type tData);
    interface PipeIn#(DtldStreamData#(tData))                   dataPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                  dataPipeOut;
endinterface

interface DtldStreamNoMetaBiDirPipesB0In#(type tData);
    interface PipeInB0#(DtldStreamData#(tData))                 dataPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                  dataPipeOut;
endinterface

instance Connectable#(DtldStreamBiDirMasterPipes#(tData, tAddr, tLen), DtldStreamBiDirSlavePipes#(tData, tAddr, tLen));
    module mkConnection#(DtldStreamBiDirMasterPipes#(tData, tAddr, tLen) master, DtldStreamBiDirSlavePipes#(tData, tAddr, tLen) slave)(Empty);
        mkConnection(master.writePipeIfc.writeMetaPipeOut, slave.writePipeIfc.writeMetaPipeIn);
        mkConnection(master.writePipeIfc.writeDataPipeOut, slave.writePipeIfc.writeDataPipeIn);
        mkConnection(master.readPipeIfc.readMetaPipeOut, slave.readPipeIfc.readMetaPipeIn);
        mkConnection(master.readPipeIfc.readDataPipeIn, slave.readPipeIfc.readDataPipeOut);
    endmodule
endinstance

instance Connectable#(DtldStreamBiDirMasterPipesB0In#(tData, tAddr, tLen), DtldStreamBiDirSlavePipesB0In#(tData, tAddr, tLen));
    module mkConnection#(DtldStreamBiDirMasterPipesB0In#(tData, tAddr, tLen) master, DtldStreamBiDirSlavePipesB0In#(tData, tAddr, tLen) slave)(Empty);
        mkConnection(master.writePipeIfc.writeMetaPipeOut, slave.writePipeIfc.writeMetaPipeIn);
        mkConnection(master.writePipeIfc.writeDataPipeOut, slave.writePipeIfc.writeDataPipeIn);
        mkConnection(master.readPipeIfc.readMetaPipeOut, slave.readPipeIfc.readMetaPipeIn);
        mkConnection(master.readPipeIfc.readDataPipeIn, slave.readPipeIfc.readDataPipeOut);
    endmodule
endinstance



instance ConnectableWithFullyPipelineCheck#(DtldStreamBiDirMasterPipes#(tData, tAddr, tLen), DtldStreamBiDirSlavePipes#(tData, tAddr, tLen));
    module mkConnectionFpCheck#(
            DtldStreamBiDirMasterPipes#(tData, tAddr, tLen) master,
            DtldStreamBiDirSlavePipes#(tData, tAddr, tLen) slave,
            DebugConf dbgConf
        )(Empty);
        mkConnection(master.writePipeIfc.writeMetaPipeOut, slave.writePipeIfc.writeMetaPipeIn);
        mkDsConnectionFpCheck(master.writePipeIfc.writeDataPipeOut, slave.writePipeIfc.writeDataPipeIn, dbgConf);
        mkConnection(master.readPipeIfc.readMetaPipeOut, slave.readPipeIfc.readMetaPipeIn);
        mkDsConnectionFpCheck(slave.readPipeIfc.readDataPipeOut, master.readPipeIfc.readDataPipeIn, dbgConf);
    endmodule
endinstance

instance ConnectableWithFullyPipelineCheck#(DtldStreamBiDirMasterPipesB0In#(tData, tAddr, tLen), DtldStreamBiDirSlavePipesB0In#(tData, tAddr, tLen));
    module mkConnectionFpCheck#(
            DtldStreamBiDirMasterPipesB0In#(tData, tAddr, tLen) master,
            DtldStreamBiDirSlavePipesB0In#(tData, tAddr, tLen) slave,
            DebugConf dbgConf
        )(Empty);
        mkConnection(master.writePipeIfc.writeMetaPipeOut, slave.writePipeIfc.writeMetaPipeIn);
        mkDsConnectionFpCheckB0(master.writePipeIfc.writeDataPipeOut, slave.writePipeIfc.writeDataPipeIn, dbgConf);
        mkConnection(master.readPipeIfc.readMetaPipeOut, slave.readPipeIfc.readMetaPipeIn);
        mkDsConnectionFpCheckB0(slave.readPipeIfc.readDataPipeOut, master.readPipeIfc.readDataPipeIn, dbgConf);
    endmodule
endinstance





interface DtldStreamArbiterSlave#(numeric type channelCnt, type tData, type tAddr, type tLen);
    interface Vector#(channelCnt, DtldStreamBiDirSlavePipesB0In#(tData, tAddr, tLen))       slaveIfcVec;
    interface DtldStreamBiDirMasterPipesB0In#(tData, tAddr, tLen)                           masterIfc;
    interface PipeOut#(Bit#(TLog#(channelCnt)))                                             writeSourceChannelIdPipeOut;
    interface PipeOut#(Bit#(TLog#(channelCnt)))                                             readSourceChannelIdPipeOut;
endinterface


module mkDtldStreamArbiterSlave#(Integer readDepth, Integer writeOutputBufDepth, Bool needReadResp, DebugConf dbgConf)(DtldStreamArbiterSlave#(channelCnt, tData, tAddr, tLen)) provisos (
        Bits#(tData, szData),
        Bits#(DtldStreamMemAccessMeta#(tAddr, tLen), szMeta),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
        FShow#(tAddr),
        FShow#(tLen),
        FShow#(tData)
    );

    Vector#(channelCnt, DtldStreamBiDirSlavePipesB0In#(tData, tAddr, tLen))     slaveIfcVecInst = newVector;

    Vector#(channelCnt, PipeInAdapterB0#(DtldStreamMemAccessMeta#(tAddr, tLen)))            slaveSideQueueVecWm     <- replicateM(mkPipeInAdapterB0);
    Vector#(channelCnt, PipeInAdapterB0#(DtldStreamData#(tData)))                           slaveSideQueueVecWd     <- replicateM(mkPipeInAdapterB0);
    Vector#(channelCnt, PipeInAdapterB0#(DtldStreamMemAccessMeta#(tAddr, tLen)))            slaveSideQueueVecRm     <- replicateM(mkPipeInAdapterB0);
    Vector#(channelCnt, FIFOF#(DtldStreamData#(tData)))                                     slaveSideQueueVecRd     = newVector;

    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        slaveSideQueueVecRd[channelIdx] <- mkFIFOFWithFullAssert(concatDebugName(dbgConf, sprintf("mkDtldStreamArbiterSlave [%s] slaveSideQueueVecRd[%0d]", dbgConf.name, channelIdx)));
    end

    FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))            masterSideQueueWm   <-  mkFIFOF;
    FIFOF#(DtldStreamData#(tData))                           masterSideQueueWd   <-  mkSizedFIFOFWithFullAssert(writeOutputBufDepth, concatDebugName(dbgConf, sprintf("mkDtldStreamArbiterSlave [%s] masterSideQueueWd", dbgConf.name)));
    FIFOF#(DtldStreamMemAccessMeta#(tAddr, tLen))            masterSideQueueRm   <-  mkFIFOF;
    PipeInAdapterB0#(DtldStreamData#(tData))                 masterSideQueueRd   <-  mkPipeInAdapterB0;

    FIFOF#(tChannelIdx)     writeSourceChannelIdPipeOutQueue <- mkFIFOF;
    FIFOF#(tChannelIdx)     readSourceChannelIdPipeOutQueue  <- mkFIFOF;


    Arbiter_IFC#(channelCnt) writeArbiter <- mkArbiter(False);
    Arbiter_IFC#(channelCnt) readArbiter  <- mkArbiter(False);

    FIFOF#(tChannelIdx) writeKeepOrderQueue <- mkSizedFIFOF(writeOutputBufDepth);

    FIFOF#(tChannelIdx) readKeepOrderQueue  <- mkSizedFIFOF(readDepth);   // TODO: check why use mkRegisteredSizedFIFOF will deadlock here


    // for read path, a big WQE may lead to read a lot of beat, DMA may be faster than ethernet port, leading to blocking.
    // we only care the output of ethernet port and make sure it is continous.
    let fpCheckerRead <- mkStreamFullyPipelineChecker(concatDebugName(dbgConf, "read"));
    let dbgConfForContinousDsCheck = dbgConf;
    dbgConfForContinousDsCheck.enableDebug = True; // Force check Write
    let fpCheckerWrite <- mkStreamFullyPipelineChecker(concatDebugName(dbgConfForContinousDsCheck, "write"));
    
    

    // rule debug;
    //     $display(
    //         "time=%0t, ", $time, "DEBUG", 
    //         ", isWriteFirstBeatReg=", fshow(isWriteFirstBeatReg),
    //         ", masterSideQueueWm.notFull=", fshow(masterSideQueueWm.notFull),
    //         ", masterSideQueueWd.notFull=", fshow(masterSideQueueWd.notFull),
    //         ", writeSourceChannelIdPipeOutQueue.notFull=", fshow(writeSourceChannelIdPipeOutQueue.notFull)

    //     );
    // endrule

    rule sendWriteArbitReq;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (slaveSideQueueVecWm[channelIdx].notEmpty && slaveSideQueueVecWd[channelIdx].notEmpty) begin
                writeArbiter.clients[channelIdx].request;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkDtldStreamArbiterSlave sendWriteArbitReq"),
                //     toBlue(", channelIdx=%d"), channelIdx
                // );
            end
        end
    endrule

    rule recvWriteArbitResp;
        Maybe#(DtldStreamMemAccessMeta#(tAddr, tLen)) wmMaybe = tagged Invalid;
        DtldStreamData#(tData) wd = ?;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (writeArbiter.clients[channelIdx].grant) begin
                wmMaybe = tagged Valid slaveSideQueueVecWm[channelIdx].first;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (wmMaybe matches tagged Valid .wm) begin
            slaveSideQueueVecWm[curChannelIdx].deq;
            masterSideQueueWm.enq(wm);
            writeKeepOrderQueue.enq(curChannelIdx);
            writeSourceChannelIdPipeOutQueue.enq(curChannelIdx);
            // $display(
            //     "time=%0t:", $time, toGreen(" mkDtldStreamArbiterSlave forward write beat first"),
            //     toBlue(", wm="), fshow(wm),
            //     toBlue(", wd="), fshow(wd)
            // );
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamArbiterSlave recvWriteArbitResp"),
        //     toBlue(", wmMaybe="), fshow(wmMaybe),
        //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
        // );
    endrule

    rule forwardMoreWriteBeat;

        let curWriteChannelIdx = writeKeepOrderQueue.first;
        let wd  = slaveSideQueueVecWd[curWriteChannelIdx].first;
        slaveSideQueueVecWd[curWriteChannelIdx].deq;
        masterSideQueueWd.enq(wd);
        let _ <- fpCheckerWrite.putStreamBeatInfo(wd.isFirst, wd.isLast);
        if (wd.isLast) begin
            writeKeepOrderQueue.deq;
        end

        $display(
            "time=%0t:", $time, toGreen(" mkDtldStreamArbiterSlave forwardMoreWriteBeat"),
            toBlue(", wd="), fshow(wd)
        );
    endrule

    rule sendReadArbitReq;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (slaveSideQueueVecRm[channelIdx].notEmpty) begin
                readArbiter.clients[channelIdx].request;
            end
        end
    endrule

    rule recvReadArbitResp;
        Maybe#(DtldStreamMemAccessMeta#(tAddr, tLen)) rmMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (readArbiter.clients[channelIdx].grant) begin
                rmMaybe = tagged Valid slaveSideQueueVecRm[channelIdx].first;
                slaveSideQueueVecRm[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (rmMaybe matches tagged Valid .rm) begin
            masterSideQueueRm.enq(rm);
            if (needReadResp) begin
                readKeepOrderQueue.enq(curChannelIdx);
            end
            readSourceChannelIdPipeOutQueue.enq(curChannelIdx);
        end
    endrule

    if (needReadResp) begin
        rule forwardReadResp;
            let rd = masterSideQueueRd.first;
            masterSideQueueRd.deq;

            let channelIdx = readKeepOrderQueue.first;
            slaveSideQueueVecRd[channelIdx].enq(rd);

            if (rd.isLast) begin
                readKeepOrderQueue.deq;
            end
            let _ <- fpCheckerRead.putStreamBeatInfo(rd.isFirst, rd.isLast);
            $display(
                "time=%0t:", $time, toGreen(" mkDtldStreamArbiterSlave forwardReadResp"),
                toBlue(", channelIdx="), fshow(channelIdx),
                toBlue(", rd="), fshow(rd)
            );
        endrule
    end


    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        slaveIfcVecInst[channelIdx] = (
            interface DtldStreamBiDirSlavePipesB0In 
                interface DtldStreamSlaveWritePipesB0In writePipeIfc;
                    interface  writeMetaPipeIn  = toPipeInB0(slaveSideQueueVecWm[channelIdx]);
                    interface  writeDataPipeIn  = toPipeInB0(slaveSideQueueVecWd[channelIdx]);
                endinterface

                interface DtldStreamSlaveReadPipesB0In readPipeIfc;
                    interface  readMetaPipeIn  = toPipeInB0(slaveSideQueueVecRm[channelIdx]);
                    interface  readDataPipeOut = toPipeOut(slaveSideQueueVecRd[channelIdx]);
                endinterface
            endinterface);
    end

    interface slaveIfcVec = slaveIfcVecInst;
    interface DtldStreamBiDirMasterPipesB0In masterIfc;
        interface DtldStreamMasterWritePipes writePipeIfc;
            interface  writeMetaPipeOut  = toPipeOut(masterSideQueueWm);
            interface  writeDataPipeOut  = toPipeOut(masterSideQueueWd);
        endinterface

        interface DtldStreamMasterReadPipesB0In readPipeIfc;
            interface  readMetaPipeOut  = toPipeOut(masterSideQueueRm);
            interface  readDataPipeIn   = toPipeInB0(masterSideQueueRd);
        endinterface
    endinterface

    interface writeSourceChannelIdPipeOut = toPipeOut(writeSourceChannelIdPipeOutQueue);
    interface readSourceChannelIdPipeOut  = toPipeOut(readSourceChannelIdPipeOutQueue);
endmodule













interface DtldStreamNoMetaArbiterSlave#(numeric type channelCnt, type tData);
    interface Vector#(channelCnt, PipeIn#(DtldStreamData#(tData)))                      pipeInIfcVec;
    interface PipeOut#(DtldStreamData#(tData))                                          pipeOutIfc;
    interface PipeOut#(Bit#(TLog#(channelCnt)))                                         sourceChannelIdPipeOut;
endinterface


module mkDtldStreamNoMetaArbiterSlave#(Integer depth)(DtldStreamNoMetaArbiterSlave#(channelCnt, tData)) provisos (
        Bits#(tData, szData),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
        FShow#(tData)
    );

    Vector#(channelCnt, PipeIn#(DtldStreamData#(tData)))                          pipeInIfcVecInst         = newVector;
    Vector#(channelCnt, FIFOF#(DtldStreamData#(tData)))                           pipeInIfcVecQueueVec     <- replicateM(mkLFIFOF);
    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        pipeInIfcVecInst[channelIdx] = toPipeIn(pipeInIfcVecQueueVec[channelIdx]);
    end

    FIFOF#(DtldStreamData#(tData))                              pipeOutIfcQueue             <-  mkFIFOF;
    FIFOF#(tChannelIdx)                                         sourceChannelIdPipeOutQueue <- mkFIFOF;

    Arbiter_IFC#(channelCnt) arbiter <- mkArbiter(False);

    Reg#(Bool) isFirstBeatReg <- mkReg(True);

    Reg#(tChannelIdx) curChannelIdxReg <- mkRegU;

    // rule debug;
    //     $display(
    //         "time=%0t, ", $time, "DEBUG", 
    //         ", isFirstBeatReg=", fshow(isFirstBeatReg),
    //         ", pipeOutIfcQueue.notFull=", fshow(pipeOutIfcQueue.notFull),
    //         ", sourceChannelIdPipeOutQueue.notFull=", fshow(sourceChannelIdPipeOutQueue.notFull)

    //     );
    // endrule

    rule sendArbitReq if (isFirstBeatReg);
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (pipeInIfcVecQueueVec[channelIdx].notEmpty) begin
                arbiter.clients[channelIdx].request;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkDtldStreamNoMetaArbiterSlave sendArbitReq"),
                //     toBlue(", channelIdx=%d"), channelIdx
                // );
            end
        end
    endrule

    rule recvArbitResp if (isFirstBeatReg);
        Maybe#(DtldStreamData#(tData)) dsMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (arbiter.clients[channelIdx].grant) begin
                dsMaybe = tagged Valid pipeInIfcVecQueueVec[channelIdx].first;
                pipeInIfcVecQueueVec[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (dsMaybe matches tagged Valid .ds) begin
            pipeOutIfcQueue.enq(ds);
            isFirstBeatReg <= ds.isLast;
            curChannelIdxReg <= curChannelIdx;
            sourceChannelIdPipeOutQueue.enq(curChannelIdx);
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamNoMetaArbiterSlave recvArbitResp"),
        //     toBlue(", dsMaybe="), fshow(dsMaybe),
        //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
        // );
    endrule

    rule forwardMoreBeat if (!isFirstBeatReg);
        let ds  = pipeInIfcVecQueueVec[curChannelIdxReg].first;
        pipeInIfcVecQueueVec[curChannelIdxReg].deq;
        pipeOutIfcQueue.enq(ds);
        isFirstBeatReg <= ds.isLast;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamNoMetaArbiterSlave forwardMoreBeat"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface pipeInIfcVec = pipeInIfcVecInst;
    interface pipeOutIfc = toPipeOut(pipeOutIfcQueue);
    interface sourceChannelIdPipeOut = toPipeOut(sourceChannelIdPipeOutQueue);
endmodule













// This concator can concat one or more datastream fragments into a single big datastream.
// The first (or only) fragment's first (or only) beat can have startByteIdx != 0
// The first (or only) fragment's last (or only) beat can have invalid bytes at the tail, i.e., (startByteIdx + byteNum < byte_nume_per_beat)
// The last (or only) fragment's last beat can have invalid bytes at the tail, i.e., (startByteIdx + byteNum < byte_nume_per_beat)
// All the other fragments's beats must be full, i.e., startByteIdx == 0 && startByteIdx == byte_nume_per_beat
interface DtldStreamConcator#(type tData, numeric type nLogOfAlign);
    interface PipeInB0#(DtldStreamData#(tData))                    dataPipeIn;
    interface PipeInB0#(Bool)                                      isLastStreamFlagPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                     dataPipeOut;
endinterface

typedef enum {
    DtldStreamConcatorStateIdle,
    DtldStreamConcatorStateOutputMore,
    DtldStreamConcatorStateOutputExtra
} DtldStreamConcatorState deriving(Eq, FShow, Bits);

module mkDtldStreamConcator#(DebugConf dbgConf)(DtldStreamConcator#(tData, nLogOfByteAlign)) provisos(
        Bits#(tData, szData),
        Bitwise#(tData),
        FShow#(DtldStream::DtldStreamData#(tData)),
        Alias#(Bit#(szAlignBlockIdx), tAlignBlockIdx),
        Alias#(Bit#(szAlignBlockCnt), tAlignBlockCnt),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteCnt), tByteCnt),
        Alias#(Bit#(szBitIdx), tBitIdx),
        Alias#(Bit#(szBitCnt), tBitCnt),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(szByteIdx, 1), szByteCnt),
        NumAlias#(TAdd#(szByteIdx, BIT_BYTE_CONVERT_SHIFT_NUM), szBitIdx),
        NumAlias#(TAdd#(szByteCnt, BIT_BYTE_CONVERT_SHIFT_NUM), szBitCnt),
        NumAlias#(TDiv#(szDataInByte, TExp#(nLogOfByteAlign)), nAlignBlockPerBeat),
        NumAlias#(TSub#(TLog#(szDataInByte), nLogOfByteAlign), szAlignBlockIdx),
        NumAlias#(TAdd#(szAlignBlockIdx, 1), szAlignBlockCnt)
    );
    PipeInAdapterB0#(DtldStreamData#(tData))  dataPipeInQueue                 <- mkPipeInAdapterB0;
    PipeInAdapterB0#(Bool)                    isLastStreamFlagPipeInQueue     <- mkPipeInAdapterB0;
    FIFOF#(DtldStreamData#(tData))  dataPipeOutQueue                <- mkFIFOFWithFullAssert(concatDebugName(dbgConf, "dataPipeOutQueue"));

    Reg#(DtldStreamConcatorState)       curStateReg                 <- mkReg(DtldStreamConcatorStateIdle);

    Reg#(Bool)                          isWholeOutputFirstBeatReg                   <- mkReg(True);
    Reg#(Bool)                          isFirstStreamReg                            <- mkReg(True);
    Reg#(Bool)                          isLastStreamReg                             <- mkRegU;
    Reg#(tAlignBlockIdx)                shiftAlignBlockCntReg                       <- mkReg(0);
    Reg#(DtldStreamData#(tData))        previousDsReg                               <- mkRegU;
    Reg#(tByteCnt)                      previousBeatByteLeftReg                     <- mkRegU;

    rule idleState if (curStateReg == DtldStreamConcatorStateIdle);
        let dsIn = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        Bool isFirstStream      = isFirstStreamReg;
        let isLastStream = isLastStreamFlagPipeInQueue.first;
        isLastStreamFlagPipeInQueue.deq;
        if (dsIn.isLast && isLastStream) begin
            // for only beat in only stream
            immAssert(
                dsIn.isFirst && isWholeOutputFirstBeatReg && isFirstStreamReg,
                "must be first",
                $format( "dsIn.isFirst=", fshow(dsIn.isFirst),
                         ", isFirstStreamReg=", fshow(isFirstStreamReg),
                         ", isWholeOutputFirstBeatReg=", fshow(isWholeOutputFirstBeatReg))
            );
            dataPipeOutQueue.enq(dsIn);
        end
        else begin
            curStateReg <= DtldStreamConcatorStateOutputMore;
            previousDsReg <= dsIn;
            isLastStreamReg <= isLastStream;
            previousBeatByteLeftReg <= dsIn.byteNum;

            if (dsIn.isLast && isFirstStream) begin
                isFirstStream = False;
                shiftAlignBlockCntReg <=  truncate((fromInteger(valueOf(szDataInByte) - 1) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx)) >> valueOf(nLogOfByteAlign)) + 1;
            end
            
            immAssert(
                pack(zeroExtend(dsIn.startByteIdx) + dsIn.byteNum)[1:0] == 2'b0,
                "not aligned",
                $format("dsIn=", fshow(dsIn))
            );
        end

        isFirstStreamReg <= isFirstStream;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamConcator idleState"),
        //     toBlue(", dsIn="), fshow(dsIn),
        //     toBlue(", isFirstStreamReg="), fshow(isFirstStreamReg),
        //     toBlue(", isLastStreamReg="), fshow(isLastStreamReg),
        //     toBlue(", isLastStream="), fshow(isLastStream)
        // );
    endrule

    rule outputState if (curStateReg == DtldStreamConcatorStateOutputMore);
        let dsIn = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        Bool isFirstStream      = isFirstStreamReg;
        Bool isLastStream       = isLastStreamReg;
        Bool newIsLastStream    = isLastStreamReg; 
        if (dsIn.isFirst) begin
            newIsLastStream = isLastStreamFlagPipeInQueue.first;
            isLastStreamFlagPipeInQueue.deq;
            isLastStreamReg <= newIsLastStream;
        end

        if (!(dsIn.isLast && newIsLastStream)) begin
            immAssert(
                pack(zeroExtend(dsIn.startByteIdx) + dsIn.byteNum)[1:0] == 2'b0,
                "not aligned",
                $format("dsIn=", fshow(dsIn))
            );
        end


        tAlignBlockIdx curDsAlignBlockRightShiftCnt = shiftAlignBlockCntReg;
        tAlignBlockCnt curDsAlignBlockLeftShiftCnt  = fromInteger(valueOf(nAlignBlockPerBeat)) - zeroExtend(shiftAlignBlockCntReg);
        
        tByteIdx curDsByteRightShiftCnt = zeroExtend(curDsAlignBlockRightShiftCnt) << valueOf(nLogOfByteAlign);
        tByteCnt curDsByteLeftShiftCnt  = zeroExtend(curDsAlignBlockLeftShiftCnt)  << valueOf(nLogOfByteAlign);

        tBitIdx curDsBitRightShiftCnt = zeroExtend(curDsByteRightShiftCnt) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        tBitCnt curDsBitLeftShiftCnt  = zeroExtend(curDsByteLeftShiftCnt)  << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        
        tData dataClearMask = unpack(-1);
        dataClearMask = dataClearMask >> (curDsBitRightShiftCnt);

        let curOutBeatData = (previousDsReg.data & dataClearMask) | (dsIn.data << curDsBitLeftShiftCnt);
        let nextBeatPrevDs = dsIn;
        nextBeatPrevDs.data = nextBeatPrevDs.data >> curDsBitRightShiftCnt;
        previousDsReg <= nextBeatPrevDs;


        let isFirst = isWholeOutputFirstBeatReg;
        let isLast = False;

        let isDsInOnly = dsIn.isFirst && dsIn.isLast;

        tByteCnt previousBeatEmptyByteCnt = zeroExtend(curDsByteRightShiftCnt);
        
        // `isLastStream` comes from the register so it doesn't reflact the newest packet's state.
        // if the last stream only has one beat, then we must consult the newest isLastStream info.
        if ((isLastStream && dsIn.isLast) || (isDsInOnly && newIsLastStream)) begin
            if (previousBeatEmptyByteCnt >= dsIn.byteNum) begin
                isLast = True;
                curStateReg <= DtldStreamConcatorStateIdle;
            end
            else begin
                curStateReg <= DtldStreamConcatorStateOutputExtra;
            end
        end

        let startByteIdx = isFirst ? previousDsReg.startByteIdx : 0;

        let byteNum;
        if (isFirst && isLast) begin
            byteNum = dsIn.byteNum + previousBeatByteLeftReg;
        end
        else if (isLast) begin
            byteNum = dsIn.byteNum + previousBeatByteLeftReg;
        end
        else begin
            byteNum = fromInteger(valueOf(szDataInByte)) - zeroExtend(startByteIdx);
        end

        previousBeatByteLeftReg <= previousBeatByteLeftReg + dsIn.byteNum - byteNum;

        let ds = DtldStreamData {
            data: curOutBeatData,
            byteNum: byteNum,
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };
        dataPipeOutQueue.enq(ds);

        isWholeOutputFirstBeatReg <= isLast;

        tAlignBlockIdx newshiftAlignBlockCnt = shiftAlignBlockCntReg;
        if (dsIn.isLast && isFirstStream) begin
            isFirstStream = False;
            newshiftAlignBlockCnt =  truncate((fromInteger(valueOf(szDataInByte) - 1) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx)) >> valueOf(nLogOfByteAlign)) + 1;
        end

        if (isLast) begin
            newshiftAlignBlockCnt = 0;
            isFirstStream = True;
        end
        shiftAlignBlockCntReg <= newshiftAlignBlockCnt;
        isFirstStreamReg <= isFirstStream;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamConcator outputState"),
        //     toBlue(", previousDsReg="), fshow(previousDsReg),
        //     toBlue(", dsIn="), fshow(dsIn),
        //     toBlue(", dsOut="), fshow(ds),
        //     toBlue(", dataClearMask="), fshow(dataClearMask),
        //     toBlue(", curDsAlignBlockRightShiftCnt="), fshow(curDsAlignBlockRightShiftCnt),
        //     toBlue(", curDsAlignBlockLeftShiftCnt="), fshow(curDsAlignBlockLeftShiftCnt),
        //     toBlue(", curDsByteRightShiftCnt="), fshow(curDsByteRightShiftCnt),
        //     toBlue(", curDsByteLeftShiftCnt="), fshow(curDsByteLeftShiftCnt),
        //     toBlue(", isFirstStreamReg="), fshow(isFirstStreamReg),
        //     toBlue(", isLastStreamReg="), fshow(isLastStreamReg),
        //     toBlue(", shiftAlignBlockCntReg="), fshow(shiftAlignBlockCntReg),
        //     toBlue(", previousBeatEmptyByteCnt="), fshow(previousBeatEmptyByteCnt),
        //     toBlue(", previousBeatByteLeftReg="), fshow(previousBeatByteLeftReg)
        // );
    endrule

    rule outputExtraState if (curStateReg == DtldStreamConcatorStateOutputExtra);
        tAlignBlockIdx shiftAlignBlockCnt = 0;
        Bool isFirstStream = True;

        if (dataPipeInQueue.notEmpty && isLastStreamFlagPipeInQueue.notEmpty) begin
            let dsIn = dataPipeInQueue.first;
            let isLastStream = isLastStreamFlagPipeInQueue.first;

            if (dsIn.isLast && isLastStream) begin
                // only stream, let DtldStreamConcatorStateIdle state to handle it. 
                curStateReg <= DtldStreamConcatorStateIdle;
            end
            else begin
                dataPipeInQueue.deq;
                isLastStreamFlagPipeInQueue.deq;

                if (dsIn.isLast && isFirstStream) begin
                    isFirstStream = False;
                    shiftAlignBlockCnt = truncate((fromInteger(valueOf(szDataInByte) - 1) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx)) >> valueOf(nLogOfByteAlign)) + 1;
                end

                isLastStreamReg <= isLastStream;
                previousDsReg <= dsIn;
                curStateReg <= DtldStreamConcatorStateOutputMore;
                previousBeatByteLeftReg <= dsIn.byteNum;
            end
        end
        else begin
            curStateReg <= DtldStreamConcatorStateIdle;
        end

        let byteNum = previousBeatByteLeftReg;
        let ds = DtldStreamData {
            data: previousDsReg.data,
            byteNum: byteNum,
            startByteIdx: 0,
            isFirst: False,
            isLast: True
        };
        dataPipeOutQueue.enq(ds);

        shiftAlignBlockCntReg <= shiftAlignBlockCnt;
        isFirstStreamReg    <= isFirstStream;
        isWholeOutputFirstBeatReg <= True;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamConcator outputExtraState"),
        //     toBlue(", shiftAlignBlockCntReg="), fshow(shiftAlignBlockCntReg),
        //     toBlue(", dsIn="), fshow(ds)
        // );
    endrule

    interface dataPipeIn                = toPipeInB0(dataPipeInQueue);
    interface isLastStreamFlagPipeIn    = toPipeInB0(isLastStreamFlagPipeInQueue);
    interface dataPipeOut               = toPipeOut(dataPipeOutQueue);
endmodule




interface DtldStreamSplitor#(type tData, type tStreamAlignBlockCount, numeric type nLogOfAlign);
    interface PipeInB0#(DtldStreamData#(tData))                    dataPipeIn;
    interface PipeInB0#(tStreamAlignBlockCount)                    streamAlignBlockCountPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                     dataPipeOut;
endinterface


typedef enum {
    DtldStreamSplitorStateOutput,
    DtldStreamSplitorStateOutputLastBeat,
    DtldStreamSplitorStateOutputLastStream
} DtldStreamSplitorState deriving(Eq, FShow, Bits);



        
module mkDtldStreamSplitor#(DebugConf dbgConf)(DtldStreamSplitor#(tData, tStreamAlignBlockCount, nLogOfByteAlign)) provisos(
        Bits#(tData, szData),
        Bitwise#(tData),
        Bits#(tStreamAlignBlockCount, szStreamAlignBlockCount),
        FShow#(DtldStream::DtldStreamData#(tData)),
        Alias#(Bit#(szAlignBlockIdx), tAlignBlockIdx),
        Alias#(Bit#(szAlignBlockCnt), tAlignBlockCnt),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteCnt), tByteCnt),
        Alias#(Bit#(szBitIdx), tBitIdx),
        Alias#(Bit#(szBitCnt), tBitCnt),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(1, szByteIdx), szByteCnt),
        NumAlias#(TAdd#(szByteIdx, BIT_BYTE_CONVERT_SHIFT_NUM), szBitIdx),
        NumAlias#(TAdd#(szByteCnt, BIT_BYTE_CONVERT_SHIFT_NUM), szBitCnt),
        NumAlias#(TDiv#(szDataInByte, TExp#(nLogOfByteAlign)), nAlignBlockPerBeat),
        NumAlias#(TSub#(TLog#(szDataInByte), nLogOfByteAlign), szAlignBlockIdx),
        NumAlias#(TAdd#(1, szAlignBlockIdx), szAlignBlockCnt),
        Ord#(tStreamAlignBlockCount),
        Add#(a__, szAlignBlockCnt, szStreamAlignBlockCount),
        Add#(b__, szByteCnt, szStreamAlignBlockCount),
        Eq#(tStreamAlignBlockCount),
        Arith#(tStreamAlignBlockCount),
        FShow#(tStreamAlignBlockCount)
    );
    PipeInAdapterB0#(DtldStreamData#(tData))  dataPipeInQueue                     <- mkPipeInAdapterB0;
    PipeInAdapterB0#(tStreamAlignBlockCount)  streamAlignBlockCountPipeInQueue    <- mkPipeInAdapterB0;
    FIFOF#(DtldStreamData#(tData))  dataPipeOutQueue                    <- mkFIFOFWithFullAssert(concatDebugName(dbgConf, "dataPipeOutQueue "));

    Reg#(DtldStreamSplitorState)       curStateReg                 <- mkReg(DtldStreamSplitorStateOutput);

    Reg#(Bool)  isSubStreamFirstReg     <- mkReg(True);
    
    Reg#(DtldStreamData#(tData))        previousDsReg                               <- mkReg(unpack(0));
    Reg#(tAlignBlockCnt)                shiftAlignBlockCntReg                       <- mkReg(fromInteger(valueOf(nAlignBlockPerBeat)));
    Reg#(tStreamAlignBlockCount)        alignBlockCntLeftForSubDsReg                <- mkRegU;


    function tAlignBlockCnt getAlignBlockCountFromDs(DtldStreamData#(tData) ds);
        tByteCnt lastByteIdx = ds.byteNum + zeroExtend(ds.startByteIdx) - 1;
        tAlignBlockCnt alignBlockCnt = truncate(lastByteIdx >> valueOf(nLogOfByteAlign)) + 1;
        return alignBlockCnt;
    endfunction

    rule outputState if (curStateReg == DtldStreamSplitorStateOutput);
        let subDsAlignBlockCount = alignBlockCntLeftForSubDsReg;
        if (isSubStreamFirstReg) begin
            subDsAlignBlockCount = streamAlignBlockCountPipeInQueue.first;
            streamAlignBlockCountPipeInQueue.deq;
        end
        
        let dsIn = dataPipeInQueue.first;
        dataPipeInQueue.deq;

        let previousDs = previousDsReg;
        if (dsIn.isFirst) begin
            // only clear important bits, data will be masked out, so no need to clear. save a lot of mux
            previousDs.byteNum = 0;
            previousDs.startByteIdx = 0;
        end

        let alignBlockCntOfInputDs = getAlignBlockCountFromDs(dsIn);
        let alignBlockCntOfPrevDs = getAlignBlockCountFromDs(previousDs);
        let totalAvailableBlockCnt = alignBlockCntOfInputDs + alignBlockCntOfPrevDs;

        tAlignBlockCnt curDsAlignBlockRightShiftCnt = shiftAlignBlockCntReg;
        tAlignBlockCnt curDsAlignBlockLeftShiftCnt  = fromInteger(valueOf(nAlignBlockPerBeat)) - zeroExtend(shiftAlignBlockCntReg);
        
        tByteCnt curDsByteRightShiftCnt = zeroExtend(curDsAlignBlockRightShiftCnt) << valueOf(nLogOfByteAlign);
        tByteCnt curDsByteLeftShiftCnt  = zeroExtend(curDsAlignBlockLeftShiftCnt)  << valueOf(nLogOfByteAlign);

        tBitCnt curDsBitRightShiftCnt = zeroExtend(curDsByteRightShiftCnt) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        tBitCnt curDsBitLeftShiftCnt  = zeroExtend(curDsByteLeftShiftCnt)  << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);

        tData dataClearMask = unpack(-1);
        dataClearMask = dataClearMask >> (curDsBitRightShiftCnt);

        tData dataForOutput = ( previousDs.data & dataClearMask ) | (dsIn.data << curDsBitLeftShiftCnt);

        let isFirst = isSubStreamFirstReg;
        let isLast = subDsAlignBlockCount <= unpack(fromInteger(valueOf(nAlignBlockPerBeat)));

        isSubStreamFirstReg <= isLast;
        
        let byteNumAvaliableNow = previousDs.byteNum + dsIn.byteNum;

        // since this already last beat of sub stream, then the subDsAlignBlockCount must be small enough. the higher bits can be truncated.
        tAlignBlockCnt alignBlockCntSmallForLastBeatOfSubStream = truncate(pack(subDsAlignBlockCount));
        tAlignBlockCnt alignBlockCntOfOutputBeat = isLast ? alignBlockCntSmallForLastBeatOfSubStream : fromInteger(valueOf(nAlignBlockPerBeat));

        tByteCnt byteNum = ?;
        tByteIdx startByteIdx = dsIn.isFirst ? dsIn.startByteIdx : 0;
        if (dsIn.isFirst && dsIn.isLast) begin
            immAssert(
                isFirst && isLast,
                "if input stream is a only one, then output beat must also be a only one. the required sub-stream is too long",
                $format("dsIn=", fshow(dsIn), 
                        "subDsAlignBlockCount=", fshow(subDsAlignBlockCount))
            );

            immAssert(
                subDsAlignBlockCount <= unpack(zeroExtend(totalAvailableBlockCnt)),
                "required sub stream is longer than original input stream",
                $format("alignBlockCntSmallForLastBeatOfSubStream=", fshow(alignBlockCntSmallForLastBeatOfSubStream), ", totalAvailableBlockCnt=", fshow(totalAvailableBlockCnt))
            );

            tByteCnt bytesNeededIfAllAlignBlockIsFull = zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign);
            if (alignBlockCntSmallForLastBeatOfSubStream == totalAvailableBlockCnt) begin
                immAssert(isLast, "must be isLast here", $format(""));
                byteNum = byteNumAvaliableNow;
            end
            else begin
                // still have a tail, need goto next rule
                byteNum = bytesNeededIfAllAlignBlockIsFull - zeroExtend(dsIn.startByteIdx);
                curStateReg <= DtldStreamSplitorStateOutputLastStream;
            end
        end
        else if (dsIn.isFirst) begin
            immAssert(
                isFirst,
                "output must also be first beat",
                $format("dsIn=", fshow(dsIn), 
                        "subDsAlignBlockCount=", fshow(subDsAlignBlockCount))
            );

            if (isLast) begin
                byteNum = (zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign)) - zeroExtend(dsIn.startByteIdx);
            end
            else begin
                byteNum = dsIn.byteNum;
            end
        end
        else if (dsIn.isLast) begin
            if (isLast) begin
                immAssert(
                    subDsAlignBlockCount <= unpack(zeroExtend(totalAvailableBlockCnt)),
                    "required sub stream is longer than original input stream",
                    $format("alignBlockCntSmallForLastBeatOfSubStream=", fshow(alignBlockCntSmallForLastBeatOfSubStream), ", totalAvailableBlockCnt=", fshow(totalAvailableBlockCnt))
                );
                tByteCnt bytesNeededIfAllAlignBlockIsFull = zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign);
                if (alignBlockCntSmallForLastBeatOfSubStream == totalAvailableBlockCnt) begin
                    byteNum = byteNumAvaliableNow;
                end
                else begin
                    // still have a tail, need goto next rule
                    byteNum = bytesNeededIfAllAlignBlockIsFull;
                    curStateReg <= DtldStreamSplitorStateOutputLastStream;
                end
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
                curStateReg <= DtldStreamSplitorStateOutputLastBeat;
            end
        end
        else begin
            if (isLast) begin
                byteNum = zeroExtend(alignBlockCntSmallForLastBeatOfSubStream) << valueOf(nLogOfByteAlign);
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
            end
        end

        let ds = DtldStreamData {
            data: dataForOutput,
            byteNum: byteNum,
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };
        dataPipeOutQueue.enq(ds);


        alignBlockCntLeftForSubDsReg <= subDsAlignBlockCount - unpack(zeroExtend(alignBlockCntOfOutputBeat));

        tAlignBlockCnt usedAlignBlockCntOfThisInputBeat = alignBlockCntOfOutputBeat - alignBlockCntOfPrevDs;

        tByteCnt inDsByteRightShiftCnt = zeroExtend(usedAlignBlockCntOfThisInputBeat) << valueOf(nLogOfByteAlign);
        tBitCnt inDsBitRightShiftCnt   = zeroExtend(inDsByteRightShiftCnt) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);

        dsIn.data = dsIn.data >> inDsBitRightShiftCnt;
        dsIn.startByteIdx = 0; // when using as previous beat, the first maybe unaligned block must already been consumed.
        dsIn.byteNum = byteNumAvaliableNow - byteNum;
        
        previousDsReg <= dsIn;

        shiftAlignBlockCntReg <= dsIn.isLast ? fromInteger(valueOf(nAlignBlockPerBeat)) : usedAlignBlockCntOfThisInputBeat;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamSplitor outputState"),
        //     toBlue(", totalAvailableBlockCnt="), fshow(totalAvailableBlockCnt),
        //     toBlue(", subDsAlignBlockCount="), fshow(subDsAlignBlockCount),
        //     toBlue(", alignBlockCntOfInputDs="), fshow(alignBlockCntOfInputDs),
        //     toBlue(", curDsAlignBlockRightShiftCnt="), fshow(curDsAlignBlockRightShiftCnt),
        //     toBlue(", curDsAlignBlockLeftShiftCnt="), fshow(curDsAlignBlockLeftShiftCnt),
        //     toBlue(", dataClearMask="), fshow(dataClearMask),
        //     toBlue(", byteNumAvaliableNow="), fshow(byteNumAvaliableNow),
        //     toBlue(", alignBlockCntOfOutputBeat="), fshow(alignBlockCntOfOutputBeat),
        //     toBlue(", previousDsReg="), fshow(previousDsReg),
        //     toBlue(", dsIn="), fshow(dsIn),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    rule outputLastBeatState if (curStateReg == DtldStreamSplitorStateOutputLastBeat);
        let subDsAlignBlockCount = alignBlockCntLeftForSubDsReg;


        immAssert(
            unpack(zeroExtend(((previousDsReg.byteNum-1) >> valueOf(nLogOfByteAlign)) + 1)) == subDsAlignBlockCount,
            "last sub stream doesn't match input stream length",
            $format("previousDsReg=", fshow(previousDsReg), ", subDsAlignBlockCount=", fshow(subDsAlignBlockCount))
        );

        let ds = DtldStreamData {
            data: previousDsReg.data,
            byteNum: previousDsReg.byteNum,
            startByteIdx: 0,
            isFirst: False,
            isLast: True
        };
        dataPipeOutQueue.enq(ds);

        curStateReg <= DtldStreamSplitorStateOutput;
        isSubStreamFirstReg <= True;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamSplitor outputLastBeatState"),
        //     toBlue(", previousDsReg="), fshow(previousDsReg),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    // Note, this is to output the last STREAM (which is also a ONLY beat stream), It's a new stream, NOT THE LAST BEAT OF PREVIOUS BEAT.
    rule outputLastStreamState if (curStateReg == DtldStreamSplitorStateOutputLastStream);
        let subDsAlignBlockCount = streamAlignBlockCountPipeInQueue.first;
        streamAlignBlockCountPipeInQueue.deq;


        immAssert(
            unpack(zeroExtend(((previousDsReg.byteNum-1) >> valueOf(nLogOfByteAlign)) + 1)) == subDsAlignBlockCount,
            "last sub stream doesn't match input stream length",
            $format("previousDsReg=", fshow(previousDsReg), ", subDsAlignBlockCount=", fshow(subDsAlignBlockCount))
        );

        let ds = DtldStreamData {
            data: previousDsReg.data,
            byteNum: previousDsReg.byteNum,
            startByteIdx: 0,
            isFirst: True,
            isLast: True
        };
        dataPipeOutQueue.enq(ds);

        curStateReg <= DtldStreamSplitorStateOutput;
        
        // $display(
        //     "time=%0t:", $time, toGreen(" mkDtldStreamSplitor outputLastStreamState"),
        //     toBlue(", previousDsReg="), fshow(previousDsReg),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface dataPipeIn                    = toPipeInB0(dataPipeInQueue);
    interface streamAlignBlockCountPipeIn   = toPipeInB0(streamAlignBlockCountPipeInQueue);
    interface dataPipeOut                   = toPipeOut(dataPipeOutQueue);
endmodule