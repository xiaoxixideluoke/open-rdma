`timescale 1ps / 1ps
`ifdef BLUE_RDMA_DMA_IP_TYPE_XILINX_XDMA
  `include "top_xdmac.v"
`elsif BLUE_RDMA_DMA_IP_TYPE_XILINX_BLUE_DMAC
  `include "top_xil_bdmac.v"
`endif