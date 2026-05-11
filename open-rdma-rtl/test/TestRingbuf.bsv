import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 

import PrimUtils :: *;
import RdmaUtils :: *;
import Utils4Test :: *;
import EthernetTypes :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;

import Ringbuf :: *;


(* doc = "testcase" *)
module mkTestRingbuf(Empty);
    Reg#(Long) exitCounterReg <- mkReg(0);

    let ringbufDmaNapWrappr <- mkRingbufDmaNapWrappr;

    RingbufC2hSlot4096 dutC2H <- mkRingbufC2h(0);
    let dutH2C <- mkRingbufH2c(0);

    mkConnection(dutC2H.dmaWriteReqPipeOut, ringbufDmaNapWrappr.dmaWriteReqPipeIn);
    mkConnection(dutC2H.dmaWriteDataPipeOut, ringbufDmaNapWrappr.dmaWriteDataPipeIn);
    mkConnection(dutC2H.dmaWriteRespPipeIn, ringbufDmaNapWrappr.dmaWriteRespPipeOut);
    mkConnection(dutH2C.dmaReadReqPipeOut, ringbufDmaNapWrappr.dmaReadReqPipeIn);
    mkConnection(dutH2C.dmaReadRespPipeIn, ringbufDmaNapWrappr.dmaReadRespPipeOut);


    let burstWriteCntRandHighSpeedVec = vec(0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
    let burstWriteCntRandLowSpeedVec = vec(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
    let burstReadCntRaandVec = vec(0, 1, 3, 0, 2, 0);
    PipeOut#(Length) c2hWriteCountHighSpeedRandPipeOut <- mkRandomItemFromVec(burstWriteCntRandHighSpeedVec);
    PipeOut#(Length) c2hWriteCountLowSpeedRandPipeOut <- mkRandomItemFromVec(burstWriteCntRandLowSpeedVec);

    PipeOut#(Length) writePointerSyncDelayRandPipeOut <- mkRandomLenPipeOut(2, 5);
    PipeOut#(Length) readPointerSyncDelayRandPipeOut <- mkRandomLenPipeOut(3, 4);

    PipeOut#(Length) h2cReadDelayRandPipeOut <- mkRandomItemFromVec(burstReadCntRaandVec);

    Reg#(Bool)      isInitReg <- mkReg(True);
    Reg#(Long)      c2hBatchWriteCounterReg <- mkReg(0);
    Reg#(Long)      writerSeqReg <- mkReg(0);
    Reg#(Long)      readerSeqReg <- mkReg(0);

    Reg#(Long)      writeSyncDelayCounterReg <- mkReg(0);
    Reg#(Long)      readSyncDelayCounterReg <- mkReg(0);
    Reg#(Long)      readDelayCntReg <- mkReg(0);

    Reg#(Long)      h2cEmptyCountReg <- mkReg(0);
    Reg#(Long)      h2cFullCountReg <- mkReg(0);
    Reg#(Long)      c2hEmptyCountReg <- mkReg(0);
    Reg#(Long)      c2hFullCountReg <- mkReg(0);

    Reg#(Bool)      h2cLastNotFullReg <- mkReg(True);
    Reg#(Bool)      h2cLastNotEmptyReg <- mkReg(False);
    Reg#(Bool)      c2hLastNotFullReg <- mkReg(True);
    Reg#(Bool)      c2hLastNotEmptyReg <- mkReg(False);


    rule doStateChangeCounter;
        let newH2cNotFull = isRingbufNotFull(dutH2C.controlRegs.head, dutH2C.controlRegs.tail);
        let newH2cNotEmpty = isRingbufNotEmpty(dutH2C.controlRegs.head, dutH2C.controlRegs.tail);
        let newC2hNotFull = isRingbufNotFull(dutC2H.controlRegs.head, dutC2H.controlRegs.tail);
        let newC2hNotEmpty = isRingbufNotEmpty(dutC2H.controlRegs.head, dutC2H.controlRegs.tail);
        
        // $display(
        //     "time=%0t:", $time,
        //     ", newH2cNotFull=", fshow(newH2cNotFull),
        //     ", newH2cNotEmpty=", fshow(newH2cNotEmpty),
        //     ", newC2hNotFull=", fshow(newC2hNotFull),
        //     ", newC2hNotEmpty=", fshow(newC2hNotEmpty)
        // );

        h2cLastNotFullReg <= newH2cNotFull;
        h2cLastNotEmptyReg <= newH2cNotEmpty;
        c2hLastNotFullReg <= newC2hNotFull;
        c2hLastNotEmptyReg <= newC2hNotEmpty;

        if (h2cLastNotFullReg != newH2cNotFull) begin
            h2cFullCountReg <= h2cFullCountReg + 1;
            // $display(
            //     "h2cFullCountReg=", fshow(h2cFullCountReg),
            //     ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
            //     ", c2hFullCountReg=", fshow(c2hFullCountReg),
            //     ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            // );
        end

        if (h2cLastNotEmptyReg != newH2cNotEmpty) begin
            h2cEmptyCountReg <= h2cEmptyCountReg + 1;
            // $display(
            //     "h2cFullCountReg=", fshow(h2cFullCountReg),
            //     ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
            //     ", c2hFullCountReg=", fshow(c2hFullCountReg),
            //     ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            // );
        end

        if (c2hLastNotFullReg != newC2hNotFull) begin
            c2hFullCountReg <= c2hFullCountReg + 1;
            // $display(
            //     "h2cFullCountReg=", fshow(h2cFullCountReg),
            //     ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
            //     ", c2hFullCountReg=", fshow(c2hFullCountReg),
            //     ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            // );
        end

        if (c2hLastNotEmptyReg != newC2hNotEmpty) begin
            c2hEmptyCountReg <= c2hEmptyCountReg + 1;
            // $display(
            //     "h2cFullCountReg=", fshow(h2cFullCountReg),
            //     ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
            //     ", c2hFullCountReg=", fshow(c2hFullCountReg),
            //     ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            // );
        end
    endrule


    rule doInit if (isInitReg);
        isInitReg <= False;
        dutC2H.controlRegs.addr <= 0;
        dutH2C.controlRegs.addr <= 0;

        dutC2H.controlRegs.head <= 0;
        dutH2C.controlRegs.head <= 0;

        dutC2H.controlRegs.tail <= 0;
        dutH2C.controlRegs.tail <= 0;
    endrule

    rule doInjectC2HWrite if (!isInitReg);

        Bool isGenInHighSpeed = h2cFullCountReg < h2cEmptyCountReg;

        if (c2hBatchWriteCounterReg == 0) begin
            if (isGenInHighSpeed) begin
                c2hBatchWriteCounterReg <= zeroExtend(c2hWriteCountHighSpeedRandPipeOut.first);
                c2hWriteCountHighSpeedRandPipeOut.deq;
            end
            else begin
                c2hBatchWriteCounterReg <= zeroExtend(c2hWriteCountLowSpeedRandPipeOut.first);
                c2hWriteCountLowSpeedRandPipeOut.deq;
            end
        end
        else begin
            c2hBatchWriteCounterReg <= c2hBatchWriteCounterReg - 1;
            writerSeqReg <= writerSeqReg + 1;
            dutC2H.descPipeIn.enq(unpack({pack(writerSeqReg), pack(writerSeqReg), pack(writerSeqReg), pack(writerSeqReg)}));
        end
    endrule

    rule syncPointerBetweenWriterAndReader if (!isInitReg);

        if (writeSyncDelayCounterReg == 0) begin
            dutH2C.controlRegs.head <= dutC2H.controlRegs.head;
            writeSyncDelayCounterReg <= zeroExtend(writePointerSyncDelayRandPipeOut.first);
            writePointerSyncDelayRandPipeOut.deq;

            // $display(
            //     "time=%0t:", $time,
            //     " advance H2C head from ", fshow(pack(dutH2C.controlRegs.head)), " to ", fshow(pack(dutC2H.controlRegs.head))
            // );

        end
        else begin
            writeSyncDelayCounterReg <= writeSyncDelayCounterReg - 1;
        end

        if (readSyncDelayCounterReg == 0) begin
            dutC2H.controlRegs.tail <= dutH2C.controlRegs.tail;
            readSyncDelayCounterReg <= zeroExtend(readPointerSyncDelayRandPipeOut.first);
            readPointerSyncDelayRandPipeOut.deq;

            // $display(
            //     "time=%0t:", $time,
            //     " advance C2H tail from ", fshow(pack(dutC2H.controlRegs.tail)), " to ", fshow(pack(dutH2C.controlRegs.tail))
            // );

        end
        else begin
            readSyncDelayCounterReg <= readSyncDelayCounterReg - 1;
        end
    endrule

    rule doReadCheck if (!isInitReg);

        if (readDelayCntReg == 0) begin
            readDelayCntReg <= zeroExtend(h2cReadDelayRandPipeOut.first);
            h2cReadDelayRandPipeOut.deq;
        end
        else begin
            readDelayCntReg <= readDelayCntReg - 1;

            let readout = dutH2C.descPipeOut.first;
            dutH2C.descPipeOut.deq;
            readerSeqReg <= readerSeqReg + 1;

            let expected = {pack(readerSeqReg), pack(readerSeqReg), pack(readerSeqReg), pack(readerSeqReg)};

            let tim <- $time;
            immAssert(
                pack(readout) == expected,
                "mkTestRingbuf doReadCheck failed",
                $format("time=%0t: ", tim, "got=", fshow(readout), ", expected=", fshow(expected))
            );

            exitCounterReg <= exitCounterReg + 1;

            if (exitCounterReg > 10000000 && h2cFullCountReg > 5000 && h2cEmptyCountReg > 5000 && c2hFullCountReg > 5000 && c2hEmptyCountReg > 5000) begin
                $display("PASS");
                $finish;
            end

            if (exitCounterReg % 100000 == 0) begin
                 $display(
                    "h2cFullCountReg=", fshow(h2cFullCountReg),
                    ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
                    ", c2hFullCountReg=", fshow(c2hFullCountReg),
                    ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg),
                    ", exitCounterReg=", fshow(exitCounterReg)
                );
            end
        end
    endrule

endmodule