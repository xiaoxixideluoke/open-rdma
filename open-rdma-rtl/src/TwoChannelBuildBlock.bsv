import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;
import Clocks :: *;

import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import PacketGenAndParse :: *;
import EthernetTypes :: *;
import PacketGenAndParse :: *;
import MemRegionAndAddressTranslate :: *;
import QPContext :: *;
import PayloadGenAndCon :: *;
import CsrRootConnector :: *;
import CsrFramework :: *;
import Ringbuf :: *;
import DescriptorParsers :: *;
import CsrAddress :: *;
import AutoAckGenerator :: *;
import SimpleNic :: *;
import CnpPacketGen :: *;

import Settings :: *;
import Utils4Test :: *;

import SQ :: *;
import RQ :: *;



// (* synthesize *)
// module mkBsvTopWithoutHardIpInstance(BsvTopWithoutHardIpInstance);
//     let qpMrPgtQpc <- mkQpMrPgtQpc;
//     let ringbufAndDescriptorHandler <- mkRingbufAndDescriptorHandler;
//     mkConnection(ringbufAndDescriptorHandler.wqePipeOutVec, qpMrPgtQpc.wqePipeInVec);  // already Nr

//     TopLevelDmaChannelMux topLevelDmaChannelMux <- mkTopLevelDmaChannelMux;
    

//     let csrRootConnector <- mkCsrRootConnector;
//     function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
//         actionvalue
//             let regIdx = req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
//             let addrBlockMask = ~fromInteger(valueOf(CSR_ADDR_BLOCK_SIZE_FOR_RINGBUFS) - 1);
//             let maskedAddr = addrBlockMask & regIdx;
//             if (fromInteger(valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_RINGBUFS)) == maskedAddr) begin
//                 return tagged CsrNodeResultForward 0;
//             end
//             else begin
//                 return tagged CsrNodeResultForward 1;
//             end
//         endactionvalue
//     endfunction
//     CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_TWO), "mkBsvTopWithoutHardIpInstance");
    
//     mkConnection(csrRootConnector.csrNodeRootPortIfc, csrNode.upStreamPort);
//     mkConnection(ringbufAndDescriptorHandler.csrUpStreamPort, csrNode.downStreamPortsVec[0]);
//     mkConnection(qpMrPgtQpc.csrUpStreamPort, csrNode.downStreamPortsVec[1]);


//     mkConnection(qpMrPgtQpc.pgtUpdateDmaMasterPipe, topLevelDmaChannelMux.pgtUpdateDmaSlavePipe);    // already Nr
//     mkConnection(qpMrPgtQpc.qpDmaRequestMasterIfcVec, topLevelDmaChannelMux.qpDmaRequestSlaveIfcVec);  // already Nr
//     mkConnection(ringbufAndDescriptorHandler.qpRingbufDmaMasterPipeIfcVec, topLevelDmaChannelMux.qpRingbufDmaSlavePipeIfcVec); // already Nr
//     mkConnection(ringbufAndDescriptorHandler.cmdQueueRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.cmdQueueRingbufDmaSlavePipeIfc);  // already Nr
//     mkConnection(ringbufAndDescriptorHandler.simpleNicRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.simpleNicRingbufDmaSlavePipeIfc);  // already Nr
//     mkConnection(ringbufAndDescriptorHandler.qpResetReqPipeOut, qpMrPgtQpc.qpResetReqPipeIn);
//     mkConnection(qpMrPgtQpc.metaReportDescPipeOutVec, ringbufAndDescriptorHandler.metaReportDescPipeInVec);
//     mkConnection(ringbufAndDescriptorHandler.mrAndPgtManagerClt, qpMrPgtQpc.mrAndPgtModifyDescSrv);
//     mkConnection(ringbufAndDescriptorHandler.qpcModifyClt, qpMrPgtQpc.qpContextUpdateSrv);

//     mkConnection(qpMrPgtQpc.simpleNicRxDescPipeOut, ringbufAndDescriptorHandler.simpleNicRxDescPipeIn);
//     mkConnection(qpMrPgtQpc.simpleNicTxDescPipeIn, ringbufAndDescriptorHandler.simpleNicTxDescPipeOut);
//     mkConnection(qpMrPgtQpc.simpleNicPacketDmaMasterPipeIfc, topLevelDmaChannelMux.simpleNicPacketDmaSlavePipeIfc);
//     rule forwardSetNetworkParamReqPipeOut;
//         ringbufAndDescriptorHandler.setNetworkParamReqPipeOut.deq;
//         qpMrPgtQpc.setLocalNetworkSettings(ringbufAndDescriptorHandler.setNetworkParamReqPipeOut.first);
//     endrule
 

//     interface dmaSlavePipeIfc = csrRootConnector.dmaSidePipeIfc;
//     interface dmaMasterPipeIfcVec = topLevelDmaChannelMux.dmaMasterPipeIfcVec;
//     interface qpEthDataStreamIfcVec = qpMrPgtQpc.qpEthDataStreamIfcVec;
// endmodule



interface QpMrPgtQpc;
    interface BlueRdmaCsrUpStreamPort                   csrUpStreamPort;

    // DMA interfaces
    interface IoChannelMemoryMasterPipeB0In pgtUpdateDmaMasterPipe;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipeB0In)       qpDmaRequestMasterIfcVec;

    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeInB0#(WorkQueueElem))            wqePipeInVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(RingbufRawDescriptor))      metaReportDescPipeOutVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipeB0In)  qpEthDataStreamIfcVec;

    interface PipeIn#(IndexQP)                                                      qpResetReqPipeIn;
        
    interface ServerP#(WriteReqQPC, Bool)                                            qpContextUpdateSrv;
    interface ServerP#(RingbufRawDescriptor, Bool)                                   mrAndPgtModifyDescSrv;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface



(* synthesize *)
module mkQpMrPgtQpc(QpMrPgtQpc);
    PipeInAdapterB0#(WriteReqQPC) qpContextUpdateReqQueue <- mkPipeInAdapterB0;
    FIFOF#(Bool) qpContextUpdateRespQueue <- mkLFIFOF;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(RingbufRawDescriptor)) metaReportDescPipeOutVecInst = newVector;

    QpContextFourWayQuery qpContext <- mkQpContextFourWayQuery;
    MemRegionTableEightWayQuery mrTable <- mkMemRegionTableEightWayQuery;
    AddressTranslateEightWayQuery addrTranslator <- mkAddressTranslateEightWayQuery;
    MrAndPgtUpdater mrAndPgtUpdater <- mkMrAndPgtUpdater;
    PgtUpdateDmaInterfaceConvertor pgtUpdateDmaInterfaceConvertor <- mkPgtUpdateDmaInterfaceConvertor;
    AutoAckGenerator    autoAckGenerator <- mkAutoAckGenerator;
    CnpPacketGenerator cnpPacketGenerator <- mkCnpPacketGenerator;

    Vector#(HARDWARE_QP_CHANNEL_CNT, PayloadGenAndCon) payloadGenAndConVec <- replicateM(mkPayloadGenAndCon);
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVec <- replicateM(mkSQ);
    Vector#(HARDWARE_QP_CHANNEL_CNT, RQ) rqVec <- replicateM(mkRQ);
    Vector#(HARDWARE_QP_CHANNEL_CNT, DtldStreamNoMetaArbiterSlave#(NUMERIC_TYPE_THREE, DATA)) ethTxStreamArbiterVec <- replicateM(mkDtldStreamNoMetaArbiterSlave(valueOf(NUMERIC_TYPE_THREE)));
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeInB0#(WorkQueueElem)) wqePipeInVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, DescriptorMux) descriptorMuxVec <- replicateM(mkDescriptorMux);


    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipeB0In)         qpDmaRequestMasterIfcVecInst    = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipeB0In)    qpEthDataStreamIfcVecInst       = newVector;

    mkConnection(mrAndPgtUpdater.dmaReadReqPipeOut, pgtUpdateDmaInterfaceConvertor.dmaReadReqPipeIn);   // already Nr
    mkConnection(mrAndPgtUpdater.dmaReadRespPipeIn, pgtUpdateDmaInterfaceConvertor.dmaReadRespPipeOut);    
    mkConnection(mrAndPgtUpdater.mrModifyClt, mrTable.modifySrv);
    mkConnection(mrAndPgtUpdater.pgtModifyClt, addrTranslator.modifySrv);

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        // Payload gen and con
        mkConnection(sqVec[idx].payloadGenReqPipeOut, payloadGenAndConVec[idx].genReqPipeIn);    // already Nr
        mkConnection(sqVec[idx].payloadGenRespPipeIn, payloadGenAndConVec[idx].payloadGenStreamPipeOut);

        mkConnection(rqVec[idx].payloadConReqPipeOut, payloadGenAndConVec[idx].conReqPipeIn);
        mkConnection(rqVec[idx].payloadConRespPipeIn, payloadGenAndConVec[idx].conRespPipeOut);
        mkConnection(rqVec[idx].payloadConStreamPipeOut, payloadGenAndConVec[idx].payloadConStreamPipeIn);

        // ethernet ifc
        mkConnection(sqVec[idx].packetPipeOut, ethTxStreamArbiterVec[idx].pipeInIfcVec[0]);
        qpEthDataStreamIfcVecInst[idx] = (
                interface IoChannelBiDirStreamNoMetaPipeB0In
                    interface dataPipeIn = rqVec[idx].ethernetFramePipeIn;
                    interface dataPipeOut = ethTxStreamArbiterVec[idx].pipeOutIfc;
                endinterface
            );


        // QPContext, MR Table and PGT
        mkConnection(rqVec[idx].qpcQueryClt, qpContext.querySrvVec[idx]);

        mkConnection(sqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2]);
        mkConnection(rqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2 + 1]);

        mkConnection(payloadGenAndConVec[idx].genAddrTranslateClt, addrTranslator.querySrvVec[idx * 2]);
        mkConnection(payloadGenAndConVec[idx].conAddrTranslateClt, addrTranslator.querySrvVec[idx * 2 + 1]);

        // auto ack, bitmap report and CNP
        mkConnection(rqVec[idx].autoAckGenReqPipeOut, autoAckGenerator.reqPipeInVec[idx]);  // already Nr
        mkConnection(rqVec[idx].genCnpReqPipeOut, cnpPacketGenerator.genReqPipeInVec[idx]);  // already Nr
        mkConnection(cnpPacketGenerator.cnpEthPacketPipeOutVec[idx], ethTxStreamArbiterVec[idx].pipeInIfcVec[1]);

        // meta report descriptors
        mkConnection(rqVec[idx].metaReportDescPipeOut, descriptorMuxVec[idx].descPipeInVec[0]);  // already Nr
        metaReportDescPipeOutVecInst[idx] = descriptorMuxVec[idx].descPipeOut;

        // RDMA payload DMA Ifc
        qpDmaRequestMasterIfcVecInst[idx] = payloadGenAndConVec[idx].ioChannelMemoryMasterPipeIfc;  
    
        // IO interface 
        wqePipeInVecInst[idx]               = sqVec[idx].wqePipeIn;

        rule deqNotUsed;
            ethTxStreamArbiterVec[idx].sourceChannelIdPipeOut.deq;
        endrule
    end

    // other meta report desc related connection
    // since after bitmap merge, four channel becomes two channel, and background loop tooks another channel
    // to simpilify design, we won't dispatch them evenly.
    mkConnection(autoAckGenerator.metaReportDescPipeOutVec[0], descriptorMuxVec[0].descPipeInVec[1]);  // already Nr
    mkConnection(autoAckGenerator.metaReportDescPipeOutVec[1], descriptorMuxVec[1].descPipeInVec[1]);  // already Nr
    mkConnection(autoAckGenerator.metaReportDescPipeOutVec[2], descriptorMuxVec[2].descPipeInVec[1]);  // already Nr

    // Ethernet Tx channel 0 will handle simple Nic's traffic. Tx channel 1 and 2 will handle auto ack traffic. It may lead to unbalance between other channels.
    mkConnection(autoAckGenerator.ackEthPacketPipeOutVec[0] , ethTxStreamArbiterVec[1].pipeInIfcVec[2]);
    mkConnection(autoAckGenerator.ackEthPacketPipeOutVec[1] , ethTxStreamArbiterVec[2].pipeInIfcVec[2]);

    let qpContextUpdateSrvRequestPipeInB0Adapter <- mkPipeInB0ToPipeIn(qpContext.updateSrv.request, 1);
    let autoAckGeneratorQpcUpdateSrvRequestPipeInB0Adapter <- mkPipeInB0ToPipeIn(autoAckGenerator.qpcUpdateSrv.request, 1);

    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
            let regIdx = req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
            let addrBlockMask = fromInteger(valueOf(CSR_ADDR_ROUTING_MASK_FOR_METRICS_OF_QPMRPGTQPC));
            let maskedAddr = addrBlockMask & regIdx;
            if (fromInteger(valueOf(CSR_ADDR_ROUTING_FOR_METRICS_RQ0)) == maskedAddr) begin
                return tagged CsrNodeResultForward 0;
            end
            else if (fromInteger(valueOf(CSR_ADDR_ROUTING_FOR_METRICS_RQ1)) == maskedAddr) begin
                return tagged CsrNodeResultForward 1;
            end
            else if (fromInteger(valueOf(CSR_ADDR_ROUTING_FOR_METRICS_RQ2)) == maskedAddr) begin
                return tagged CsrNodeResultForward 2;
            end
            else if (fromInteger(valueOf(CSR_ADDR_ROUTING_FOR_METRICS_RQ3)) == maskedAddr) begin
                return tagged CsrNodeResultForward 3;
            end
            else begin
                return tagged CsrNodeResultNotMatched;
            end
        endactionvalue
    endfunction
    
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_ONE), "mkQpMrPgtQpc");
    mkConnection(rqVec[0].csrUpStreamPort, csrNode.downStreamPortsVec[0]);
    mkConnection(rqVec[1].csrUpStreamPort, csrNode.downStreamPortsVec[1]);
    mkConnection(rqVec[2].csrUpStreamPort, csrNode.downStreamPortsVec[2]);
    mkConnection(rqVec[3].csrUpStreamPort, csrNode.downStreamPortsVec[3]);

    
    rule forwardQpContextUpdateReq;
        let req = qpContextUpdateReqQueue.first;
        qpContextUpdateReqQueue.deq;
        qpContextUpdateSrvRequestPipeInB0Adapter.enq(req);
        autoAckGeneratorQpcUpdateSrvRequestPipeInB0Adapter.enq(req);
    endrule
    
    rule forwardQpContextUpdateResp;
        let r1 = qpContext.updateSrv.response.first;
        qpContext.updateSrv.response.deq;
        let r2 = autoAckGenerator.qpcUpdateSrv.response.first;
        autoAckGenerator.qpcUpdateSrv.response.deq;
        qpContextUpdateRespQueue.enq(r1 && r2);
    endrule

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            sqVec[idx].setLocalNetworkSettings(networkSettings);
            rqVec[idx].setLocalNetworkSettings(networkSettings);
        end
        autoAckGenerator.setLocalNetworkSettings(networkSettings);
        cnpPacketGenerator.setLocalNetworkSettings(networkSettings);
    endmethod

    interface csrUpStreamPort                   = csrNode.upStreamPort;
    interface pgtUpdateDmaMasterPipe            = pgtUpdateDmaInterfaceConvertor.dmaSidePipeIfc;
    interface wqePipeInVec                      = wqePipeInVecInst;
    interface metaReportDescPipeOutVec          = metaReportDescPipeOutVecInst;
    interface qpDmaRequestMasterIfcVec          = qpDmaRequestMasterIfcVecInst;
    interface qpEthDataStreamIfcVec             = qpEthDataStreamIfcVecInst;
    interface qpContextUpdateSrv                = toGPServerP(toPipeInB0(qpContextUpdateReqQueue), toPipeOut(qpContextUpdateRespQueue));

    interface qpResetReqPipeIn                  = autoAckGenerator.resetReqPipeIn;
    interface mrAndPgtModifyDescSrv             = mrAndPgtUpdater.mrAndPgtModifyDescSrv;
endmodule
