import Reserved :: *;


typedef 3 PCIE_HEADER_FIELD_FMT_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_FMT_WIDTH) PcieHeaderFieldFmt;

typedef 5 PCIE_HEADER_FIELD_TYPE_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_TYPE_WIDTH) PcieHeaderFieldType;

typedef 10 PCIE_HEADER_FIELD_LENGTH_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_LENGTH_WIDTH) PcieHeaderFieldLength;

typedef 3 PCIE_HEADER_FIELD_TC_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_TC_WIDTH) PcieHeaderFieldTc;

typedef 2 PCIE_HEADER_FIELD_ATTR_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_ATTR_WIDTH) PcieHeaderFieldAttr;

typedef 2 PCIE_HEADER_FIELD_AT_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_AT_WIDTH) PcieHeaderFieldAt;

typedef 16 PCIE_HEADER_FIELD_REQUESTER_ID_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_REQUESTER_ID_WIDTH) PcieHeaderFieldRequesterId;

typedef 8 PCIE_HEADER_FIELD_TAG_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_TAG_WIDTH) PcieHeaderFieldTag;

typedef 8 PCIE_HEADER_FIELD_ST_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_ST_WIDTH) PcieHeaderFieldSt;

typedef 4 PCIE_HEADER_FIELD_LAST_DW_BE_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_LAST_DW_BE_WIDTH) PcieHeaderFieldLastDwBe;

typedef 4 PCIE_HEADER_FIELD_FIRST_DW_BE_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_FIRST_DW_BE_WIDTH) PcieHeaderFieldFirstDwBe;

typedef 16 PCIE_HEADER_FIELD_COMPLETER_ID_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_COMPLETER_ID_WIDTH) PcieHeaderFieldCompleterId;

typedef 3 PCIE_HEADER_FIELD_CPLT_STATUS_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_CPLT_STATUS_WIDTH) PcieHeaderFieldCpltStatus;

typedef 12 PCIE_HEADER_FIELD_BYTE_COUNT_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_BYTE_COUNT_WIDTH) PcieHeaderFieldByteCount;

typedef 7 PCIE_HEADER_FIELD_LOWER_ADDRESS_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_LOWER_ADDRESS_WIDTH) PcieHeaderFieldLowerAddress;

typedef 30 PCIE_HEADER_FIELD_32_BIT_ADDR_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_32_BIT_ADDR_WIDTH) PcieHeaderField32BitAddr;

typedef 62 PCIE_HEADER_FIELD_64_BIT_ADDR_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_64_BIT_ADDR_WIDTH) PcieHeaderField64BitAddr;

typedef 2 PCIE_HEADER_FIELD_PH_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_PH_WIDTH) PcieHeaderFieldPh;

typedef 10 PCIE_HEADER_FIELD_EXTENDED_TAG_WIDTH;
typedef Bit#(PCIE_HEADER_FIELD_EXTENDED_TAG_WIDTH) PcieHeaderFieldExtendedTag;



typedef struct {
    PcieHeaderFieldFmt      fmt;
    PcieHeaderFieldType     typ;
    Bool                    t9;
    PcieHeaderFieldTc       tc;
    Bool                    t8;
    Bool                    attrh;
    Bool                    ln;
    Bool                    th;
    Bool                    td;
    Bool                    ep;
    PcieHeaderFieldAttr     attrl;
    PcieHeaderFieldAt       at;
    PcieHeaderFieldLength   length;
} PcieTlpHeaderCommon deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderCommon         commonHeader;
    PcieHeaderFieldRequesterId  requesterId;
    PcieHeaderFieldTag          tag;
    PcieHeaderFieldLastDwBe     lastDwBe;
    PcieHeaderFieldFirstDwBe    firstDwBe;
} PcieTlpHeaderMemoryAccess deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderCommon         commonHeader;
    PcieHeaderFieldRequesterId  requesterId;
    PcieHeaderFieldTag          tag;
    PcieHeaderFieldLastDwBe     lastDwBe;
    PcieHeaderFieldFirstDwBe    firstDwBe;
} PcieTlpHeaderMemoryRead deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderCommon         commonHeader;
    PcieHeaderFieldRequesterId  requesterId;
    PcieHeaderFieldSt           st;
    PcieHeaderFieldLastDwBe     lastDwBe;
    PcieHeaderFieldFirstDwBe    firstDwBe;
} PcieTlpHeaderMemoryWrite deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderMemoryWrite    memoryWriteHeader;
    PcieHeaderField64BitAddr    addr;
    PcieHeaderFieldPh           ph;
} PcieTlpHeaderMemoryWrite4Dw deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderMemoryRead     memoryReadHeader;
    PcieHeaderField64BitAddr    addr;
    PcieHeaderFieldPh           ph;
} PcieTlpHeaderMemoryRead4Dw deriving(Bits, FShow);


typedef struct {
    PcieTlpHeaderMemoryWrite    memoryWriteHeader;
    PcieHeaderField32BitAddr    addr;
    PcieHeaderFieldPh           ph;
} PcieTlpHeaderMemoryWrite3Dw deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderMemoryRead     memoryReadHeader;
    PcieHeaderField32BitAddr    addr;
    PcieHeaderFieldPh           ph;
} PcieTlpHeaderMemoryRead3Dw deriving(Bits, FShow);

typedef struct {
    PcieTlpHeaderCommon         commonHeader;
    PcieHeaderFieldCompleterId  completerId;
    PcieHeaderFieldCpltStatus   cpltStatus;
    Bool                        bcm;
    PcieHeaderFieldByteCount    byteCount;
    PcieHeaderFieldRequesterId  requesterId;
    PcieHeaderFieldTag          tag;
    ReservedZero#(1)            rsv1;
    PcieHeaderFieldLowerAddress lowerAddress;
} PcieTlpHeaderCompletion deriving(Bits, FShow);