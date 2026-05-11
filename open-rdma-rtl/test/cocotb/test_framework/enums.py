# class StateQP:
#     IBV_QPS_RESET = 0
#     IBV_QPS_INIT = 1
#     IBV_QPS_RTR = 2
#     IBV_QPS_RTS = 3
#     IBV_QPS_SQD = 4
#     IBV_QPS_SQE = 5
#     IBV_QPS_ERR = 6
#     IBV_QPS_UNKNOWN = 7
#     IBV_QPS_CREATE = 8


# class TypeQP:
#     IBV_QPT_RC = 2
#     IBV_QPT_UC = 3
#     IBV_QPT_UD = 4
#     IBV_QPT_RAW_PACKET = 8
#     IBV_QPT_XRC_SEND = 9
#     IBV_QPT_XRC_RECV = 10
#     # IBV_QPT_DRIVER = 0xff


# class QpReqType:
#     REQ_QP_CREATE = 0
#     REQ_QP_DESTROY = 1
#     REQ_QP_MODIFY = 2
#     REQ_QP_QUERY = 3


# class MemAccessTypeFlag:
#     IBV_ACCESS_NO_FLAGS = 0  # Not defined in rdma-core
#     IBV_ACCESS_LOCAL_WRITE = 1  # (1 << 0)
#     IBV_ACCESS_REMOTE_WRITE = 2  # (1 << 1)
#     IBV_ACCESS_REMOTE_READ = 4  # (1 << 2)
#     IBV_ACCESS_REMOTE_ATOMIC = 8  # (1 << 3)
#     IBV_ACCESS_MW_BIND = 16  # (1 << 4)
#     IBV_ACCESS_ZERO_BASED = 32  # (1 << 5)
#     IBV_ACCESS_ON_DEMAND = 64  # (1 << 6)
#     IBV_ACCESS_HUGETLB = 128  # (1 << 7)
#     # IBV_ACCESS_RELAXED_ORDERING    = IBV_ACCESS_OPTIONAL_FIRST


# class QpAttrMaskFlag:
#     IBV_QP_NO_FLAGS = 0       # Not defined in rdma-core
#     IBV_QP_STATE = 1       # 1 << 0
#     IBV_QP_CUR_STATE = 2       # 1 << 1
#     IBV_QP_EN_SQD_ASYNC_NOTIFY = 4       # 1 << 2
#     IBV_QP_ACCESS_FLAGS = 8       # 1 << 3
#     IBV_QP_PKEY_INDEX = 16      # 1 << 4
#     IBV_QP_PORT = 32      # 1 << 5
#     IBV_QP_QKEY = 64      # 1 << 6
#     IBV_QP_AV = 128     # 1 << 7
#     IBV_QP_PATH_MTU = 256     # 1 << 8
#     IBV_QP_TIMEOUT = 512     # 1 << 9
#     IBV_QP_RETRY_CNT = 1024    # 1 << 10
#     IBV_QP_RNR_RETRY = 2048    # 1 << 11
#     IBV_QP_RQ_PSN = 4096    # 1 << 12
#     IBV_QP_MAX_QP_RD_ATOMIC = 8192    # 1 << 13
#     IBV_QP_ALT_PATH = 16384   # 1 << 14
#     IBV_QP_MIN_RNR_TIMER = 32768   # 1 << 15
#     IBV_QP_SQ_PSN = 65536   # 1 << 16
#     IBV_QP_MAX_DEST_RD_ATOMIC = 131072  # 1 << 17
#     IBV_QP_PATH_MIG_STATE = 262144  # 1 << 18
#     IBV_QP_CAP = 524288  # 1 << 19
#     IBV_QP_DEST_QPN = 1048576  # 1 << 20
#     # These bits were supported on older kernels, but never exposed from libibverbs
#     # _IBV_QP_SMAC               = 1 << 21
#     # _IBV_QP_ALT_SMAC           = 1 << 22
#     # _IBV_QP_VID                = 1 << 23
#     # _IBV_QP_ALT_VID            = 1 << 24
#     IBV_QP_RATE_LIMIT = 33554432  # 1 << 25


# class PMTU:
#     IBV_MTU_256 = 1
#     IBV_MTU_512 = 2
#     IBV_MTU_1024 = 3
#     IBV_MTU_2048 = 4
#     IBV_MTU_4096 = 5


# class CmdQueueDescOperators:
#     F_OPCODE_CMDQ_UPDATE_MR_TABLE = 0x00
#     F_OPCODE_CMDQ_UPDATE_PGT = 0x01
#     F_OPCODE_CMDQ_MANAGE_QP = 0x02
#     F_OPCODE_CMDQ_SET_NETWORK_PARAM = 0x03
#     F_OPCODE_CMDQ_SET_RAW_PACKET_RECEIVE_META = 0x04
#     F_OPCODE_CMDQ_UPDATE_ERROR_PSN_RECOVER_POINT = 0x05


# class WorkReqOpCode:
#     IBV_WR_RDMA_WRITE = 0
#     IBV_WR_RDMA_WRITE_WITH_IMM = 1
#     IBV_WR_SEND = 2
#     IBV_WR_SEND_WITH_IMM = 3
#     IBV_WR_RDMA_READ = 4
#     IBV_WR_ATOMIC_CMP_AND_SWP = 5
#     IBV_WR_ATOMIC_FETCH_AND_ADD = 6
#     IBV_WR_LOCAL_INV = 7
#     IBV_WR_BIND_MW = 8
#     IBV_WR_SEND_WITH_INV = 9
#     IBV_WR_TSO = 10
#     IBV_WR_DRIVER1 = 11


# class RdmaOpCode:
#     SEND_FIRST = 0x00
#     SEND_MIDDLE = 0x01
#     SEND_LAST = 0x02
#     SEND_LAST_WITH_IMMEDIATE = 0x03
#     SEND_ONLY = 0x04
#     SEND_ONLY_WITH_IMMEDIATE = 0x05
#     RDMA_WRITE_FIRST = 0x06
#     RDMA_WRITE_MIDDLE = 0x07
#     RDMA_WRITE_LAST = 0x08
#     RDMA_WRITE_LAST_WITH_IMMEDIATE = 0x09
#     RDMA_WRITE_ONLY = 0x0a
#     RDMA_WRITE_ONLY_WITH_IMMEDIATE = 0x0b
#     RDMA_READ_REQUEST = 0x0c
#     RDMA_READ_RESPONSE_FIRST = 0x0d
#     RDMA_READ_RESPONSE_MIDDLE = 0x0e
#     RDMA_READ_RESPONSE_LAST = 0x0f
#     RDMA_READ_RESPONSE_ONLY = 0x10
#     ACKNOWLEDGE = 0x11
#     ATOMIC_ACKNOWLEDGE = 0x12
#     COMPARE_SWAP = 0x13
#     FETCH_ADD = 0x14
#     RESYNC = 0x15
#     SEND_LAST_WITH_INVALIDATE = 0x16
#     SEND_ONLY_WITH_INVALIDATE = 0x17


# class WorkReqSendFlag:
#     IBV_SEND_NO_FLAGS = 0  # Not defined in rdma-core
#     IBV_SEND_FENCE = 1
#     IBV_SEND_SIGNALED = 2
#     IBV_SEND_SOLICITED = 4
#     IBV_SEND_INLINE = 8
#     IBV_SEND_IP_CSUM = 16


# class AethCode:
#     AETH_CODE_ACK = 0b00
#     AETH_CODE_RNR = 0b01
#     AETH_CODE_RSVD = 0b10
#     AETH_CODE_NAK = 0b11


# class AethAckValueCreditCnt:
#     AETH_ACK_VALUE_INVALID_CREDIT_CNT = 0b11111


# class RdmaReqStatus:
#     RDMA_REQ_ST_NORMAL = 1
#     RDMA_REQ_ST_INV_ACC_FLAG = 2
#     RDMA_REQ_ST_INV_OPCODE = 3
#     RDMA_REQ_ST_INV_MR_KEY = 4
#     RDMA_REQ_ST_INV_MR_REGION = 5
#     RDMA_REQ_ST_UNKNOWN = 6
#     RDMA_REQ_ST_INV_HEADER = 7
#     RDMA_REQ_ST_MAX_GUARD = 255
