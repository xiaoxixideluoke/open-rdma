# coding: utf-8

import subprocess
from ctypes import *
from itertools import islice


def memcpy(dst, start_addr, src):
    dst[start_addr:start_addr + len(src)] = src


class RingbufDescCommonHead(Structure):
    _pack_ = 1
    _align_ = 1
    _fields_ = [
        ("F_OP_CODE", c_ubyte, 8),
        ("F_IS_EXTEND_OP_CODE", c_ubyte, 1),
        ("F_RESERVED_0", c_ubyte, 5),
        ("F_HAS_NEXT_FRAG", c_ubyte, 1),
        ("F_VALID", c_ubyte, 1),
    ]


class RingbufDescCmdQueueCommonHead(Structure):
    _pack_ = 1
    _fields_ = [("F_USER_DATA", c_ushort, 8),
                ("F_IS_SUCCESS", c_ushort, 1),
                ("F_RESERVED_0", c_ushort, 7),
                ]


class CmdQueueRespDescOnlyCommonHeader(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_RESERVED_3", c_uint64, 64),
                ("F_RESERVED_2", c_uint64, 64),
                ("F_RESERVED_1", c_uint64, 64),
                ("F_RESERVED_0", c_uint32, 32),
                ("cmd_queue_common_header", RingbufDescCmdQueueCommonHead),
                ("common_header", RingbufDescCommonHead),
                ]


class CmdQueueDescUpdateMrTable(Structure):
    _fields_ = [
                ("F_RESERVED_2", c_uint32, 7),
                ("F_MR_TABLE_PGT_OFFSET", c_uint32, 17),
                ("F_MR_TABLE_ACC_FLAGS", c_uint32, 8),
                ("F_RESERVED_1", c_uint32, 32),
                ("F_MR_TABLE_MR_KEY", c_uint32, 32),
                ("F_MR_TABLE_MR_LENGTH", c_uint32, 32),
                ("F_MR_TABLE_MR_BASE_VA", c_uint64),
                ("F_RESERVED_0", c_uint32, 32),
                ("cmd_queue_common_header", RingbufDescCmdQueueCommonHead),
                ("common_header", RingbufDescCommonHead),
                ]


class CmdQueueDescUpdatePGT(Structure):
    _fields_ = [
                ("F_RESERVED_1", c_uint64, 64),
                ("F_PGT_ZERO_BASED_ENTRY_CNT", c_uint32, 32),
                ("F_PGT_START_INDEX", c_uint32, 32),
                ("F_PGT_DMA_ADDR", c_uint64),
                ("F_RESERVED_0", c_uint32, 32),
                ("cmd_queue_common_header", RingbufDescCmdQueueCommonHead),
                ("common_header", RingbufDescCommonHead),
                ]


class StateQP:
    IBV_QPS_RESET = 0
    IBV_QPS_INIT = 1
    IBV_QPS_RTR = 2
    IBV_QPS_RTS = 3
    IBV_QPS_SQD = 4
    IBV_QPS_SQE = 5
    IBV_QPS_ERR = 6
    IBV_QPS_UNKNOWN = 7
    IBV_QPS_CREATE = 8


class TypeQP:
    IBV_QPT_RC = 2
    IBV_QPT_UC = 3
    IBV_QPT_UD = 4
    IBV_QPT_RAW_PACKET = 8
    IBV_QPT_XRC_SEND = 9
    IBV_QPT_XRC_RECV = 10
    # IBV_QPT_DRIVER = 0xff


class QpReqType:
    REQ_QP_CREATE = 0
    REQ_QP_DESTROY = 1
    REQ_QP_MODIFY = 2
    REQ_QP_QUERY = 3


class MemAccessTypeFlag:
    IBV_ACCESS_NO_FLAGS = 0  # Not defined in rdma-core
    IBV_ACCESS_LOCAL_WRITE = 1  # (1 << 0)
    IBV_ACCESS_REMOTE_WRITE = 2  # (1 << 1)
    IBV_ACCESS_REMOTE_READ = 4  # (1 << 2)
    IBV_ACCESS_REMOTE_ATOMIC = 8  # (1 << 3)
    IBV_ACCESS_MW_BIND = 16  # (1 << 4)
    IBV_ACCESS_ZERO_BASED = 32  # (1 << 5)
    IBV_ACCESS_ON_DEMAND = 64  # (1 << 6)
    IBV_ACCESS_HUGETLB = 128  # (1 << 7)
    # IBV_ACCESS_RELAXED_ORDERING    = IBV_ACCESS_OPTIONAL_FIRST


class QpAttrMaskFlag:
    IBV_QP_NO_FLAGS = 0       # Not defined in rdma-core
    IBV_QP_STATE = 1       # 1 << 0
    IBV_QP_CUR_STATE = 2       # 1 << 1
    IBV_QP_EN_SQD_ASYNC_NOTIFY = 4       # 1 << 2
    IBV_QP_ACCESS_FLAGS = 8       # 1 << 3
    IBV_QP_PKEY_INDEX = 16      # 1 << 4
    IBV_QP_PORT = 32      # 1 << 5
    IBV_QP_QKEY = 64      # 1 << 6
    IBV_QP_AV = 128     # 1 << 7
    IBV_QP_PATH_MTU = 256     # 1 << 8
    IBV_QP_TIMEOUT = 512     # 1 << 9
    IBV_QP_RETRY_CNT = 1024    # 1 << 10
    IBV_QP_RNR_RETRY = 2048    # 1 << 11
    IBV_QP_RQ_PSN = 4096    # 1 << 12
    IBV_QP_MAX_QP_RD_ATOMIC = 8192    # 1 << 13
    IBV_QP_ALT_PATH = 16384   # 1 << 14
    IBV_QP_MIN_RNR_TIMER = 32768   # 1 << 15
    IBV_QP_SQ_PSN = 65536   # 1 << 16
    IBV_QP_MAX_DEST_RD_ATOMIC = 131072  # 1 << 17
    IBV_QP_PATH_MIG_STATE = 262144  # 1 << 18
    IBV_QP_CAP = 524288  # 1 << 19
    IBV_QP_DEST_QPN = 1048576  # 1 << 20
    # These bits were supported on older kernels, but never exposed from libibverbs
    # _IBV_QP_SMAC               = 1 << 21
    # _IBV_QP_ALT_SMAC           = 1 << 22
    # _IBV_QP_VID                = 1 << 23
    # _IBV_QP_ALT_VID            = 1 << 24
    IBV_QP_RATE_LIMIT = 33554432  # 1 << 25


class PMTU:
    IBV_MTU_256 = 1
    IBV_MTU_512 = 2
    IBV_MTU_1024 = 3
    IBV_MTU_2048 = 4
    IBV_MTU_4096 = 5


class CmdQueueDescQpManagement(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_QP_ADMIN_PEER_MAC_ADDR", c_uint64, 48),
                ("F_QP_ADMIN_LOCAL_UDP_PORT", c_uint32, 16),
                ("F_RESERVED_4", c_uint32, 16),
                ("F_RESERVED_3", c_uint32, 5),
                ("F_QP_ADMIN_PMTU", c_uint32, 3),
                ("F_RESERVED_2", c_uint32, 4),
                ("F_QP_ADMIN_QP_TYPE", c_uint32, 4),
                ("F_QP_ADMIN_ACCESS_FLAG", c_uint32, 8),
                ("F_QP_PEER_QPN", c_uint32, 24),
                ("F_RESERVED_1", c_uint32, 32),
                ("F_QP_ADMIN_QPN", c_uint32, 24),
                ("F_RESERVED_0", c_uint32, 6),
                ("F_QP_ADMIN_IS_ERROR", c_uint32, 1),
                ("F_QP_ADMIN_IS_VALID", c_uint32, 1),
                ("F_QP_ADMIN_PEER_IP_ADDR", c_uint32, 32),
                ("cmd_queue_common_header", RingbufDescCmdQueueCommonHead),
                ("common_header", RingbufDescCommonHead),
                ]


class CmdQueueDescSetNetworkParam(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_RESERVED_2", c_uint64, 16),
                ("F_NET_PARAM_MACADDR", c_uint64, 48),
                ("F_RESERVED_1", c_uint64, 32),
                ("F_NET_PARAM_IPADDR", c_uint32, 32),
                ("F_NET_PARAM_NETMASK", c_uint32, 32),
                ("F_NET_PARAM_GATEWAY", c_uint32, 32),
                ("F_RESERVED_0", c_uint32, 32),
                ("cmd_queue_common_header", RingbufDescCmdQueueCommonHead),
                ("common_header", RingbufDescCommonHead),
                ]


class CmdQueueDescSetRawPacketReceiveMeta(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_RESERVED_2", c_uint64),
                ("F_RESERVED_1", c_uint64),
                ("F_RAW_PACKET_META_BASE_ADDR", c_uint64),
                ("F_RESERVED_0", c_uint32, 32),
                ("cmd_queue_common_header", RingbufDescCmdQueueCommonHead),
                ("common_header", RingbufDescCommonHead), 
                ]


class CmdQueueDescOperators:
    F_OPCODE_CMDQ_UPDATE_MR_TABLE = 0x00
    F_OPCODE_CMDQ_UPDATE_PGT = 0x01
    F_OPCODE_CMDQ_MANAGE_QP = 0x02
    F_OPCODE_CMDQ_SET_NETWORK_PARAM = 0x03
    F_OPCODE_CMDQ_SET_RAW_PACKET_RECEIVE_META = 0x04
    F_OPCODE_CMDQ_UPDATE_ERROR_PSN_RECOVER_POINT = 0x05


class SendQueueReqDescSeg0(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_RESERVED_1", c_uint32, 3),
                ("F_FLAGS", c_uint32, 5),
                ("F_DQPN", c_uint32, 24),
                ("F_RESERVED_0", c_uint32, 4),
                ("F_QP_TYPE", c_uint32, 4),
                ("F_PSN", c_uint32, 24),
                ("F_R_ADDR", c_uint64, 64),
                ("F_DST_IP", c_uint32, 32),
                ("F_RKEY", c_uint32, 32),
                ("F_TOTAL_LEN", c_uint32, 32),
                ("F_MSN", c_ushort, 16),
                ("common_header", RingbufDescCommonHead),
                ]


class SendQueueReqDescSeg1(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_LADDR", c_uint64),
                ("F_LEN", c_uint32, 32),
                ("F_LKEY", c_uint32, 32),
                ("F_SQPN_HIGH_16_BITS", c_uint64, 16),
                ("F_MAC_ADDR", c_uint64, 48),
                ("F_IMM", c_uint32, 32),
                ("F_SQPN_LOW_8_BITS", c_ushort, 8),
                ("F_RESERVED_0", c_ushort, 1),
                ("F_ENABLE_ECN", c_ushort, 1),
                ("F_IS_RETRY", c_ushort, 1),
                ("F_IS_LAST", c_ushort, 1),
                ("F_IS_FIRST", c_ushort, 1),
                ("F_PMTU", c_ushort, 3),
                ("common_header", RingbufDescCommonHead), 
                ]


class WorkReqOpCode:
    IBV_WR_RDMA_WRITE = 0
    IBV_WR_RDMA_WRITE_WITH_IMM = 1
    IBV_WR_SEND = 2
    IBV_WR_SEND_WITH_IMM = 3
    IBV_WR_RDMA_READ = 4
    IBV_WR_ATOMIC_CMP_AND_SWP = 5
    IBV_WR_ATOMIC_FETCH_AND_ADD = 6
    IBV_WR_LOCAL_INV = 7
    IBV_WR_BIND_MW = 8
    IBV_WR_SEND_WITH_INV = 9
    IBV_WR_TSO = 10
    IBV_WR_DRIVER1 = 11


class RdmaOpCode:
    SEND_FIRST = 0x00
    SEND_MIDDLE = 0x01
    SEND_LAST = 0x02
    SEND_LAST_WITH_IMMEDIATE = 0x03
    SEND_ONLY = 0x04
    SEND_ONLY_WITH_IMMEDIATE = 0x05
    RDMA_WRITE_FIRST = 0x06
    RDMA_WRITE_MIDDLE = 0x07
    RDMA_WRITE_LAST = 0x08
    RDMA_WRITE_LAST_WITH_IMMEDIATE = 0x09
    RDMA_WRITE_ONLY = 0x0a
    RDMA_WRITE_ONLY_WITH_IMMEDIATE = 0x0b
    RDMA_READ_REQUEST = 0x0c
    RDMA_READ_RESPONSE_FIRST = 0x0d
    RDMA_READ_RESPONSE_MIDDLE = 0x0e
    RDMA_READ_RESPONSE_LAST = 0x0f
    RDMA_READ_RESPONSE_ONLY = 0x10
    ACKNOWLEDGE = 0x11
    ATOMIC_ACKNOWLEDGE = 0x12
    COMPARE_SWAP = 0x13
    FETCH_ADD = 0x14
    RESYNC = 0x15
    SEND_LAST_WITH_INVALIDATE = 0x16
    SEND_ONLY_WITH_INVALIDATE = 0x17


class WorkReqSendFlag:
    IBV_SEND_NO_FLAGS = 0  # Not defined in rdma-core
    IBV_SEND_FENCE = 1
    IBV_SEND_SIGNALED = 2
    IBV_SEND_SOLICITED = 4
    IBV_SEND_INLINE = 8
    IBV_SEND_IP_CSUM = 16


def is_power_of_2(x):
    if x <= 0:
        return False
    return (x & (x-1)) == 0


class MetaReportQueuePacketBasicInfoDesc(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_IMM_DATA", c_uint32, 32),
                ("F_RKEY", c_uint32, 32),
                ("F_RADDR", c_uint64, 64),
                ("F_TOTAL_LEN", c_uint32, 32),
                ("F_RESERVED_1", c_uint32, 8),
                ("F_DQPN", c_uint32, 24),
                ("F_RESERVED_0", c_uint32, 4),
                ("F_IS_RETRY", c_uint32, 1),
                ("F_ACK_REQ", c_uint32, 1),
                ("F_SOLICITED", c_uint32, 1),
                ("F_ECN_MARKED", c_uint32, 1),
                ("F_PSN", c_uint32, 24),
                ("F_MSN", c_ushort, 16),
                ("common_header", RingbufDescCommonHead),
        ]


class MetaReportQueueReadReqExtendInfoDesc(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_RESERVED_2", c_uint64, 64),
                ("F_RESERVED_1", c_uint32, 32),
                ("F_LKEY", c_uint32, 32),
                ("F_LADDR", c_uint64, 64),
                ("F_TOTAL_LEN", c_uint32, 32),
                ("F_RESERVED_0", c_ushort, 16),
                ("common_header", RingbufDescCommonHead),
    ]


class MetaReportQueueAckDesc(Structure):
    _pack_ = 1
    # _align_ = 1
    _fields_ = [
                ("F_NOW_BITMAP_HIGH", c_uint64, 64),
                ("F_NOW_BITMAP_LOW", c_uint64, 64),

                # the following line is a trick to handle bug described at https://github.com/python/cpython/pull/97702
                # Since Python 3.14 is not released now, the layout has buf if we split it into 3 fields.
                # so we provide additional functions to get those fields.
                # should be changed after python 3.14 is released
                ("F_PSN_NOW_QPN_MSN", c_uint64, 64),
                # ("F_MSN", c_uint64, 16),
                # ("F_QPN", c_uint64, 24),
                # ("F_PSN_NOW", c_uint64, 24),
                ("F_RESERVED_2", c_uint32, 8),
                ("F_PSN_BEFORE_SLIDE", c_uint32, 24),
                ("F_RESERVED_1", c_uint16, 8),
                ("F_IS_PACKET_LOST", c_uint16, 1),
                ("F_IS_WINDOW_SLIDED", c_uint16, 1),
                ("F_IS_SEND_BY_DRIVER", c_uint16, 1),
                ("F_IS_SEND_BY_LOCAL_HW", c_uint16, 1),
                ("F_RESERVED_0", c_uint16, 4),
                ("common_header", RingbufDescCommonHead),
    ]

    def get_psn_now(self):
        return (self.F_PSN_NOW_QPN_MSN >> 40) & 0xFFFFFF

    def get_qpn(self):
        return (self.F_PSN_NOW_QPN_MSN >> 16) & 0xFFFFFF

    def get_msn(self):
        return (self.F_PSN_NOW_QPN_MSN) & 0xFFFF


class MetaReportQueueAckExtraDesc(Structure):
    _pack_ = 1
    _fields_ = [
                ("F_PRE_BITMAP_HIGH", c_uint64, 64),
                ("F_PRE_BITMAP_LOW", c_uint64, 64),
                ("F_RESERVED_2", c_uint64, 64),
                ("F_RESERVED_1", c_uint32, 32),
                ("F_RESERVED_0", c_ushort, 16),
                ("common_header", RingbufDescCommonHead),        
    ]


class AethCode:
    AETH_CODE_ACK = 0b00
    AETH_CODE_RNR = 0b01
    AETH_CODE_RSVD = 0b10
    AETH_CODE_NAK = 0b11


class AethAckValueCreditCnt:
    AETH_ACK_VALUE_INVALID_CREDIT_CNT = 0b11111


class RdmaReqStatus:
    RDMA_REQ_ST_NORMAL = 1
    RDMA_REQ_ST_INV_ACC_FLAG = 2
    RDMA_REQ_ST_INV_OPCODE = 3
    RDMA_REQ_ST_INV_MR_KEY = 4
    RDMA_REQ_ST_INV_MR_REGION = 5
    RDMA_REQ_ST_UNKNOWN = 6
    RDMA_REQ_ST_INV_HEADER = 7
    RDMA_REQ_ST_MAX_GUARD = 255


class SimpleNicTxQueueDesc(Structure):
    _pack_ = 1
    _fields_ = [
        ("F_RESERVED_2", c_uint64, 64),
        ("F_RESERVED_1", c_uint64, 64),
        ("F_ADDR", c_uint64, 64),
        ("F_LEN", c_uint32, 32),
        ("F_RESERVED_0", c_ushort, 16),
        ("common_header", RingbufDescCommonHead),
    ]


class SimpleNicRxQueueDesc(Structure):
    _pack_ = 1
    _fields_ = [
        ("F_RESERVED_3", c_uint64, 64),
        ("F_RESERVED_2", c_uint64, 64),
        ("F_RESERVED_1", c_uint64, 32),
        ("F_SLOT_IDX", c_uint32, 32),
        ("F_LEN", c_uint32, 32),
        ("F_RESERVED_0", c_ushort, 16),
        ("common_header", RingbufDescCommonHead),
    ]
