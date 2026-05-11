import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;
import Clocks :: *;
import Probe :: *;

import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;
import RdmaHeaders :: *;

import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import PacketGenAndParse :: *;
import EthernetTypes :: *;
import AxiBus :: *;

import EthernetFrameIO256 :: *;
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
import FullyPipelineChecker :: *;

import SQ :: *;
import RQ :: *;

import XilinxCmacController :: *;
`ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_XDMA
    import XdmaWrapper :: *;
`elsif BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC
    import XilBdmaPcieTypes :: *;
    import XilBdmaDmaTypes :: *;
    import XilBDmacWrapper :: *;
`endif

typedef 16 CMAC_SYNC_BRAM_BUF_DEPTH;
typedef 2 CMAC_CDC_SYNC_STAGE;

typedef Vector#(VIRTUAL_CHANNEL_NUM, Maybe#(FlowControlRequest)) FlowControlReqVec;

interface BsvTop;
    // Interface with CMAC IP
    (* prefix = "" *)
    interface XilinxCmacController cmacController;
    `ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_XDMA
        interface RawAxi4LiteSlave#(ADDR, XdmaAxiLiteData, XdmaAxiLiteStrb) cntrlAxil;
        interface XdmaChannel#(DATA, XdmaAxisTkeep, XdmaAxisTuser) xdmaChannel;
    `elsif BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC
        (* prefix = "" *)       interface   RawXilinxPcieIp         rawPcie;
        (* prefix = "" *)       method      TlpSizeCfg              tlpSizeDebugPort;
        (* prefix = "" *)       method      Bool                    sys_reset;
    `endif
endinterface

(* synthesize *)
module mkBsvTop(
        (* osc   = "cmac_rxtx_clk" *) Clock cmacRxTxClk,
        (* reset = "cmac_rx_resetn" *) Reset cmacRxReset,
        (* reset = "cmac_tx_resetn" *) Reset cmacTxReset,
    BsvTop ifc);

    `ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_XDMA
        BsvTopOnlyHardIpWithXDMA                bsvTopOnlyHardIp            <- mkBsvTopOnlyHardIpWithXDMA(cmacRxTxClk, cmacRxReset, cmacTxReset);
    `elsif BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC
        BsvTopOnlyHardIpWithXilBDMA             bsvTopOnlyHardIp            <- mkBsvTopOnlyHardIpWithXilBDMA(cmacRxTxClk, cmacRxReset, cmacTxReset);
    `endif

    BsvTopWithoutHardIpInstance bsvTopWithoutHardIpInstance <- mkBsvTopWithoutHardIpInstance;

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(IoChannelMemoryAccessMeta)) slrCrossFifoDmacHipSideReadMetaVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(IoChannelMemoryAccessDataStream)) slrCrossFifoDmacUserLogicSideReadDataVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(IoChannelMemoryAccessMeta)) slrCrossFifoDmacHipSideWriteMetaVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(IoChannelMemoryAccessDataStream)) slrCrossFifoDmacHipSideWriteDataVec <- replicateM(mkFIFOF);


    for (Integer channelIdx = 0; channelIdx < valueOf(NUMERIC_TYPE_TWO); channelIdx = channelIdx + 1) begin
        // read meta
        mkConnection(bsvTopWithoutHardIpInstance.dmaMasterPipeIfcVec[channelIdx].readPipeIfc.readMetaPipeOut, toPipeIn(slrCrossFifoDmacHipSideReadMetaVec[channelIdx]));
        mkConnection(toPipeOut(slrCrossFifoDmacHipSideReadMetaVec[channelIdx]), bsvTopOnlyHardIp.dmaSlavePipeIfcVec[channelIdx].readPipeIfc.readMetaPipeIn);
        // read data
        mkConnection(bsvTopWithoutHardIpInstance.dmaMasterPipeIfcVec[channelIdx].readPipeIfc.readDataPipeIn, toPipeOut(slrCrossFifoDmacUserLogicSideReadDataVec[channelIdx]));
        mkConnection(toPipeIn(slrCrossFifoDmacUserLogicSideReadDataVec[channelIdx]), bsvTopOnlyHardIp.dmaSlavePipeIfcVec[channelIdx].readPipeIfc.readDataPipeOut);


        // write meta
        mkConnection(bsvTopWithoutHardIpInstance.dmaMasterPipeIfcVec[channelIdx].writePipeIfc.writeMetaPipeOut, toPipeIn(slrCrossFifoDmacHipSideWriteMetaVec[channelIdx]));
        mkConnection(toPipeOut(slrCrossFifoDmacHipSideWriteMetaVec[channelIdx]), bsvTopOnlyHardIp.dmaSlavePipeIfcVec[channelIdx].writePipeIfc.writeMetaPipeIn);
        // write data
        mkConnection(bsvTopWithoutHardIpInstance.dmaMasterPipeIfcVec[channelIdx].writePipeIfc.writeDataPipeOut, toPipeIn(slrCrossFifoDmacHipSideWriteDataVec[channelIdx]));
        mkConnection(toPipeOut(slrCrossFifoDmacHipSideWriteDataVec[channelIdx]), bsvTopOnlyHardIp.dmaSlavePipeIfcVec[channelIdx].writePipeIfc.writeDataPipeIn);
    end

    

    mkConnection(bsvTopOnlyHardIp.dmaMasterPipeIfc, bsvTopWithoutHardIpInstance.dmaSlavePipeIfc);

    mkConnection(bsvTopOnlyHardIp.macStreamBiDirPipe.dataPipeOut, bsvTopWithoutHardIpInstance.qpEthDataStreamIfc.dataPipeIn);
    mkConnection(bsvTopOnlyHardIp.macStreamBiDirPipe.dataPipeIn, bsvTopWithoutHardIpInstance.qpEthDataStreamIfc.dataPipeOut);



    interface cmacController = bsvTopOnlyHardIp.cmacController;
    `ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_XDMA
        interface cntrlAxil = bsvTopOnlyHardIp.cntrlAxil;
        interface xdmaChannel = bsvTopOnlyHardIp.xdmaChannel;
    `elsif BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC
        interface  rawPcie          = bsvTopOnlyHardIp.rawPcie;
        method     tlpSizeDebugPort = bsvTopOnlyHardIp.tlpSizeDebugPort;
        method     sys_reset        = bsvTopOnlyHardIp.sys_reset;
    `endif
endmodule



`ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_XDMA
    interface BsvTopOnlyHardIpWithXDMA;
        // to verilog side ===================================================

        // Interface with Hard IP
        (* prefix = "" *)
        interface XilinxCmacController cmacController;
        interface RawAxi4LiteSlave#(ADDR, XdmaAxiLiteData, XdmaAxiLiteStrb) cntrlAxil;
        interface XdmaChannel#(DATA, XdmaAxisTkeep, XdmaAxisTuser) xdmaChannel;

        // to bsv side =======================================================

        interface Vector#(NUMERIC_TYPE_TWO, IoChannelMemorySlavePipeB0In)   dmaSlavePipeIfcVec;
        interface IoChannelMemoryMasterPipe                                 dmaMasterPipeIfc;

        interface IoChannelBiDirStreamNoMetaPipeB0In                        macStreamBiDirPipe;
        
    endinterface

    (* synthesize *)
    module mkBsvTopOnlyHardIpWithXDMA#(
            Clock cmacRxTxClk,
            Reset cmacRxReset,
            Reset cmacTxReset
        )(BsvTopOnlyHardIpWithXDMA);

        Vector#(NUMERIC_TYPE_TWO, IoChannelMemorySlavePipeB0In)   dmaSlavePipeIfcVecInst = newVector;

        SyncFIFOIfc#(CmacAxiStream) axiStream512TxSyncFifo <- mkSyncFIFOFromCC(valueOf(CMAC_SYNC_BRAM_BUF_DEPTH), cmacRxTxClk);
        SyncFIFOIfc#(CmacAxiStream) axiStream512RxSyncFifo <- mkSyncFIFOToCC(valueOf(CMAC_SYNC_BRAM_BUF_DEPTH), cmacRxTxClk, cmacRxReset);

        Bool isEnableRsFec = True;
        Bool isEnableFlowControl = False;
        Bool isCmacTxWaitRxAligned = True;

        FIFOF#(FlowControlReqVec) dummyTxFlowCtrlReqVecQueue <- mkFIFOF(clocked_by cmacRxTxClk, reset_by cmacTxReset);
        FIFOF#(FlowControlReqVec) dummyRxFlowCtrlReqVecQueue <- mkFIFOF(clocked_by cmacRxTxClk, reset_by cmacRxReset);

        let xilinxCmacCtrl <- mkXilinxCmacController(
            isEnableRsFec,
            isEnableFlowControl,
            isCmacTxWaitRxAligned,
            toPipeOutSync(axiStream512TxSyncFifo),
            toPipeInSync(axiStream512RxSyncFifo),
            toPipeOut(dummyTxFlowCtrlReqVecQueue),
            toPipeIn(dummyRxFlowCtrlReqVecQueue),
            cmacRxReset,
            cmacTxReset,
            clocked_by cmacRxTxClk
        );

        
        PipeInAdapterB0#(IoChannelEthDataStream) ethTxDataPipeInQueue <- mkPipeInAdapterB0;
        FIFOF#(IoChannelEthDataStream) ethRxDataPipeOutQueue <- mkFIFOF;

        Reg#(Bool) isEthRxForwardFirstBeatReg <- mkReg(True);

        let xilinxXdmaStreamCtrl <- mkXdmaWrapper;
        let xilinxXdmaAxiLiteCtrl <- mkXdmaAxiLiteBridgeWrapper;

        dmaSlavePipeIfcVecInst[0] = xilinxXdmaStreamCtrl.dmaSlavePipeIfc;
        // dmaSlavePipeIfcVecInst[1] = not used;

        Probe#(IoChannelEthDataStream) ethTxDataProbe <- mkProbe;
        Probe#(IoChannelEthDataStream) ethRxDataProbe <- mkProbe;

        // rule forwardEthRxStream;
        //     let axiDs = axiStream512RxSyncFifo.first;
        //     axiStream512RxSyncFifo.deq;

        //     let ds = IoChannelEthDataStream {
        //         data: axiDs.axisData,
        //         startByteIdx: 0,
        //         byteNum: axiDs.axisLast ? unpack(pack(countZerosLSB(~axiDs.axisKeep))) : fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)),
        //         isFirst: isEthRxForwardFirstBeatReg,
        //         isLast: axiDs.axisLast
        //     };
        //     ethRxDataPipeOutQueue.enq(ds);
        //     isEthRxForwardFirstBeatReg <= axiDs.axisLast;
        //     ethRxDataProbe <= ds;
        // endrule

        // rule forwardEthTxStream;
        //     let ds = ethTxDataPipeInQueue.first;
        //     ethTxDataPipeInQueue.deq;

        //     let axiDs = AxiStream {
        //         axisData: ds.data,
        //         axisKeep: ds.isLast ? (1 << ds.byteNum) - 1 : maxBound,
        //         axisLast: ds.isLast,
        //         axisUser: 0
        //     };
        //     axiStream512TxSyncFifo.enq(axiDs);
        //     ethTxDataProbe <= ethTxDataPipeInQueue.first;
        // endrule

        

        rule loopbackForTest;
            ethRxDataPipeOutQueue.enq(ethTxDataPipeInQueue.first);
            ethTxDataPipeInQueue.deq;
            ethTxDataProbe <= ethTxDataPipeInQueue.first;
        endrule

        interface cmacController = xilinxCmacCtrl;
        interface cntrlAxil = xilinxXdmaAxiLiteCtrl.cntrlAxil;
        interface xdmaChannel = xilinxXdmaStreamCtrl.xdmaChannel;


        interface dmaSlavePipeIfcVec = dmaSlavePipeIfcVecInst;
        interface dmaMasterPipeIfc = xilinxXdmaAxiLiteCtrl.dmaMasterPipeIfc;
        interface IoChannelBiDirStreamNoMetaPipeB0In           macStreamBiDirPipe;
            interface dataPipeIn = toPipeInB0(ethTxDataPipeInQueue);
            interface dataPipeOut = toPipeOut(ethRxDataPipeOutQueue);
        endinterface
    endmodule
`elsif BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC

    interface BsvTopOnlyHardIpWithXilBDMA;
        // to verilog side ===================================================

        // Interface with Hard IP
        (* prefix = "" *)       interface   XilinxCmacController    cmacController;
        (* prefix = "" *)       interface   RawXilinxPcieIp         rawPcie;
        (* prefix = "" *)       method      TlpSizeCfg              tlpSizeDebugPort;
        (* prefix = "" *)       method      Bool                    sys_reset;

        // to bsv side =======================================================

        interface Vector#(NUMERIC_TYPE_TWO, IoChannelMemorySlavePipeB0In)   dmaSlavePipeIfcVec;
        interface IoChannelMemoryMasterPipe                                 dmaMasterPipeIfc;

        interface IoChannelBiDirStreamNoMetaPipeB0In            macStreamBiDirPipe;
        
    endinterface

    (* synthesize *)
    module mkBsvTopOnlyHardIpWithXilBDMA#(
            Clock cmacRxTxClk,
            Reset cmacRxReset,
            Reset cmacTxReset
        )(BsvTopOnlyHardIpWithXilBDMA);


        SyncFIFOIfc#(CmacAxiStream) axiStream512TxSyncFifo <- mkSyncFIFOFromCC(valueOf(CMAC_SYNC_BRAM_BUF_DEPTH), cmacRxTxClk);
        SyncFIFOIfc#(CmacAxiStream) axiStream512RxSyncFifo <- mkSyncFIFOToCC(valueOf(CMAC_SYNC_BRAM_BUF_DEPTH), cmacRxTxClk, cmacRxReset);


        FIFOF#(CmacAxiStream) axiStream512TxTimingFixFifo <- mkFIFOF;
        FIFOF#(CmacAxiStream) axiStream512RxTimingFixFifo <- mkFIFOF;

        Bool isEnableRsFec = True;
        Bool isEnableFlowControl = False;
        Bool isCmacTxWaitRxAligned = True;

        FIFOF#(FlowControlReqVec) dummyTxFlowCtrlReqVecQueue <- mkFIFOF(clocked_by cmacRxTxClk, reset_by cmacTxReset);
        FIFOF#(FlowControlReqVec) dummyRxFlowCtrlReqVecQueue <- mkFIFOF(clocked_by cmacRxTxClk, reset_by cmacRxReset);

        let xilinxCmacCtrl <- mkXilinxCmacController(
            isEnableRsFec,
            isEnableFlowControl,
            isCmacTxWaitRxAligned,
            toPipeOutSync(axiStream512TxSyncFifo),
            toPipeInSync(axiStream512RxSyncFifo),
            toPipeOut(dummyTxFlowCtrlReqVecQueue),
            toPipeIn(dummyRxFlowCtrlReqVecQueue),
            cmacRxReset,
            cmacTxReset,
            clocked_by cmacRxTxClk
        );

        
        PipeInAdapterB0#(IoChannelEthDataStream) ethTxDataPipeInQueue <- mkPipeInAdapterB0;
        FIFOF#(IoChannelEthDataStream) ethRxDataPipeOutQueue <- mkFIFOF;

        Reg#(Bool) isEthRxForwardFirstBeatReg <- mkReg(True);

        let xilBdmaController <- mkXilBdmacWrapper;

        Probe#(IoChannelEthDataStream) ethTxDataProbe <- mkProbe;
        Probe#(IoChannelEthDataStream) ethRxDataProbe <- mkProbe;

        rule forwardTimingFixTx;
            axiStream512TxTimingFixFifo.deq;
            axiStream512TxSyncFifo.enq(axiStream512TxTimingFixFifo.first);
        endrule

        rule forwardTimingFixRx;
            axiStream512RxSyncFifo.deq;
            axiStream512RxTimingFixFifo.enq(axiStream512RxSyncFifo.first);
        endrule

        rule forwardEthRxStream;
            let axiDs = axiStream512RxTimingFixFifo.first;
            axiStream512RxTimingFixFifo.deq;

            let ds = IoChannelEthDataStream {
                data: axiDs.axisData,
                startByteIdx: 0,
                byteNum: axiDs.axisLast ? unpack(pack(countZerosLSB(~axiDs.axisKeep))) : fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)),
                isFirst: isEthRxForwardFirstBeatReg,
                isLast: axiDs.axisLast
            };
            ethRxDataPipeOutQueue.enq(ds);
            isEthRxForwardFirstBeatReg <= axiDs.axisLast;
            ethRxDataProbe <= ds;
        endrule

        rule forwardEthTxStream;
            let ds = ethTxDataPipeInQueue.first;
            ethTxDataPipeInQueue.deq;

            let axiDs = AxiStream {
                axisData: ds.data,
                axisKeep: ds.isLast ? (1 << ds.byteNum) - 1 : maxBound,
                axisLast: ds.isLast,
                axisUser: 0
            };
            axiStream512TxTimingFixFifo.enq(axiDs);
            ethTxDataProbe <= ethTxDataPipeInQueue.first;
        endrule

        

        // rule loopbackForTest;
        //     ethRxDataPipeOutQueue.enq(ethTxDataPipeInQueue.first);
        //     ethTxDataPipeInQueue.deq;
        //     ethTxDataProbe <= ethTxDataPipeInQueue.first;
        // endrule

        interface cmacController = xilinxCmacCtrl;    

        interface   rawPcie             = xilBdmaController.rawPcie;
        method      tlpSizeDebugPort    = xilBdmaController.tlpSizeDebugPort;
        method      sys_reset           = xilBdmaController.sys_reset;

        interface dmaSlavePipeIfcVec    = xilBdmaController.dmaSlavePipeIfcVec;
        interface dmaMasterPipeIfc      = xilBdmaController.dmaMasterPipeIfc;

        interface IoChannelBiDirStreamNoMetaPipeB0In           macStreamBiDirPipe;
            interface dataPipeIn = toPipeInB0(ethTxDataPipeInQueue);
            interface dataPipeOut = toPipeOut(ethRxDataPipeOutQueue);
        endinterface
    endmodule
`endif


typedef DtldStreamArbiterSlave#(NUMERIC_TYPE_SIX, DATA, ADDR, Length) IoChannelSixChannelDmaMux;

interface TopLevelDmaChannelMux;
    // upstream port
    interface IoChannelMemoryMasterPipeB0In   dmaMasterPipeIfc;

    // downstream port
    interface IoChannelMemorySlavePipeB0In qpRingbufDmaSlavePipeIfc;
    interface IoChannelMemorySlavePipeB0In cmdQueueRingbufDmaSlavePipeIfc;
    interface IoChannelMemorySlavePipeB0In simpleNicRingbufDmaSlavePipeIfc;

    interface IoChannelMemorySlavePipeB0In qpDmaRequestSlaveIfc;
    interface IoChannelMemorySlavePipeB0In simpleNicPacketDmaSlavePipeIfc;
    
    interface IoChannelMemorySlavePipeB0In pgtUpdateDmaSlavePipe;
endinterface


(* synthesize *)
module mkTopLevelDmaChannelMux(TopLevelDmaChannelMux);
    // Note: the write depth of the mux should match the delay between Mux output and the DMA engine consume.
    // For example, the Xilinx XDMA has a delay between it consumes the descriptor and begin to consume payload data.
    IoChannelSixChannelDmaMux         muxInst <- mkDtldStreamArbiterSlave(256, 16, True, DebugConf{name: "mkTopLevelDmaChannelMux muxInst", enableDebug: False});


    rule discardUselessPipeOutSignal;
        if (muxInst.writeSourceChannelIdPipeOut.notEmpty) begin
            muxInst.writeSourceChannelIdPipeOut.deq;
        end
        if (muxInst.readSourceChannelIdPipeOut.notEmpty) begin
            muxInst.readSourceChannelIdPipeOut.deq;
        end
    endrule


    // upstream port
    interface dmaMasterPipeIfc = muxInst.masterIfc;


    // downstream port
    interface qpRingbufDmaSlavePipeIfc          = muxInst.slaveIfcVec[0];
    interface qpDmaRequestSlaveIfc              = muxInst.slaveIfcVec[1];
    interface cmdQueueRingbufDmaSlavePipeIfc    = muxInst.slaveIfcVec[2]; 
    interface pgtUpdateDmaSlavePipe             = muxInst.slaveIfcVec[3]; 
    interface simpleNicRingbufDmaSlavePipeIfc   = muxInst.slaveIfcVec[4]; 
    interface simpleNicPacketDmaSlavePipeIfc    = muxInst.slaveIfcVec[5]; 
endmodule


interface BsvTopWithoutHardIpInstance;
    interface IoChannelMemorySlavePipe dmaSlavePipeIfc;
    interface Vector#(NUMERIC_TYPE_TWO, IoChannelMemoryMasterPipeB0In)   dmaMasterPipeIfcVec;
    interface IoChannelBiDirStreamNoMetaPipeB0In  qpEthDataStreamIfc;
endinterface



(* synthesize *)
module mkBsvTopWithoutHardIpInstance(BsvTopWithoutHardIpInstance);

    Vector#(NUMERIC_TYPE_TWO, IoChannelMemoryMasterPipeB0In)   dmaMasterPipeIfcVecInst = newVector;

    let qpMrPgtQpc <- mkQpMrPgtQpc;
    let ringbufAndDescriptorHandler <- mkRingbufAndDescriptorHandler;
    mkConnection(ringbufAndDescriptorHandler.wqePipeOut, qpMrPgtQpc.wqePipeIn);  // already Nr

    TopLevelDmaChannelMux topLevelDmaChannelMux <- mkTopLevelDmaChannelMux;

    let csrRootConnector <- mkCsrRootConnector;
    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
            // $display(
            //     "time=%0t:", $time, toGreen("mkBsvTopWithoutHardIpInstance csrMatchFunc"),
            //     ", req=", fshow(req)
            // );
            let regIdx = req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
            let addrBlockMask = ~fromInteger(valueOf(CSR_ADDR_BLOCK_SIZE_FOR_RINGBUFS) - 1);
            let maskedAddr = addrBlockMask & regIdx;
            if (fromInteger(valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_RINGBUFS)) == maskedAddr) begin
                return tagged CsrNodeResultForward 0;
            end
            else begin
                return tagged CsrNodeResultForward 1;
            end
        endactionvalue
    endfunction
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_TWO), "mkBsvTopWithoutHardIpInstance");
    
    mkConnection(csrRootConnector.csrNodeRootPortIfc, csrNode.upStreamPort);
    mkConnection(ringbufAndDescriptorHandler.csrUpStreamPort, csrNode.downStreamPortsVec[0]);
    mkConnection(qpMrPgtQpc.csrUpStreamPort, csrNode.downStreamPortsVec[1]);


    let notUsedDmaWriteMetaQueue <- mkLFIFOF;
    let notUsedDmaWriteDataQueue <- mkLFIFOF;
    let notUsedDmaReadMetaQueue <- mkLFIFOF;
    let notUsedDmaReadDataQueue          <- mkPipeInAdapterB0;

    `ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_XDMA
        mkConnection(qpMrPgtQpc.qpDmaRequestMasterIfc, topLevelDmaChannelMux.qpDmaRequestSlaveIfc);  // already Nr
        dmaMasterPipeIfcVecInst[0] = topLevelDmaChannelMux.dmaMasterPipeIfc;
        dmaMasterPipeIfcVecInst[1].writePipeIfc.writeMetaPipeOut = toPipeOut(notUsedDmaWriteMetaQueue);
        dmaMasterPipeIfcVecInst[1].writePipeIfc.writeDataPipeOut = toPipeOut(notUsedDmaWriteDataQueue);
        dmaMasterPipeIfcVecInst[1].readPipeIfc.readMetaPipeOut = toPipeOut(notUsedDmaReadMetaQueue);
        dmaMasterPipeIfcVecInst[1].readPipeIfc.readDataPipeIn = toPipeInB0(notUsedDmaReadDataQueue);

        // dmaMasterPipeIfcVecInst[1] = not used;
    `elsif BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC
        // dmaMasterPipeIfcVecInst[0] = qpMrPgtQpc.qpDmaRequestMasterIfc;
        // dmaMasterPipeIfcVecInst[1] = topLevelDmaChannelMux.dmaMasterPipeIfc;

        dmaMasterPipeIfcVecInst[1].writePipeIfc.writeMetaPipeOut = toPipeOut(notUsedDmaWriteMetaQueue);
        dmaMasterPipeIfcVecInst[1].writePipeIfc.writeDataPipeOut = toPipeOut(notUsedDmaWriteDataQueue);
        dmaMasterPipeIfcVecInst[1].readPipeIfc.readMetaPipeOut = toPipeOut(notUsedDmaReadMetaQueue);
        dmaMasterPipeIfcVecInst[1].readPipeIfc.readDataPipeIn = toPipeInB0(notUsedDmaReadDataQueue);

        mkConnection(qpMrPgtQpc.qpDmaRequestMasterIfc, topLevelDmaChannelMux.qpDmaRequestSlaveIfc);  // already Nr
        dmaMasterPipeIfcVecInst[0] = topLevelDmaChannelMux.dmaMasterPipeIfc;
    `endif

    mkConnection(qpMrPgtQpc.pgtUpdateDmaMasterPipe, topLevelDmaChannelMux.pgtUpdateDmaSlavePipe);    // already Nr
    mkConnection(ringbufAndDescriptorHandler.qpRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.qpRingbufDmaSlavePipeIfc); // already Nr
    mkConnection(ringbufAndDescriptorHandler.cmdQueueRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.cmdQueueRingbufDmaSlavePipeIfc);  // already Nr
    mkConnection(ringbufAndDescriptorHandler.simpleNicRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.simpleNicRingbufDmaSlavePipeIfc);  // already Nr
    mkConnection(ringbufAndDescriptorHandler.qpResetReqPipeOut, qpMrPgtQpc.qpResetReqPipeIn);
    mkConnection(qpMrPgtQpc.metaReportDescPipeOut, ringbufAndDescriptorHandler.metaReportDescPipeIn);
    mkConnection(ringbufAndDescriptorHandler.mrAndPgtManagerClt, qpMrPgtQpc.mrAndPgtModifyDescSrv);
    mkConnection(ringbufAndDescriptorHandler.qpcModifyClt, qpMrPgtQpc.qpContextUpdateSrv);

    mkConnection(qpMrPgtQpc.simpleNicRxDescPipeOut, ringbufAndDescriptorHandler.simpleNicRxDescPipeIn);
    mkConnection(qpMrPgtQpc.simpleNicTxDescPipeIn, ringbufAndDescriptorHandler.simpleNicTxDescPipeOut);
    mkConnection(qpMrPgtQpc.simpleNicPacketDmaMasterPipeIfc, topLevelDmaChannelMux.simpleNicPacketDmaSlavePipeIfc);
    rule forwardSetNetworkParamReqPipeOut;
        ringbufAndDescriptorHandler.setNetworkParamReqPipeOut.deq;
        qpMrPgtQpc.setLocalNetworkSettings(ringbufAndDescriptorHandler.setNetworkParamReqPipeOut.first);
    endrule
 

    interface dmaSlavePipeIfc = csrRootConnector.dmaSidePipeIfc;
    interface dmaMasterPipeIfcVec = dmaMasterPipeIfcVecInst;
    interface qpEthDataStreamIfc = qpMrPgtQpc.qpEthDataStreamIfc;
endmodule



interface RingbufAndDescriptorHandler;
    interface IoChannelMemoryMasterPipeB0In                                     qpRingbufDmaMasterPipeIfc;
    interface IoChannelMemoryMasterPipeB0In                                     cmdQueueRingbufDmaMasterPipeIfc;
    interface IoChannelMemoryMasterPipeB0In                                     simpleNicRingbufDmaMasterPipeIfc;
    interface BlueRdmaCsrUpStreamPort                                           csrUpStreamPort;

    interface PipeOut#(WorkQueueElem)                                           wqePipeOut;
    interface PipeIn#(RingbufRawDescriptor)                                     metaReportDescPipeIn;

    interface PipeIn#(RingbufRawDescriptor)                                     simpleNicRxDescPipeIn;
    interface PipeOut#(RingbufRawDescriptor)                                    simpleNicTxDescPipeOut;
    
    interface ClientP#(RingbufRawDescriptor, Bool)                              mrAndPgtManagerClt;
    interface ClientP#(WriteReqQPC, Bool)                                       qpcModifyClt;
    interface PipeOut#(LocalNetworkSettings)                                    setNetworkParamReqPipeOut;
    interface PipeOut#(IndexQP)                                                 qpResetReqPipeOut;
endinterface

(* synthesize *)
module mkRingbufAndDescriptorHandler(RingbufAndDescriptorHandler);

    WorkQueueDescParser workQueueDescParser <- mkWorkQueueDescParser;
    CommandQueueDescParserAndDispatcher cmdQueueDescParserAndDispatcher <- mkCommandQueueDescParserAndDispatcher;


    RingbufDmaIfcConvertor qpRingbufDmaIfcConvertor <- mkRingbufDmaIfcConvertor;



    RingbufH2cSlot4096 wqeRingbuf <- mkRingbufH2c(0);
    RingbufC2hSlot4096 rqMetaReportRingbuf <- mkRingbufC2h(0);
    mkConnection(wqeRingbuf.descPipeOut, workQueueDescParser.rawDescPipeIn);


    mkConnection(wqeRingbuf.dmaReadReqPipeOut, qpRingbufDmaIfcConvertor.dmaReadReqPipeIn);               // already Nr
    mkConnection(wqeRingbuf.dmaReadRespPipeIn, qpRingbufDmaIfcConvertor.dmaReadRespPipeOut);
    mkConnection(rqMetaReportRingbuf.dmaWriteReqPipeOut, qpRingbufDmaIfcConvertor.dmaWriteReqPipeIn);    // already Nr
    mkConnection(rqMetaReportRingbuf.dmaWriteDataPipeOut, qpRingbufDmaIfcConvertor.dmaWriteDataPipeIn);  // already Nr
    mkConnection(rqMetaReportRingbuf.dmaWriteRespPipeIn, qpRingbufDmaIfcConvertor.dmaWriteRespPipeOut);

    
    RingbufH2cSlot4096 cmdReqQueueRingbuf <- mkRingbufH2c(1);
    RingbufC2hSlot4096 cmdRespQueueRingbuf <- mkRingbufC2h(1);
    RingbufDmaIfcConvertor cmdQueueRingbufDmaIfcConvertor <- mkRingbufDmaIfcConvertor;

    mkConnection(cmdReqQueueRingbuf.descPipeOut, cmdQueueDescParserAndDispatcher.reqRawDescPipeIn);
    mkConnection(cmdRespQueueRingbuf.descPipeIn, cmdQueueDescParserAndDispatcher.respRawDescPipeOut);

    mkConnection(cmdReqQueueRingbuf.dmaReadReqPipeOut, cmdQueueRingbufDmaIfcConvertor.dmaReadReqPipeIn);        // already Nr
    mkConnection(cmdReqQueueRingbuf.dmaReadRespPipeIn, cmdQueueRingbufDmaIfcConvertor.dmaReadRespPipeOut);
    mkConnection(cmdRespQueueRingbuf.dmaWriteReqPipeOut, cmdQueueRingbufDmaIfcConvertor.dmaWriteReqPipeIn);     // already Nr
    mkConnection(cmdRespQueueRingbuf.dmaWriteDataPipeOut, cmdQueueRingbufDmaIfcConvertor.dmaWriteDataPipeIn);   // already Nr
    mkConnection(cmdRespQueueRingbuf.dmaWriteRespPipeIn, cmdQueueRingbufDmaIfcConvertor.dmaWriteRespPipeOut);


    RingbufH2cSlot4096 simpleNicTxQueueRingbuf <- mkRingbufH2c(2);
    RingbufC2hSlot4096 simpleNicRxQueueRingbuf <- mkRingbufC2h(2);
    RingbufDmaIfcConvertor simpleNicRingbufDmaIfcConvertor <- mkRingbufDmaIfcConvertor;

    mkConnection(simpleNicTxQueueRingbuf.dmaReadReqPipeOut, simpleNicRingbufDmaIfcConvertor.dmaReadReqPipeIn);      // already Nr
    mkConnection(simpleNicTxQueueRingbuf.dmaReadRespPipeIn, simpleNicRingbufDmaIfcConvertor.dmaReadRespPipeOut);    
    mkConnection(simpleNicRxQueueRingbuf.dmaWriteReqPipeOut, simpleNicRingbufDmaIfcConvertor.dmaWriteReqPipeIn);    // already Nr
    mkConnection(simpleNicRxQueueRingbuf.dmaWriteDataPipeOut, simpleNicRingbufDmaIfcConvertor.dmaWriteDataPipeIn);  // already Nr
    mkConnection(simpleNicRxQueueRingbuf.dmaWriteRespPipeIn, simpleNicRingbufDmaIfcConvertor.dmaWriteRespPipeOut);
    




    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue        
            // $display(
            //     "time=%0t:", $time, toGreen("mkRingbufAndDescriptorHandler csrMatchFunc"),
            //     ", req=", fshow(req)
            // );
            if (req.isWrite) begin
                case (req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM))
                    // QP ring bufs
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        wqeRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        wqeRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        rqMetaReportRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        rqMetaReportRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end

                    // Cmd Queue ring bufs
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t =cmdReqQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        cmdReqQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t = cmdReqQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        cmdReqQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdReqQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdReqQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t = cmdRespQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        cmdRespQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t = cmdRespQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        cmdRespQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdRespQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdRespQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end

                    // Simple NIC Ringbuf
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t =simpleNicTxQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        simpleNicTxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t = simpleNicTxQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        simpleNicTxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicTxQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicTxQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t = simpleNicRxQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        simpleNicRxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t = simpleNicRxQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        simpleNicRxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicRxQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicRxQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end

                    default: begin
                        return tagged CsrNodeResultNotMatched;
                    end
                endcase
            end
            else begin
                case (req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM))
                    // QP ring bufs
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbuf.controlRegs.tail)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbuf.controlRegs.tail)))};
                    end

                    //  Cmd Queue ring bufs
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdReqQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdReqQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdReqQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdReqQueueRingbuf.controlRegs.tail)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdRespQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdRespQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdRespQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdRespQueueRingbuf.controlRegs.tail)))};
                    end
                    
                    // Simple NIC Ringbuf
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicTxQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicTxQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicTxQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicTxQueueRingbuf.controlRegs.tail)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicRxQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicRxQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicRxQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicRxQueueRingbuf.controlRegs.tail)))};
                    end
                    default: begin
                        return tagged CsrNodeResultNotMatched;
                    end
                endcase
            end
        endactionvalue
    endfunction
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_TWO), "mkRingbufAndDescriptorHandler");


    interface qpRingbufDmaMasterPipeIfc = qpRingbufDmaIfcConvertor.dmaMasterPipeIfc;
    interface cmdQueueRingbufDmaMasterPipeIfc = cmdQueueRingbufDmaIfcConvertor.dmaMasterPipeIfc;
    interface simpleNicRingbufDmaMasterPipeIfc = simpleNicRingbufDmaIfcConvertor.dmaMasterPipeIfc;
    interface csrUpStreamPort = csrNode.upStreamPort;
    
    interface wqePipeOut = workQueueDescParser.workReqPipeOut;
    interface metaReportDescPipeIn = rqMetaReportRingbuf.descPipeIn;

    interface simpleNicRxDescPipeIn = simpleNicRxQueueRingbuf.descPipeIn;
    interface simpleNicTxDescPipeOut = simpleNicTxQueueRingbuf.descPipeOut;

    interface mrAndPgtManagerClt = cmdQueueDescParserAndDispatcher.mrAndPgtManagerClt;
    interface qpcModifyClt = cmdQueueDescParserAndDispatcher.qpcModifyClt;
    interface setNetworkParamReqPipeOut = cmdQueueDescParserAndDispatcher.setNetworkParamReqPipeOut;
    interface qpResetReqPipeOut = cmdQueueDescParserAndDispatcher.qpResetReqPipeOut;
endmodule


interface QpMrPgtQpc;
    interface BlueRdmaCsrUpStreamPort                                               csrUpStreamPort;

    // DMA interfaces
    interface IoChannelMemoryMasterPipeB0In                                         pgtUpdateDmaMasterPipe;
    interface IoChannelMemoryMasterPipeB0In                                         qpDmaRequestMasterIfc;
    interface IoChannelMemoryMasterPipeB0In                                         simpleNicPacketDmaMasterPipeIfc;

    interface PipeInB0#(WorkQueueElem)                                              wqePipeIn;
    interface PipeOut#(RingbufRawDescriptor)                                        metaReportDescPipeOut;
    interface IoChannelBiDirStreamNoMetaPipeB0In                                    qpEthDataStreamIfc;

    interface PipeOut#(RingbufRawDescriptor)                                        simpleNicRxDescPipeOut;
    interface PipeIn#(RingbufRawDescriptor)                                         simpleNicTxDescPipeIn;

    interface PipeIn#(IndexQP)                                                      qpResetReqPipeIn;
        
    interface ServerP#(WriteReqQPC, Bool)                                           qpContextUpdateSrv;
    interface ServerP#(RingbufRawDescriptor, Bool)                                  mrAndPgtModifyDescSrv;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface



(* synthesize *)
module mkQpMrPgtQpc(QpMrPgtQpc);
    PipeInAdapterB0#(WriteReqQPC) qpContextUpdateReqQueue <- mkPipeInAdapterB0;
    FIFOF#(Bool) qpContextUpdateRespQueue <- mkLFIFOF;

    QpContext qpContext <- mkQpContext;
    MemRegionTableTwoWayQuery mrTable <- mkMemRegionTableTwoWayQuery;
    AddressTranslateTwoWayQuery addrTranslator <- mkAddressTranslateTwoWayQuery;
    MrAndPgtUpdater mrAndPgtUpdater <- mkMrAndPgtUpdater;
    PgtUpdateDmaInterfaceConvertor pgtUpdateDmaInterfaceConvertor <- mkPgtUpdateDmaInterfaceConvertor;
    AutoAckGenerator    autoAckGenerator <- mkAutoAckGenerator;
    SimpleNic simpleNic <- mkSimpleNic;
    CnpPacketGenerator cnpPacketGenerator <- mkCnpPacketGenerator;



    PayloadGenAndCon payloadGenAndCon <- mkPayloadGenAndCon;
    SQ sq <- mkSQ;
    RQ rq <- mkRQ;
    DtldStreamNoMetaArbiterSlave#(NUMERIC_TYPE_TWO, DATA) ethTxStreamArbiter <- mkDtldStreamNoMetaArbiterSlave(valueOf(NUMERIC_TYPE_TWO));
    EthernetPacketGenerator ethernetPacketGen <- mkEthernetPacketGenerator;



    // Connection for ethernet packet generate
    PacketGenReqArbiter packetGenReqArbiter <- mkPacketGenReqArbiter;
    mkConnection(sq.macIpUdpMetaPipeOut, packetGenReqArbiter.macIpUdpMetaPipeInVec[0]);
    mkConnection(sq.rdmaPacketMetaPipeOut, packetGenReqArbiter.rdmaPacketMetaPipeInVec[0]);
    mkConnection(sq.rdmaPayloadPipeOut, packetGenReqArbiter.rdmaPayloadPipeInVec[0]);

    mkConnection(cnpPacketGenerator.macIpUdpMetaPipeOut, packetGenReqArbiter.macIpUdpMetaPipeInVec[1]);
    mkConnection(cnpPacketGenerator.rdmaPacketMetaPipeOut, packetGenReqArbiter.rdmaPacketMetaPipeInVec[1]);
    mkConnection(cnpPacketGenerator.rdmaPayloadPipeOut, packetGenReqArbiter.rdmaPayloadPipeInVec[1]);

    mkConnection(autoAckGenerator.macIpUdpMetaPipeOut, packetGenReqArbiter.macIpUdpMetaPipeInVec[2]);
    mkConnection(autoAckGenerator.rdmaPacketMetaPipeOut, packetGenReqArbiter.rdmaPacketMetaPipeInVec[2]);
    mkConnection(autoAckGenerator.rdmaPayloadPipeOut, packetGenReqArbiter.rdmaPayloadPipeInVec[2]);

    mkConnection(packetGenReqArbiter.macIpUdpMetaPipeOut, ethernetPacketGen.macIpUdpMetaPipeIn);
    mkConnection(packetGenReqArbiter.rdmaPacketMetaPipeOut, ethernetPacketGen.rdmaPacketMetaPipeIn);
    mkConnection(packetGenReqArbiter.rdmaPayloadPipeOut, ethernetPacketGen.rdmaPayloadPipeIn);

    mkConnection(ethernetPacketGen.ethernetPacketPipeOut         , ethTxStreamArbiter.pipeInIfcVec[0]);
    mkConnection(simpleNic.rawEthernetPacketPipeOut         , ethTxStreamArbiter.pipeInIfcVec[1]);



    mkConnection(mrAndPgtUpdater.dmaReadReqPipeOut, pgtUpdateDmaInterfaceConvertor.dmaReadReqPipeIn);   // already Nr
    mkConnection(mrAndPgtUpdater.dmaReadRespPipeIn, pgtUpdateDmaInterfaceConvertor.dmaReadRespPipeOut);    
    mkConnection(mrAndPgtUpdater.mrModifyClt, mrTable.modifySrv);
    mkConnection(mrAndPgtUpdater.pgtModifyClt, addrTranslator.modifySrv);

    
    // Payload gen and con
    mkConnection(sq.payloadGenReqPipeOut, payloadGenAndCon.genReqPipeIn);    // already Nr
    mkConnection(sq.payloadGenRespPipeIn, payloadGenAndCon.payloadGenStreamPipeOut);

    mkConnection(rq.payloadConReqPipeOut, payloadGenAndCon.conReqPipeIn);
    mkConnection(rq.payloadConRespPipeIn, payloadGenAndCon.conRespPipeOut);
    mkConnection(rq.payloadConStreamPipeOut, payloadGenAndCon.payloadConStreamPipeIn);

    // ethernet ifc
    let qpEthDataStreamIfcInst = (
            interface IoChannelBiDirStreamNoMetaPipeB0In
                interface dataPipeIn = rq.ethernetFramePipeIn;
                interface dataPipeOut = ethTxStreamArbiter.pipeOutIfc;
            endinterface
        );


    // QPContext, MR Table and PGT
    mkConnection(rq.qpcQueryClt, qpContext.querySrv);

    // query server channel 0 has higher priority
    mkConnection(rq.mrTableQueryClt, mrTable.querySrvVec[0]);
    mkConnection(sq.mrTableQueryClt, mrTable.querySrvVec[1]);

    // query server channel 0 has higher priority
    mkConnection(payloadGenAndCon.conAddrTranslateClt, addrTranslator.querySrvVec[0]);
    mkConnection(payloadGenAndCon.genAddrTranslateClt, addrTranslator.querySrvVec[1]);
    

    // Simple Nic Packet input
    mkConnection(rq.otherRawPacketPipeOut, simpleNic.rawEthernetPacketPipeIn);

    // auto ack, bitmap report and CNP
    mkConnection(rq.autoAckGenReqPipeOut, autoAckGenerator.reqPipeIn);  // already Nr
    mkConnection(rq.genCnpReqPipeOut, cnpPacketGenerator.genReqPipeIn);  // already Nr

    // meta report descriptors
    DescriptorMux descriptorMux <- mkDescriptorMux;
    mkConnection(rq.metaReportDescPipeOut, descriptorMux.descPipeInVec[0]);  // already Nr
    mkConnection(autoAckGenerator.metaReportDescPipeOut, descriptorMux.descPipeInVec[1]);  // already Nr

    rule deqNotused;
        ethTxStreamArbiter.sourceChannelIdPipeOut.deq;
    endrule


    let qpContextUpdateSrvRequestPipeInB0Adapter <- mkPipeInB0ToPipeIn(qpContext.updateSrv.request, 1);

    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
            let regIdx = req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
            let addrBlockMask = fromInteger(valueOf(CSR_ADDR_ROUTING_MASK_FOR_METRICS_OF_QPMRPGTQPC));
            let maskedAddr = addrBlockMask & regIdx;
            if (fromInteger(valueOf(CSR_ADDR_ROUTING_FOR_METRICS_RQ0)) == maskedAddr) begin
                return tagged CsrNodeResultForward 0;
            end
            else begin
                return tagged CsrNodeResultNotMatched;
            end
        endactionvalue
    endfunction
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_ONE), "mkQpMrPgtQpc");
    mkConnection(rq.csrUpStreamPort, csrNode.downStreamPortsVec[0]);

    rule forwardQpContextUpdateReq;
        let req = qpContextUpdateReqQueue.first;
        qpContextUpdateReqQueue.deq;
        qpContextUpdateSrvRequestPipeInB0Adapter.enq(req);
    endrule
    
    rule forwardQpContextUpdateResp;
        let r1 = qpContext.updateSrv.response.first;
        qpContext.updateSrv.response.deq;
        qpContextUpdateRespQueue.enq(r1);
    endrule

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
        rq.setLocalNetworkSettings(networkSettings);
    endmethod

    interface csrUpStreamPort                   = csrNode.upStreamPort;
    interface pgtUpdateDmaMasterPipe            = pgtUpdateDmaInterfaceConvertor.dmaSidePipeIfc;
    interface wqePipeIn                         = sq.wqePipeIn;
    interface metaReportDescPipeOut             = descriptorMux.descPipeOut;
    interface qpDmaRequestMasterIfc             = payloadGenAndCon.ioChannelMemoryMasterPipeIfc;
    interface qpEthDataStreamIfc                = qpEthDataStreamIfcInst;
    interface qpContextUpdateSrv                = toGPServerP(toPipeInB0(qpContextUpdateReqQueue), toPipeOut(qpContextUpdateRespQueue));

    interface simpleNicRxDescPipeOut            = simpleNic.simpleNicRxDescPipeOut;
    interface simpleNicTxDescPipeIn             = simpleNic.simpleNicTxDescPipeIn;

    interface qpResetReqPipeIn                  = autoAckGenerator.resetReqPipeIn;
    interface mrAndPgtModifyDescSrv             = mrAndPgtUpdater.mrAndPgtModifyDescSrv;

    interface simpleNicPacketDmaMasterPipeIfc   = simpleNic.simpleNicPacketDmaMasterPipeIfc;
endmodule
