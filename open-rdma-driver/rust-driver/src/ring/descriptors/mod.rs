#![allow(clippy::missing_docs_in_private_items)]
#![allow(clippy::too_many_arguments, clippy::fn_params_excessive_bools)] // FIXME: use builder

/// Cmd queue pair descriptors
pub(crate) mod cmd;

/// Simple NIC descriptors
pub(crate) mod simple_nic;

/// Meta report queue descriptors
pub(crate) mod meta_report;

/// Send queue descriptors
pub(crate) mod send;

pub(crate) use cmd::*;
pub(crate) use meta_report::*;
pub(crate) use send::*;

use bilge::prelude::*;

use crate::ring::traits::{DescDeserialize, DescSerialize};
use crate::workers::send::WorkReqOpCode;

/// Size of a descriptor in bytes.
pub(crate) const DESC_SIZE: usize = 32;

// NOTE: The `#[bitsize]` macro errors shown by rust-analyzer is a false-positive

/// Implements the `DescSerde` trait
#[macro_export]
macro_rules! impl_desc_serde {
    ($($t:ty),*) => {
        $(
            impl DescSerialize for $t {
                fn serialize(&self) -> [u8; 32] {
                    bytemuck::cast([
                        self.c0.value,
                        self.c1.value,
                        self.c2.value,
                        self.c3.value,
                    ])
                }
            }

            impl DescDeserialize for $t {
                fn deserialize(d: [u8; 32]) -> Self {
                    let t: [u64; 4] = bytemuck::cast(d);
                    Self {
                        c0: t[0].into(),
                        c1: t[1].into(),
                        c2: t[2].into(),
                        c3: t[3].into(),
                    }
                }
            }
        )*
    }
}

#[bitsize(16)]
#[derive(Default, Clone, Copy, DebugBits, FromBits)]
struct RingBufDescCommonHead {
    pub op_code: u8,
    pub is_extended_op_code: bool,
    reserved0: u5,
    pub has_next: bool,
    pub valid: bool,
}

#[allow(clippy::as_conversions)] // converting `repr(u8)` enum variants to u8
impl RingBufDescCommonHead {
    fn new_cmd_desc(operator: CmdQueueDescOperators) -> Self {
        Self::new_with_op_code(operator as u8)
    }
    fn new_send_desc(opcode: WorkReqOpCode) -> Self {
        Self::new_with_op_code(opcode as u8)
    }
    /// Creates a new `SimpleNicTxQueueDesc` header
    fn new_simple_nic_desc() -> Self {
        Self::new_with_op_code(0)
    }
    /// Creates a new header with given op code
    fn new_with_op_code(op_code: u8) -> Self {
        let mut this: Self = 0.into();
        this.set_op_code(op_code);
        this.set_valid(true);
        this
    }
}

#[bitsize(64)]
#[derive(Clone, Copy, DebugBits, FromBits)]
struct MetaReportQueueDescBthRethChunk0 {
    pub expected_psn: u24,
    pub req_status: u8,

    // BTH
    pub trans: u3,
    pub opcode: u5,
    pub dqpn: u24,
}

#[bitsize(64)]
#[derive(Clone, Copy, DebugBits, FromBits)]
struct MetaReportQueueDescBthRethChunk1 {
    pub psn: u24,
    pub solicited: bool,
    pub ack_req: bool,
    pub pad_cnt: u2,
    pub reserved1: u4,

    // RETH
    pub rkey: u32,
}

#[bitsize(64)]
#[derive(Clone, Copy, DebugBits, FromBits)]
struct MetaReportQueueDescBthRethChunk2 {
    pub va: u64,
}

#[bitsize(64)]
#[derive(Clone, Copy, DebugBits, FromBits)]
struct MetaReportQueueDescBthRethChunk3 {
    pub dlen: u32,

    pub msn: u24,
    reserved: u7,
    pub can_auto_ack: bool,
}

#[repr(C)]
/// RDMA Normal Packet Header Descriptor
#[allow(clippy::missing_docs_in_private_items)]
pub(crate) struct MetaReportQueueDescBthReth {
    c0: MetaReportQueueDescBthRethChunk0,
    c1: MetaReportQueueDescBthRethChunk1,
    c2: MetaReportQueueDescBthRethChunk2,
    c3: MetaReportQueueDescBthRethChunk3,
}

#[allow(missing_docs, clippy::missing_docs_in_private_items, unused)] // method delegations
impl MetaReportQueueDescBthReth {
    pub(crate) fn expected_psn(&self) -> u32 {
        self.c0.expected_psn().into()
    }
    pub(crate) fn set_expected_psn(&mut self, val: u32) {
        self.c0.set_expected_psn(u24::masked_new(val));
    }
    pub(crate) fn req_status(&self) -> u8 {
        self.c0.req_status()
    }
    pub(crate) fn set_req_status(&mut self, val: u8) {
        self.c0.set_req_status(val);
    }
    pub(crate) fn trans(&self) -> u8 {
        self.c0.trans().into()
    }
    pub(crate) fn set_trans(&mut self, val: u8) {
        self.c0.set_trans(u3::masked_new(val));
    }
    pub(crate) fn opcode(&self) -> u8 {
        self.c0.opcode().into()
    }
    pub(crate) fn set_opcode(&mut self, val: u8) {
        self.c0.set_opcode(u5::masked_new(val));
    }
    pub(crate) fn dqpn(&self) -> u32 {
        self.c0.dqpn().into()
    }
    pub(crate) fn set_dqpn(&mut self, val: u32) {
        self.c0.set_dqpn(u24::masked_new(val));
    }
    pub(crate) fn psn(&self) -> u32 {
        self.c1.psn().into()
    }
    pub(crate) fn set_psn(&mut self, val: u32) {
        self.c1.set_psn(u24::masked_new(val));
    }
    pub(crate) fn solicited(&self) -> bool {
        self.c1.solicited()
    }
    pub(crate) fn set_solicited(&mut self, val: bool) {
        self.c1.set_solicited(val);
    }
    pub(crate) fn ack_req(&self) -> bool {
        self.c1.ack_req()
    }
    pub(crate) fn set_ack_req(&mut self, val: bool) {
        self.c1.set_ack_req(val);
    }
    pub(crate) fn pad_cnt(&self) -> u8 {
        self.c1.pad_cnt().into()
    }
    pub(crate) fn set_pad_cnt(&mut self, val: u8) {
        self.c1.set_pad_cnt(u2::masked_new(val));
    }
    pub(crate) fn rkey(&self) -> u32 {
        self.c1.rkey()
    }
    pub(crate) fn set_rkey(&mut self, val: u32) {
        self.c1.set_rkey(val);
    }
    pub(crate) fn va(&self) -> u64 {
        self.c2.va()
    }
    pub(crate) fn set_va(&mut self, val: u64) {
        self.c2.set_va(val);
    }
    pub(crate) fn dlen(&self) -> u32 {
        self.c3.dlen()
    }
    pub(crate) fn set_dlen(&mut self, val: u32) {
        self.c3.set_dlen(val);
    }
    pub(crate) fn msn(&self) -> u32 {
        self.c3.msn().into()
    }
    pub(crate) fn set_msn(&mut self, val: u32) {
        self.c3.set_msn(u24::masked_new(val));
    }
    pub(crate) fn can_auto_ack(&self) -> bool {
        self.c3.can_auto_ack()
    }
    pub(crate) fn set_can_auto_ack(&mut self, val: bool) {
        self.c3.set_can_auto_ack(val);
    }
}

impl_desc_serde!(MetaReportQueueDescBthReth);
