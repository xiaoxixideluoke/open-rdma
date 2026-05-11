import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;
import Clocks :: *;
import Settings :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import PayloadGenAndCon :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;
import NapWrapper :: *;
import StreamShifterG :: *;
import EthernetTypes :: *;
import QPContext :: *;
import RQ :: *;
import SQ :: *;
import MemRegionAndAddressTranslate :: *;
import PacketGenAndParse :: *;
import Top100G :: *;

typedef 1 HARDWARE_QP_CHANNEL_CNT_100G;

interface TestTopTimingNoHardIP;
    method Bit#(32) getOutput;
endinterface

module mkTestTopTimingNoHardIP(TestTopTimingNoHardIP);

    let dut <- mkBsvTopWithoutHardIpInstance;

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    let randSource6 <- mkSynthesizableRng512('h11111111);
    let randSource7 <- mkSynthesizableRng512('h22222222);
    let randSource8 <- mkSynthesizableRng512('h33333333);


    ForceKeepWideSignals#(Bit#(768), Bit#(32)) signalKeeper1 <- mkForceKeepWideSignals; 

    ForceKeepWideSignals#(Bit#(768), Bit#(32)) signalKeeper2 <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(768), Bit#(32)) signalKeeper3 <- mkForceKeepWideSignals; 

    Reg#(Bit#(32)) outputReg <- mkRegU;

    rule injectPcieSlave1;
        let randValue1 <- randSource1.get;
        dut.dmaSlavePipeIfc.writePipeIfc.writeMetaPipeIn.enq(unpack(truncate(randValue1)));
    endrule

    rule injectPcieSlave2;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;
        dut.dmaSlavePipeIfc.writePipeIfc.writeDataPipeIn.enq(unpack(truncate({randValue2, randValue3})));
    endrule

    rule injectPcieSlave3;
        let randValue4 <- randSource4.get;
        dut.dmaSlavePipeIfc.readPipeIfc.readMetaPipeIn.enq(unpack(truncate(randValue4)));
    endrule 

    let dutDmaMasterPipeIfcReadPipeIfcReadDataPipeInAdapter <- mkPipeInB0ToPipeInWithDebug(dut.dmaMasterPipeIfc.readPipeIfc.readDataPipeIn, 1, False, "dutDmaMasterPipeIfcReadPipeIfcReadDataPipeInAdapter");
    rule injectPcieMaster;
        let randValue5 <- randSource5.get;
        let randValue6 <- randSource6.get;

        if (dutDmaMasterPipeIfcReadPipeIfcReadDataPipeInAdapter.notFull) begin
            dutDmaMasterPipeIfcReadPipeIfcReadDataPipeInAdapter.enq(unpack(truncate({randValue5, randValue6})));
        end
    endrule 

    let dutQpEthDataStreamIfcDataPipeIn <- mkPipeInB0ToPipeInWithDebug(dut.qpEthDataStreamIfc.dataPipeIn, 1, False, "dutQpEthDataStreamIfcDataPipeIn");
    rule injectEth;
        let randValue7 <- randSource7.get;
        let randValue8 <- randSource8.get;
        
        if (dutQpEthDataStreamIfcDataPipeIn.notFull) begin
            dutQpEthDataStreamIfcDataPipeIn.enq(unpack(truncate({randValue7, randValue8})));
        end

    endrule


    rule handleOutputPcieSlave;
        if (dut.dmaSlavePipeIfc.readPipeIfc.readDataPipeOut.notEmpty) begin
            dut.dmaSlavePipeIfc.readPipeIfc.readDataPipeOut.deq;
            signalKeeper1.bitsPipeIn.enq(zeroExtend(pack(dut.dmaSlavePipeIfc.readPipeIfc.readDataPipeOut.first)));
        end
    endrule

    

    rule handleOptputPcieMaster;
        Bit#(768) tmpV = 0;
        if (dut.dmaMasterPipeIfc.writePipeIfc.writeMetaPipeOut.notEmpty) begin
            dut.dmaMasterPipeIfc.writePipeIfc.writeMetaPipeOut.deq;
            tmpV = tmpV ^ zeroExtend(pack(dut.dmaMasterPipeIfc.writePipeIfc.writeMetaPipeOut.first));
        end

        if (dut.dmaMasterPipeIfc.writePipeIfc.writeDataPipeOut.notEmpty) begin
            dut.dmaMasterPipeIfc.writePipeIfc.writeDataPipeOut.deq;
            tmpV = tmpV ^ zeroExtend(pack(dut.dmaMasterPipeIfc.writePipeIfc.writeDataPipeOut.first));
        end

        if (dut.dmaMasterPipeIfc.readPipeIfc.readMetaPipeOut.notEmpty) begin
            dut.dmaMasterPipeIfc.readPipeIfc.readMetaPipeOut.deq;
            tmpV = tmpV ^ zeroExtend(pack(dut.dmaMasterPipeIfc.readPipeIfc.readMetaPipeOut.first));
        end

        signalKeeper2.bitsPipeIn.enq(zeroExtend(pack(tmpV)));
    endrule




    rule handleOptputEth;
        if (dut.qpEthDataStreamIfc.dataPipeOut.notEmpty) begin
            dut.qpEthDataStreamIfc.dataPipeOut.deq;
            signalKeeper3.bitsPipeIn.enq(zeroExtend(pack(dut.qpEthDataStreamIfc.dataPipeOut.first)));
        end
    endrule



    rule combineOutput;
        Bit#(32) outputVal = signalKeeper1.out; 
        outputVal = unpack(pack(outputVal) ^ pack(signalKeeper2.out));
        outputVal = unpack(pack(outputVal) ^ pack(signalKeeper3.out));
        outputReg <= outputVal;
    endrule

    method getOutput = outputReg;
endmodule