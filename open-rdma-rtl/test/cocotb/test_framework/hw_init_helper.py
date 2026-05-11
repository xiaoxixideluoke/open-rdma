import logging
import random
from . import test_case_common as tcc
from .descriptors import MemAccessTypeFlag, RingbufDescCommonHead, CmdQueueRespDescOnlyCommonHeader, PMTU
from .hw_consts import MEM_REGION_PAGE_SIZE, LR_KEY_IDX_PART_WIDTH, LR_KEY_KEY_PART_WIDTH, QPN_IDX_PART_WIDTH, QPN_KEY_PART_WIDTH
from ctypes import c_longlong
from .ringbufs import RingbufCommandReqQueue, RingbufCommandRespQueue, RingbufSendQueue, RingbufMetaReportQueue, RingbufSimpleNicTxQueue, RingbufSimpleNicRxQueue
import cocotb
from cocotb import queue

CARD_A_MAC_ADDRESS = 0xAABBCCDDEE0A
CARD_A_IP_ADDRESS = 0x1122330A

CARD_B_MAC_ADDRESS = 0xAABBCCDDEE0B
CARD_B_IP_ADDRESS = 0x1122330B


def gen_lrkey_from_idx_and_key(idx, key):
    t = (idx << LR_KEY_KEY_PART_WIDTH) | key
    return t


def gen_qpn_from_idx_and_key(idx, key):
    t = (idx << QPN_KEY_PART_WIDTH) | key
    return t


class HardwareTestHelper:
    def __init__(self, pcie_bfm, channel_cnt=1):
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.INFO)

        self.channel_cnt = channel_cnt

        self.pcie_bfm = pcie_bfm
        self.ringbuf_buffer_size = 0x20000

        self.mem_alloc_ptr = 0
        self.total_mem_size = tcc.TOTAL_MEMORY_SIZE

        backmem_start_addr, backmem = self.alloc_physical_memory(
            self.ringbuf_buffer_size, self.ringbuf_buffer_size)
        self.cmd_req_queue = RingbufCommandReqQueue(
            backmem,
            backmem_start_addr,
            self.pcie_bfm
        )
        self.log.info(
            f"create cmd_req_queue, phy addr = {hex(backmem_start_addr)}")

        backmem_start_addr, backmem = self.alloc_physical_memory(
            self.ringbuf_buffer_size, self.ringbuf_buffer_size)
        self.cmd_resp_queue = RingbufCommandRespQueue(
            backmem,
            backmem_start_addr,
            self.pcie_bfm
        )
        self.log.info(
            f"create cmd_resp_queue, phy addr = {hex(backmem_start_addr)}")

        self.send_queues = []
        self.meta_report_queues = []
        self.collected_meta_report_descs_queue = queue.Queue()

        for channel_idx in range(channel_cnt):
            backmem_start_addr, backmem = self.alloc_physical_memory(
                self.ringbuf_buffer_size, self.ringbuf_buffer_size)
            self.send_queues.append(
                RingbufSendQueue(
                    backmem,
                    backmem_start_addr,
                    self.pcie_bfm,
                    channel_idx
                )
            )
            self.log.info(
                f"create send_queue[{channel_idx}], phy addr = {hex(backmem_start_addr)}")

            backmem_start_addr, backmem = self.alloc_physical_memory(
                self.ringbuf_buffer_size, self.ringbuf_buffer_size)
            self.meta_report_queues.append(
                RingbufMetaReportQueue(
                    backmem,
                    backmem_start_addr,
                    self.pcie_bfm,
                    channel_idx
                )
            )
            self.log.info(
                f"create meta_report_queues[{channel_idx}], phy addr = {hex(backmem_start_addr)}")

        backmem_start_addr, backmem = self.alloc_physical_memory(
            self.ringbuf_buffer_size, self.ringbuf_buffer_size)
        self.simple_nix_tx_queue = RingbufSimpleNicTxQueue(
            backmem,
            backmem_start_addr,
            self.pcie_bfm
        )
        backmem_start_addr, backmem = self.alloc_physical_memory(
            self.ringbuf_buffer_size, self.ringbuf_buffer_size)
        self.simple_nix_rx_queue = RingbufSimpleNicRxQueue(
            backmem,
            backmem_start_addr,
            self.pcie_bfm
        )

        self.pgt_offset = 0
        self.mr_idx_now = 0
        self.mr_list = []

        self.qpn_idx_now = 0
        self.qp_list = []

    def alloc_physical_memory(self, size, align):
        self.log.info(
            f"alloc phy mem self.mem_alloc_ptr = {self.mem_alloc_ptr}, size={size}, align={align}")
        tmp_start_ptr = self.mem_alloc_ptr
        if self.mem_alloc_ptr % align != 0:
            tmp_start_ptr += (align - (self.mem_alloc_ptr % align))

        if tmp_start_ptr + size > self.total_mem_size:
            self.log.error("no enough memory to alloc")
            raise Exception("no enough memory to alloc")

        self.mem_alloc_ptr = tmp_start_ptr + size
        return tmp_start_ptr, self.pcie_bfm.mem[tmp_start_ptr: tmp_start_ptr + size]

    async def do_device_init(self):
        await self.cmd_req_queue.init_addr_csr()
        await self.cmd_resp_queue.init_addr_csr()
        await self.simple_nix_tx_queue.init_addr_csr()
        await self.simple_nix_rx_queue.init_addr_csr()
        for idx in range(self.channel_cnt):
            await self.send_queues[idx].init_addr_csr()
            await self.meta_report_queues[idx].init_addr_csr()

        self.log.info("d------------------1")
        self.cmd_req_queue.put_desc_set_udp_param(
            0x00000000,
            0xFFFFFF00,
            CARD_A_IP_ADDRESS,
            CARD_A_MAC_ADDRESS
        )
        await self.cmd_req_queue.sync_pointers()
        self.log.info("d------------------2")
        resp = await self.cmd_resp_queue.deq_blocking_in_descriptor_valid_bit_polling_mode()
        self.log.info("d------------------3")
        self.log.info(f"cmd resp queue got desc: {resp}")

    def alloc_qpn(self):
        qpn_key_part = random.randint(0, 1024)
        new_qpn = gen_qpn_from_idx_and_key(self.qpn_idx_now, qpn_key_part)
        self.qpn_idx_now += 1
        self.qp_list.append(new_qpn)
        return new_qpn

    async def create_qp(self, peer_mac_addr, peer_ip_addr, local_udp_port, self_qpn, peer_qpn,
                        acc_flag=MemAccessTypeFlag.IBV_ACCESS_LOCAL_WRITE | MemAccessTypeFlag.IBV_ACCESS_REMOTE_READ | MemAccessTypeFlag.IBV_ACCESS_REMOTE_WRITE,
                        pmtu=PMTU.IBV_MTU_256):

        self.cmd_req_queue.put_desc_update_qp(
            peer_mac_addr=peer_mac_addr,
            peer_ip_addr=peer_ip_addr,
            local_udp_port=local_udp_port,
            qpn=self_qpn,
            peer_qpn=peer_qpn,
            qp_type=peer_qpn,
            acc_flag=acc_flag,
            pmtu=pmtu,
        )

        await self.cmd_req_queue.sync_pointers()
        resp_raw = await self.cmd_resp_queue.deq_blocking_in_descriptor_valid_bit_polling_mode()
        resp = CmdQueueRespDescOnlyCommonHeader.from_buffer(resp_raw)
        assert resp.cmd_queue_common_header.F_IS_SUCCESS == 1

    async def reg_mr(self, start_addr, length,
                     acc_flag=MemAccessTypeFlag.IBV_ACCESS_LOCAL_WRITE | MemAccessTypeFlag.IBV_ACCESS_REMOTE_READ | MemAccessTypeFlag.IBV_ACCESS_REMOTE_WRITE):

        start_ppn = start_addr // MEM_REGION_PAGE_SIZE
        end_ppn = (start_addr + length) // MEM_REGION_PAGE_SIZE
        total_ppn_cnt = end_ppn - start_ppn + 1
        if total_ppn_cnt > 64:  # for 512 pcie burst transfer
            raise Exception(
                "doesn't support update more than 64 page table entry at once")

        # generate second level PGT entry
        PgtEntries = c_longlong * total_ppn_cnt
        entries = PgtEntries()

        for i in range(len(entries)):
            entries[i] = start_ppn * MEM_REGION_PAGE_SIZE + \
                i * MEM_REGION_PAGE_SIZE

        backmem_start_addr, backmem = self.alloc_physical_memory(
            total_ppn_cnt * 8, 512)

        bytes_to_copy = bytes(entries)
        backmem[:] = bytes_to_copy

        self.cmd_req_queue.put_desc_update_pgt(
            dma_addr=backmem_start_addr,
            zerobased_entry_cnt=total_ppn_cnt-1,
            start_index=self.pgt_offset
        )

        mr_key_part = random.randint(0, 1024)

        mr_key = gen_lrkey_from_idx_and_key(self.mr_idx_now, mr_key_part)
        self.mr_idx_now += 1

        self.cmd_req_queue.put_desc_update_mr_table(
            base_va=start_addr,
            length=length,
            key=mr_key,
            pgt_offset=self.pgt_offset,
            acc_flag=acc_flag)

        self.pgt_offset += total_ppn_cnt

        await self.cmd_req_queue.sync_pointers()

        resp_raw = await self.cmd_resp_queue.deq_blocking_in_descriptor_valid_bit_polling_mode()
        resp = CmdQueueRespDescOnlyCommonHeader.from_buffer(resp_raw)
        assert resp.cmd_queue_common_header.F_IS_SUCCESS == 1

        resp_raw = await self.cmd_resp_queue.deq_blocking_in_descriptor_valid_bit_polling_mode()
        resp = CmdQueueRespDescOnlyCommonHeader.from_buffer(resp_raw)
        assert resp.cmd_queue_common_header.F_IS_SUCCESS == 1

        return mr_key

    async def start_meta_report_queue_collector(self):
        async def _inner_thread():
            while True:
                await cocotb.triggers.Timer(2, "ns")
                for channel_idx in range(self.channel_cnt):
                    desc_raw_maybe = await self.meta_report_queues[channel_idx].try_deq_in_descriptor_valid_bit_polling_mode(
                    )
                    if desc_raw_maybe is None:
                        continue
                    self.collected_meta_report_descs_queue.put_nowait(
                        desc_raw_maybe)
                    desc_common_header = RingbufDescCommonHead.from_buffer(
                        desc_raw_maybe)
                    while desc_common_header.F_HAS_NEXT_FRAG == 1:
                        await cocotb.triggers.Timer(2, "ns")
                        desc_raw_maybe = await self.meta_report_queues[channel_idx].try_deq_in_descriptor_valid_bit_polling_mode(
                        )
                        if desc_raw_maybe is None:
                            continue
                        self.collected_meta_report_descs_queue.put_nowait(
                            desc_raw_maybe)
                        desc_common_header = RingbufDescCommonHead.from_buffer(
                            desc_raw_maybe)
        cocotb.start_soon(_inner_thread())

    async def get_meta_report_from_collected_queue(self):
        return await self.collected_meta_report_descs_queue.get()
