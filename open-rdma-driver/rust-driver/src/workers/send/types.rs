use std::marker::PhantomData;

use crossbeam_deque::{Injector, Stealer, Worker};

use crate::{
    rdma_utils::{psn::Psn, qp::convert_ibv_mtu_to_u16},
    types::{RemoteAddr, VirtAddr},
};

/// Injector
pub(super) type WrInjector = Injector<WrChunk>;
/// Stealer
pub(super) type WrStealer = Stealer<WrChunk>;
/// Worker
pub(super) type WrWorker = Worker<WrChunk>;

// /// A transmit queue for the send operations
// pub(crate) struct SendQueue<Dev: DeviceAdaptor> {
//     /// Inner producer ring buffer
//     inner: ProducerRingDefault<Dev, SendRingSpec>,
// }

// impl<Dev: DeviceAdaptor> SendQueue<Dev> {
//     pub(crate) fn new(ring: ProducerRingDefault<Dev, SendRingSpec>) -> Self {
//         Self { inner: ring }
//     }

//     pub(crate) fn push(&mut self, desc: SendQueueDesc) -> bool {
//         self.inner.try_push(desc).unwrap()
//     }

//     /// Returns the head pointer of the buffer
//     pub(crate) fn head(&self) -> u32 {
//         self.inner.head()
//     }

//     #[allow(clippy::cast_possible_truncation)]
//     pub(crate) fn remaining(&mut self) -> usize {
//         self.inner.available().unwrap() as usize
//     }
// }

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct Initial;
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct WithQpParams;
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct WithIbvParams;
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct WithChunkInfo;

/// Work Request Builder
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct WrChunkBuilder<S> {
    inner: WrChunk,
    _state: PhantomData<S>,
}

impl WrChunkBuilder<Initial> {
    pub(crate) fn new() -> Self {
        Self {
            inner: WrChunk::default(),
            _state: PhantomData,
        }
    }

    pub(crate) fn new_with_opcode(opcode: WorkReqOpCode) -> Self {
        let inner = WrChunk {
            opcode,
            ..Default::default()
        };
        Self {
            inner,
            _state: PhantomData,
        }
    }

    #[allow(clippy::unused_self, clippy::too_many_arguments)]
    pub(crate) fn set_qp_params(mut self, qp_params: QpParams) -> WrChunkBuilder<WithQpParams> {
        self.inner.qp_type = qp_params.qp_type;
        self.inner.sqpn = qp_params.sqpn;
        self.inner.mac_addr = qp_params.mac_addr;
        self.inner.dqpn = qp_params.dqpn;
        self.inner.dqp_ip = qp_params.dqp_ip;
        self.inner.pmtu = qp_params.pmtu;
        self.inner.msn = qp_params.msn;

        WrChunkBuilder {
            inner: self.inner,
            _state: PhantomData,
        }
    }
}

impl WrChunkBuilder<WithQpParams> {
    pub(crate) fn set_ibv_params(
        mut self,
        flags: u8,
        rkey: u32,
        total_len: u32,
        lkey: u32,
        imm: u32,
    ) -> WrChunkBuilder<WithIbvParams> {
        self.inner.flags = flags;
        self.inner.rkey = rkey;
        self.inner.total_len = total_len;
        self.inner.lkey = lkey;
        self.inner.imm = imm;

        WrChunkBuilder {
            inner: self.inner,
            _state: PhantomData,
        }
    }

    pub(crate) fn pmtu(&self) -> u16 {
        convert_ibv_mtu_to_u16(self.inner.pmtu).unwrap_or_else(|| unreachable!("invalid ibv_mtu"))
    }
}

impl WrChunkBuilder<WithIbvParams> {
    pub(crate) fn set_chunk_meta(
        mut self,
        psn: Psn,
        laddr: u64,
        raddr: u64,
        len: u32,
        pos: ChunkPos,
    ) -> WrChunkBuilder<WithChunkInfo> {
        self.inner.psn = psn;
        self.inner.laddr = VirtAddr::new(laddr);
        self.inner.raddr = RemoteAddr::new(raddr);
        self.inner.len = len;
        match pos {
            ChunkPos::First => self.inner.is_first = true,
            ChunkPos::Last => self.inner.is_last = true,
            ChunkPos::Middle => {}
            ChunkPos::Only => {
                self.inner.is_first = true;
                self.inner.is_last = true;
            }
        }

        WrChunkBuilder {
            inner: self.inner,
            _state: PhantomData,
        }
    }

    pub(crate) fn pmtu(&self) -> u16 {
        convert_ibv_mtu_to_u16(self.inner.pmtu).unwrap_or_else(|| unreachable!("invalid ibv_mtu"))
    }
}

impl WrChunkBuilder<WithChunkInfo> {
    pub(crate) fn set_is_retry(mut self) -> Self {
        self.inner.is_retry = true;
        self
    }

    pub(crate) fn set_enable_ecn(mut self) -> Self {
        self.inner.enable_ecn = true;
        self
    }

    pub(crate) fn build(self) -> WrChunk {
        self.inner
    }
}

#[allow(clippy::struct_excessive_bools)]
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct WrChunk {
    pub(crate) opcode: WorkReqOpCode,
    pub(crate) qp_type: u8,
    pub(crate) sqpn: u32,
    pub(crate) mac_addr: u64,
    pub(crate) dqpn: u32,
    pub(crate) dqp_ip: u32,
    pub(crate) pmtu: u8,
    pub(crate) flags: u8,
    pub(crate) raddr: RemoteAddr,
    pub(crate) rkey: u32,
    pub(crate) total_len: u32,
    pub(crate) lkey: u32,
    pub(crate) imm: u32,
    pub(crate) laddr: VirtAddr,
    pub(crate) len: u32,
    pub(crate) is_first: bool,
    pub(crate) is_last: bool,
    pub(crate) msn: u16,
    pub(crate) psn: Psn,
    pub(crate) is_retry: bool,
    pub(crate) enable_ecn: bool,
}

impl WrChunk {
    pub(crate) fn set_is_retry(&mut self) {
        self.is_retry = true;
    }
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ChunkPos {
    #[default]
    First,
    Middle,
    Last,
    Only,
}

impl ChunkPos {
    pub(crate) fn next(self) -> Self {
        match self {
            ChunkPos::First | ChunkPos::Middle => ChunkPos::Middle,
            ChunkPos::Last => ChunkPos::Last,
            ChunkPos::Only => ChunkPos::Only,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct QpParams {
    pub(crate) msn: u16,
    pub(crate) qp_type: u8,
    pub(crate) sqpn: u32,
    pub(crate) mac_addr: u64,
    pub(crate) dqpn: u32,
    pub(crate) dqp_ip: u32,
    pub(crate) pmtu: u8,
}

impl QpParams {
    pub(crate) fn new(
        msn: u16,
        qp_type: u8,
        sqpn: u32,
        mac_addr: u64,
        dqpn: u32,
        dqp_ip: u32,
        pmtu: u8,
    ) -> Self {
        Self {
            msn,
            qp_type,
            sqpn,
            mac_addr,
            dqpn,
            dqp_ip,
            pmtu,
        }
    }
}

#[derive(Default, Debug, PartialEq, Eq, Clone, Copy)]
#[repr(u8)]
pub(crate) enum WorkReqOpCode {
    #[default]
    RdmaWrite = 0,
    RdmaWriteWithImm = 1,
    Send = 2,
    SendWithImm = 3,
    RdmaRead = 4,
    AtomicCmpAndSwp = 5,
    AtomicFetchAndAdd = 6,
    LocalInv = 7,
    BindMw = 8,
    SendWithInv = 9,
    Tso = 10,
    Driver1 = 11,
    RdmaReadResp = 12,
    RdmaAck = 13,
    Flush = 14,
    AtomicWrite = 15,
}
