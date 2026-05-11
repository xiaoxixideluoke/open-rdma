import copy
import time
import logging

from .descriptors import *
from .hw_consts import *

import cocotb


class Ringbuf:
    def __init__(self, backend_mem, pcie_bfm, buffer_addr, is_h2c, head_csr_addr, tail_csr_addr, mem_addr_high_csr_addr, mem_addr_low_csr_addr, desc_size=32, ringbuf_len=65536) -> None:
        if not is_power_of_2(desc_size):
            raise Exception("desc_size must be power of 2")
        if not is_power_of_2(ringbuf_len):
            raise Exception("ringbuf_len must be power of 2")

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.INFO)

        self.backend_mem = backend_mem
        self.buffer_addr = buffer_addr
        self.mem_addr_low_csr_addr = mem_addr_low_csr_addr
        self.mem_addr_high_csr_addr = mem_addr_high_csr_addr
        self.head = 0
        self.tail = 0
        self.desc_size = desc_size
        self.ringbuf_len = ringbuf_len
        self.ringbuf_idx_mask = ringbuf_len - 1
        self.pcie_bfm = pcie_bfm
        self.is_h2c = is_h2c
        self.head_csr_addr = head_csr_addr
        self.tail_csr_addr = tail_csr_addr

    async def init_addr_csr(self):
        await self.pcie_bfm.host_write_blocking(
            self.mem_addr_low_csr_addr, self.buffer_addr & 0xFFFFFFFF)
        await self.pcie_bfm.host_write_blocking(
            self.mem_addr_high_csr_addr, self.buffer_addr >> 32)

    async def sync_pointers(self):

        if (self.is_h2c):
            await self.pcie_bfm.host_write_blocking(self.head_csr_addr, self.head)
            new_tail = await self.pcie_bfm.host_read_blocking(self.tail_csr_addr)
            self.set_tail_pointer_with_guard_bit(new_tail)
        else:
            await self.pcie_bfm.host_write_blocking(self.tail_csr_addr, self.tail)
            new_head = await self.pcie_bfm.host_read_blocking(self.head_csr_addr)
            self.set_head_pointer_with_guard_bit(new_head)

    def is_full(self):
        is_guard_bit_same = (
            self.head ^ self.tail) & self.ringbuf_len != self.ringbuf_len

        head_idx = self.head & self.ringbuf_idx_mask
        tail_idx = self.tail & self.ringbuf_idx_mask
        return (head_idx == tail_idx) and (not is_guard_bit_same)

    def is_empty(self):
        is_guard_bit_same = (
            self.head ^ self.tail) & self.ringbuf_len != self.ringbuf_len

        head_idx = self.head & self.ringbuf_idx_mask
        tail_idx = self.tail & self.ringbuf_idx_mask
        return (head_idx == tail_idx) and (is_guard_bit_same)

    def set_head_pointer_with_guard_bit(self, head):
        self.head = head

    def set_tail_pointer_with_guard_bit(self, tail):
        self.tail = tail

    def enq(self, element):
        if self.is_full():
            raise Exception("Ringbuf Full")

        raw_element = bytes(element)
        if len(raw_element) != self.desc_size:
            raise Exception("Descriptor size is not ",
                            self.desc_size, "got size = ", len(raw_element))

        head_idx = self.head & self.ringbuf_idx_mask
        self.head += 1
        write_start_addr = head_idx * self.desc_size

        self.backend_mem[write_start_addr: write_start_addr +
                         self.desc_size] = raw_element

    def deq(self):
        if self.is_empty():
            raise Exception("Ringbuf Empty")
        tail_idx = self.tail & self.ringbuf_idx_mask
        self.tail += 1
        read_start_addr = tail_idx * self.desc_size
        raw_element = self.backend_mem[read_start_addr: read_start_addr +
                                       self.desc_size]

        return raw_element

    async def deq_blocking(self):
        while self.is_empty():
            await self.sync_pointers()
            await cocotb.triggers.Timer(2, "ns")
        return self.deq()

    def force_peek_element_at_tail(self):
        tail_idx = self.tail & self.ringbuf_idx_mask
        read_start_addr = tail_idx * self.desc_size
        raw_element = self.backend_mem[read_start_addr: read_start_addr +
                                       self.desc_size]
        # self.log.debug(
        #     f"tail_idx = {tail_idx}, read_start_addr={read_start_addr}, buffer_addr={hex(self.buffer_addr)}")
        return raw_element

    async def try_deq_in_descriptor_valid_bit_polling_mode(self):
        resp_raw = memoryview(bytearray(self.force_peek_element_at_tail()))
        desc = RingbufDescCommonHead.from_buffer(resp_raw)
        if desc.F_VALID == 0:
            return None

        tail_idx = self.tail & self.ringbuf_idx_mask
        write_start_addr = tail_idx * self.desc_size
        # only clear CmdQueueRespDescOnlyCommonHeader, two bytes to write
        self.backend_mem[write_start_addr: write_start_addr + 2] = b'\x00\x00'
        self.tail += 1
        return resp_raw

    async def deq_blocking_in_descriptor_valid_bit_polling_mode(self):
        while True:
            resp_raw = await self.try_deq_in_descriptor_valid_bit_polling_mode()
            if resp_raw is None:
                await cocotb.triggers.Timer(2, "ns")
                continue
            return resp_raw


class RingbufCommandReqQueue:
    def __init__(self, backend_mem, addr, pcie_bfm) -> None:
        self.rb = Ringbuf(
            backend_mem=backend_mem,
            buffer_addr=addr,
            pcie_bfm=pcie_bfm,
            is_h2c=True,
            mem_addr_high_csr_addr=CSR_ADDR_CMD_REQ_QUEUE_ADDR_HIGH,
            mem_addr_low_csr_addr=CSR_ADDR_CMD_REQ_QUEUE_ADDR_LOW,
            head_csr_addr=CSR_ADDR_CMD_REQ_QUEUE_HEAD,
            tail_csr_addr=CSR_ADDR_CMD_REQ_QUEUE_TAIL)
        self.pcie_bfm = pcie_bfm

    async def sync_pointers(self):
        await self.rb.sync_pointers()

    async def init_addr_csr(self):
        await self.rb.init_addr_csr()

    def put_desc_update_mr_table(self, base_va, length, key, pgt_offset, acc_flag, user_data=0):
        common_header = RingbufDescCommonHead(
            F_OP_CODE=CmdQueueDescOperators.F_OPCODE_CMDQ_UPDATE_MR_TABLE,
            F_IS_EXTEND_OP_CODE=0,
            F_HAS_NEXT_FRAG=0,
            F_VALID=1,
        )
        cmd_queue_common_header = RingbufDescCmdQueueCommonHead(
            F_USER_DATA=user_data,
            F_IS_SUCCESS=0,
        )

        obj = CmdQueueDescUpdateMrTable(
            common_header=common_header,
            cmd_queue_common_header=cmd_queue_common_header,
            F_MR_TABLE_MR_BASE_VA=base_va,
            F_MR_TABLE_MR_LENGTH=length,
            F_MR_TABLE_MR_KEY=key,
            F_MR_TABLE_ACC_FLAGS=acc_flag,
            F_MR_TABLE_PGT_OFFSET=pgt_offset,
        )
        self.rb.enq(obj)

    def put_desc_update_pgt(self, dma_addr, zerobased_entry_cnt, start_index, user_data=0):
        common_header = RingbufDescCommonHead(
            F_OP_CODE=CmdQueueDescOperators.F_OPCODE_CMDQ_UPDATE_PGT,
            F_IS_EXTEND_OP_CODE=0,
            F_HAS_NEXT_FRAG=0,
            F_VALID=1,
        )
        cmd_queue_common_header = RingbufDescCmdQueueCommonHead(
            F_USER_DATA=user_data,
            F_IS_SUCCESS=0,
        )
        obj = CmdQueueDescUpdatePGT(
            common_header=common_header,
            cmd_queue_common_header=cmd_queue_common_header,
            F_PGT_DMA_ADDR=dma_addr,
            F_PGT_START_INDEX=start_index,
            F_PGT_ZERO_BASED_ENTRY_CNT=zerobased_entry_cnt,
        )
        self.rb.enq(obj)

    def put_desc_update_qp(self, peer_mac_addr, peer_ip_addr, local_udp_port, qpn, peer_qpn, qp_type, acc_flag, pmtu, user_data=0):
        common_header = RingbufDescCommonHead(
            F_OP_CODE=CmdQueueDescOperators.F_OPCODE_CMDQ_MANAGE_QP,
            F_IS_EXTEND_OP_CODE=0,
            F_HAS_NEXT_FRAG=0,
            F_VALID=1,
        )
        cmd_queue_common_header = RingbufDescCmdQueueCommonHead(
            F_USER_DATA=user_data,
            F_IS_SUCCESS=0,
        )
        obj = CmdQueueDescQpManagement(
            common_header=common_header,
            cmd_queue_common_header=cmd_queue_common_header,
            F_QP_ADMIN_PEER_IP_ADDR=peer_ip_addr,
            F_QP_ADMIN_IS_VALID=True,
            F_QP_ADMIN_IS_ERROR=False,
            F_QP_ADMIN_QPN=qpn,
            F_QP_PEER_QPN=peer_qpn,
            F_QP_ADMIN_ACCESS_FLAG=acc_flag,
            F_QP_ADMIN_QP_TYPE=qp_type,
            F_QP_ADMIN_PMTU=pmtu,
            F_QP_ADMIN_LOCAL_UDP_PORT=local_udp_port,
            F_QP_ADMIN_PEER_MAC_ADDR=peer_mac_addr,
        )
        self.rb.enq(obj)

    def put_desc_set_udp_param(self, gateway, netmask, ip_addr, mac_addr, user_data=0):
        common_header = RingbufDescCommonHead(
            F_OP_CODE=CmdQueueDescOperators.F_OPCODE_CMDQ_SET_NETWORK_PARAM,
            F_IS_EXTEND_OP_CODE=0,
            F_HAS_NEXT_FRAG=0,
            F_VALID=1,
        )
        cmd_queue_common_header = RingbufDescCmdQueueCommonHead(
            F_USER_DATA=user_data,
            F_IS_SUCCESS=0,
        )
        obj = CmdQueueDescSetNetworkParam(
            common_header=common_header,
            cmd_queue_common_header=cmd_queue_common_header,
            F_NET_PARAM_GATEWAY=gateway,
            F_NET_PARAM_NETMASK=netmask,
            F_NET_PARAM_IPADDR=ip_addr,
            F_NET_PARAM_MACADDR=mac_addr,
        )
        self.rb.enq(obj)

    def put_desc_set_raw_packet_receive_meta(self, base_addr, user_data=0):
        common_header = RingbufDescCommonHead(
            F_OP_CODE=CmdQueueDescOperators.F_OPCODE_CMDQ_SET_RAW_PACKET_RECEIVE_META,
            F_IS_EXTEND_OP_CODE=0,
            F_HAS_NEXT_FRAG=0,
            F_VALID=1,
        )
        cmd_queue_common_header = RingbufDescCmdQueueCommonHead(
            F_USER_DATA=user_data,
            F_IS_SUCCESS=0,
        )
        obj = CmdQueueDescSetRawPacketReceiveMeta(
            common_header=common_header,
            cmd_queue_common_header=cmd_queue_common_header,
            F_RAW_PACKET_META_BASE_ADDR=base_addr,
        )
        self.rb.enq(obj)


class RingbufCommandRespQueue:
    def __init__(self, backend_mem, addr, pcie_bfm) -> None:
        self.rb = Ringbuf(
            backend_mem=backend_mem,
            buffer_addr=addr,
            pcie_bfm=pcie_bfm,
            is_h2c=False,
            mem_addr_high_csr_addr=CSR_ADDR_CMD_RESP_QUEUE_ADDR_HIGH,
            mem_addr_low_csr_addr=CSR_ADDR_CMD_RESP_QUEUE_ADDR_LOW,
            head_csr_addr=CSR_ADDR_CMD_RESP_QUEUE_HEAD,
            tail_csr_addr=CSR_ADDR_CMD_RESP_QUEUE_TAIL)
        self.pcie_bfm = pcie_bfm

    async def sync_pointers(self):
        await self.rb.sync_pointers()

    async def init_addr_csr(self):
        await self.rb.init_addr_csr()

    def deq(self):
        return self.rb.deq()

    async def deq_blocking(self):
        return await self.rb.deq_blocking()

    async def deq_blocking_in_descriptor_valid_bit_polling_mode(self):
        return await self.rb.deq_blocking_in_descriptor_valid_bit_polling_mode()


class RingbufSendQueue:
    def __init__(self, backend_mem, addr, pcie_bfm, channel_idx) -> None:

        self.rb = Ringbuf(
            backend_mem=backend_mem,
            buffer_addr=addr,
            pcie_bfm=pcie_bfm,
            is_h2c=True,
            mem_addr_high_csr_addr=CSR_ADDR_SEND_QUEUE_ADDR_HIGH+channel_idx * 64,
            mem_addr_low_csr_addr=CSR_ADDR_SEND_QUEUE_ADDR_LOW+channel_idx * 64,
            head_csr_addr=CSR_ADDR_SEND_QUEUE_HEAD+channel_idx * 64,
            tail_csr_addr=CSR_ADDR_SEND_QUEUE_TAIL+channel_idx * 64)
        self.pcie_bfm = pcie_bfm

    async def sync_pointers(self):
        await self.rb.sync_pointers()

    async def init_addr_csr(self):
        await self.rb.init_addr_csr()

    def put_work_request(self, opcode, is_first, is_last, is_retry, enable_ecn, total_len, lkey, laddr, data_len, r_va, r_key, r_ip, r_mac, dqpn, sqpn, msn, psn, qp_type=TypeQP.IBV_QPT_RC, pmtu=PMTU.IBV_MTU_256, send_flag=WorkReqSendFlag.IBV_SEND_NO_FLAGS, imm_data=0):

        common_header = RingbufDescCommonHead(
            F_OP_CODE=opcode,
            F_IS_EXTEND_OP_CODE=0,
            F_HAS_NEXT_FRAG=1,
            F_VALID=1,
        )

        obj = SendQueueReqDescSeg0(
            common_header=common_header,
            F_MSN=msn,
            F_TOTAL_LEN=total_len,
            F_RKEY=r_key,
            F_R_ADDR=r_va,
            F_DST_IP=r_ip,
            F_PSN=psn,
            F_QP_TYPE=qp_type,
            F_DQPN=dqpn,
            F_FLAGS=send_flag,
        )
        self.rb.enq(obj)

        common_header = RingbufDescCommonHead(
            F_OP_CODE=opcode,
            F_IS_EXTEND_OP_CODE=0,
            F_HAS_NEXT_FRAG=0,
            F_VALID=1,
        )
        obj = SendQueueReqDescSeg1(
            common_header=common_header,
            F_PMTU=pmtu,
            F_IS_FIRST=is_first,
            F_IS_LAST=is_last,
            F_IS_RETRY=is_retry,
            F_ENABLE_ECN=enable_ecn,
            F_SQPN_LOW_8_BITS=sqpn & 0xFF,
            F_IMM=imm_data,
            F_MAC_ADDR=r_mac,
            F_SQPN_HIGH_16_BITS=sqpn >> 8,
            F_LKEY=lkey,
            F_LEN=data_len,
            F_LADDR=laddr,
        )
        self.rb.enq(obj)


class RingbufMetaReportQueue:
    def __init__(self, backend_mem, addr, pcie_bfm, channel_idx) -> None:
        self.rb = Ringbuf(
            backend_mem=backend_mem,
            buffer_addr=addr,
            pcie_bfm=pcie_bfm,
            is_h2c=False,
            mem_addr_high_csr_addr=CSR_ADDR_META_REPORT_QUEUE_ADDR_HIGH+channel_idx * 64,
            mem_addr_low_csr_addr=CSR_ADDR_META_REPORT_QUEUE_ADDR_LOW+channel_idx * 64,
            head_csr_addr=CSR_ADDR_META_REPORT_QUEUE_HEAD+channel_idx * 64,
            tail_csr_addr=CSR_ADDR_META_REPORT_QUEUE_TAIL+channel_idx * 64)
        self.pcie_bfm = pcie_bfm

    async def sync_pointers(self):
        await self.rb.sync_pointers()

    async def init_addr_csr(self):
        await self.rb.init_addr_csr()

    def deq(self):
        return self.rb.deq()

    def deq_blocking(self):
        return self.rb.deq_blocking()

    async def try_deq_in_descriptor_valid_bit_polling_mode(self):
        return await self.rb.try_deq_in_descriptor_valid_bit_polling_mode()

    async def deq_blocking_in_descriptor_valid_bit_polling_mode(self):
        return await self.rb.deq_blocking_in_descriptor_valid_bit_polling_mode()


class RingbufSimpleNicTxQueue:
    def __init__(self, backend_mem, addr, pcie_bfm) -> None:

        self.rb = Ringbuf(
            backend_mem=backend_mem,
            buffer_addr=addr,
            pcie_bfm=pcie_bfm,
            is_h2c=True,
            mem_addr_high_csr_addr=CSR_ADDR_SIMPLE_NIX_TX_QUEUE_ADDR_HIGH,
            mem_addr_low_csr_addr=CSR_ADDR_SIMPLE_NIX_TX_QUEUE_ADDR_LOW,
            head_csr_addr=CSR_ADDR_SIMPLE_NIX_TX_QUEUE_HEAD,
            tail_csr_addr=CSR_ADDR_SIMPLE_NIX_TX_QUEUE_TAIL)
        self.pcie_bfm = pcie_bfm

    async def sync_pointers(self):
        await self.rb.sync_pointers()

    async def init_addr_csr(self):
        await self.rb.init_addr_csr()

    def put_tx_request(self, len, addr):

        common_header = RingbufDescCommonHead(
            F_OP_CODE=0,
            F_IS_EXTEND_OP_CODE=1,
            F_HAS_NEXT_FRAG=0,
            F_VALID=1,
        )

        obj = SimpleNicTxQueueDesc(
            common_header=common_header,
            F_LEN=len,
            F_ADDR=addr,
        )
        self.rb.enq(obj)


class RingbufSimpleNicRxQueue:
    def __init__(self, backend_mem, addr, pcie_bfm) -> None:

        self.rb = Ringbuf(
            backend_mem=backend_mem,
            buffer_addr=addr,
            pcie_bfm=pcie_bfm,
            is_h2c=False,
            mem_addr_high_csr_addr=CSR_ADDR_SIMPLE_NIX_RX_QUEUE_ADDR_HIGH,
            mem_addr_low_csr_addr=CSR_ADDR_SIMPLE_NIX_RX_QUEUE_ADDR_LOW,
            head_csr_addr=CSR_ADDR_SIMPLE_NIX_RX_QUEUE_HEAD,
            tail_csr_addr=CSR_ADDR_SIMPLE_NIX_RX_QUEUE_TAIL)
        self.pcie_bfm = pcie_bfm

    async def sync_pointers(self):
        await self.rb.sync_pointers()

    async def init_addr_csr(self):
        await self.rb.init_addr_csr()

    def deq(self):
        return self.rb.deq()

    def deq_blocking(self):
        return self.rb.deq_blocking()

    async def deq_blocking_in_descriptor_valid_bit_polling_mode(self):
        return await self.rb.deq_blocking_in_descriptor_valid_bit_polling_mode()
