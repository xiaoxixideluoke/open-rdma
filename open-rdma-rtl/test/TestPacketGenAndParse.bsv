import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

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
import EthernetTypes :: *;
import PacketGenAndParse :: *;
import MemRegionAndAddressTranslate :: *;
import IoChannels :: *;

interface TestCocotbPacketGenAndParse;
    interface IoChannelMemoryMasterPipe ioChannelMemoryMasterPipeIfc;
    interface PipeIn#(WorkQueueElem) wqePipeIn;
endinterface

module mkTestCocotbPacketGenAndParse(TestCocotbPacketGenAndParse);
    // TODO: This Testcase is too simple now. should add more checkers.
    
    let clk <- exposeCurrentClock;
    let rst <- exposeCurrentReset;

    Reg#(Bit#(32)) exitCounterReg <- mkReg(10000);

    PayloadGenAndCon payloadGenAndCon <- mkPayloadGenAndCon(clk, rst);
    let fakeAddrTranslatorForGen <- mkBypassAddressTranslateForTest;
    let fakeAddrTranslatorForCon <- mkBypassAddressTranslateForTest;
    mkConnection(payloadGenAndCon.genAddrTranslateClt, fakeAddrTranslatorForGen.translateSrv);
    mkConnection(payloadGenAndCon.conAddrTranslateClt, fakeAddrTranslatorForCon.translateSrv);


    let dut <- mkPacketGen(clk, rst, clk, rst);

    mkConnection(dut.genReqPipeOut, payloadGenAndCon.genReqPipeIn);
    mkConnection(dut.genRespPipeIn, payloadGenAndCon.payloadGenStreamPipeOut);

    let fakeMrTable <- mkBypassMemRegionTableForTest;
    mkConnection(dut.mrTableQueryClt, fakeMrTable.querySrv);

    Reg#(Bool) isInitedReg <- mkReg(False);

    rule doInit if (!isInitedReg);
        isInitedReg <= True;
        dut.setLocalNetworkSettings(LocalNetworkSettings{
            macAddr: unpack('h112233445566),
            ipAddr: unpack('hAABBCCDD),
            gatewayAddr: unpack(0),
            netMask: unpack(0)
        });
    endrule

    rule getResponse;
        let ds = dut.packetPipeOut.first;
        dut.packetPipeOut.deq;
        if (ds.eop) begin
            exitCounterReg <= exitCounterReg - 1;
            if (exitCounterReg == 0) begin
                $display("PASS");
                $finish;
            end
            if (exitCounterReg % 1000 == 0) begin
                $display(exitCounterReg);
            end
        end
        $display(
            "time=%0t:", $time, toGreen(" mkTestCocotbPacketGenAndParse getResponse"),
            toBlue(", ds="), fshow(ds)
        );
    endrule


    interface ioChannelMemoryMasterPipeIfc = payloadGenAndCon.ioChannelMemoryMasterPipeIfc;
    interface wqePipeIn = dut.wqePipeIn;
endmodule
