import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;
import EthernetTypes :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;
import EthernetFrameIO :: *;
import StreamShifterG :: *;

typedef enum {
    TestEthernetFrameIoStateGenReq = 0,
    TestEthernetFrameIoStateCheckPacketClassifierOutput = 1,
    TestEthernetFrameIoStateCheckRdmaMetaAndPayloadExtractorOutput = 2
} TestEthernetFrameIoState deriving(Bits, FShow, Eq);

(* doc = "testcase" *)
module mkTestEthernetFrameIO(Empty);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(1000000);

    Reg#(TestEthernetFrameIoState) stateReg <- mkReg(TestEthernetFrameIoStateGenReq);

    let packetGen <- mkEthernetPacketGenerator;
    let packetCon <- mkRdmaMetaAndPayloadExtractor;
    let packetClassifier <- mkInputPacketClassifier;



    mkConnection(packetGen.ethernetPacketPipeOut, packetClassifier.ethRawPacketPipeIn);
    mkConnection(packetClassifier.rdmaRawPacketPipeOut, packetCon.ethPipeIn);

    Integer     normalPacketUdpPortForTest = 1234;
    IpAddr      ipAddrForTestSendNode = unpack('h11223344);
    IpAddr      ipAddrForTestRecvNode = unpack('h55667788);
    EthMacAddr  macUnicastAddrForTestSendNode = unpack('h123456789ABC);
    EthMacAddr  macUnicastAddrForTestRecvNode = unpack('hDDEEFFAABBCC);
    EthMacAddr  macBroadcastAddrForTest = unpack('hFFFFFFFFFFFF);


    
    let macAddrVec = vec(macUnicastAddrForTestRecvNode, macBroadcastAddrForTest, macUnicastAddrForTestRecvNode, macBroadcastAddrForTest);
    Vector#(9, RdmaTransAndOpcode) rdmaOpcodeVec = vec(
        unpack(fromInteger(valueOf(RC_SEND_FIRST))),                          // 12
        unpack(fromInteger(valueOf(RC_SEND_LAST_WITH_IMMEDIATE))),            // 16
        unpack(fromInteger(valueOf(RC_ACKNOWLEDGE))),                         // 20
        unpack(fromInteger(valueOf(UD_SEND_ONLY_WITH_IMMEDIATE))),            // 24
        unpack(fromInteger(valueOf(RC_RDMA_WRITE_FIRST))),                    // 28
        unpack(fromInteger(valueOf(RC_RDMA_WRITE_LAST_WITH_IMMEDIATE))),      // 32
        unpack(fromInteger(valueOf(XRC_RDMA_WRITE_ONLY_WITH_IMMEDIATE))),     // 36
        unpack(fromInteger(valueOf(RC_COMPARE_SWAP))),                        // 40
        unpack(fromInteger(valueOf(RC_RDMA_READ_REQUEST)))                    // 44
    );

    let trueFalseVec = vec(True, False, True, False);

    PipeOut#(Length) rdmaPayloadLenRandPipeOut <- mkRandomLenPipeOut(1, 1024); //fromInteger(valueOf(MAX_PMTU)));
    PipeOut#(RdmaTransAndOpcode) transAndOpecodeRandPipeOut <- mkRandomItemFromVec(rdmaOpcodeVec);
    PipeOut#(Bool) isRdmaPacketRandPipeOut <- mkRandomItemFromVec(trueFalseVec);
    PipeOut#(EthMacAddr) macAddrRandPipeOut <- mkRandomItemFromVec(macAddrVec);
    PipeOut#(RdmaExtendHeaderBuffer) extendHeaderBufferRandPipeOut <- mkGenericRandomPipeOut;

    FIFOF#(ThinMacIpUdpMetaDataForSend) rdmaMacIpUspMetadataCheckerExpectedQ <- mkFIFOF;
    FIFOF#(ThinMacIpUdpMetaDataForSend) normalPacketCheckerExpectedQ <- mkFIFOF;

    FIFOF#(RdmaRecvPacketMeta) rdmaHeaderExtractorMetaExpectedQ <- mkFIFOF;
    FIFOF#(DataStream) rdmaHeaderExtractorPayloadExpectedQ <- mkFIFOF;

    let payloadStreamGen <- mkFixedLengthDateStreamRandomGen;
    let txStreamShifter <- mkBiDirectionStreamShifterLsbRightG;
    mkConnection(payloadStreamGen.streamPipeOut, txStreamShifter.streamPipeIn);
    Vector#(2, PipeOut#(DataStream)) rdmaPayloadDataStreamPipeOutForkedVec <- mkForkVector(txStreamShifter.streamPipeOut);
    mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[0], packetGen.rdmaPayloadPipeIn);
    mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[1], toPipeIn(rdmaHeaderExtractorPayloadExpectedQ));

    Reg#(RdmaRecvPacketMeta) curRecvPacketMetaDataReg <- mkRegU;

    rule genRandomPacketHeader if (stateReg == TestEthernetFrameIoStateGenReq);
        
        ThinMacIpUdpMetaDataForSend macIpUdpMeta = unpack(0);

        let isRdmaPacket = isRdmaPacketRandPipeOut.first;
        isRdmaPacketRandPipeOut.deq;
        isRdmaPacket = True;

        PktLen rdmaPayloadLen = truncate(rdmaPayloadLenRandPipeOut.first);
        rdmaPayloadLenRandPipeOut.deq;
        let transAndOpecode = transAndOpecodeRandPipeOut.first;
        transAndOpecodeRandPipeOut.deq;
        let macAddr = macAddrRandPipeOut.first;
        macAddrRandPipeOut.deq;
        let rdmaExtendHeaderBuf = extendHeaderBufferRandPipeOut.first;
        extendHeaderBufferRandPipeOut.deq;

        RdmaBthAndEthTotalLength bthAndEthTotalLength = fromInteger(valueOf(RDMA_FIXED_HEADER_BYTE_NUM));

        let hasPayload = rdmaOpCodeHasPayload(transAndOpecode.opcode);
        
        macIpUdpMeta.dstMacAddr = macAddr;
        macIpUdpMeta.dstIpAddr = ipAddrForTestRecvNode;

        let localNetworkSettingsForSendNode = LocalNetworkSettings{
            macAddr: macUnicastAddrForTestSendNode,
            ipAddr: ipAddrForTestSendNode,
            gatewayAddr: unpack(0),
            netMask: unpack(0)
        };
        packetGen.setLocalNetworkSettings(localNetworkSettingsForSendNode);

        let localNetworkSettingsForRecvNode = LocalNetworkSettings{
            macAddr: macUnicastAddrForTestRecvNode,
            ipAddr: ipAddrForTestRecvNode,
            gatewayAddr: unpack(0),
            netMask: unpack(0)
        };
        packetClassifier.setLocalNetworkSettings(localNetworkSettingsForRecvNode);

        if (isRdmaPacket) begin
            macIpUdpMeta.dstPort = fromInteger(valueOf(UDP_PORT_RDMA));
            macIpUdpMeta.ethType = fromInteger(valueOf(ETH_TYPE_IP));
            macIpUdpMeta.udpPayloadLen = unpack(zeroExtend(bthAndEthTotalLength));
            if (hasPayload) begin
                macIpUdpMeta.udpPayloadLen = macIpUdpMeta.udpPayloadLen + zeroExtend(rdmaPayloadLen);
            end
            rdmaMacIpUspMetadataCheckerExpectedQ.enq(macIpUdpMeta);
        end
        else begin
            macIpUdpMeta.udpPayloadLen = zeroExtend(rdmaPayloadLen);
            macIpUdpMeta.dstPort = fromInteger(normalPacketUdpPortForTest);
            normalPacketCheckerExpectedQ.enq(macIpUdpMeta);
        end
        packetGen.macIpUdpMetaPipeIn.enq(macIpUdpMeta);

        if (isRdmaPacket) begin
            let rdmaExtendHeaderByteNum = bthAndEthTotalLength - fromInteger(valueOf(BTH_BYTE_WIDTH));
            let rdmaExtendHeaderBufInvalidByteNum = fromInteger(valueOf(RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH)) - rdmaExtendHeaderByteNum;
            BusBitCnt tmpShiftCnt = zeroExtend(rdmaExtendHeaderBufInvalidByteNum) * fromInteger(valueOf(BYTE_WIDTH));
            RdmaExtendHeaderBuffer rdmaExtendHeaderMask = ~((1 << tmpShiftCnt) - 1);
            rdmaExtendHeaderBuf = rdmaExtendHeaderBuf & rdmaExtendHeaderMask;
            
            BTH bth = unpack(0);
            bth.trans = transAndOpecode.trans;
            bth.opcode = transAndOpecode.opcode;
            let rdmaBthAndExtendHeader = RdmaBthAndExtendHeader{
                bth: bth,
                rdmaExtendHeaderBuf: rdmaExtendHeaderBuf
            };
            let rdmaPacketMeta = RdmaSendPacketMeta{
                header: rdmaBthAndExtendHeader,
                hasPayload: hasPayload
            };
            if (hasPayload) begin
                payloadStreamGen.reqPipeIn.enq(zeroExtend(rdmaPayloadLen));
                
                BusByteCnt firstPayloadByteOneBasedOffsetInFirstPayloadBeat = fromInteger(valueOf(BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT)) - truncate(bthAndEthTotalLength);
                BusByteIdx firstPayloadByteOneBasedOffsetInFirstPayloadBeatTmpValue = truncate(firstPayloadByteOneBasedOffsetInFirstPayloadBeat);
                firstPayloadByteOneBasedOffsetInFirstPayloadBeat = zeroExtend(firstPayloadByteOneBasedOffsetInFirstPayloadBeatTmpValue);
                DataBusSignedByteShiftOffset signedShiftOffset = zeroExtend(firstPayloadByteOneBasedOffsetInFirstPayloadBeat) - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                txStreamShifter.offsetPipeIn.enq(signedShiftOffset);
            end
            packetGen.rdmaPacketMetaPipeIn.enq(rdmaPacketMeta);
            let infoForChecker = RdmaRecvPacketMeta{
                header: rdmaBthAndExtendHeader,
                hasPayload: hasPayload
            };
            rdmaHeaderExtractorMetaExpectedQ.enq(infoForChecker);
            stateReg <= TestEthernetFrameIoStateCheckPacketClassifierOutput;

            // $display(
            //     "time=%0t:", $time, toGreen(" mkTestEthernetFrameIO genRandomPacketHeader"),
            //     toBlue(", macIpUdpMeta="), fshow(macIpUdpMeta),
            //     toBlue(", rdmaPayloadLen="), fshow(rdmaPayloadLen),
            //     toBlue(", rdmaPacketMeta="), fshow(rdmaPacketMeta)
            // );
            // $display("============Finish genRandomPacketHeader Request==============");
        end
        else begin
            immFail("TODO", $format(""));
        end

        
    endrule

    

    rule checkPacketClassifierOutput if (stateReg == TestEthernetFrameIoStateCheckPacketClassifierOutput);
        let expected = rdmaMacIpUspMetadataCheckerExpectedQ.first;
        rdmaMacIpUspMetadataCheckerExpectedQ.deq;
        let got = packetClassifier.rdmaMacIpUdpMetaPipeOut.first;
        packetClassifier.rdmaMacIpUdpMetaPipeOut.deq;
        
        immAssert(
            got.srcMacAddr == macUnicastAddrForTestSendNode && 
            got.ipDscp == expected.ipDscp && 
            got.ipEcn == expected.ipEcn &&
            got.srcIpAddr == ipAddrForTestSendNode &&
            got.srcPort == expected.srcPort,
            "mkTestEthernetFrameIO getPacketClassifierOutput check failed",
            $format(
                ", got=", fshow(got),
                ", expected=", fshow(expected),
                ", macUnicastAddrForTestSendNode=", fshow(macUnicastAddrForTestSendNode),
                ", ipAddrForTestSendNode=", fshow(ipAddrForTestSendNode)
            )
        );

        stateReg <= TestEthernetFrameIoStateCheckRdmaMetaAndPayloadExtractorOutput;
        // $display("============Finish checkPacketClassifierOutput==============");
    endrule

    rule checkRdmaMetaAndPayloadExtractorOutput if (stateReg == TestEthernetFrameIoStateCheckRdmaMetaAndPayloadExtractorOutput);
        if (packetCon.rdmaPacketMetaPipeOut.notEmpty && rdmaHeaderExtractorMetaExpectedQ.notEmpty) begin
            let expected = rdmaHeaderExtractorMetaExpectedQ.first;
            rdmaHeaderExtractorMetaExpectedQ.deq;
            let got = packetCon.rdmaPacketMetaPipeOut.first;
            packetCon.rdmaPacketMetaPipeOut.deq;

            let rdmaTotalHeaderLen = calcHeaderLenByTransTypeAndRdmaOpCode(got.header.bth.trans, got.header.bth.opcode);
            let invalidExtHeaderBufferBitNum = (valueOf(RDMA_BTH_AND_ETH_MAX_BYTE_WIDTH) - rdmaTotalHeaderLen) * valueOf(BYTE_WIDTH);
            BusBitCnt shiftInvalidExtHeaderBufferBitNum = fromInteger(invalidExtHeaderBufferBitNum);
            // Note, the rdmaExtendHeaderBuf may contain garbage data at it's lower bits.
            immAssert(
                (pack(got.header) >> shiftInvalidExtHeaderBufferBitNum) == (pack(expected.header) >> shiftInvalidExtHeaderBufferBitNum),
                "mkTestEthernetFrameIO checkRdmaMetaAndPayloadExtractorOutput meta check failed",
                $format(
                    ", got=", fshow(got),
                    ", expected=", fshow(expected)
                )
            );

            curRecvPacketMetaDataReg <= got;

            if (!got.hasPayload) begin
                stateReg <= TestEthernetFrameIoStateGenReq;
                // $display("============Finish checkRdmaMetaAndPayloadExtractorOutput  no payload==============");
            end

            quitCounterReg <= quitCounterReg - 1;
            if (quitCounterReg % 50000 == 0) begin
                $display(quitCounterReg);
            end
        end
        else begin
            let got = packetCon.rdmaPayloadPipeOut.first;
            packetCon.rdmaPayloadPipeOut.deq;
            let expected = rdmaHeaderExtractorPayloadExpectedQ.first;
            rdmaHeaderExtractorPayloadExpectedQ.deq;

            if (got.isFirst) begin
                // since the payload is directly aligned to receive side's address, the valid bytes can be calculated from
                // start address and payload len, so no need to mark now many byte is valid in DataStream struct.
                expected.byteNum = 'h20;
                got.byteNum = 'h20;
            end

            // For received side, don't care those value. The same as above, we can calculate from address and length
            expected.startByteIdx=0;
            got.startByteIdx = 0;
            
            immAssert(
                got == expected,
                "mkTestEthernetFrameIO checkRdmaMetaAndPayloadExtractorOutput payload check failed",
                $format(
                    ", got=", fshow(got),
                    ", expected=", fshow(expected)
                )
            );
  

            if (got.isLast) begin
                // TODO: maybe we should also check this pipeOut's value. for now, we simple ignore it.
                packetCon.rdmaPacketTailMetaPipeOut.deq;

                stateReg <= TestEthernetFrameIoStateGenReq;
                // $display("============Finish checkRdmaMetaAndPayloadExtractorOutput with payload==============");
                // $display("PASS");
            end
        end
        

    endrule

    rule checkQuitCounter;
        if (quitCounterReg == 0) begin
            $display("pass");
            $finish;
        end
    endrule
endmodule

interface TestEthernetFrameIoTiming;
    method Bit#(512) getOutput;
endinterface

(* synthesize *)
(* doc = "testcase" *)
module mkTestEthernetFrameIoTiming(TestEthernetFrameIoTiming);
    
    let packetGen <- mkEthernetPacketGenerator;
    let packetCon <- mkRdmaMetaAndPayloadExtractor;
    let packetClassifier <- mkInputPacketClassifier;

    mkConnection(packetGen.ethernetPacketPipeOut, packetClassifier.ethRawPacketPipeIn);
    mkConnection(packetClassifier.rdmaRawPacketPipeOut, packetCon.ethPipeIn);

    StreamShifterG#(DATA) txStreamShifter <- mkBiDirectionStreamShifterLsbRightG;
    mkConnection(txStreamShifter.streamPipeOut, packetGen.rdmaPayloadPipeIn);
    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);

    Reg#(Bit#(32)) cntReg <- mkReg(0);
    Reg#(Bit#(512)) relayReg <- mkReg(0);

    Reg#(Bit#(512)) outReg1 <- mkRegU;
    Reg#(Bit#(256)) outReg2 <- mkRegU;
    Reg#(Bit#(128)) outReg3 <- mkRegU;

    Reg#(ThinMacIpUdpMetaDataForRecv) tmpReg1 <- mkRegU;
    Reg#(DataStream) tmpReg2 <- mkRegU;
    Reg#(RdmaRecvPacketMeta) tmpReg3 <- mkRegU;
    Reg#(DataStream) tmpReg4 <- mkRegU;

    rule t;
        cntReg <= cntReg + 1;
        relayReg <= (relayReg << 3) | zeroExtend(cntReg);
    endrule

    rule injectInput1;
        let randValue1 <- randSource1.get;
        let localNetworkSettingsForSendNode = unpack(truncate(randValue1));
        let localNetworkSettingsForRecvNode = unpack(truncate(randValue1 >> 128));
        let payloadStream = unpack(truncate(randValue1 >> 32));

        packetGen.setLocalNetworkSettings(localNetworkSettingsForSendNode);
        packetClassifier.setLocalNetworkSettings(localNetworkSettingsForRecvNode);
        txStreamShifter.streamPipeIn.enq(payloadStream);
    endrule

    rule injectInput2;
        let randValue2 <- randSource2.get;
        let rdmaPacketMeta = unpack(truncate(randValue2));
        packetGen.rdmaPacketMetaPipeIn.enq(rdmaPacketMeta);
    endrule


    rule injectInput3;
        let randValue3 <- randSource3.get;
        let signedShiftOffset = unpack(truncate(randValue3));
        txStreamShifter.offsetPipeIn.enq(signedShiftOffset);
    endrule


    rule injectInput4;
        let randValue4 <- randSource4.get;
        ThinMacIpUdpMetaDataForSend macIpUdpMeta = unpack(truncate(randValue4));
        packetGen.macIpUdpMetaPipeIn.enq(macIpUdpMeta);
    endrule

    rule deq1;
        tmpReg1 <= packetClassifier.rdmaMacIpUdpMetaPipeOut.first;
        packetClassifier.rdmaMacIpUdpMetaPipeOut.deq;
    endrule

    rule deq2;
        tmpReg2 <= packetClassifier.otherRawPacketPipeOut.first;
        packetClassifier.otherRawPacketPipeOut.deq;
    endrule

    rule deq3;
        tmpReg3 <= packetCon.rdmaPacketMetaPipeOut.first;
        packetCon.rdmaPacketMetaPipeOut.deq;
    endrule

    rule deq4;
        tmpReg4 <= packetCon.rdmaPayloadPipeOut.first;
        packetCon.rdmaPayloadPipeOut.deq;
    endrule

    rule merge;
        outReg1 <= zeroExtend(pack(tmpReg1)) ^
                  zeroExtend(pack(tmpReg2))  ^ 
                  zeroExtend(pack(tmpReg3))     ^
                  zeroExtend(pack(tmpReg4));

        outReg2 <= outReg1[255:0] ^ outReg1[511:256];
        outReg3 <= outReg2[127:0] ^ outReg2[255:128];
    endrule

    method getOutput = outReg1;
endmodule