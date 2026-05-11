#!/usr/bin/env python
import itertools
import gc
import logging
import os
import random
import threading

import time

import cocotb_test.simulator
import pytest
from collections import deque

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.clock import Clock
from cocotb.queue import Queue

from test_framework.descriptors import WorkReqOpCode, WorkReqSendFlag, RdmaOpCode, MetaReportQueueAckDesc, MetaReportQueueAckExtraDesc, MetaReportQueuePacketBasicInfoDesc, PMTU
from test_framework.mock_host import UserspaceDriverServer, open_shared_mem_to_hw_simulator
from test_framework.hw_init_helper import HardwareTestHelper, CARD_A_IP_ADDRESS, CARD_A_MAC_ADDRESS

from test_framework import test_case_common as tcc

from test_framework.common import gen_rtl_file_list, copy_mem_file_to_sim_build_dir
from test_framework.eth_bfm import SimpleEthBehaviorModel
from test_framework.pcie_bfm import SimplePcieBehaviorModel
from scapy.layers.inet import IP, UDP
from scapy.layers.l2 import Ether


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.shared_mem = open_shared_mem_to_hw_simulator(
            tcc.TOTAL_MEMORY_SIZE)

        is_test_100g = True
        if is_test_100g:
            channel_cnt = 1
            self.pcie_bfm = SimplePcieBehaviorModel(
                dut,
                ["dmaMasterPipeIfc"],
                ["dmaSlavePipeIfc"],
                self.shared_mem.buf
            )

            self.eth_bfm = SimpleEthBehaviorModel(
                dut,
                ["qpEthDataStreamIfc_dataPipeOut"],
                ["qpEthDataStreamIfc_dataPipeIn"],
            )
        else:
            channel_cnt = 4
            self.pcie_bfm = SimplePcieBehaviorModel(
                dut,
                ["dmaMasterPipeIfcVec_0",
                 "dmaMasterPipeIfcVec_1",
                 "dmaMasterPipeIfcVec_2",
                 "dmaMasterPipeIfcVec_3"],
                [
                    "dmaSlavePipeIfc"
                ],
                self.shared_mem.buf
            )

            self.eth_bfm = SimpleEthBehaviorModel(
                dut,
                [
                    "qpEthDataStreamIfcVec_0_dataPipeOut",
                    "qpEthDataStreamIfcVec_1_dataPipeOut",
                    "qpEthDataStreamIfcVec_2_dataPipeOut",
                    "qpEthDataStreamIfcVec_3_dataPipeOut",
                ],
                [
                    "qpEthDataStreamIfcVec_0_dataPipeIn",
                    # "qpEthDataStreamIfcVec_1_dataPipeIn",
                    # "qpEthDataStreamIfcVec_2_dataPipeIn",
                    # "qpEthDataStreamIfcVec_3_dataPipeIn",
                ],
            )

        self.init_helper: HardwareTestHelper = HardwareTestHelper(
            self.pcie_bfm, channel_cnt)

        self.eth_packet_forward_delay_ns = 0
        self.eth_packet_forward_delay_queue = deque()

    def clean_up(self):
        # need to ensure no reference to shared_mem, if not, the shared memory resource can not be released.
        self.pcie_bfm = None
        shared_mem = self.shared_mem
        self.shared_mem = None
        self.init_helper = None
        gc.collect()
        # shared_mem.close()

    async def put_rx_data(self, packet_data):
        await self.eth_bfm.inject_rx_packet(packet_data)

    async def gen_reset_and_do_hw_init(self):
        self.resetn.value = 0
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.resetn.value = 1
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.log.info("Generated DMA RST_N")

        await self.init_helper.do_device_init()

    async def start_single_card_loop_back(self):

        async def _loop_back_collect_tx_packet(self):
            while True:
                tx_beat = await self.eth_bfm.get_tx_packet()
                self.eth_packet_forward_delay_queue.append(tx_beat)
                self.log.info(
                    f"single_card_loop_back forward beat to delay queue: {tx_beat}")

        async def _loop_back_inject_rx_packet(self):
            while True:
                await Timer(2, units='ns')
                cur_time = cocotb.utils.get_sim_time("ns")
                if cur_time < self.eth_packet_forward_delay_ns:
                    continue
                if len(self.eth_packet_forward_delay_queue) == 0:
                    continue
                tx_beat = self.eth_packet_forward_delay_queue.popleft()
                await self.eth_bfm.inject_rx_packet(tx_beat)
                self.log.info(
                    f"single_card_loop_back inject to rx port: {tx_beat}")

        cocotb.start_soon(_loop_back_collect_tx_packet(self))
        cocotb.start_soon(_loop_back_inject_rx_packet(self))

    '''
    In this test, will send a write only packet with PSN = 256, which will lead the bitmap window overflow.
    The NIC is connected in loopback mode, with two QP.
    The bitmap overflow at recv side will trigger a desc report and an auto ACK packet. When send side recv the ACK packet,
    it should also tirgger a desc report. 
    '''

    async def testcase_send_simple_write_loopback_req(self):

        await self.init_helper.start_meta_report_queue_collector()

        src_buf_mem_addr, src_buf_mem = self.init_helper.alloc_physical_memory(
            1024, 1)
        src_mr_key = await self.init_helper.reg_mr(src_buf_mem_addr, 1024)

        dst_buf_mem_addr, dst_buf_mem = self.init_helper.alloc_physical_memory(
            1024, 1)
        dst_mr_key = await self.init_helper.reg_mr(dst_buf_mem_addr, 1024)

        self.log.info(
            f"src_mr_key={hex(src_mr_key)}, dst_mr_key={hex(dst_mr_key)}")

        src_buf_mem[0] = 0x12
        src_buf_mem[1] = 0x13

        dst_buf_mem[0] = 0xFF
        dst_buf_mem[1] = 0xFF

        self_qpn = self.init_helper.alloc_qpn()
        peer_qpn = self.init_helper.alloc_qpn()

        self.log.info(
            f"create qp: self qpn = {hex(self_qpn)}, peer qpn = {hex(peer_qpn)}")

        # create qp for send side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=self_qpn,
            peer_qpn=peer_qpn,
        )

        # create qp for recv side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=peer_qpn,
            peer_qpn=self_qpn,
        )

        imm_data = random.randint(0, 0xFFFFFFFF)
        msn = random.randint(0, 0xFFF)
        psn = 256

        self.init_helper.send_queues[0].put_work_request(
            opcode=WorkReqOpCode.IBV_WR_RDMA_WRITE_WITH_IMM,
            is_first=True,
            is_last=True,
            is_retry=False,
            enable_ecn=False,
            total_len=1,
            lkey=src_mr_key,
            laddr=src_buf_mem_addr,
            data_len=1,
            r_va=dst_buf_mem_addr,
            r_key=dst_mr_key,
            r_ip=CARD_A_IP_ADDRESS,
            r_mac=CARD_A_MAC_ADDRESS,
            dqpn=peer_qpn,
            sqpn=self_qpn,
            msn=msn,
            psn=psn,
            imm_data=imm_data
        )
        await self.init_helper.send_queues[0].sync_pointers()

        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")

        # check meta report desc for write only packet
        resp = MetaReportQueuePacketBasicInfoDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.RDMA_WRITE_ONLY_WITH_IMMEDIATE
        assert resp.common_header.F_HAS_NEXT_FRAG == 0
        assert resp.F_MSN == msn
        assert resp.F_PSN == psn
        assert resp.F_SOLICITED == 0
        assert resp.F_ACK_REQ == 0
        assert resp.F_IS_RETRY == 0
        assert resp.F_DQPN == peer_qpn
        assert resp.F_TOTAL_LEN == 1
        assert resp.F_RADDR == dst_buf_mem_addr
        assert resp.F_RKEY == dst_mr_key
        assert resp.F_IMM_DATA == imm_data

        # check memory access is correct
        # since meta report DMA path is simplier than payload write DMA path, desc may arrive before payload has been written to memory.
        # currently, we think the driver handle the descriptor need some time, when the software is notified by the driver, the payload
        # should already been written to memory. If this is not the real case, then we must modify the hardware to provide addtional
        # write finish signal. Or delay the desc report on hardware.
        await Timer(4, units='ns')
        assert dst_buf_mem[0] == 0x12  # should be modified
        assert dst_buf_mem[1] == 0xFF  # should not be modified

        # check meta report desc for ACK packet generated at recv side
        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        resp = MetaReportQueueAckDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        assert resp.common_header.F_HAS_NEXT_FRAG == 1
        assert resp.F_IS_SEND_BY_LOCAL_HW == 1
        assert resp.F_IS_SEND_BY_DRIVER == 0
        assert resp.F_IS_WINDOW_SLIDED == 1
        assert resp.F_IS_PACKET_LOST == 1
        assert resp.F_PSN_BEFORE_SLIDE == 0xFFFFF0
        assert resp.get_psn_now() == psn
        assert resp.get_qpn() == peer_qpn
        assert resp.get_msn() == 0
        assert resp.F_NOW_BITMAP_LOW == 0
        assert resp.F_NOW_BITMAP_HIGH == 0x00010000_00000000

        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        resp = MetaReportQueueAckExtraDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        assert resp.common_header.F_HAS_NEXT_FRAG == 0
        assert resp.F_PRE_BITMAP_LOW == 0xFFFFFFFF_FFFFFFFF
        assert resp.F_PRE_BITMAP_HIGH == 0xFFFFFFFF_FFFFFFFF

        # check meta report desc for ACK packet generated at send side
        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        resp = MetaReportQueueAckDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        assert resp.common_header.F_HAS_NEXT_FRAG == 1
        # Note: this line is the difference from the recv side
        assert resp.F_IS_SEND_BY_LOCAL_HW == 0
        assert resp.F_IS_SEND_BY_DRIVER == 0
        assert resp.F_IS_WINDOW_SLIDED == 1
        assert resp.F_IS_PACKET_LOST == 1
        assert resp.F_PSN_BEFORE_SLIDE == 0xFFFFF0
        assert resp.get_psn_now() == psn
        assert resp.get_qpn() == self_qpn
        assert resp.get_msn() == 0
        assert resp.F_NOW_BITMAP_LOW == 0
        assert resp.F_NOW_BITMAP_HIGH == 0x00010000_00000000

        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        resp = MetaReportQueueAckExtraDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        assert resp.common_header.F_HAS_NEXT_FRAG == 0
        assert resp.F_PRE_BITMAP_LOW == 0xFFFFFFFF_FFFFFFFF
        assert resp.F_PRE_BITMAP_HIGH == 0xFFFFFFFF_FFFFFFFF

        metrics_csr_val = await self.pcie_bfm.host_read_blocking((
            0x0100+0x0020+0x0002) * 4)
        self.log.debug(f"read metrics: {metrics_csr_val}")

    async def testcase_send_simple_write_loopback_req_8191(self):

        await self.init_helper.start_meta_report_queue_collector()

        src_buf_mem_addr, src_buf_mem = self.init_helper.alloc_physical_memory(
            65536*4, 4096)
        src_mr_key = await self.init_helper.reg_mr(src_buf_mem_addr, 65536 * 4)

        dst_buf_mem_addr, dst_buf_mem = self.init_helper.alloc_physical_memory(
            65536*4, 4096)
        dst_mr_key = await self.init_helper.reg_mr(dst_buf_mem_addr, 65536 * 4)

        self.log.info(
            f"addr before random: src_buf_mem_addr={hex(src_buf_mem_addr)}, dst_buf_mem_addr={hex(dst_buf_mem_addr)}")

        src_addr_offset = random.randint(0, 15)
        dst_addr_offset = random.randint(0, 15)

        write_src_addr = src_buf_mem_addr + src_addr_offset
        write_dst_addr = dst_buf_mem_addr + dst_addr_offset
        write_len = 65536 * 2

        for d in range(65536*4):
            src_buf_mem[d] = d % 256
            dst_buf_mem[d] = 0xFF

        self_qpn = self.init_helper.alloc_qpn()
        peer_qpn = self.init_helper.alloc_qpn()

        self.log.info(
            f"create qp: self qpn = {hex(self_qpn)}, peer qpn = {hex(peer_qpn)}")
        self.log.info(
            f"src_buf_mem_addr={hex(src_buf_mem_addr)}, dst_buf_mem_addr={hex(dst_buf_mem_addr)}")

        pmtu = PMTU.IBV_MTU_1024
        # create qp for send side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=self_qpn,
            peer_qpn=peer_qpn,
            pmtu=pmtu
        )

        # create qp for recv side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=peer_qpn,
            peer_qpn=self_qpn,
            pmtu=pmtu
        )

        imm_data = random.randint(0, 0xFFFFFFFF)
        msn = random.randint(0, 0xFFF)
        psn = 256

        self.init_helper.send_queues[0].put_work_request(
            opcode=WorkReqOpCode.IBV_WR_RDMA_WRITE_WITH_IMM,
            is_first=True,
            is_last=True,
            is_retry=False,
            enable_ecn=False,
            total_len=write_len,
            lkey=src_mr_key,
            laddr=write_src_addr,
            data_len=write_len,
            r_va=write_dst_addr,
            r_key=dst_mr_key,
            r_ip=CARD_A_IP_ADDRESS,
            r_mac=CARD_A_MAC_ADDRESS,
            dqpn=peer_qpn,
            sqpn=self_qpn,
            msn=msn,
            psn=psn,
            imm_data=imm_data,
            pmtu=pmtu,
            send_flag=WorkReqSendFlag.IBV_SEND_SIGNALED | WorkReqSendFlag.IBV_SEND_SOLICITED
        )
        await self.init_helper.send_queues[0].sync_pointers()

        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()

        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")

        # check meta report desc for write only packet
        resp = MetaReportQueuePacketBasicInfoDesc.from_buffer(resp_raw)
        # assert resp.common_header.F_OP_CODE == RdmaOpCode.RDMA_WRITE_FIRST
        # assert resp.common_header.F_HAS_NEXT_FRAG == 0
        # assert resp.F_MSN == msn
        # assert resp.F_PSN == psn
        # assert resp.F_SOLICITED == 0
        # assert resp.F_ACK_REQ == 0
        # assert resp.F_IS_RETRY == 0
        # assert resp.F_DQPN == peer_qpn
        # assert resp.F_TOTAL_LEN == 1
        # assert resp.F_RADDR == dst_buf_mem_addr
        # assert resp.F_RKEY == dst_mr_key
        # assert resp.F_IMM_DATA == imm_data

        # check memory access is correct
        # since meta report DMA path is simplier than payload write DMA path, desc may arrive before payload has been written to memory.
        # currently, we think the driver handle the descriptor need some time, when the software is notified by the driver, the payload
        # should already been written to memory. If this is not the real case, then we must modify the hardware to provide addtional
        # write finish signal. Or delay the desc report on hardware.
        await Timer(8000, units='ns')

        for d in range(write_len):
            expected_data = src_buf_mem[d+src_addr_offset]
            got_data = dst_buf_mem[d+dst_addr_offset]
            if expected_data != got_data:
                self.log.info(
                    f"checking at idx = {d}, src addr={hex(d+write_src_addr)}, dst addr={hex(d+write_dst_addr)}, expected_data={hex(expected_data)}, got_data={hex(got_data)}")
            assert expected_data == got_data  # should be modified
        for d in range(dst_addr_offset):
            assert dst_buf_mem[d] == 0xFF  # should not be modified
        for d in range(dst_addr_offset+write_len, 65536*4):
            assert dst_buf_mem[d] == 0xFF  # should not be modified

        # # check meta report desc for ACK packet generated at recv side
        # resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        # self.log.debug(
        #     f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        # resp = MetaReportQueueAckDesc.from_buffer(resp_raw)
        # assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        # assert resp.common_header.F_HAS_NEXT_FRAG == 1
        # assert resp.F_IS_SEND_BY_LOCAL_HW == 1
        # assert resp.F_IS_SEND_BY_DRIVER == 0
        # assert resp.F_IS_WINDOW_SLIDED == 1
        # assert resp.F_IS_PACKET_LOST == 1
        # assert resp.F_PSN_BEFORE_SLIDE == 0xFFFFF0
        # assert resp.get_psn_now() == psn
        # assert resp.get_qpn() == peer_qpn
        # assert resp.get_msn() == 0
        # assert resp.F_NOW_BITMAP_LOW == 0
        # assert resp.F_NOW_BITMAP_HIGH == 0x00010000_00000000

        # resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        # self.log.debug(
        #     f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        # resp = MetaReportQueueAckExtraDesc.from_buffer(resp_raw)
        # assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        # assert resp.common_header.F_HAS_NEXT_FRAG == 0
        # assert resp.F_PRE_BITMAP_LOW == 0xFFFFFFFF_FFFFFFFF
        # assert resp.F_PRE_BITMAP_HIGH == 0xFFFFFFFF_FFFFFFFF

        # # check meta report desc for ACK packet generated at send side
        # resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        # self.log.debug(
        #     f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        # resp = MetaReportQueueAckDesc.from_buffer(resp_raw)
        # assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        # assert resp.common_header.F_HAS_NEXT_FRAG == 1
        # # Note: this line is the difference from the recv side
        # assert resp.F_IS_SEND_BY_LOCAL_HW == 0
        # assert resp.F_IS_SEND_BY_DRIVER == 0
        # assert resp.F_IS_WINDOW_SLIDED == 1
        # assert resp.F_IS_PACKET_LOST == 1
        # assert resp.F_PSN_BEFORE_SLIDE == 0xFFFFF0
        # assert resp.get_psn_now() == psn
        # assert resp.get_qpn() == self_qpn
        # assert resp.get_msn() == 0
        # assert resp.F_NOW_BITMAP_LOW == 0
        # assert resp.F_NOW_BITMAP_HIGH == 0x00010000_00000000

        # resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        # self.log.debug(
        #     f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        # resp = MetaReportQueueAckExtraDesc.from_buffer(resp_raw)
        # assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        # assert resp.common_header.F_HAS_NEXT_FRAG == 0
        # assert resp.F_PRE_BITMAP_LOW == 0xFFFFFFFF_FFFFFFFF
        # assert resp.F_PRE_BITMAP_HIGH == 0xFFFFFFFF_FFFFFFFF

        # metrics_csr_val = await self.pcie_bfm.host_read_blocking((
        #     0x0100+0x0020+0x0002) * 4)
        # self.log.debug(f"read metrics: {metrics_csr_val}")

    async def testcase_send_multi_small_packet_to_test_fully_pipeline(self):

        await self.init_helper.start_meta_report_queue_collector()

        src_buf_mem_addr, src_buf_mem = self.init_helper.alloc_physical_memory(
            65536, 4096)
        src_mr_key = await self.init_helper.reg_mr(src_buf_mem_addr, 65536)

        dst_buf_mem_addr, dst_buf_mem = self.init_helper.alloc_physical_memory(
            65536, 4096)
        dst_mr_key = await self.init_helper.reg_mr(dst_buf_mem_addr, 65536)

        self.log.info(
            f"addr before random: src_buf_mem_addr={hex(src_buf_mem_addr)}, dst_buf_mem_addr={hex(dst_buf_mem_addr)}")

        self.log.info(
            f"src_mr_key={hex(src_mr_key)}, dst_mr_key={hex(dst_mr_key)}")

        src_addr_offset = random.randint(0, 15)
        dst_addr_offset = random.randint(0, 15)
        write_src_addr_start = src_buf_mem_addr + src_addr_offset
        write_dst_addr_start = dst_buf_mem_addr + dst_addr_offset
        write_src_addr = write_src_addr_start
        write_dst_addr = write_dst_addr_start

        # this var controls the total write request cnt. with the signle_msg_len set to 1, we can make the worst case (the control is the most busy one), and to check if fully-pipeline is achieved.
        write_len = 512
        signle_msg_len = 1

        for d in range(65536):
            src_buf_mem[d] = d % 256
            dst_buf_mem[d] = 0xFF

        self_qpn = self.init_helper.alloc_qpn()
        peer_qpn = self.init_helper.alloc_qpn()

        self.log.info(
            f"create qp: self qpn = {hex(self_qpn)}, peer qpn = {hex(peer_qpn)}")
        self.log.info(
            f"src_buf_mem_addr={hex(src_buf_mem_addr)}, dst_buf_mem_addr={hex(dst_buf_mem_addr)}")

        pmtu = PMTU.IBV_MTU_1024
        # create qp for send side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=self_qpn,
            peer_qpn=peer_qpn,
            pmtu=pmtu
        )

        # create qp for recv side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=peer_qpn,
            peer_qpn=self_qpn,
            pmtu=pmtu
        )

        imm_data = random.randint(0, 0xFFFFFFFF)
        msn = random.randint(0, 0xFFF)
        psn = 256

        written_len = 0
        while written_len != write_len:
            self.init_helper.send_queues[0].put_work_request(
                opcode=WorkReqOpCode.IBV_WR_RDMA_WRITE_WITH_IMM,
                is_first=True,
                is_last=True,
                is_retry=False,
                enable_ecn=False,
                total_len=signle_msg_len,
                lkey=src_mr_key,
                laddr=write_src_addr,
                data_len=signle_msg_len,
                r_va=write_dst_addr,
                r_key=dst_mr_key,
                r_ip=CARD_A_IP_ADDRESS,
                r_mac=CARD_A_MAC_ADDRESS,
                dqpn=peer_qpn,
                sqpn=self_qpn,
                msn=msn,
                psn=psn,
                imm_data=imm_data,
                pmtu=pmtu
            )
            self.log.info(
                f"put wqe, src addr = {hex(write_src_addr)}, dst addr = {hex(write_dst_addr)}, len={hex(signle_msg_len)}")
            written_len += signle_msg_len
            write_src_addr += signle_msg_len
            write_dst_addr += signle_msg_len
            msn += 1
            psn += 1
        await self.init_helper.send_queues[0].sync_pointers()

        # check memory access is correct
        # since meta report DMA path is simplier than payload write DMA path, desc may arrive before payload has been written to memory.
        # currently, we think the driver handle the descriptor need some time, when the software is notified by the driver, the payload
        # should already been written to memory. If this is not the real case, then we must modify the hardware to provide addtional
        # write finish signal. Or delay the desc report on hardware.
        await Timer(7000, units='ns')

        for d in range(write_len):
            expected_data = src_buf_mem[d+src_addr_offset]
            got_data = dst_buf_mem[d+dst_addr_offset]
            if expected_data != got_data:
                self.log.info(
                    f"checking at idx = {d}, src addr={hex(d+write_src_addr_start)}, dst addr={hex(d+write_dst_addr_start)}, expected_data={hex(expected_data)}, got_data={hex(got_data)}")
            assert expected_data == got_data  # should be modified
        for d in range(dst_addr_offset):
            assert dst_buf_mem[d] == 0xFF  # should not be modified
        for d in range(dst_addr_offset+write_len, 65536):
            assert dst_buf_mem[d] == 0xFF  # should not be modified

    async def testcase_simple_nic_loop_back(self):
        self.init_helper.simple_nix_tx_queue.put_tx_request(1000, 0)
        await self.init_helper.simple_nix_tx_queue.sync_pointers()


@ cocotb.test(timeout_time=1100000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)

    await cocotb.start(Clock(tb.clock, 2, "ns").start())

    await tb.gen_reset_and_do_hw_init()

    await tb.start_single_card_loop_back()

    await Timer(2048, units='ns')  # wait bram init finish

    # await tb.testcase_send_simple_write_loopback_req()
    await tb.testcase_send_simple_write_loopback_req_8191()
    # await tb.testcase_send_multi_small_packet_to_test_fully_pipeline()
    # await tb.testcase_simple_nic_loop_back()

    await Timer(10, units='ns')
    tb.clean_up()


def test_top_without_hard_ip():
    rtl_dirs = os.getenv("COCOTB_VERILOG_DIR") or ""
    dut = os.getenv("COCOTB_DUT") or ""
    tests_dir = os.path.dirname(__file__)
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = gen_rtl_file_list(rtl_dirs)

    sim_build = os.path.join(tests_dir, "sim_build", dut)
    copy_mem_file_to_sim_build_dir(rtl_dirs, sim_build)

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        timescale="1ns/1ps",
        sim_build=sim_build,
        waves=True,
        plus_args=["+fully-pipeline-check"]
    )


if __name__ == "__main__":
    test_top_without_hard_ip()
