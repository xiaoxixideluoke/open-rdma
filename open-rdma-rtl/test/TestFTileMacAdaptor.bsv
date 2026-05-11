import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;
import StmtFSM :: * ;
import MIMO :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import FTileMacAdaptor :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;

import PcieTypes :: *;
import StreamShifterG :: *;
import DtldStream :: *;
import AddressChunker :: *;


// module mkTestFtileMacRxPingPongSingleChannelProcessor(Empty);
//     let dut <- mkFtileMacRxPingPongSingleChannelProcessor;

//     Reg#(Byte) injectStepReg <- mkReg(1);
//     Reg#(Word) checkStepReg <- mkReg(0);

//     rule injectBeat if (injectStepReg <= 15);
//         injectStepReg <= injectStepReg + 1;
//         let inputMeta = ?;
//         case (injectStepReg)
//             1: begin
//                 // normal case, output one packet
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1}),
//                     eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             2: begin
//                 // normal case, output one packet, but has empty field at head and tail
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             3: begin
//                 // normal case, output one packet, but has empty field at head, and not reach eop inn this beat
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             4: begin
//                 // normal case, output one packet, but no sop, only have eop, so it's a packet with previous beat
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             5: begin
//                 // normal case, output two packet
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             6: begin
//                 // normal case, output two packet, but has gap between them
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             7: begin
//                 // normal case, output three packet, has gap between them
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0}),
//                     eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             8: begin
//                 // normal case, output three packet, has gap between them, first one is a eop, last one is a sop
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             9: begin
//                 // normal case, output one packet, no sop or eop, it's middle packet
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             10: begin
//                 // abnormal case, output four packet, with last segment invalid. won't affact next beat.
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             11: begin
//                 // abnormal case, output four packet, with last segment just eop. won't affact next beat.
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1}),
//                     eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             12: begin
//                 // abnormal case, output four packet, with last segment not eop. will affact next beat, should output overflow True
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             13: begin
//                 // abnormal case, output four packet, with first packet continous from previous beat,
//                 // and last segment not eop. will affact next beat, should output overflow True
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             14: begin
//                 // abnormal case, output five packet, with first packet continous from previous beat,
//                 // and last segment not eop. will affact next beat, should output overflow True
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
//                     eop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//             15: begin
//                 // abnormal case, output five packet, with first packet continous from previous beat,
//                 // and last segment eop. will not affact next beat, should output overflow False
//                 inputMeta = FtileMacRxPingPongSingleChannelProcessorInputMeta {
//                     bufferAddr  : zeroExtend(injectStepReg),
//                     eopEmpty    : unpack({3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0}),       
//                     sop         : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0}),
//                     eop         : unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}),
//                     fcsError    : unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0})
//                 };
//             end
//         endcase
//         dut.beatMetaPipeIn.enq(inputMeta);
//     endrule

//     rule checkBeat;
//         checkStepReg <= checkStepReg + 1;
//         let startStepOffset = 1;

//         let outMeta0 = ?;
//         let outMeta1 = ?;
//         let outMeta2 = ?;
//         let overflowFlag = ?;
//         let packestMeta = ?;

//         if (dut.packetsChunkMetaPipeOut.notEmpty) begin
//             dut.packetsChunkMetaPipeOut.deq; 
//             packestMeta = dut.packetsChunkMetaPipeOut.first;

//             outMeta0 = fromMaybe(?, packestMeta.packetChunkMetaVector[0]);
//             outMeta1 = fromMaybe(?, packestMeta.packetChunkMetaVector[1]);
//             outMeta2 = fromMaybe(?, packestMeta.packetChunkMetaVector[2]);
//             overflowFlag = packestMeta.packetNumOverflowAffectNextBeat;
//         end

//         case (checkStepReg)
//             (1 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (1 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 15 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (2 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("outMeta0=", fshow(outMeta0), "outMeta1=", fshow(outMeta1), "outMeta2=", fshow(outMeta2))
//                 );
//             end
//             (2 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 1 && 
//                     outMeta0.zeroBasedValidSegCnt == 12 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (3 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (3 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 1 && 
//                     outMeta0.zeroBasedValidSegCnt == 14 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (4 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (4 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 4 &&
//                     outMeta0.isFirst == False && outMeta0.isLast == True,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (5 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (5 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 1 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 3 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     overflowFlag == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (6 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (6 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 1 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 4 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     overflowFlag == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (7 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (7 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 1 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 4 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 14 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == True &&
//                     overflowFlag == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (8 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (8 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 2 &&
//                     outMeta0.isFirst == False && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 4 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 14 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == False &&
//                     overflowFlag == False,
//                     "check error",$format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (9 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (9 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && !isValid(packestMeta.packetChunkMetaVector[1]) && !isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 15 &&
//                     outMeta0.isFirst == False && outMeta0.isLast == False &&
//                     overflowFlag == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (10 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (10 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 2 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 5 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == True &&
//                     overflowFlag == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (11 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (11 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 2 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 5 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == True &&
//                     overflowFlag == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (12 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (12 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == True && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 2 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 5 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == True &&
//                     overflowFlag == True,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (13 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (13 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == False && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 2 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 5 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == True &&
//                     overflowFlag == True,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (14 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (14 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == False && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 2 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 5 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == True &&
//                     overflowFlag == True,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (15 * 16 - 1 + startStepOffset): begin
//                 immAssert(
//                     !dut.packetsChunkMetaPipeOut.notEmpty,
//                     "check error",
//                     $format("")
//                 );
//             end
//             (15 * 16 + startStepOffset): begin
//                 immAssert(
//                     isValid(packestMeta.packetChunkMetaVector[0]) && isValid(packestMeta.packetChunkMetaVector[1]) && isValid(packestMeta.packetChunkMetaVector[2]) &&
//                     outMeta0.startSegIdx == 0 && 
//                     outMeta0.zeroBasedValidSegCnt == 1 &&
//                     outMeta0.isFirst == False && outMeta0.isLast == True &&
//                     outMeta1.startSegIdx == 2 && 
//                     outMeta1.zeroBasedValidSegCnt == 1 &&
//                     outMeta1.isFirst == True && outMeta1.isLast == True &&
//                     outMeta2.startSegIdx == 5 && 
//                     outMeta2.zeroBasedValidSegCnt == 1 &&
//                     outMeta2.isFirst == True && outMeta2.isLast == True &&
//                     overflowFlag == False,
//                     "check error",
//                     $format("outMeta0=", fshow(packestMeta.packetChunkMetaVector[0]), "outMeta1=", fshow(packestMeta.packetChunkMetaVector[1]), "outMeta2=", fshow(packestMeta.packetChunkMetaVector[2]), "overflowFlag=", fshow(overflowFlag))
//                 );
//             end
//             (16 * 16 + startStepOffset): begin
//                 $finish;
//             end
//         endcase
//     endrule
// endmodule



// interface TestFtileMacRxPingPongSingleChannelProcessorTimingTest;
//     method Bit#(128) getOutput;
// endinterface


// (* synthesize *)
// module mkTestFtileMacRxPingPongSingleChannelProcessorTimingTest(TestFtileMacRxPingPongSingleChannelProcessorTimingTest);
//     Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);
//     Reg#(Bool) runReg <- mkReg(True);
//     Reg#(Bit#(128)) outReg <- mkReg(0);

//     let dut <- mkFtileMacRxPingPongSingleChannelProcessor;

//     ForceKeepWideSignals#(Bit#(128), Bit#(128)) signalKeeperForOutput   <- mkForceKeepWideSignals; 
    

//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);


//     rule injectInput if (runReg);
//         let randValue1 <- randSource1.get;
//         let inputMeta = unpack(truncate(randValue1));
//         dut.beatMetaPipeIn.enq(inputMeta);
//     endrule

//     rule handleDutOutput;
//         dut.packetsChunkMetaPipeOut.deq;

//         signalKeeperForOutput.bitsPipeIn.enq(zeroExtend(pack(dut.packetsChunkMetaPipeOut.first)));
//     endrule

//     rule forwardOutput;
//         outReg <= signalKeeperForOutput.out;
//     endrule



//     method getOutput = outReg;
// endmodule




// module mkTestFtileMacRxPingPongChannelMetaJoin(Empty);

//     let ftileMacRxBeatFork <- mkFtileMacRxBeatFork;
//     Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FtileMacRxPingPongSingleChannelProcessor) pingPongChannelVec <- replicateM(mkFtileMacRxPingPongSingleChannelProcessor); 
//     let ftileMacRxBeatJoin <- mkFtileMacRxPingPongChannelMetaJoin;

//     for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
//         mkConnection(ftileMacRxBeatFork.rxPingPongChannelMetaPipeOutVec[idx], pingPongChannelVec[idx].beatMetaPipeIn);
//         mkConnection(pingPongChannelVec[idx].packetsChunkMetaPipeOut, ftileMacRxBeatJoin.metaPipeInVec[idx]);
//     end

//     Reg#(Word) injectStepReg <- mkReg(1);
//     Reg#(Word) checkStepReg <- mkReg(0);

//     Reg#(Word) totalRecvPacketCntReg <- mkReg(0);
//     Reg#(Word) totalRecvSegmentCntReg <- mkReg(0);

//     rule discard;
//         ftileMacRxBeatFork.rxBramWriteReqPipeOut.deq;
//     endrule

//     rule injectBeat;
//         injectStepReg <= injectStepReg + 1;
//         FtileMacRxBeat inputBeat = ?;
//         case (injectStepReg)
//             // normal case, for the 1st to 4th beat, each beat has one or two packet.
//             1: begin
//                 // 1 packet, 10 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             2: begin
//                 // 2 packet, 9 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.eop       = unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             3: begin
//                 // 1 packet, 16 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
//                 inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             4: begin
//                 // one packet, 16 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
//                 inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end

//             // normal case, for the 1st to 5th beat, each beat has one or two packet, but some packet will span multi beat
//             31: begin
//                 // 2 packet, 16 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             32: begin
//                 // 1 packet, 16 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             33: begin
//                 // 1 packet, 16 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             34: begin
//                 // 2 packet, 16 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             35: begin
//                 // 3 packet, 16 seg
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0});
//                 inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end

//             // abnormal case
//             100: begin
//                 // 3 packet, but middle packet is error, so only 2 packet should be output, valid seg cnt = 11
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1});
//                 inputBeat.eop       = unpack({1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             101: begin
//                 // 4 packet, overflow but not affact next beat.  so only 3 packet should be output, valid seg cnt = 6
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             102: begin
//                 // 4 packet, overflow and will affact next beat.  so only 3 packet should be output, valid seg cnt = 6
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             103: begin
//                 // 1 packet, but is affacted by previous overflow, should be dropped
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.eop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//             104: begin
//                 // 3 packet, but first packet is affacted by previous overflow. so only 2 packet should be output, valid seg cnt = 14
//                 inputBeat.sop       = unpack({1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0});
//                 inputBeat.eop       = unpack({1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0});
//                 inputBeat.fcs_error = 0;
//                 ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//             end
//         endcase
//     endrule

//     rule checkBeat;
//         checkStepReg <= checkStepReg + 1;

//         Word totalRecvPacketCnt  = totalRecvPacketCntReg;
//         Word totalRecvSegmentCnt = totalRecvSegmentCntReg;

//         for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
//             if (ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].notEmpty) begin
//                 let outputMeta = ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].first;
//                 ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].deq;
//                 totalRecvPacketCnt = totalRecvPacketCnt + 1;
//                 totalRecvSegmentCnt = totalRecvSegmentCnt + zeroExtend(outputMeta.zeroBasedValidSegCnt) + 1;
//                 $display("time=%0t:", $time, "idx=%d", idx , "outputMeta=", fshow(outputMeta));
//             end
//         end



//         case (checkStepReg)
//             30: begin
//                 immAssert(
//                     totalRecvPacketCnt == 6 && totalRecvSegmentCnt == 51,
//                     "packet num or seg num wrong",
//                     $format("totalRecvPacketCnt=", fshow(totalRecvPacketCnt), ", totalRecvSegmentCnt=", fshow(totalRecvSegmentCnt))
//                 );
//                 // reset counter
//                 totalRecvPacketCnt = 0;
//                 totalRecvSegmentCnt = 0;
//             end
//             100: begin
//                 immAssert(
//                     totalRecvPacketCnt == 9 && totalRecvSegmentCnt == 80,
//                     "packet num or seg num wrong",
//                     $format("totalRecvPacketCnt=", fshow(totalRecvPacketCnt), ", totalRecvSegmentCnt=", fshow(totalRecvSegmentCnt))
//                 );
//                 // reset counter
//                 totalRecvPacketCnt = 0;
//                 totalRecvSegmentCnt = 0;
//             end
//             150: begin
//                 immAssert(
//                     totalRecvPacketCnt == 10 && totalRecvSegmentCnt == 37,
//                     "packet num or seg num wrong",
//                     $format("totalRecvPacketCnt=", fshow(totalRecvPacketCnt), ", totalRecvSegmentCnt=", fshow(totalRecvSegmentCnt))
//                 );
//                 // reset counter
//                 totalRecvPacketCnt = 0;
//                 totalRecvSegmentCnt = 0;
//             end
//             2000: begin
//                 $finish;
//             end
//         endcase


//         totalRecvPacketCntReg   <= totalRecvPacketCnt;
//         totalRecvSegmentCntReg  <= totalRecvSegmentCnt;
//     endrule
// endmodule




// interface TestFtileMacRxPingPongChannelMetaJoinTimingTest;
//     method Bit#(128) getOutput;
// endinterface


// (* synthesize *)
// module mkTestFtileMacRxPingPongChannelMetaJoinTimingTest(TestFtileMacRxPingPongChannelMetaJoinTimingTest);
//     Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);
//     Reg#(Bool) runReg <- mkReg(True);
//     Reg#(Bit#(128)) outReg <- mkReg(0);

//     let ftileMacRxBeatFork <- mkFtileMacRxBeatFork;
//     Vector#(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT, FtileMacRxPingPongSingleChannelProcessor) pingPongChannelVec <- replicateM(mkFtileMacRxPingPongSingleChannelProcessor); 
//     let ftileMacRxBeatJoin <- mkFtileMacRxPingPongChannelMetaJoin;

//     for (Integer idx = 0; idx < valueOf(FTILE_MAC_RX_PING_PONG_CHANNEL_CNT); idx = idx + 1) begin
//         mkConnection(ftileMacRxBeatFork.rxPingPongChannelMetaPipeOutVec[idx], pingPongChannelVec[idx].beatMetaPipeIn);
//         mkConnection(pingPongChannelVec[idx].packetsChunkMetaPipeOut, ftileMacRxBeatJoin.metaPipeInVec[idx]);
//     end

//     ForceKeepWideSignals#(Bit#(128), Bit#(128)) signalKeeperForOutput   <- mkForceKeepWideSignals; 
    

//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
//     let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
//     let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);


//     rule discard;
//         ftileMacRxBeatFork.rxBramWriteReqPipeOut.deq;
//     endrule

//     rule injectInput if (runReg);
//         let randValue1 <- randSource1.get;
//         let randValue2 <- randSource2.get;
//         let randValue3 <- randSource3.get;

//         let inputBeat = unpack(truncate({randValue1, randValue2, randValue3}));
//         ftileMacRxBeatFork.rxBetaPipeIn.enq(inputBeat);
//     endrule

//     rule handleDutOutput;
//         FtileMacRxPacketChunkMeta outputMeta = ?;
//         for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
//             if (ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].notEmpty) begin
//                 outputMeta = unpack(pack(outputMeta) ^ pack(ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].first));
//                 ftileMacRxBeatJoin.packetChunkMetaPipeOutVec[idx].deq;
//             end
//         end

//         signalKeeperForOutput.bitsPipeIn.enq(zeroExtend(pack(outputMeta)));
//     endrule

//     rule forwardOutput;
//         outReg <= signalKeeperForOutput.out;
//     endrule



//     method getOutput = outReg;
// endmodule



// module mkTestFtileMacRxPayloadStorageAndGearBox(Empty);

//     let dut <- mkFtileMacRxPayloadStorageAndGearBox;

//     Reg#(Word) injectStepReg <- mkReg(1);
//     Reg#(Word) checkStepReg <- mkReg(0);

    

//     Stmt injectProc = seq
//         dut.rxBramWriteReqPipeIn.enq(FtileMacRxBramBufferWriteReq{
//             addr: 0,
//             data: unpack({64'hF, 64'hE, 64'hD, 64'hC, 64'hB, 64'hA, 64'h9, 64'h8, 64'h7, 64'h6, 64'h5, 64'h4, 64'h3, 64'h2, 64'h1, 64'h0})
//         });
//         dut.rxBramWriteReqPipeIn.enq(FtileMacRxBramBufferWriteReq{
//             addr: 1,
//             data: unpack({64'h0, 64'h1, 64'h2, 64'h3, 64'h4, 64'h5, 64'h6, 64'h7, 64'h8, 64'h9, 64'hA, 64'hB, 64'hC, 64'hD, 64'hE, 64'hF})
//         });

//         // Case 1
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 1;
//             req.startSegIdx             = 0;
//             req.zeroBasedValidSegCnt    = 15;
//             req.lastSegEmptyByteCnt     = 2;
//             req.isFirst                 = True;
//             req.isLast                  = True;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction

//         // Case 2
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 0;
//             req.startSegIdx             = 0;
//             req.zeroBasedValidSegCnt    = 1;
//             req.lastSegEmptyByteCnt     = 2;
//             req.isFirst                 = True;
//             req.isLast                  = True;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction

//         // Case 3
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 1;
//             req.startSegIdx             = 1;
//             req.zeroBasedValidSegCnt    = 1;
//             req.lastSegEmptyByteCnt     = 2;
//             req.isFirst                 = True;
//             req.isLast                  = True;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction

//         // Case 4
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 0;
//             req.startSegIdx             = 3;
//             req.zeroBasedValidSegCnt    = 4;
//             req.lastSegEmptyByteCnt     = 2;
//             req.isFirst                 = True;
//             req.isLast                  = True;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction

//         // Case 5
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 1;
//             req.startSegIdx             = 3;
//             req.zeroBasedValidSegCnt    = 0;
//             req.lastSegEmptyByteCnt     = 1;
//             req.isFirst                 = True;
//             req.isLast                  = True;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction

//         // Case 6
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 0;
//             req.startSegIdx             = 15;
//             req.zeroBasedValidSegCnt    = 0;
//             req.lastSegEmptyByteCnt     = ?;
//             req.isFirst                 = True;
//             req.isLast                  = False;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 1;
//             req.startSegIdx             = 0;
//             req.zeroBasedValidSegCnt    = 0;
//             req.lastSegEmptyByteCnt     = 7;
//             req.isFirst                 = False;
//             req.isLast                  = True;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction

//         // Case 7
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 0;
//             req.startSegIdx             = 11;
//             req.zeroBasedValidSegCnt    = 4;
//             req.lastSegEmptyByteCnt     = ?;
//             req.isFirst                 = True;
//             req.isLast                  = False;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 1;
//             req.startSegIdx             = 0;
//             req.zeroBasedValidSegCnt    = 15;
//             req.lastSegEmptyByteCnt     = ?;
//             req.isFirst                 = False;
//             req.isLast                  = False;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction
//         action
//             FtileMacRxPacketChunkMeta req = ?;
//             req.bufferAddr              = 0;
//             req.startSegIdx             = 0;
//             req.zeroBasedValidSegCnt    = 4;
//             req.lastSegEmptyByteCnt     = 3;
//             req.isFirst                 = False;
//             req.isLast                  = True;
//             dut.packetChunkMetaPipeIn.enq(req);
//         endaction
//     endseq;


//     let outPipeOut = dut.streamPipeOut;
//     Stmt checkProc = (seq
//         // Case 1
//         action
//             dut.streamPipeOut.deq;
//             immAssert(outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'hF, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'hB, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'h7, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 30 && outPipeOut.first.data[3:0] == 4'h3, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//             $display("Case 1 pass");
//         endaction

//         // Case 2
//         action
//             dut.streamPipeOut.deq;
//             immAssert(outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 14 && outPipeOut.first.data[3:0] == 4'h0, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//             $display("Case 2 pass");
//         endaction

//         // Case 3
//         action
//             dut.streamPipeOut.deq;
//             immAssert(outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 14 && outPipeOut.first.data[3:0] == 4'hE, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//             $display("Case 3 pass");
//         endaction

//         // Case 4
//         action
//             dut.streamPipeOut.deq;
//             immAssert(outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'h3, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 6 && outPipeOut.first.data[3:0] == 4'h7, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//             $display("Case 4 pass");
//         endaction

//         // Case 5
//         action
//             dut.streamPipeOut.deq;
//             immAssert(outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 7 && outPipeOut.first.data[3:0] == 4'hC, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//             $display("Case 5 pass");
//         endaction

//         // Case 6
//         action
//             dut.streamPipeOut.deq;
//             immAssert(outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 9 && outPipeOut.first.data[3:0] == 4'hF && outPipeOut.first.data[64+3:64+0] == 4'hF, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//             $display("Case 6 pass");
//         endaction

//         // Case 7
//         action
//             dut.streamPipeOut.deq;
//             immAssert(outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'hB, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'hF, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'hC, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'h8, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'h4, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && !outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 32 && outPipeOut.first.data[3:0] == 4'h0, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//         endaction
//         action
//             dut.streamPipeOut.deq;
//             immAssert(!outPipeOut.first.isFirst && outPipeOut.first.isLast && outPipeOut.first.startByteIdx == 0 && outPipeOut.first.byteNum == 13 && outPipeOut.first.data[3:0] == 4'h3, "assert Fail", $format("dsOut=", fshow(outPipeOut.first)));
//             $display("Case 7 pass");
//         endaction

//         $finish;
//     endseq);

//     FSM injectFSM <- mkFSM(injectProc);
//     FSM checkFSM  <- mkFSM(checkProc);
    
//     Reg#(Bool) goingReg <- mkReg(False);

//     rule start (!goingReg);
//         goingReg <= True;
//         injectFSM.start;
//         checkFSM.start;
//     endrule
// endmodule




// interface TestFtileMacAdaptorTimingTest;
//     method Bit#(128) getOutput;
// endinterface

// (* synthesize *)
// module mkTestFtileMacAdaptorTimingTest(TestFtileMacAdaptorTimingTest);
//     Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);
//     Reg#(Bool) runReg <- mkReg(True);
//     Reg#(Bit#(128)) outReg <- mkReg(0);

//     let ftileMac <- mkFTileMac;
//     let dut <- mkFTileMacAdaptor;

//     mkConnection(dut.ftilemacRxPipeOut, ftileMac.ftilemacRxPipeIn);
//     mkConnection(dut.ftilemacTxPipeIn, ftileMac.ftilemacTxPipeOut);


//     ForceKeepWideSignals#(Bit#(2048), Bit#(32)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 
//     ForceKeepWideSignals#(Bit#(512), Bit#(16)) signalKeeperForRxBusOutput           <- mkForceKeepWideSignals; 
//     ForceKeepWideSignals#(Bit#(4164), Bit#(32)) signalKeeperForUserLogicReadOutput   <- mkForceKeepWideSignals; 
    

//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
//     let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
//     let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
//     let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
//     let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
//     let randSource6 <- mkSynthesizableRng512('h11111111);
//     let randSource7 <- mkSynthesizableRng512('h22222222);
//     let randSource8 <- mkSynthesizableRng512('h33333333);
//     let randSource9 <- mkSynthesizableRng512('h44444444);
//     let randSourceA <- mkSynthesizableRng512('h55555555);
//     let randSourceB <- mkSynthesizableRng512('h66666666);
//     let randSourceC <- mkSynthesizableRng512('h77777777);
//     let randSourceD <- mkSynthesizableRng512('h88888888);


//     Reg#(Bit#(2048)) rxBusInputSignalReg <- mkReg(0);
//     Reg#(Bit#(512)) txBusInputSignalReg <- mkReg(0);

//     Reg#(Bit#(512)) rxBusOutputSignalReg <- mkReg(0);
//     Reg#(Bit#(2048)) txBusOutputSignalReg <- mkReg(0);

//     rule injectUserLogicReq if (runReg);
        
//         let randValue1 <- randSource1.get;
//         let randValue2 <- randSource2.get;
//         let randValue3 <- randSource3.get;
//         let randValue4 <- randSource4.get;
//         let randValue5 <- randSource5.get;


//         let writeStream1 = unpack(truncate(randValue1));
//         let writeStream2 = unpack(truncate(randValue2));
//         let writeStream3 = unpack(truncate(randValue3));
//         let writeStream4 = unpack(truncate(randValue4));

//         // write req
//         ftileMac.ftilemacTxStreamPipeInVec[0].enq(writeStream1);
//         ftileMac.ftilemacTxStreamPipeInVec[1].enq(writeStream2);
//         ftileMac.ftilemacTxStreamPipeInVec[2].enq(writeStream3);
//         ftileMac.ftilemacTxStreamPipeInVec[3].enq(writeStream4);
//     endrule

//     rule updateBusSignalReg;
//         let randValue6 <- randSource6.get;
//         let randValue7 <- randSource7.get;
//         let randValue8 <- randSource8.get;
//         let randValue9 <- randSource9.get;
//         let randValueA <- randSourceA.get;

//         rxBusInputSignalReg <= {randValue6, randValue7, randValue8, randValue9};
//         txBusInputSignalReg <= {randValueA};
//     endrule

//     rule handleRxBusInputSignals;
//         FtileMacDataBusSegBundle        data;
//         Bool                            valid;
//         SegmentInframeSignalBundle      inframe;
//         SegmentEopEmptySignalBundle     eop_empty;
//         SegmentFcsErrorSignalBundle     fcs_error;
//         SegmentRxMacErrorSignalBundle   error;
//         SegmentStatusDataSignalBundle   status_data;

//         {data, valid, inframe, eop_empty, fcs_error, error, status_data} = unpack(truncate(rxBusInputSignalReg));
//         dut.rx.setRxInputData(data, valid, inframe, eop_empty, fcs_error, error, status_data);
//     endrule

//     rule handleRxBusOutputSignals;
//         rxBusOutputSignalReg <= zeroExtend({
//             pack(dut.rx.ready)
//         });
//         signalKeeperForRxBusOutput.bitsPipeIn.enq(zeroExtend(pack(rxBusOutputSignalReg)));
//     endrule

//     rule handleTxBusInputSignals;
//         Bool                                ready;
//         {ready} = unpack(truncate(txBusInputSignalReg));
//         dut.tx.setTxInputData(ready);
//     endrule

//     rule handleTxBusOutputSignals;
//         txBusOutputSignalReg <= zeroExtend({
//             pack(dut.tx.data),
//             pack(dut.tx.valid),
//             pack(dut.tx.inframe),
//             pack(dut.tx.eop_empty),
//             pack(dut.tx.error),
//             pack(dut.tx.skip_crc)
//         });
//         signalKeeperForTxBusOutput.bitsPipeIn.enq(zeroExtend(pack(txBusOutputSignalReg)));
//     endrule

//     rule handleUSerlogicReadOutput;
//         Vector#(NUMERIC_TYPE_FOUR, FtileMacRxUserStream) resultVec = newVector;

//         for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
//             if (ftileMac.ftilemacRxStreamPipeOutVec[idx].notEmpty) begin
//                 resultVec[idx] = ftileMac.ftilemacRxStreamPipeOutVec[idx].first;
//                 ftileMac.ftilemacRxStreamPipeOutVec[idx].deq;
//             end
//         end

//         signalKeeperForUserLogicReadOutput.bitsPipeIn.enq(zeroExtend(pack(resultVec)));

//     endrule


//     rule handleOutput;
//         outReg <= zeroExtend({signalKeeperForRxBusOutput.out, signalKeeperForTxBusOutput.out, signalKeeperForUserLogicReadOutput.out});
//     endrule



//     method getOutput = outReg;
// endmodule



// interface TestRotateTimingTest;
//     method Bit#(128) getOutput;
// endinterface

// (* synthesize *)
// module mkTestRotateTimingTest(TestRotateTimingTest);
//     Reg#(Bit#(128)) outReg <- mkReg(0);
//     Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
//     Reg#(Bit#(2))  rotReg <- mkReg(0);


//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
//     let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

//     Reg#(Vector#(32, Bit#(64))) testReg <- mkRegU;
//     ForceKeepWideSignals#(Bit#(2048), Bit#(128)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 

//     rule test;
//         stepCounterReg <= stepCounterReg + 1;
//         rotReg <= rotReg + 1;
//         let randValue1 <- randSource1.get;
//         let randValue2 <- randSource2.get;
//         if (stepCounterReg == 0) begin
//             testReg <= unpack({0, randValue1, randValue2});
//         end
//         else begin
//             let t = testReg;
//             case (rotReg)
//                 0: begin
//                     t = shiftInAt0(t, unpack(truncate(randValue2)));
//                 end
//                 1: begin
//                     t = shiftInAt0(t, unpack(truncate(randValue2)));
//                     t = shiftInAt0(t, unpack(truncate(randValue1)));
//                 end
//                 2: begin
//                     t = shiftInAt0(t, unpack(truncate(randValue2)));
//                     t = shiftInAt0(t, unpack(truncate(randValue1)));
//                     t = shiftInAt0(t, unpack(truncateLSB(randValue2)));
//                 end
//                 3: begin
//                     t = shiftInAt0(t, unpack(truncate(randValue2)));
//                     t = shiftInAt0(t, unpack(truncate(randValue1)));
//                     t = shiftInAt0(t, unpack(truncateLSB(randValue2)));
//                     t = shiftInAt0(t, unpack(truncateLSB(randValue1)));
//                 end 
//             endcase
//             testReg <= t;
            
//         end
//         signalKeeperForTxBusOutput.bitsPipeIn.enq(pack(testReg));
//     endrule



//     rule handleOutput;
//         outReg <= zeroExtend({signalKeeperForTxBusOutput.out});
//     endrule

//     method getOutput = outReg;
// endmodule



// interface TestMimoTimingTest;
//     method Bit#(128) getOutput;
// endinterface

// (* synthesize *)
// module mkTestMimoTimingTest(TestMimoTimingTest);
//     Reg#(Bit#(128)) outReg <- mkReg(0);
//     Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
//     Reg#(Bit#(2))  rotReg <- mkReg(0);

//     let mimoCfg = MIMOConfiguration {
//         unguarded: True,
//         bram_based: False
//     };

//     MIMO#(2, 2, 4, Bit#(256)) dut <- mkMIMO(mimoCfg);

//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
//     let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

//     ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 

//     rule test;
//         stepCounterReg <= stepCounterReg + 1;
//         rotReg <= rotReg + 1;
//         let randValue1 <- randSource1.get;
//         let randValue2 <- randSource2.get;
        
//         LUInt#(2) cntEnq = unpack(truncate(randValue1));
//         if (dut.enqReadyN(cntEnq)) begin
//             dut.enq(cntEnq, vec(truncate(randValue1), truncateLSB(randValue1)));
//         end

//         LUInt#(2) cntDeq = unpack(truncate(randValue2));
//         if (dut.deqReadyN(cntDeq)) begin
//             dut.deq(cntDeq);
//             signalKeeperForTxBusOutput.bitsPipeIn.enq(pack(dut.first));
//         end
//     endrule



//     rule handleOutput;
//         outReg <= zeroExtend({signalKeeperForTxBusOutput.out});
//     endrule

//     method getOutput = outReg;
// endmodule



// interface TestFtileMacTxPingPongForkTimingTest;
//     method Bit#(128) getOutput;
// endinterface

// (* synthesize *)
// module mkTestFtileMacTxPingPongForkTimingTest(TestFtileMacTxPingPongForkTimingTest);
//     Reg#(Bit#(128)) outReg <- mkReg(0);
//     Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
//     Reg#(Bit#(2))  rotReg <- mkReg(0);

//     ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 

//     let dut <- mkFtileMacTxPingPongFork;
    

//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
//     let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

//     rule inject;
//         let randValue1 <- randSource1.get;
//         let randValue2 <- randSource2.get;

//         if (randValue1[0] == 1) begin
//             dut.packetMetaPipeInVec[0].enq(unpack(truncate(randValue1)));
//         end
//         if (randValue1[1] == 1) begin
//             dut.packetMetaPipeInVec[1].enq(unpack(truncateLSB(randValue1)));
//         end
//         if (randValue1[2] == 1) begin
//             dut.packetMetaPipeInVec[2].enq(unpack(truncate(randValue2)));
//         end
//         if (randValue1[3] == 1) begin
//             dut.packetMetaPipeInVec[3].enq(unpack(truncateLSB(randValue2)));
//         end
//     endrule

//     rule deq;
//         Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, FtileMacTxPingPongChannelMetaBundle) res = newVector;
//         if (dut.pingpongChannelMetaPipeOutVec[0].notEmpty) begin
//             res[0] = dut.pingpongChannelMetaPipeOutVec[0].first;
//             dut.pingpongChannelMetaPipeOutVec[0].deq;
//         end
//         if (dut.pingpongChannelMetaPipeOutVec[1].notEmpty) begin
//             res[1] = dut.pingpongChannelMetaPipeOutVec[1].first;
//             dut.pingpongChannelMetaPipeOutVec[1].deq;
//         end
//         if (dut.pingpongChannelMetaPipeOutVec[2].notEmpty) begin
//             res[2] = dut.pingpongChannelMetaPipeOutVec[2].first;
//             dut.pingpongChannelMetaPipeOutVec[2].deq;
//         end
//         if (dut.pingpongChannelMetaPipeOutVec[3].notEmpty) begin
//             res[3] = dut.pingpongChannelMetaPipeOutVec[3].first;
//             dut.pingpongChannelMetaPipeOutVec[3].deq;
//         end

//         signalKeeperForTxBusOutput.bitsPipeIn.enq(zeroExtend(pack(res)));
//     endrule



//     rule handleOutput;
//         outReg <= zeroExtend({signalKeeperForTxBusOutput.out});
//     endrule
    
//     method getOutput = outReg;
// endmodule



// module mkTestFtileTx(Empty);

//     Reg#(Word) injectStepReg <- mkReg(1);
//     Reg#(Word) checkStepReg <- mkReg(0);


//     Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, FtileMacTxUserInputGearboxStorageAndMetaExtractor) txInputChannelVec <- replicateM(mkFtileMacTxUserInputGearboxStorageAndMetaExtractor);
//     let ftileMacTxBeatFork <- mkFtileMacTxPingPongFork;
//     Vector#(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT, FtileMacTxPingPongSingleChannel) txPingPongChannelVec <- replicateM(mkFtileMacTxPingPongSingleChannel);
//     let ftileMacTxBeatJoin <- mkFtileMacTxPingPongJoin;

//     for (Integer inputChannelIdx = 0; inputChannelIdx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); inputChannelIdx = inputChannelIdx + 1) begin
//         for (Integer pingpongChannelIdx = 0; pingpongChannelIdx < valueOf(FTILE_MAC_TX_PING_PONG_CHANNEL_CNT); pingpongChannelIdx = pingpongChannelIdx + 1) begin
//             mkConnection(txPingPongChannelVec[pingpongChannelIdx].bramReadReqPipeOutVec[inputChannelIdx], txInputChannelVec[inputChannelIdx].bramReadReqPipeInVec[pingpongChannelIdx]);
//             mkConnection(txInputChannelVec[inputChannelIdx].bramReadRespPipeOutVec[pingpongChannelIdx], txPingPongChannelVec[pingpongChannelIdx].bramReadRespPipeInVec[inputChannelIdx]);
//         end
//     end


//     for (Integer idx = 0; idx < valueOf(FTILE_MAC_USER_LOGIC_CHANNEL_CNT); idx = idx + 1) begin
//         mkConnection(txInputChannelVec[idx].packetMetaPipeOut, ftileMacTxBeatFork.packetMetaPipeInVec[idx]);
//         mkConnection(ftileMacTxBeatFork.pingpongChannelMetaPipeOutVec[idx], txPingPongChannelVec[idx].metaPipeIn);
//         mkConnection(txPingPongChannelVec[idx].beatPipeOut, ftileMacTxBeatJoin.pingpongBeatPipeInVec[idx]);
//     end

    

//     Stmt injectProc = seq
//         // case 1
//         par
//             seq
//                 txInputChannelVec[0].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h11111117_11111116_11111115_11111114_11111113_11111112_11111111_11111110, byteNum: 32, startByteIdx: 0, isFirst: True,  isLast: False});
//                 txInputChannelVec[0].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h22222227_22222226_22222225_22222224_22222223_22222222_22222221_22222220, byteNum: 32, startByteIdx: 0, isFirst: False, isLast: True});
//                 txInputChannelVec[0].streamPipeIn.enq(FtileMacTxUserStream {data: 256'hDDDDDDD7_DDDDDDD6_DDDDDDD5_DDDDDDD4_DDDDDDD3_DDDDDDD2_DDDDDDD1_DDDDDDD0, byteNum: 32, startByteIdx: 0, isFirst: True,  isLast: False});
//                 txInputChannelVec[0].streamPipeIn.enq(FtileMacTxUserStream {data: 256'hEEEEEEE7_EEEEEEE6_EEEEEEE5_EEEEEEE4_EEEEEEE3_EEEEEEE2_EEEEEEE1_EEEEEEE0, byteNum: 5,  startByteIdx: 0, isFirst: False, isLast: True});
//             endseq
//             seq
//                 txInputChannelVec[1].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h33333337_33333336_33333335_33333334_33333333_33333332_33333331_33333330, byteNum: 32, startByteIdx: 0, isFirst: True,  isLast: False});
//                 txInputChannelVec[1].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h44444447_44444446_44444445_44444444_44444443_44444442_44444441_44444440, byteNum: 32, startByteIdx: 0, isFirst: False, isLast: False});
//                 txInputChannelVec[1].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h55555557_55555556_55555555_55555554_55555553_55555552_55555551_55555550, byteNum: 2,  startByteIdx: 0, isFirst: False, isLast: True});
//             endseq
//             seq
//                 txInputChannelVec[2].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h66666667_66666666_66666665_66666664_66666663_66666662_66666661_66666660, byteNum: 32, startByteIdx: 0, isFirst: True,  isLast: False});
//                 txInputChannelVec[2].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h77777777_77777776_77777775_77777774_77777773_77777772_77777771_77777770, byteNum: 32, startByteIdx: 0, isFirst: False, isLast: False});
//                 txInputChannelVec[2].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h88888887_88888886_88888885_88888884_88888883_88888882_88888881_88888880, byteNum: 16, startByteIdx: 0, isFirst: False, isLast: True});
//             endseq
//             seq
//                 txInputChannelVec[3].streamPipeIn.enq(FtileMacTxUserStream {data: 256'h99999997_99999996_99999995_99999994_99999993_99999992_99999991_99999990, byteNum: 32, startByteIdx: 0, isFirst: True,  isLast: False});
//                 txInputChannelVec[3].streamPipeIn.enq(FtileMacTxUserStream {data: 256'hAAAAAAA7_AAAAAAA6_AAAAAAA5_AAAAAAA4_AAAAAAA3_AAAAAAA2_AAAAAAA1_AAAAAAA0, byteNum: 32, startByteIdx: 0, isFirst: False, isLast: False});
//                 txInputChannelVec[3].streamPipeIn.enq(FtileMacTxUserStream {data: 256'hBBBBBBB7_BBBBBBB6_BBBBBBB5_BBBBBBB4_BBBBBBB3_BBBBBBB2_BBBBBBB1_BBBBBBB0, byteNum: 32, startByteIdx: 0, isFirst: False, isLast: False});
//                 txInputChannelVec[3].streamPipeIn.enq(FtileMacTxUserStream {data: 256'hCCCCCCC7_CCCCCCC6_CCCCCCC5_CCCCCCC4_CCCCCCC3_CCCCCCC2_CCCCCCC1_CCCCCCC0, byteNum: 19, startByteIdx: 0, isFirst: False, isLast: True});
//             endseq
//         endpar
//     endseq;


//     let outPipeOut = ftileMacTxBeatJoin.ftilemacTxPipeOut;
//     Stmt checkProc = (seq
//         // Case 1
//         action
//             outPipeOut.deq;
//             let beat = outPipeOut.first;
//             immAssert(
//                 beat.inframe    == unpack('hff7f) &&
//                 beat.eop_empty  == vec(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) &&
//                 beat.data[0]    == 'h11111111_11111110 && 
//                 beat.data[15]   == 'h44444447_44444446,
//                 "Error",
//                 $format("beat=", fshow(beat)) 
//             );
//         endaction
//         action
//             outPipeOut.deq;
//             let beat = outPipeOut.first;
//             immAssert(
//                 beat.inframe    == 'h1ff0 &&
//                 beat.eop_empty  == vec(6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0) &&
//                 beat.data[0]    == 'h55555551_55555550 && 
//                 beat.data[15]   == 'h88888887_88888886,
//                 "Error",
//                 $format("beat=", fshow(beat)) 
//             );
//         endaction
//         action
//             outPipeOut.deq;
//             let beat = outPipeOut.first;
//             immAssert(
//                 beat.inframe    == 'h3fff &&
//                 beat.eop_empty  == vec(0,0,0,0,0,0,0,0,0,0,0,0,0,0,5,0) &&
//                 beat.data[0]    == 'h99999991_99999990 && 
//                 beat.data[15]   == 'hccccccc7_ccccccc6,
//                 "Error",
//                 $format("beat=", fshow(beat)) 
//             );
//         endaction
//         action
//             outPipeOut.deq;
//             let beat = outPipeOut.first;
//             immAssert(
//                 beat.inframe    == 'h000f &&
//                 beat.eop_empty  == vec(0,0,0,0,3,0,0,0,0,0,0,0,0,0,0,0) &&
//                 beat.data[0]    == 'hddddddd1_ddddddd0 && 
//                 beat.data[15]   == 'h00000000_00000000,
//                 "Error",
//                 $format("beat=", fshow(beat)) 
//             );
//         endaction
//         $finish;
//     endseq);

//     FSM injectFSM <- mkFSM(injectProc);
//     FSM checkFSM  <- mkFSM(checkProc);
    
//     Reg#(Bool) goingReg <- mkReg(False);

//     rule start (!goingReg);
//         goingReg <= True;
//         injectFSM.start;
//         checkFSM.start;
//     endrule
// endmodule


interface TestFtileMacCocotbLoopBackTest;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeInB0#(FtileMacTxUserStream))   ftilemacTxStreamPipeInVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxUserStream))  ftilemacRxStreamPipeOutVec;
endinterface

(* synthesize *)
module mkTestFtileMacCocotbLoopBackTest(TestFtileMacCocotbLoopBackTest);
    
    let dut <- mkFTileMac;
    let busAdapter <- mkFTileMacAdaptor;

    mkConnection(busAdapter.ftilemacRxPipeOut, dut.ftilemacRxPipeIn);
    mkConnection(busAdapter.ftilemacTxPipeIn, dut.ftilemacTxPipeOut);
    

    rule loopBack1;
        busAdapter.rx.setRxInputData(
            busAdapter.tx.data,
            busAdapter.tx.valid,
            busAdapter.tx.inframe,
            busAdapter.tx.eop_empty,
            unpack(0),
            unpack(0),
            unpack(0)
        );
    endrule

    rule loopBack2;
        busAdapter.tx.setTxInputData(
            busAdapter.rx.ready
        );
    endrule

    interface ftilemacTxStreamPipeInVec = dut.ftilemacTxStreamPipeInVec;
    interface ftilemacRxStreamPipeOutVec = dut.ftilemacRxStreamPipeOutVec;
endmodule
