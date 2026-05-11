import Connectable :: *;
import FIFOF :: *;

import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import BasicDataTypes :: *;
import DtldStream :: *;

/*

For the stream that LSB is at right, the rightmost beat is the first beat and the leftmost beat is last beat.

Note: THIS KIND OF STREAM IS **NOT** SUPPORTED BY THIS SHIFT MODULE. YOU MUST CONVERT IT TO THE STREAM THAT THE LSB
      IS AT THE LEFT.

       Last Beat            Middle Beat          First Beat
    (Byte 2N ~ 3N-1)      (Byte N ~ 2N-1)      (Byte 0 ~ N-1)
  +--------------------+--------------------+--------------------+
  |               xxxxx|xxxxxxxxxxxxxxxxxxxx|xxxxxxxxxxxxx       |
  +--------------------+--------------------+--------------------+
                      ^ startByteIdx = 0                 ^ startByteIdx = 7
                        Since it's not the first beat      The startByteIdx always means the Byte index of the first valid byte in the FIRST beat.
                                                           no matter the whole stream is right aligned or left aligned, the value of startByteIdx
                                                           is always counted from the right to the left.


Below is stream that LSB is at left, THIS KIND OF STREAM IS SUPPORTED BY THIS SHIFT MODULE.

       FIRST Beat            Middle Beat          LAST Beat
     (Byte 0 ~ N-1)        (Byte N ~ 2N-1)      (Byte 2N ~ 3N-1)
  +--------------------+--------------------+--------------------+
  |       xxxxxxxxxxxxx|xxxxxxxxxxxxxxxxxxxx|xxxxx               |
  +--------------------+--------------------+--------------------+
                      ^ startByteIdx = 0         ^ startByteIdx = 0
                                                   Since it's not the first beat

       ONLY Beat            
     (Byte 0 ~ N-1)    
  +--------------------+
  |       xxxxxxxxxxx  |
  +--------------------+
                    ^ startByteIdx = 2
        
       ONLY Beat            
     (Byte 0 ~ N-1)    
  +--------------------+
  |       xxxxxxxxxxxxx|
  +--------------------+
                      ^ startByteIdx = 0
*/


interface StreamShifterG#(type tData);
    interface PipeInB0#(Bit#(TAdd#(1, TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH))))) offsetPipeIn;
    interface PipeInB0#(DtldStreamData#(tData))                                   streamPipeIn;
    interface PipeOut#(DtldStreamData#(tData))                                  streamPipeOut;
endinterface


typedef enum {
    BiDirectionStreamShifterLeftShiftStateIdle=0,
    BiDirectionStreamShifterLeftShiftStateOutputBeat=1,
    BiDirectionStreamShifterLeftShiftStateOutputExtraBeat=2
} BiDirectionStreamShifterLeftShiftState deriving(FShow, Eq, Bits);

typedef enum {
    BiDirectionStreamShifterRightShiftStateOutputBeat=0,
    BiDirectionStreamShifterRightShiftStateOutputExtraBeat=1
} BiDirectionStreamShifterRightShiftState deriving(FShow, Eq, Bits);

typedef struct {
    DtldStreamData#(tData)                          ds;
    Bit#(TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH)))  offset;
} BiDirectionStreamShifterPipelineEntry#(type tData) deriving(FShow, Eq, Bits);

typedef struct {
    Bit#(TAdd#(1, TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH))))    byteNum;
    Bit#(TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH)))              startByteIdx;
    Bool                                                        isFirst;
    Bool                                                        isLast;
} DataStreamMeta#(type tData) deriving(FShow, Eq, Bits);

typedef struct {
    Tuple2#(tData, tData)                           concatData;
    Bit#(TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH)))  offset;
    DataStreamMeta#(tData)                          meta;
} ShiftIntermediateData#(type tData) deriving(FShow, Eq, Bits);


// ========== IMPORTANT! =======================
// Must ensure the stream's lsb is at Left
// =============================================
// module mkBiDirectionStreamShifterG(StreamShifterG#(tData)) provisos (
//         Bits#(tData, szData),
//         NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
//         NumAlias#(TLog#(szDataInByte), szByteIdx),
//         NumAlias#(TAdd#(1, szByteIdx), szByteNum),
//         Alias#(Bit#(szByteIdx), tByteIdx),
//         Alias#(Bit#(szByteNum), tByteNum),
//         Alias#(DtldStreamData#(tData), tDataStream),
//         Alias#(BiDirectionStreamShifterPipelineEntry#(tData), tBiDirectionStreamShifterPipelineEntry),
//         Alias#(ShiftIntermediateData#(tData), tShiftIntermediateData),
//         NumAlias#(TSub#(TLog#(szData), 2), szShiftOffsetForLowerPartShift),
//         NumAlias#(TLog#(szData), szShiftOffsetForHigherPartShift),
//         Add#(a__, szByteIdx, szShiftOffsetForLowerPartShift),
//         FShow#(tData),
//         FShow#(tBiDirectionStreamShifterPipelineEntry)
//     );
//     FIFOF#(tByteNum) offsetPipeInQ <- mkLFIFOF;
//     FIFOF#(tDataStream) streamPipeInQ <- mkLFIFOF;
//     FIFOF#(tDataStream) streamPipeOutQ <- mkFIFOF;


//     FIFOF#(tBiDirectionStreamShifterPipelineEntry) leftShiftPipeQ <- mkLFIFOF;
//     FIFOF#(tBiDirectionStreamShifterPipelineEntry) rightShiftPipeQ <- mkLFIFOF;

//     FIFOF#(tShiftIntermediateData) doLeftShiftPipeQ <- mkLFIFOF;
//     FIFOF#(tShiftIntermediateData) doLeftShiftPipeQ2 <- mkLFIFOF;
//     FIFOF#(tDataStream) leftShiftResultQ <- mkLFIFOF;
//     FIFOF#(tShiftIntermediateData) doRightShiftPipeQ <- mkLFIFOF;
//     FIFOF#(tShiftIntermediateData) doRightShiftPipeQ2 <- mkLFIFOF;
//     FIFOF#(tDataStream) rightShiftResultQ <- mkFIFOF;

//     FIFOF#(Bool) keepOrderQ <- mkSizedFIFOF(4);

//     Reg#(tBiDirectionStreamShifterPipelineEntry) leftShiftPrevDataReg <- mkRegU;
//     Reg#(BiDirectionStreamShifterLeftShiftState) leftShiftStateReg <- mkReg(BiDirectionStreamShifterLeftShiftStateIdle);

//     Reg#(tBiDirectionStreamShifterPipelineEntry) rightShiftPrevDataReg <- mkRegU;
//     Reg#(BiDirectionStreamShifterRightShiftState) rightShiftStateReg <- mkReg(BiDirectionStreamShifterRightShiftStateOutputBeat);

//     tData zeroData = unpack(0);

//     if (valueOf(szByteIdx) > 2) begin
//         rule doLeftShift1;
//             let req = doLeftShiftPipeQ.first;
//             doLeftShiftPipeQ.deq;
//             // only shift by higher 2 bits
//             Bit#(szShiftOffsetForHigherPartShift) shiftCnt = 0;
//             shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-1] = req.offset[valueOf(szByteIdx)-1];
//             shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-2] = req.offset[valueOf(szByteIdx)-2];
//             req.concatData = unpack(pack(req.concatData) << shiftCnt);
//             doLeftShiftPipeQ2.enq(req);
//         endrule

//         rule doLeftShift2;
//             let req = doLeftShiftPipeQ2.first;
//             doLeftShiftPipeQ2.deq;

//             // only shift by lower bits
//             Bit#(szShiftOffsetForLowerPartShift) shiftCnt = unpack(zeroExtend(pack(req.offset)));
//             shiftCnt = shiftCnt << 3; // convert byte offset to bit offset
//             tData outputData = unpack(truncateLSB(pack(req.concatData) << shiftCnt));  
//             leftShiftResultQ.enq(DtldStreamData{
//                 data: outputData,
//                 byteNum: req.meta.byteNum,
//                 startByteIdx: req.meta.startByteIdx,
//                 isFirst: req.meta.isFirst,
//                 isLast: req.meta.isLast
//             });
//         endrule
//     end
//     else begin
//         rule doPanic1;
//             immFail("not support too narrow DataStream", $format(""));
//         endrule
//     end

//     if (valueOf(szByteIdx) > 2) begin
//         rule doRightShift;
//             let req = doRightShiftPipeQ.first;
//             doRightShiftPipeQ.deq;
//             // only shift by higher 2 bits
//             Bit#(szShiftOffsetForHigherPartShift) shiftCnt = 0;
//             shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-1] = req.offset[valueOf(szByteIdx)-1];
//             shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-2] = req.offset[valueOf(szByteIdx)-2];
//             req.concatData = unpack(pack(req.concatData) >> shiftCnt); 
//             doRightShiftPipeQ2.enq(req);
//         endrule

//         rule doRightShift2;
//             let req = doRightShiftPipeQ2.first;
//             doRightShiftPipeQ2.deq;
//             // only shift by lower bits
//             Bit#(szShiftOffsetForLowerPartShift) shiftCnt = unpack(zeroExtend(pack(req.offset)));
//             shiftCnt = shiftCnt << 3; // convert byte offset to bit offset
//             tData outputData = unpack(truncate(pack(req.concatData) >> shiftCnt)); 
//             rightShiftResultQ.enq(DtldStreamData{
//                 data: outputData,
//                 byteNum: req.meta.byteNum,
//                 startByteIdx: req.meta.startByteIdx,
//                 isFirst: req.meta.isFirst,
//                 isLast: req.meta.isLast
//             });
//         endrule
//     end
//     else begin
//         rule doPanic2;
//             immFail("not support too narrow DataStream", $format(""));
//         endrule
//     end

//     rule doFinalOutput;
//         let isShiftRight = keepOrderQ.first;
//         if (isShiftRight) begin
//             streamPipeOutQ.enq(rightShiftResultQ.first);
//             rightShiftResultQ.deq;
//             if (rightShiftResultQ.first.isLast) begin
//                 keepOrderQ.deq;
//             end
//         end
//         else begin
//             streamPipeOutQ.enq(leftShiftResultQ.first);
//             leftShiftResultQ.deq;
//             if (leftShiftResultQ.first.isLast) begin
//                 keepOrderQ.deq;
//             end
//         end
//     endrule

//     rule decideDirection;
//         let offset = offsetPipeInQ.first;
//         let ds = streamPipeInQ.first;
//         streamPipeInQ.deq;
//         if (ds.isLast) begin
//             offsetPipeInQ.deq;
//         end

//         // positive number means shift right and negative means shift left
//         let isNegativeOffset = msb(offset) == 1;
//         let isShiftRight = !isNegativeOffset;
//         let absOffset = getAbsValue(offset);

//         let shiftEntry = BiDirectionStreamShifterPipelineEntry{
//             ds: ds,
//             offset: truncate(absOffset)
//         };

//         if (ds.isFirst) begin
//             keepOrderQ.enq(isShiftRight);
//         end

//         if (isShiftRight) begin
//             rightShiftPipeQ.enq(shiftEntry);
//         end
//         else begin
//             immAssert(absOffset != 0, "The offset should not be zero, left shift path does not handle 0 offset, 0 offset should be handled by right shift path", $format(""));
//             leftShiftPipeQ.enq(shiftEntry);
//         end
//         // $display(
//         //     "time=%0t: ", $time, toGreen("decideDirection"),
//         //     toBlue(", offset="), fshow(offset),
//         //     toBlue(", ds="), fshow(ds)
//         // );
//     endrule
    
//     // (* conflict_free = "shiftLeftIdle, \
//     //                     shiftLeftOptput, \
//     //                     shiftLeftOptputExtra, \
//     //                     shiftRightOptput, \
//     //                     shiftRightOptputExtra" *)
//     rule shiftLeftIdle if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateIdle);
//         let pipelineEntry = leftShiftPipeQ.first;
//         leftShiftPipeQ.deq;
//         leftShiftPrevDataReg <= pipelineEntry;

//         immAssert(pipelineEntry.ds.isFirst, "this rule is only for first beat", $format(""));

//         if (pipelineEntry.ds.isLast) begin
//             // only have one beat, no need to concat other beat
//             let interShiftData = ShiftIntermediateData{
//                 concatData: tuple2(pipelineEntry.ds.data, zeroData),
//                 offset: pipelineEntry.offset,
//                 meta: DataStreamMeta{
//                     byteNum: pipelineEntry.ds.byteNum,
//                     startByteIdx: pipelineEntry.ds.startByteIdx + pipelineEntry.offset,
//                     isFirst: pipelineEntry.ds.isFirst,
//                     isLast: pipelineEntry.ds.isLast
//                 }
//             };
//             doLeftShiftPipeQ.enq(interShiftData);
//             // $display(
//             //     "time=%0t: ", $time, toGreen("shiftLeftIdle forward single beat data"),
//             //     toBlue(", pipelineEntry="), fshow(pipelineEntry)
//             // );
//         end
//         else begin
//             leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputBeat;
//         end
//         // $display(
//         //     "time=%0t: ", $time, toGreen("shiftLeftIdle"),
//         //     toBlue(", pipelineEntry="), fshow(pipelineEntry)
//         // );
//     endrule

//     rule shiftLeftOptput if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateOutputBeat);
//         let pipelineEntry = leftShiftPipeQ.first;
//         leftShiftPipeQ.deq;

//         tByteNum byteNum = leftShiftPrevDataReg.ds.byteNum;
//         let inputBeatCanFitInOutputBeat = (pipelineEntry.ds.byteNum <= unpack(zeroExtend(leftShiftPrevDataReg.offset)));
//         let isFirst = leftShiftPrevDataReg.ds.isFirst;
//         let isLast = inputBeatCanFitInOutputBeat && pipelineEntry.ds.isLast;
//         if (inputBeatCanFitInOutputBeat) begin
//             if (leftShiftPrevDataReg.ds.isFirst) begin
//                 byteNum = byteNum + pipelineEntry.ds.byteNum;
//             end
//             else begin
//                 byteNum = byteNum + pipelineEntry.ds.byteNum - zeroExtend(pipelineEntry.offset);
//             end
            
//             immAssert(
//                 pipelineEntry.ds.isLast,
//                 "Since the inputBeatCanFitInOutputBeat is True, the new input beat must be last beat",
//                 $format("pipelineEntry=", fshow(pipelineEntry), "leftShiftPrevDataReg=", fshow(leftShiftPrevDataReg))
//             );
//         end
//         else begin
//             if (isFirst) begin
//                 byteNum = byteNum + zeroExtend(leftShiftPrevDataReg.offset);
//             end
//             else begin
//                 byteNum = fromInteger(valueOf(szDataInByte));
//                 immAssert(
//                     !isFirst && !isLast,
//                     "this branch must output middle beat, but isFirst or isLast is True",
//                     $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
//                 );
//             end
//         end


//         let startByteIdx = isFirst ? ( inputBeatCanFitInOutputBeat ? pipelineEntry.offset - truncate(pipelineEntry.ds.byteNum) : 0 ) : 0;

//         let interShiftData = ShiftIntermediateData{
//             concatData: tuple2(leftShiftPrevDataReg.ds.data, pipelineEntry.ds.data),
//             offset: leftShiftPrevDataReg.offset,
//             meta: DataStreamMeta{
//                 byteNum: byteNum,
//                 startByteIdx: startByteIdx,
//                 isFirst: isFirst,
//                 isLast: isLast
//             }
//         };
//         doLeftShiftPipeQ.enq(interShiftData);

//         if (pipelineEntry.ds.isLast && !isLast) begin
//             leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputExtraBeat;
//         end
//         else if (isLast) begin
//             leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateIdle;
//         end
        
//         leftShiftPrevDataReg <= pipelineEntry;

//         // $display(
//         //     "time=%0t:", $time, " shiftLeftOptput",
//         //     toBlue(", pipelineEntry="), fshow(pipelineEntry),
//         //     toBlue(", leftShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
//         //     toBlue(", interShiftData="), fshow(interShiftData)
//         // );

//     endrule

//     rule shiftLeftOptputExtra if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateOutputExtraBeat);

//         let interShiftData = ShiftIntermediateData{
//             concatData: tuple2(leftShiftPrevDataReg.ds.data, zeroData),
//             offset: leftShiftPrevDataReg.offset,
//             meta: DataStreamMeta{
//                 byteNum: leftShiftPrevDataReg.ds.byteNum - zeroExtend(leftShiftPrevDataReg.offset),
//                 startByteIdx: 0,
//                 isFirst: False,
//                 isLast: True
//             }
//         };
//         doLeftShiftPipeQ.enq(interShiftData);


//         if (leftShiftPipeQ.notEmpty) begin 
//             let pipelineEntry = leftShiftPipeQ.first;
//             leftShiftPrevDataReg <= pipelineEntry;
//             if (pipelineEntry.ds.isFirst && pipelineEntry.ds.isLast) begin
//                 // only have one beat, no need to concat other beat
//                 leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateIdle;
//             end
//             else begin
//                 leftShiftPipeQ.deq;
//                 leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputBeat;
//             end
//         end
//         else begin
//             leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateIdle;
//         end
//         // $display(
//         //     "time=%0t:", $time, " shiftLeftOptputExtra",
//         //     toBlue(", leftShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
//         //     toBlue(", interShiftData="), fshow(interShiftData)
//         // );
//     endrule


//     rule shiftRightOptput if (rightShiftStateReg == BiDirectionStreamShifterRightShiftStateOutputBeat);
//         let pipelineEntry = rightShiftPipeQ.first;
//         rightShiftPipeQ.deq;
//         rightShiftPrevDataReg <= pipelineEntry;     

//         let inputBeatCanFitInOutputBeatForNonOnlyBeat = (
//             pipelineEntry.ds.byteNum + unpack(zeroExtend(pipelineEntry.offset)) <= fromInteger(valueOf(szDataInByte)));

//         let inputBeatCanFitInOutputBeatForOnlyBeat = (zeroExtend(pipelineEntry.ds.startByteIdx) >= pipelineEntry.offset);
        
//         let isOnlyBeat = pipelineEntry.ds.isFirst && pipelineEntry.ds.isLast;
//         let isFirst = pipelineEntry.ds.isFirst;
//         let isLast = isOnlyBeat ? inputBeatCanFitInOutputBeatForOnlyBeat : inputBeatCanFitInOutputBeatForNonOnlyBeat && pipelineEntry.ds.isLast;
        
//         let shiftWillChangeByteNum = pipelineEntry.ds.startByteIdx < pipelineEntry.offset;

//         tByteNum byteNum;
//         if (isFirst) begin
//             if (shiftWillChangeByteNum) begin
//                 byteNum = pipelineEntry.ds.byteNum + zeroExtend(pipelineEntry.ds.startByteIdx) - zeroExtend(pipelineEntry.offset);
//             end
//             else begin
//                 byteNum = pipelineEntry.ds.byteNum;
//             end
//         end
//         else begin
//             if (isLast) begin
//                 byteNum = pipelineEntry.ds.byteNum + zeroExtend(pipelineEntry.offset);
//             end
//             else begin
//                 byteNum = fromInteger(valueOf(szDataInByte));
//                 immAssert(
//                     !isFirst && !isLast,
//                     "this branch must output middle beat, but isFirst or isLast is True",
//                     $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
//                 );
//             end
//         end
//         let startByteIdx = shiftWillChangeByteNum ? 0 : pipelineEntry.ds.startByteIdx - zeroExtend(pipelineEntry.offset);

//         let interShiftData = ShiftIntermediateData{
//             concatData: pipelineEntry.ds.isFirst ? tuple2(zeroData, pipelineEntry.ds.data) : tuple2(rightShiftPrevDataReg.ds.data, pipelineEntry.ds.data),
//             offset: pipelineEntry.offset,
//             meta: DataStreamMeta{
//                 byteNum: byteNum,
//                 startByteIdx: startByteIdx,
//                 isFirst: isFirst,
//                 isLast: isLast
//             }
//         };
//         doRightShiftPipeQ.enq(interShiftData);

//         if ((pipelineEntry.ds.isLast && !inputBeatCanFitInOutputBeatForNonOnlyBeat) || (isOnlyBeat && !inputBeatCanFitInOutputBeatForOnlyBeat)) begin
//             rightShiftStateReg <= BiDirectionStreamShifterRightShiftStateOutputExtraBeat;
//         end
//         // $display(
//         //     "time=%0t: ", $time, toGreen("shiftRightOptput"),
//         //     toBlue(", pipelineEntry="), fshow(pipelineEntry),
//         //     toBlue(", rightShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
//         //     toBlue(", interShiftData="), fshow(interShiftData)
//         // );
//     endrule


//     rule shiftRightOptputExtra if (rightShiftStateReg == BiDirectionStreamShifterRightShiftStateOutputExtraBeat);

//         tByteNum byteNum = rightShiftPrevDataReg.ds.isFirst ? (
//             zeroExtend(rightShiftPrevDataReg.offset) - zeroExtend(rightShiftPrevDataReg.ds.startByteIdx)
//         ) : ( zeroExtend(rightShiftPrevDataReg.offset) - (fromInteger(valueOf(szDataInByte)) - rightShiftPrevDataReg.ds.byteNum));

//         let interShiftData = ShiftIntermediateData{
//             concatData: tuple2(rightShiftPrevDataReg.ds.data, zeroData),
//             offset: rightShiftPrevDataReg.offset,
//             meta: DataStreamMeta{
//                 byteNum: byteNum,
//                 startByteIdx: 0,
//                 isFirst: False,
//                 isLast: True
//             }
//         };
//         doRightShiftPipeQ.enq(interShiftData);

//         rightShiftStateReg <= BiDirectionStreamShifterRightShiftStateOutputBeat;
//         // $display(
//         //     "time=%0t: ", $time, toGreen("shiftRightOptputExtra"),
//         //     toBlue(", rightShiftPrevDataReg="), fshow(rightShiftPrevDataReg),
//         //     toBlue(", interShiftData="), fshow(interShiftData)
//         // );
//     endrule

//     interface offsetPipeIn  = toPipeIn(offsetPipeInQ);
//     interface streamPipeIn  = toPipeIn(streamPipeInQ);
//     interface streamPipeOut = toPipeOut(streamPipeOutQ);
// endmodule




































typedef enum {
    UniDirectionStreamShifterRightShiftStateIdle=0,
    UniDirectionStreamShifterRightShiftStateOutputBeat=1,
    UniDirectionStreamShifterRightShiftStateOutputExtraBeat=2
}  UniDirectionStreamShifterRightShiftState deriving(FShow, Eq, Bits);

typedef enum {
    UniDirectionStreamShifterLeftShiftStateOutputBeat=0,
    UniDirectionStreamShifterLeftShiftStateOutputExtraBeat=1
}  UniDirectionStreamShifterLeftShiftState deriving(FShow, Eq, Bits);

typedef struct {
    DtldStreamData#(tData)                          ds;
    Bit#(TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH)))  offset;
}  UniDirectionStreamShifterPipelineEntry#(type tData) deriving(FShow, Eq, Bits);


interface UniDirStreamShifter#(type tData);
    interface PipeInB0#(Bit#(TLog#(TDiv#(SizeOf#(tData), BYTE_WIDTH)))) offsetPipeIn;
    interface PipeInB0#(DtldStreamData#(tData)) streamPipeIn;
    interface PipeOut#(DtldStreamData#(tData)) streamPipeOut;
endinterface




module mkLsbRightStreamLeftShifterG(UniDirStreamShifter#(tData)) provisos (
        Bits#(tData, szData),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(1, szByteIdx), szByteNum),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteNum), tByteNum),
        Alias#(DtldStreamData#(tData), tDataStream),
        Alias#(UniDirectionStreamShifterPipelineEntry#(tData), tUniDirectionStreamShifterPipelineEntry),
        Alias#(ShiftIntermediateData#(tData), tShiftIntermediateData),
        NumAlias#(TSub#(TLog#(szData), 2), szShiftOffsetForLowerPartShift),
        NumAlias#(TLog#(szData), szShiftOffsetForHigherPartShift),
        Add#(a__, szByteIdx, szShiftOffsetForLowerPartShift),
        FShow#(tData),
        FShow#(tUniDirectionStreamShifterPipelineEntry),
        FShow#(Tuple2#(tData, tData))
    );
    PipeInAdapterB0#(tByteIdx) offsetPipeInQ <- mkPipeInAdapterB0;
    PipeInAdapterB0#(tDataStream) leftShiftPipeQ <- mkPipeInAdapterB0;


    FIFOF#(tShiftIntermediateData) doLeftShiftPipeQ <- mkLFIFOF;
    FIFOF#(tShiftIntermediateData) doLeftShiftPipeQ2 <- mkLFIFOF;
    FIFOF#(tDataStream) leftShiftResultQ <- mkFIFOF;


    Reg#(tUniDirectionStreamShifterPipelineEntry) leftShiftPrevDataReg <- mkRegU;
    Reg#(UniDirectionStreamShifterLeftShiftState) leftShiftStateReg <- mkReg(UniDirectionStreamShifterLeftShiftStateOutputBeat);


    tData zeroData = unpack(0);

    if (valueOf(szByteIdx) > 2) begin
        rule doLeftShift1;
            let req = doLeftShiftPipeQ.first;
            doLeftShiftPipeQ.deq;
            // only shift by higher 2 bits
            Bit#(szShiftOffsetForHigherPartShift) shiftCnt = 0;
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-1] = req.offset[valueOf(szByteIdx)-1];
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-2] = req.offset[valueOf(szByteIdx)-2];
            req.concatData = unpack(pack(req.concatData) << shiftCnt);
            doLeftShiftPipeQ2.enq(req);
        endrule

        rule doLeftShift2;
            let req = doLeftShiftPipeQ2.first;
            doLeftShiftPipeQ2.deq;

            // only shift by lower bits
            Bit#(szShiftOffsetForLowerPartShift) shiftCnt = unpack(zeroExtend(pack(req.offset)));
            shiftCnt = shiftCnt << 3; // convert byte offset to bit offset
            tData outputData = unpack(truncateLSB(pack(req.concatData) << shiftCnt));  
            leftShiftResultQ.enq(DtldStreamData{
                data: outputData,
                byteNum: req.meta.byteNum,
                startByteIdx: req.meta.startByteIdx,
                isFirst: req.meta.isFirst,
                isLast: req.meta.isLast
            });
        endrule
    end
    else begin
        rule doPanic;
            immFail("not support too narrow DataStream", $format(""));
        endrule
    end


    rule shiftLeftOptput if (leftShiftStateReg == UniDirectionStreamShifterLeftShiftStateOutputBeat);
        let ds = leftShiftPipeQ.first;
        leftShiftPipeQ.deq;

        let pipelineEntry = UniDirectionStreamShifterPipelineEntry {
            ds: ds,
            offset: offsetPipeInQ.first
        };
        leftShiftPrevDataReg <= pipelineEntry;     

        let inputBeatCanFitInOutputBeatForNonOnlyBeat = (
            pipelineEntry.ds.byteNum + unpack(zeroExtend(pipelineEntry.offset)) <= fromInteger(valueOf(szDataInByte)));

        let inputBeatCanFitInOutputBeatForOnlyBeat = (
            pipelineEntry.ds.byteNum + unpack(zeroExtend(pipelineEntry.offset)) + unpack(zeroExtend(pipelineEntry.ds.startByteIdx)) <= fromInteger(valueOf(szDataInByte)));
        
        let isOnlyBeat = pipelineEntry.ds.isFirst && pipelineEntry.ds.isLast;
        let isFirst = pipelineEntry.ds.isFirst;
        let isLast = isOnlyBeat ? inputBeatCanFitInOutputBeatForOnlyBeat : inputBeatCanFitInOutputBeatForNonOnlyBeat && pipelineEntry.ds.isLast;
        
        let firstBeatShiftWillChangeByteNum = !inputBeatCanFitInOutputBeatForOnlyBeat;

        tByteNum byteNum;
        if (isFirst) begin
            if (firstBeatShiftWillChangeByteNum) begin
                byteNum = fromInteger(valueOf(szDataInByte)) - (zeroExtend(pipelineEntry.offset) + zeroExtend(pipelineEntry.ds.startByteIdx));
            end
            else begin
                byteNum = pipelineEntry.ds.byteNum;
            end
        end
        else begin
            if (isLast) begin
                byteNum = pipelineEntry.ds.byteNum + zeroExtend(pipelineEntry.offset);
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
                immAssert(
                    !isFirst && !isLast,
                    "this branch must output middle beat, but isFirst or isLast is True",
                    $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
                );
            end
        end
        let startByteIdx = isFirst ? pipelineEntry.ds.startByteIdx + zeroExtend(pipelineEntry.offset) : 0;

        let interShiftData = ShiftIntermediateData{
            concatData: pipelineEntry.ds.isFirst ? tuple2(pipelineEntry.ds.data, zeroData) : tuple2(pipelineEntry.ds.data, leftShiftPrevDataReg.ds.data),
            offset: pipelineEntry.offset,
            meta: DataStreamMeta{
                byteNum: byteNum,
                startByteIdx: startByteIdx,
                isFirst: isFirst,
                isLast: isLast
            }
        };
        doLeftShiftPipeQ.enq(interShiftData);

        if ((pipelineEntry.ds.isLast && !inputBeatCanFitInOutputBeatForNonOnlyBeat) || (isOnlyBeat && !inputBeatCanFitInOutputBeatForOnlyBeat)) begin
            leftShiftStateReg <= UniDirectionStreamShifterLeftShiftStateOutputExtraBeat;
        end

        if (isLast) begin
            offsetPipeInQ.deq;
        end
        // $display(
        //     "time=%0t: ", $time, toGreen("shiftLeftOptput"),
        //     toBlue(", pipelineEntry="), fshow(pipelineEntry),
        //     toBlue(", leftShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );
    endrule


    rule shiftLeftOptputExtra if (leftShiftStateReg == UniDirectionStreamShifterLeftShiftStateOutputExtraBeat);

        tByteNum byteNum = zeroExtend(leftShiftPrevDataReg.offset) - (fromInteger(valueOf(szDataInByte)) - leftShiftPrevDataReg.ds.byteNum - zeroExtend(leftShiftPrevDataReg.ds.startByteIdx));

        let interShiftData = ShiftIntermediateData{
            concatData: tuple2(zeroData, leftShiftPrevDataReg.ds.data),
            offset: leftShiftPrevDataReg.offset,
            meta: DataStreamMeta{
                byteNum: byteNum,
                startByteIdx: 0,
                isFirst: False,
                isLast: True
            }
        };
        doLeftShiftPipeQ.enq(interShiftData);

        leftShiftStateReg <= UniDirectionStreamShifterLeftShiftStateOutputBeat;

        offsetPipeInQ.deq;

        // $display(
        //     "time=%0t: ", $time, toGreen("shiftLeftOptputExtra"),
        //     toBlue(", leftShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );
    endrule

    interface offsetPipeIn  = toPipeInB0(offsetPipeInQ);
    interface streamPipeIn  = toPipeInB0(leftShiftPipeQ);
    interface streamPipeOut = toPipeOut(leftShiftResultQ);
endmodule

module mkLsbRightStreamRightShifterG(UniDirStreamShifter#(tData)) provisos (
        Bits#(tData, szData),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(1, szByteIdx), szByteNum),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteNum), tByteNum),
        Alias#(DtldStreamData#(tData), tDataStream),
        Alias#(UniDirectionStreamShifterPipelineEntry#(tData), tUniDirectionStreamShifterPipelineEntry),
        Alias#(ShiftIntermediateData#(tData), tShiftIntermediateData),
        NumAlias#(TSub#(TLog#(szData), 2), szShiftOffsetForLowerPartShift),
        NumAlias#(TLog#(szData), szShiftOffsetForHigherPartShift),
        Add#(a__, szByteIdx, szShiftOffsetForLowerPartShift),
        FShow#(tData),
        FShow#(tUniDirectionStreamShifterPipelineEntry),
        FShow#(tShiftIntermediateData),
        FShow#(Tuple2#(tData, tData))
    );
    PipeInAdapterB0#(tByteIdx) offsetPipeInQ <- mkPipeInAdapterB0;
    PipeInAdapterB0#(tDataStream) rightShiftPipeQ <- mkPipeInAdapterB0;

    FIFOF#(tShiftIntermediateData) doRightShiftPipeQ <- mkLFIFOF;
    FIFOF#(tShiftIntermediateData) doRightShiftPipeQ2 <- mkLFIFOF;
    FIFOF#(tDataStream) rightShiftResultQ <- mkFIFOF;


    Reg#(tUniDirectionStreamShifterPipelineEntry) rightShiftPrevDataReg <- mkRegU;
    Reg#(UniDirectionStreamShifterRightShiftState) rightShiftStateReg <- mkReg(UniDirectionStreamShifterRightShiftStateIdle);

    tData zeroData = unpack(0);


    if (valueOf(szByteIdx) > 2) begin
        rule doRightShift;
            let req = doRightShiftPipeQ.first;
            doRightShiftPipeQ.deq;
            // only shift by higher 2 bits
            Bit#(szShiftOffsetForHigherPartShift) shiftCnt = 0;
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-1] = req.offset[valueOf(szByteIdx)-1];
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-2] = req.offset[valueOf(szByteIdx)-2];
            req.concatData = unpack(pack(req.concatData) >> shiftCnt); 
            doRightShiftPipeQ2.enq(req);
            // $display(
            //     "time=%0t: ", $time, toGreen("mkLsbRightStreamRightShifterG doRightShift"),
            //     toBlue(", req="), fshow(req)
            // );
        endrule

        rule doRightShift2;
            let req = doRightShiftPipeQ2.first;
            doRightShiftPipeQ2.deq;
            // only shift by lower bits
            Bit#(szShiftOffsetForLowerPartShift) shiftCnt = unpack(zeroExtend(pack(req.offset)));
            shiftCnt = shiftCnt << 3; // convert byte offset to bit offset
            tData outputData = unpack(truncate(pack(req.concatData) >> shiftCnt)); 
            rightShiftResultQ.enq(DtldStreamData{
                data: outputData,
                byteNum: req.meta.byteNum,
                startByteIdx: req.meta.startByteIdx,
                isFirst: req.meta.isFirst,
                isLast: req.meta.isLast
            });
            // $display(
            //     "time=%0t: ", $time, toGreen("mkLsbRightStreamRightShifterG doRightShift2"),
            //     toBlue(", req="), fshow(req)
            // );
        endrule
    end
    else begin
        rule doPanic;
            immFail("not support too narrow DataStream", $format(""));
        endrule
    end

    
    // (* conflict_free = "shiftRightIdle, \
    //                     shiftRightOptput, \
    //                     shiftRightOptputExtra, \
    //                     shiftRightOptput, \
    //                     shiftRightOptputExtra" *)
    rule shiftRightIdle if (rightShiftStateReg == UniDirectionStreamShifterRightShiftStateIdle);

        let ds = rightShiftPipeQ.first;
        rightShiftPipeQ.deq;

        let pipelineEntry = UniDirectionStreamShifterPipelineEntry {
            ds: ds,
            offset: offsetPipeInQ.first
        };

        rightShiftPrevDataReg <= pipelineEntry;

        immAssert(pipelineEntry.ds.isFirst, "this rule is only for first beat", $format(""));

        if (pipelineEntry.ds.isLast) begin
            // only have one beat, no need to concat other beat
            let interShiftData = ShiftIntermediateData{
                concatData: tuple2(zeroData, pipelineEntry.ds.data),
                offset: pipelineEntry.offset,
                meta: DataStreamMeta{
                    byteNum: pipelineEntry.ds.byteNum,
                    startByteIdx: pipelineEntry.ds.startByteIdx - pipelineEntry.offset,
                    isFirst: True,
                    isLast: True
                }
            };
            doRightShiftPipeQ.enq(interShiftData);
            offsetPipeInQ.deq;
            // $display(
            //     "time=%0t: ", $time, toGreen("shiftRightIdle forward single beat data"),
            //     toBlue(", pipelineEntry="), fshow(pipelineEntry)
            // );
        end
        else begin
            rightShiftStateReg <= UniDirectionStreamShifterRightShiftStateOutputBeat;
        end
        // $display(
        //     "time=%0t: ", $time, toGreen("shiftRightIdle"),
        //     toBlue(", pipelineEntry="), fshow(pipelineEntry)
        // );
    endrule

    rule shiftRightOptput if (rightShiftStateReg == UniDirectionStreamShifterRightShiftStateOutputBeat);
        let ds = rightShiftPipeQ.first;
        rightShiftPipeQ.deq;

        let pipelineEntry = UniDirectionStreamShifterPipelineEntry {
            ds: ds,
            offset: offsetPipeInQ.first
        };

        tByteNum byteNum = rightShiftPrevDataReg.ds.byteNum;
        let inputBeatCanFitInOutputBeat = (pipelineEntry.ds.byteNum <= unpack(zeroExtend(rightShiftPrevDataReg.offset)));
        let isFirst = rightShiftPrevDataReg.ds.isFirst;
        let isLast = inputBeatCanFitInOutputBeat && pipelineEntry.ds.isLast;
        if (inputBeatCanFitInOutputBeat) begin
            if (rightShiftPrevDataReg.ds.isFirst) begin
                byteNum = byteNum + pipelineEntry.ds.byteNum;
            end
            else begin
                byteNum = byteNum + pipelineEntry.ds.byteNum - zeroExtend(pipelineEntry.offset);
            end
            
            immAssert(
                pipelineEntry.ds.isLast,
                "Since the inputBeatCanFitInOutputBeat is True, the new input beat must be last beat",
                $format("pipelineEntry=", fshow(pipelineEntry), "rightShiftPrevDataReg=", fshow(rightShiftPrevDataReg))
            );
        end
        else begin
            if (isFirst) begin
                byteNum = byteNum + zeroExtend(rightShiftPrevDataReg.offset);
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
                immAssert(
                    !isFirst && !isLast,
                    "this branch must output middle beat, but isFirst or isLast is True",
                    $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
                );
            end
        end


        let startByteIdx = isFirst ? ( rightShiftPrevDataReg.ds.startByteIdx - pipelineEntry.offset ) : 0;

        let interShiftData = ShiftIntermediateData{
            concatData: tuple2(pipelineEntry.ds.data, rightShiftPrevDataReg.ds.data),
            offset: rightShiftPrevDataReg.offset,
            meta: DataStreamMeta{
                byteNum: byteNum,
                startByteIdx: startByteIdx,
                isFirst: isFirst,
                isLast: isLast
            }
        };
        doRightShiftPipeQ.enq(interShiftData);

        if (pipelineEntry.ds.isLast && !isLast) begin
            rightShiftStateReg <= UniDirectionStreamShifterRightShiftStateOutputExtraBeat;
        end
        else if (isLast) begin
            rightShiftStateReg <= UniDirectionStreamShifterRightShiftStateIdle;
            offsetPipeInQ.deq;
        end
        
        rightShiftPrevDataReg <= pipelineEntry;

        // $display(
        //     "time=%0t:", $time, toGreen(" shiftRightOptput"),
        //     toBlue(", pipelineEntry="), fshow(pipelineEntry),
        //     toBlue(", rightShiftPrevDataReg="), fshow(rightShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );

    endrule

    rule shiftRightOptputExtra if (rightShiftStateReg == UniDirectionStreamShifterRightShiftStateOutputExtraBeat);

        let interShiftData = ShiftIntermediateData{
            concatData: tuple2(zeroData, rightShiftPrevDataReg.ds.data),
            offset: rightShiftPrevDataReg.offset,
            meta: DataStreamMeta{
                byteNum: rightShiftPrevDataReg.ds.byteNum - zeroExtend(rightShiftPrevDataReg.offset),
                startByteIdx: 0,
                isFirst: False,
                isLast: True
            }
        };
        doRightShiftPipeQ.enq(interShiftData);
        offsetPipeInQ.deq;

        if (rightShiftPipeQ.notEmpty) begin 
            let ds = rightShiftPipeQ.first;
            let pipelineEntry = UniDirectionStreamShifterPipelineEntry {
                ds: ds,
                offset: offsetPipeInQ.first
            };


            rightShiftPrevDataReg <= pipelineEntry;
            if (pipelineEntry.ds.isFirst && pipelineEntry.ds.isLast) begin
                // only have one beat, no need to concat other beat
                rightShiftStateReg <= UniDirectionStreamShifterRightShiftStateIdle;
            end
            else begin
                rightShiftPipeQ.deq;
                rightShiftStateReg <= UniDirectionStreamShifterRightShiftStateOutputBeat;
            end
        end
        else begin
            rightShiftStateReg <= UniDirectionStreamShifterRightShiftStateIdle;
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" shiftRightOptputExtra"),
        //     toBlue(", rightShiftPrevDataReg="), fshow(rightShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );
    endrule

    interface offsetPipeIn  = toPipeInB0(offsetPipeInQ);
    interface streamPipeIn  = toPipeInB0(rightShiftPipeQ);
    interface streamPipeOut = toPipeOut(rightShiftResultQ);
endmodule



// ========== IMPORTANT! =======================
// Must ensure the stream's lsb is at Right
// =============================================
module mkBiDirectionStreamShifterLsbRightG(StreamShifterG#(tData)) provisos (
        Bits#(tData, szData),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(1, szByteIdx), szByteNum),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteNum), tByteNum),
        Alias#(DtldStreamData#(tData), tDataStream),
        Alias#(BiDirectionStreamShifterPipelineEntry#(tData), tBiDirectionStreamShifterPipelineEntry),
        Alias#(ShiftIntermediateData#(tData), tShiftIntermediateData),
        NumAlias#(TSub#(TLog#(szData), 2), szShiftOffsetForLowerPartShift),
        NumAlias#(TLog#(szData), szShiftOffsetForHigherPartShift),
        Add#(a__, szByteIdx, szShiftOffsetForLowerPartShift),
        FShow#(tData),
        FShow#(tBiDirectionStreamShifterPipelineEntry),
        FShow#(Tuple2#(tData, tData))
    );
    PipeInAdapterB0#(tByteNum)    offsetPipeInQ  <- mkPipeInAdapterB0;
    PipeInAdapterB0#(tDataStream) streamPipeInQ  <- mkPipeInAdapterB0;
    FIFOF#(tDataStream) streamPipeOutQ <- mkFIFOF;

    FIFOF#(Bool) keepOrderQ <- mkSizedFIFOF(4);


    UniDirStreamShifter#(tData) rightShifter    <- mkLsbRightStreamRightShifterG;
    UniDirStreamShifter#(tData) leftShifter     <- mkLsbRightStreamLeftShifterG;

    let rightShifterOffsetPipeInConverter <- mkPipeInB0ToPipeIn(rightShifter.offsetPipeIn, 1);
    let leftShifterOffsetPipeInConverter <- mkPipeInB0ToPipeIn(leftShifter.offsetPipeIn, 1);
    let rightShifterStreamPipeInConverter <- mkPipeInB0ToPipeIn(rightShifter.streamPipeIn, 1);
    let leftShifterStreamPipeInConverter <- mkPipeInB0ToPipeIn(leftShifter.streamPipeIn, 1);

    rule doFinalOutput;
        let isShiftRight = keepOrderQ.first;
        if (isShiftRight) begin
            streamPipeOutQ.enq(rightShifter.streamPipeOut.first);
            rightShifter.streamPipeOut.deq;
            if (rightShifter.streamPipeOut.first.isLast) begin
                keepOrderQ.deq;
            end
        end
        else begin
            streamPipeOutQ.enq(leftShifter.streamPipeOut.first);
            leftShifter.streamPipeOut.deq;
            if (leftShifter.streamPipeOut.first.isLast) begin
                keepOrderQ.deq;
            end
        end
    endrule

    rule decideDirection;
        let offset = offsetPipeInQ.first;
        // positive number means shift right and negative means shift left
        let isNegativeOffset = msb(offset) == 1;
        let isShiftRight = !isNegativeOffset;
        let absOffset = getAbsValue(offset);

        let ds = streamPipeInQ.first;
        streamPipeInQ.deq;

        if (ds.isFirst) begin
            keepOrderQ.enq(isShiftRight);
            if (isShiftRight) begin
                rightShifterOffsetPipeInConverter.enq(truncate(absOffset));
            end
            else begin
                leftShifterOffsetPipeInConverter.enq(truncate(absOffset));
            end
        end

        if (ds.isLast) begin
            offsetPipeInQ.deq;
        end

        if (isShiftRight) begin
            rightShifterStreamPipeInConverter.enq(ds);
        end
        else begin
            immAssert(absOffset != 0, "The offset should not be zero, left shift path does not handle 0 offset, 0 offset should be handled by right shift path", $format(""));
            leftShifterStreamPipeInConverter.enq(ds);
        end
        // $display(
        //     "time=%0t: ", $time, toGreen("mkBiDirectionStreamShifterLsbRightG decideDirection"),
        //     toBlue(", offset="), fshow(offset),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule
    
    

    

    interface offsetPipeIn  = toPipeInB0(offsetPipeInQ);
    interface streamPipeIn  = toPipeInB0(streamPipeInQ);
    interface streamPipeOut = toPipeOut(streamPipeOutQ);
endmodule