import ClientServer :: *;
import PAClib :: *;
import Vector :: *;
import GetPut :: *;

import FullyPipelineChecker :: *;
import RdmaHeaders :: *;
import Settings :: *;
import EthernetTypes :: *;

typedef 0 NUMERIC_TYPE_ZERO;
typedef 1 NUMERIC_TYPE_ONE;
typedef 2 NUMERIC_TYPE_TWO;
typedef 3 NUMERIC_TYPE_THREE;
typedef 4 NUMERIC_TYPE_FOUR;
typedef 5 NUMERIC_TYPE_FIVE;
typedef 6 NUMERIC_TYPE_SIX;
typedef 7 NUMERIC_TYPE_SEVEN;
typedef 8 NUMERIC_TYPE_EIGHT;
typedef 16 NUMERIC_TYPE_SIXTEEN;

typedef NUMERIC_TYPE_TWO QUEUE_DEPTH_2;
typedef NUMERIC_TYPE_FOUR QUEUE_DEPTH_4;




typedef 3 BIT_BYTE_CONVERT_SHIFT_NUM;
typedef 2 BYTE_DWORD_CONVERT_SHIFT_NUM;
typedef 2 BYTE_CNT_PER_WOED;
typedef 4 BYTE_CNT_PER_DWOED;
typedef 8 BYTE_WIDTH;
typedef 16 WORD_WIDTH;
typedef 32 DWORD_WIDTH;
typedef Bit#(BYTE_WIDTH) Byte;
typedef Bit#(WORD_WIDTH) Word;
typedef Bit#(DWORD_WIDTH) Dword;
typedef Bit#(BYTE_DWORD_CONVERT_SHIFT_NUM) ByteIdxInDword;

typedef Bit#(TLog#(TLog#(MAX_PMTU))) ChunkAlignLogValue;
typedef NUMERIC_TYPE_TWO    LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE;

// Protocol settings
typedef TExp#(31) RDMA_MAX_LEN;
typedef 8         ATOMIC_WORK_REQ_LEN;
typedef 3         RETRY_CNT_WIDTH;

typedef 7 INFINITE_RETRY;
typedef 0 INFINITE_TIMEOUT;

typedef TMul#(8192, TExp#(30)) MAX_TIMEOUT_NS; // 2^43
typedef TMul#(655360, 1000)    MAX_RNR_WAIT_NS; // 2^30

typedef 16'hFFFF     DEFAULT_PKEY;
typedef 32'hFFFFFFFF DEFAULT_QKEY;
typedef 3            DEFAULT_RETRY_NUM;

typedef 64 ATOMIC_ADDR_BIT_ALIGNMENT;

typedef 32 PD_HANDLE_WIDTH;

typedef 8 QP_CAP_CNT_WIDTH;
// typedef 32 QP_CAP_CNT_WIDTH;
// typedef 8 PENDING_READ_ATOMIC_REQ_CNT_WIDTH;

// Derived settings
typedef AETH_VALUE_WIDTH TIMER_WIDTH;


// 12 + 4 + 16 + 16 = 48 bytes
typedef 48 RDMA_HEADER_MAX_BYTE_LENGTH;
typedef 42 ETH_IP_UDP_HEADER_BYTE_LENGTH; // 14(MAC) + 20(IP) + 8(UDP) = 42
typedef TAdd#(ETH_IP_UDP_HEADER_BYTE_LENGTH, RDMA_HEADER_MAX_BYTE_LENGTH) ETH_IP_UDP_RDMA_HEADER_MAX_BYTE_LENGTH;
typedef TAdd#(ETH_IP_UDP_RDMA_HEADER_MAX_BYTE_LENGTH, MAX_PMTU) RDMA_ETHERNET_FRAME_MAX_BYTE_LENGTH;
typedef Bit#(TAdd#(1, TLog#(RDMA_ETHERNET_FRAME_MAX_BYTE_LENGTH))) RdmaEthernetFrameByteLen;

typedef TDiv#(DATA_BUS_WIDTH, BYTE_WIDTH)   DATA_BUS_BYTE_WIDTH; // 32 (bus 256b), 64 (bus 512b)
typedef TLog#(DATA_BUS_BYTE_WIDTH)          DATA_BUS_BYTE_NUM_WIDTH; // 5 (bus 256b), 6 (bus 512b)
typedef TLog#(DATA_BUS_WIDTH)               DATA_BUS_BIT_NUM_WIDTH; // 8 (bus 256b), 9 (bus 512b)

typedef 256 DESC_DATA_WIDTH;
typedef TDiv#(DESC_DATA_WIDTH, BYTE_WIDTH)  DESC_DATA_BUS_BYTE_WIDTH; // 32 
typedef TLog#(DESC_DATA_BUS_BYTE_WIDTH)     DESC_DATA_BUS_BYTE_NUM_WIDTH; // 5 
typedef TLog#(DESC_DATA_WIDTH)              DESC_DATA_BUS_BIT_NUM_WIDTH; // 8

typedef Bit#(DESC_DATA_WIDTH)               DESC_DATA;


typedef TLog#(MAX_PMTU)                      MAX_PMTU_WIDTH; // 12
// typedef TLog#(TLog#(MAX_PMTU))               PMTU_VALUE_MAX_WIDTH; // 4
typedef TDiv#(MAX_PMTU, DATA_BUS_BYTE_WIDTH) PMTU_MAX_FRAG_NUM; // 128 (bus 256b), 64 (bus 512b)
typedef TDiv#(MIN_PMTU, DATA_BUS_BYTE_WIDTH) PMTU_MIN_FRAG_NUM; // 8 (bus 256b), 4 (bus 512b)

typedef TAdd#(1, TSub#(RDMA_MAX_LEN_WIDTH, TLog#(DATA_BUS_BYTE_WIDTH))) TOTAL_FRAG_NUM_WIDTH; // 28 (bus 256b), 27 (bus 512b)
typedef TAdd#(1, TLog#(PMTU_MAX_FRAG_NUM))                              PMTU_FRAG_NUM_WIDTH; // 8
typedef TAdd#(1, TSub#(RDMA_MAX_LEN_WIDTH, TLog#(MIN_PMTU)))            PKT_NUM_WIDTH; // 25
typedef TAdd#(1, TLog#(MAX_PMTU))                                       PKT_LEN_WIDTH; // 13

typedef TDiv#(ATOMIC_ADDR_BIT_ALIGNMENT, BYTE_WIDTH) ATOMIC_ADDR_BYTE_ALIGNMENT; // 8




typedef 48                                            PHYSICAL_ADDR_WIDTH; // X86 physical address width
typedef TLog#(PAGE_SIZE_CAP)                          PAGE_OFFSET_WIDTH;
typedef TSub#(PHYSICAL_ADDR_WIDTH, PAGE_OFFSET_WIDTH) PAGE_NUMBER_WIDTH;   // 48-21=27
typedef Bit#(PAGE_OFFSET_WIDTH)  PageOffset;
typedef Bit#(PAGE_NUMBER_WIDTH)  PageNumber;
typedef Bit#(PHYSICAL_ADDR_WIDTH) PADDR;

typedef TExp#(14) TLB_CACHE_SIZE; // TLB cache size 16K
typedef TLog#(TLB_CACHE_SIZE) TLB_CACHE_INDEX_WIDTH; // 14
typedef TSub#(TSub#(ADDR_WIDTH, TLB_CACHE_INDEX_WIDTH), PAGE_OFFSET_WIDTH) TLB_CACHE_TAG_WIDTH; // 64-14-21=29

// Derived types
typedef Bit#(DATA_BUS_WIDTH)      DATA;

typedef Bit#(32) ADDR32;


typedef Bit#(TAdd#(1, DATA_BUS_BIT_NUM_WIDTH))  BusBitCnt;                      // 9 (bus 256b)
typedef Bit#(DATA_BUS_BIT_NUM_WIDTH)            BusBitIdx;                      // 8 (bus 256b)
typedef Bit#(TAdd#(1, DATA_BUS_BYTE_NUM_WIDTH)) BusByteCnt;                     // 6 (bus 256b)
typedef Bit#(DATA_BUS_BYTE_NUM_WIDTH)           BusByteIdx;                     // 5 (bus 256b)
typedef BusByteCnt                              DataBusSignedByteShiftOffset;   // 6 (bus 256b)

typedef TDiv#(DATA_BUS_BYTE_WIDTH, BYTE_CNT_PER_DWOED)  DWORD_CNT_PER_DATA_BUS_BEAT;


typedef 3 RDMA_PACKET_HEADER_BETA_CNT;

typedef 4 PCIE_BAR_ADDR_BYTE_WIDTH;
typedef 4 PCIE_BAR_DATA_BYTE_WIDTH;
typedef TMul#(PCIE_BAR_ADDR_BYTE_WIDTH, BYTE_WIDTH) PCIE_BAR_ADDR_BIT_WIDTH;
typedef TMul#(PCIE_BAR_DATA_BYTE_WIDTH, BYTE_WIDTH) PCIE_BAR_DATA_BIT_WIDTH;
typedef Bit#(PCIE_BAR_ADDR_BIT_WIDTH) PcieBarAddr;
typedef Bit#(PCIE_BAR_DATA_BIT_WIDTH) PcieBarData;



typedef Bit#(PMTU_FRAG_NUM_WIDTH)  PktFragNum;
typedef Bit#(PKT_NUM_WIDTH)        PktNum;
typedef Bit#(PKT_LEN_WIDTH)        PktLen;


typedef Bit#(PD_HANDLE_WIDTH) HandlerPD;



typedef Bit#(TLog#(MAX_PTE_ENTRY_CNT)) PTEIndex;

typedef struct {
    PTEIndex pgtOffset;
    ADDR baseVA;
    Length len;
    FlagsType#(MemAccessTypeFlag) accFlags;
    KeyPartMR keyPart;
} MemRegionTableEntry deriving(Bits, FShow);

typedef struct {
    PageNumber pn;
} PageTableEntry deriving(Bits, FShow);

typedef struct {
    IndexMR idx;
    Maybe#(MemRegionTableEntry) entry;
} MrTableModifyReq deriving(Bits, FShow);

typedef struct {
    Bool success;
} MrTableModifyResp deriving(Bits, FShow);

typedef struct {
    IndexMR idx;
} MrTableQueryReq deriving(Bits, FShow);

typedef struct {
    PTEIndex idx;
    PageTableEntry pte;
} PgtModifyReq deriving(Bits, FShow);

typedef struct {
    Bool success;
} PgtModifyResp deriving(Bits, FShow);

typedef struct {
    PTEIndex pgtOffset;
    ADDR baseVA;
    ADDR addrToTrans;
} PgtAddrTranslateReq deriving(Bits, FShow);


typedef Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) MrTableQueryClt;
typedef Client#(PgtAddrTranslateReq, ADDR) PgtQueryClt;

// Common types




// This buffer should be able to contain the largest extend header combinations.
// the largest one is 42 Byte;
typedef 336 RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH;
typedef Bit#(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) RdmaExtendHeaderBuffer;
typedef TDiv#(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH, BYTE_WIDTH) RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH;        // 42
typedef TAdd#(1, TLog#(RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH)) RDMA_EXTEND_HEADER_LENGTH_BIT_WIDTH;          // 6
typedef Bit#(RDMA_EXTEND_HEADER_LENGTH_BIT_WIDTH) RdmaExtendHeaderLength;

typedef TAdd#(RDMA_EXTEND_HEADER_BUFFER_BYTE_WIDTH, BTH_BYTE_WIDTH) RDMA_BTH_AND_ETH_MAX_BYTE_WIDTH;        // 54
typedef TAdd#(1, TLog#(RDMA_BTH_AND_ETH_MAX_BYTE_WIDTH)) RDMA_BTH_AND_ETH_MAX_LENGTH_WIDTH;                 // 7    TODO: should reduce to 6?
typedef Bit#(RDMA_BTH_AND_ETH_MAX_LENGTH_WIDTH) RdmaBthAndEthTotalLength;


typedef struct {
    BTH bth;
    RdmaExtendHeaderBuffer rdmaExtendHeaderBuf;
} RdmaBthAndExtendHeader deriving(Bits, Eq, FShow);

typedef struct {
    RdmaBthAndExtendHeader header;
    Bool hasPayload;
    Bool isEcnMarked;
    SimulationTime  fpDebugTime;
} RdmaRecvPacketMeta deriving(Bits, FShow);

typedef struct {
    PktFragNum beatCnt;
    SimulationTime  fpDebugTime;
} RdmaRecvPacketTailMeta deriving(Bits, FShow);

typedef struct {
    RdmaBthAndExtendHeader header;
    Bool hasPayload;
    // SimulationTime  fpDebugTime;
} RdmaSendPacketMeta deriving(Bits, FShow);



// QP related types

typedef enum {
    IBV_QPS_RESET,
    IBV_QPS_INIT,
    IBV_QPS_RTR,
    IBV_QPS_RTS,
    IBV_QPS_SQD,
    IBV_QPS_SQE,
    IBV_QPS_ERR,
    IBV_QPS_UNKNOWN,
    IBV_QPS_CREATE // TODO: remote it. Not defined in rdma-core
} StateQP deriving(Bits, Eq, FShow);

typedef enum {
    IBV_QPT_RC         = 2,
    IBV_QPT_UC         = 3,
    IBV_QPT_UD         = 4,
    IBV_QPT_RAW_PACKET = 8,
    IBV_QPT_XRC_SEND   = 9,
    IBV_QPT_XRC_RECV   = 10
    // IBV_QPT_DRIVER = 0xff
} TypeQP deriving(Bits, Eq, FShow);

typedef enum {
    IBV_ACCESS_NO_FLAGS      =  0, // Not defined in rdma-core
    IBV_ACCESS_LOCAL_WRITE   =  1, // (1 << 0)
    IBV_ACCESS_REMOTE_WRITE  =  2, // (1 << 1)
    IBV_ACCESS_REMOTE_READ   =  4, // (1 << 2)
    IBV_ACCESS_REMOTE_ATOMIC =  8, // (1 << 3)
    IBV_ACCESS_MW_BIND       = 16, // (1 << 4)
    IBV_ACCESS_ZERO_BASED    = 32, // (1 << 5)
    IBV_ACCESS_ON_DEMAND     = 64, // (1 << 6)
    IBV_ACCESS_HUGETLB       = 128 // (1 << 7)
    // IBV_ACCESS_RELAXED_ORDERING    = IBV_ACCESS_OPTIONAL_FIRST,
} MemAccessTypeFlag deriving(Bits, Eq, FShow);

instance Flags#(MemAccessTypeFlag);
    function Bool isOneHotOrZero(MemAccessTypeFlag inputVal) = 1 >= countOnes(pack(inputVal));
endinstance

typedef enum {
    IBV_MTU_256  = 1,
    IBV_MTU_512  = 2,
    IBV_MTU_1024 = 3,
    IBV_MTU_2048 = 4,
    IBV_MTU_4096 = 5
} PMTU deriving(Bits, Eq, FShow);


typedef enum {
    IBV_QP_NO_FLAGS            = 0,       // Not defined in rdma-core
    IBV_QP_STATE               = 1,       // 1 << 0
    IBV_QP_CUR_STATE           = 2,       // 1 << 1
    IBV_QP_EN_SQD_ASYNC_NOTIFY = 4,       // 1 << 2
    IBV_QP_ACCESS_FLAGS        = 8,       // 1 << 3
    IBV_QP_PKEY_INDEX          = 16,      // 1 << 4
    IBV_QP_PORT                = 32,      // 1 << 5
    IBV_QP_QKEY                = 64,      // 1 << 6
    IBV_QP_AV                  = 128,     // 1 << 7
    IBV_QP_PATH_MTU            = 256,     // 1 << 8
    IBV_QP_TIMEOUT             = 512,     // 1 << 9
    IBV_QP_RETRY_CNT           = 1024,    // 1 << 10
    IBV_QP_RNR_RETRY           = 2048,    // 1 << 11
    IBV_QP_RQ_PSN              = 4096,    // 1 << 12
    IBV_QP_MAX_QP_RD_ATOMIC    = 8192,    // 1 << 13
    IBV_QP_ALT_PATH            = 16384,   // 1 << 14
    IBV_QP_MIN_RNR_TIMER       = 32768,   // 1 << 15
    IBV_QP_SQ_PSN              = 65536,   // 1 << 16
    IBV_QP_MAX_DEST_RD_ATOMIC  = 131072,  // 1 << 17
    IBV_QP_PATH_MIG_STATE      = 262144,  // 1 << 18
    IBV_QP_CAP                 = 524288,  // 1 << 19
    IBV_QP_DEST_QPN            = 1048576, // 1 << 20
    // These bits were supported on older kernels, but never exposed from libibverbs
    // _IBV_QP_SMAC               = 1 << 21,
    // _IBV_QP_ALT_SMAC           = 1 << 22,
    // _IBV_QP_VID                = 1 << 23,
    // _IBV_QP_ALT_VID            = 1 << 24,
    IBV_QP_RATE_LIMIT          = 33554432 // 1 << 25
} QpAttrMaskFlag deriving(Bits, Eq, FShow);

instance Flags#(QpAttrMaskFlag);
    function Bool isOneHotOrZero(QpAttrMaskFlag inputVal) = 1 >= countOnes(pack(inputVal));
endinstance


typedef 8 QPN_KEY_PART_WIDTH;
typedef TLog#(MAX_QP) QP_INDEX_WIDTH_SUPPORTED;
typedef TSub#(QPN_WIDTH, QPN_KEY_PART_WIDTH) QP_INDEX_PART_WIDTH;

typedef Bit#(QP_INDEX_WIDTH_SUPPORTED)     IndexQP;
typedef Bit#(QPN_KEY_PART_WIDTH) KeyQP;
typedef Bit#(QP_INDEX_PART_WIDTH) QpnRawIndexPart;


function KeyQP   getKeyQP  (QPN qpn) = unpack(truncate(qpn));
function IndexQP getIndexQP(QPN qpn);
    QpnRawIndexPart indexPart = unpack(truncateLSB(qpn));
    return unpack(truncate(indexPart));
endfunction 

function QPN genQPN(IndexQP qpIndex, KeyQP qpKey);
    return zeroExtend({ pack(qpIndex), pack(qpKey) });
endfunction

function QpnRawIndexPart getQpnRawIndexPart(QPN qpn) = unpack(truncateLSB(qpn));



// WorkReq related

typedef enum {
    IBV_WR_RDMA_WRITE           =  0,
    IBV_WR_RDMA_WRITE_WITH_IMM  =  1,
    IBV_WR_SEND                 =  2,
    IBV_WR_SEND_WITH_IMM        =  3,
    IBV_WR_RDMA_READ            =  4,
    IBV_WR_ATOMIC_CMP_AND_SWP   =  5,
    IBV_WR_ATOMIC_FETCH_AND_ADD =  6,
    IBV_WR_LOCAL_INV            =  7,
    IBV_WR_BIND_MW              =  8,
    IBV_WR_SEND_WITH_INV        =  9,
    IBV_WR_TSO                  = 10,
    IBV_WR_DRIVER1              = 11,
    IBV_WR_RDMA_READ_RESP       = 12, // Not defined in rdma-core
    IBV_WR_RDMA_ACK             = 13, // Not defined in rdma-core
    IBV_WR_FLUSH                = 14,
    IBV_WR_ATOMIC_WRITE         = 15
} WorkReqOpCode deriving(Bits, Eq, FShow);

typedef enum {
    IBV_SEND_NO_FLAGS  = 0, // Not defined in rdma-core
    IBV_SEND_FENCE     = 1,
    IBV_SEND_SIGNALED  = 2,
    IBV_SEND_SOLICITED = 4,
    IBV_SEND_INLINE    = 8,
    IBV_SEND_IP_CSUM   = 16
} WorkReqSendFlag deriving(Bits, Eq, FShow);

instance Flags#(WorkReqSendFlag);
    function Bool isOneHotOrZero(WorkReqSendFlag inputVal) = 1 >= countOnes(pack(inputVal));
endinstance


// MR related
typedef 8 MR_KEY_PART_WIDTH;

typedef TLog#(MAX_MR) MR_INDEX_SUPPORTED_WIDTH;
typedef TSub#(KEY_WIDTH, MR_KEY_PART_WIDTH) MR_INDEX_PART_WIDTH;

typedef UInt#(MR_INDEX_SUPPORTED_WIDTH) IndexMR;
typedef Bit#(MR_KEY_PART_WIDTH) KeyPartMR;
typedef Bit#(MR_INDEX_PART_WIDTH) MrRawIndexPart;


// QP Context Related

typedef 8 QPC_QUERY_RESP_MAX_DELAY;

typedef struct {
    QPN  qpn;
    Bool needCheckKey;
} ReadReqQPC deriving(Bits, Eq, FShow);

typedef struct {
    QPN  qpn;
    Maybe#(EntryQPC)  ent;
} WriteReqQPC deriving(Bits, Eq, FShow);

typedef struct {
    KeyQP                           qpnKeyPart;         // TSub#(QPN_WIDTH, QP_INDEX_WIDTH_SUPPORTED) bits = 24-11 = 13 bits
    TypeQP                          qpType;             // 4 bits
    FlagsType#(MemAccessTypeFlag)   rqAccessFlags;      // 8 bits
    PMTU                            pmtu;               // 3 bits
    QPN                             peerQPN;            // 24 bits
    EthMacAddr                      peerMacAddr;        // 48  bits
    IpAddr                          peerIpAddr;         // 32  bits
    UdpPort                         localUdpPort;       // 16  bits
} EntryQPC deriving(Bits, Eq, FShow);



typedef struct {
    // Fields from BTH  // total 60 bits
    TransType trans;    // 3
    RdmaOpCode opcode;  // 5
    Bool solicited;     // 1
    QPN dqpn;           // 24
    Bool ackReq;        // 1
    PSN psn;            // 24
    PAD padCnt;         // 2

    // Fields from RETH // total 128 bits
    ADDR va;            // 64
    RKEY rkey;          // 32
    Length dlen;        // 32

    // Fields from Secondary RETH    // total 96 bits
    ADDR secondaryVa;                // 64
    RKEY secondaryRkey;              // 32

    // Fields from AETH    // total 96 bits
    AethCode                code;         // 2
    AethValue               value;        // 5
    MSN                     msn;          // 24
    PSN                     lastRetryPSN; // 24

    // Fields from ImmDT   // total 32 bits
    IMM                     immDt;        // 32

    // Fields generated by RQ logic  // total 8 bits
    RdmaRecvPacketStatus           reqStatus;    // 8 

    // Ack related                   // total 25 bits
    PSN                     expectedPsn;  // 24
    Bool                    canAutoAck;   // 1
    
} C2hReportEntry deriving(Bits);

// Note, the msb of this type indicate if some error has occured
typedef enum {
    RdmaRecvPacketStatusNormal                 =   0, //   0 +   0
    RdmaRecvPacketStatusInvalidQpAccessFlag    = 128, // 128 +   0
    RdmaRecvPacketStatusInvalidOpcode          = 129, // 128 +   1
    RdmaRecvPacketStatusInvalidMrKey           = 130, // 128 +   2
    RdmaRecvPacketStatusMemAccessOutOfBound    = 131, // 128 +   3
    RdmaRecvPacketStatusInvalidMrAccessFlag    = 132, // 128 +   4
    RdmaRecvPacketStatusInvalidHeader          = 133, // 128 +   5
    RdmaRecvPacketStatusInvalidQpContext       = 134, // 128 +   6
    RdmaRecvPacketStatusCorruptPktLength       = 135, // 128 +   7
    RdmaRecvPacketStatusQpIdxOverflow          = 136, // 128 +   8
    RdmaRecvPacketStatusMrIdxOverflow          = 137, // 128 +   9
    RdmaRecvPacketStatusUnknown                = 255  // 128 + 127
} RdmaRecvPacketStatus deriving(Bits, Eq, FShow);


// Received payload stream related

typedef 9 INPUT_STREAM_FRAG_BUFFER_INDEX_WITHOUT_GUARD_WIDTH;
// typedef Bit#(INPUT_STREAM_FRAG_BUFFER_INDEX_WITHOUT_GUARD_WIDTH) InputStreamFragBufferIdxWithoutGuard; 

typedef TAdd#(1, INPUT_STREAM_FRAG_BUFFER_INDEX_WITHOUT_GUARD_WIDTH) INPUT_STREAM_FRAG_BUFFER_INDEX_WIDTH;
typedef Bit#(INPUT_STREAM_FRAG_BUFFER_INDEX_WIDTH) InputStreamFragBufferIdx; 

typedef struct {
    BusByteCnt                byteNum;
    Bool                        isFirst;
    Bool                        isLast;
    Bool                        isEmpty;
    InputStreamFragBufferIdx    bufIdx;
} DataStreamFragMetaData deriving(Bits, FShow);

typedef PipeOut#(DataStreamFragMetaData) DataStreamFragMetaPipeOut;
typedef Put#(DataStreamFragMetaData) DataStreamFragMetaPipeIn;

typedef 9 RAW_PACKET_RECV_BUFFER_INDEX_WIDTH;    // 512 Slots
typedef Bit#(RAW_PACKET_RECV_BUFFER_INDEX_WIDTH) RawPacketRecvBufIndex;

typedef struct {
    ADDR writeBaseAddr;
} RawPacketReceiveMeta deriving(Bits, FShow);

typedef 4 FORCE_REPORT_HEADER_META_INTERVAL_MASK_WIDTH;

typedef struct {
    PSN  expectedPSN;
    PSN  latestErrorPSN;
    Bool isQpPsnContinous;
} ExpectedPsnContextEntry deriving(Bits, FShow);

typedef struct {
    IndexQP    qpnIdx;
    PSN        newIncomingPSN;
    Bool       isPacketStateAbnormal;
} ExpectedPsnCheckReq deriving(Bits, FShow);


typedef struct {
    PSN        expectedPSN;
    Bool       isQpPsnContinous;
    Bool       isAdjacentPsnContinous;
} ExpectedPsnCheckResp deriving(Bits, FShow);

typedef 6 RECV_PACKET_SRC_MAC_IP_BUFFER_INDEX_WIDTH;
typedef Bit#(RECV_PACKET_SRC_MAC_IP_BUFFER_INDEX_WIDTH) RecvPacketSrcMacIpBufferIdx; 

typedef struct {
    IpAddr ip;
    EthMacAddr macAddr;
} RecvPacketSrcMacIpBufferEntry deriving(Bits, FShow);


// FlagsType related

typeclass Flags#(type enumType);
    function Bool isOneHotOrZero(enumType inputVal);
endtypeclass

instance FShow#(FlagsType#(enumType)) provisos(
    Bits#(enumType, tSz),
    FShow#(enumType)
);
    function Fmt fshow(FlagsType#(enumType) inputVal);
        Bit#(tSz) enumBits = pack(inputVal);

        Fmt resultFmt = $format("FlagsType { flags: ", pack(inputVal), " = ");
        for (Integer idx = 0; idx < valueOf(tSz); idx = idx + 1) begin
            Bool bitValid = unpack(enumBits[idx]);
            enumType enumVal = unpack(1 << idx);
            if (bitValid) begin
                resultFmt = resultFmt + $format(fshow(enumVal), " | ");
            end
        end

        if (enumBits == 0) begin
            enumType enumVal = unpack(0);
            resultFmt = resultFmt + $format(fshow(enumVal), " }");
        end
        else begin
            resultFmt = resultFmt + $format("}");
        end
        return resultFmt;
    endfunction
endinstance

typedef struct {
    Bit#(SizeOf#(enumType)) flags;
} FlagsType#(type enumType) deriving(Bits, Bitwise, Eq);