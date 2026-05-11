use bincode::{Decode, Encode};
use ibverbs_sys::{
    ibv_send_wr,
    ibv_wr_opcode::{
        IBV_WR_RDMA_READ, IBV_WR_RDMA_WRITE, IBV_WR_RDMA_WRITE_WITH_IMM, IBV_WR_SEND,
        IBV_WR_SEND_WITH_IMM,
    },
};
use serde::{Deserialize, Serialize};

use crate::{
    types::{RemoteAddr, VirtAddr},
    workers::send::WorkReqOpCode,
    RdmaError,
};

#[derive(Debug, Clone, Copy)]
pub(crate) enum SendWr {
    Rdma(SendWrRdma),
    Send(SendWrBase),
}

impl SendWr {
    #[allow(unsafe_code)]
    /// Creates a new `SendWr`
    pub(crate) fn new(wr: ibv_send_wr) -> crate::error::Result<Self> {
        let num_sge = usize::try_from(wr.num_sge)
            .map_err(|e| RdmaError::InvalidInput(format!("Invalid SGE count: {e}")))?;

        if num_sge > 1 {
            return Err(RdmaError::Unimplemented(format!(
                "Only 0 or 1 SGE supported, got {}",
                num_sge
            )));
        }

        // Extract SGE information, handling num_sge = 0 case
        let (laddr, length, lkey) = if num_sge == 1 {
            // SAFETY: sg_list is valid when num_sge > 0
            let sge = unsafe { *wr.sg_list };
            (sge.addr, sge.length, sge.lkey)
        } else {
            // num_sge = 0: Zero-byte operation (e.g., RDMA_WRITE_WITH_IMM with immediate data only)
            (0, 0, 0)
        };

        // only with imm can support num_sge == 0
        if num_sge == 0 {
            let has_imm =
                wr.opcode == IBV_WR_RDMA_WRITE_WITH_IMM || wr.opcode == IBV_WR_SEND_WITH_IMM;
            if !has_imm {
                return Err(RdmaError::InvalidInput(format!(
                    "Only IBV_WR_RDMA_WRITE_WITH_IMM or IBV_WR_SEND_WITH_IMM  supported SGE == 0, got {}",
                    wr.opcode
                )));
            }
        }

        let opcode = match wr.opcode {
            IBV_WR_RDMA_WRITE => WorkReqOpCode::RdmaWrite,
            IBV_WR_RDMA_WRITE_WITH_IMM => WorkReqOpCode::RdmaWriteWithImm,
            IBV_WR_RDMA_READ => WorkReqOpCode::RdmaRead,
            IBV_WR_SEND => WorkReqOpCode::Send,
            IBV_WR_SEND_WITH_IMM => WorkReqOpCode::SendWithImm,
            _ => {
                return Err(RdmaError::Unimplemented(format!(
                    "Opcode {} not supported",
                    wr.opcode
                )))
            }
        };

        let base = SendWrBase {
            wr_id: wr.wr_id,
            send_flags: wr.send_flags,
            laddr: VirtAddr::new(laddr),
            length,
            lkey,
            // SAFETY: imm_data is valid for operations with immediate data
            imm_data: unsafe { wr.__bindgen_anon_1.imm_data },
            opcode,
        };

        match wr.opcode {
            IBV_WR_RDMA_WRITE | IBV_WR_RDMA_WRITE_WITH_IMM | IBV_WR_RDMA_READ => {
                let wr = SendWrRdma {
                    base,
                    // SAFETY: rdma field is valid for RDMA operations
                    raddr: RemoteAddr::new(unsafe { wr.wr.rdma.remote_addr }),
                    rkey: unsafe { wr.wr.rdma.rkey },
                };
                Ok(Self::Rdma(wr))
            }
            IBV_WR_SEND | IBV_WR_SEND_WITH_IMM => Ok(Self::Send(base)),
            _ => Err(RdmaError::Unimplemented("opcode not supported".into())),
        }
    }

    pub(crate) fn wr_id(&self) -> u64 {
        match *self {
            SendWr::Rdma(wr) => wr.base.wr_id,
            SendWr::Send(wr) => wr.wr_id,
        }
    }
    pub(crate) fn send_flags(&self) -> u32 {
        match *self {
            SendWr::Rdma(wr) => wr.base.send_flags,
            SendWr::Send(wr) => wr.send_flags,
        }
    }

    pub(crate) fn laddr(&self) -> VirtAddr {
        match *self {
            SendWr::Rdma(wr) => wr.base.laddr,
            SendWr::Send(wr) => wr.laddr,
        }
    }

    pub(crate) fn length(&self) -> u32 {
        match *self {
            SendWr::Rdma(wr) => wr.base.length,
            SendWr::Send(wr) => wr.length,
        }
    }

    pub(crate) fn lkey(&self) -> u32 {
        match *self {
            SendWr::Rdma(wr) => wr.base.lkey,
            SendWr::Send(wr) => wr.lkey,
        }
    }

    pub(crate) fn imm_data(&self) -> u32 {
        match *self {
            SendWr::Rdma(wr) => wr.base.imm_data,
            SendWr::Send(wr) => wr.imm_data,
        }
    }
}

impl From<SendWrRdma> for SendWr {
    fn from(wr: SendWrRdma) -> Self {
        SendWr::Rdma(wr)
    }
}

impl From<SendWrBase> for SendWr {
    fn from(wr: SendWrBase) -> Self {
        SendWr::Send(wr)
    }
}

/// A resolver and validator for send work requests
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) struct SendWrRdma {
    pub(crate) base: SendWrBase,
    pub(crate) raddr: RemoteAddr,
    pub(crate) rkey: u32,
}

impl std::fmt::Debug for SendWrRdma {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SendWrRdma")
            .field("base", &self.base)
            .field("raddr", &format_args!("{:x}", self.raddr))
            .field("rkey", &self.rkey)
            .finish()
    }
}

impl SendWrRdma {
    #[allow(unsafe_code)]
    /// Creates a new resolver from the given work request.
    /// Returns None if the input is invalid
    pub(crate) fn new(wr: ibv_send_wr) -> crate::error::Result<Self> {
        match wr.opcode {
            IBV_WR_RDMA_WRITE | IBV_WR_RDMA_WRITE_WITH_IMM => {}
            _ => {
                return Err(RdmaError::Unimplemented(format!(
                    "Opcode {} not supported for RDMA operations",
                    wr.opcode
                )))
            }
        }

        let num_sge = usize::try_from(wr.num_sge)
            .map_err(|e| RdmaError::InvalidInput(format!("Invalid SGE count: {e}")))?;

        if num_sge != 1 {
            return Err(RdmaError::Unimplemented(
                "Only support for single SGE in RDMA operations".into(),
            ));
        }

        // SAFETY: sg_list is valid when num_sge > 0, which we've verified above
        let sge = unsafe { *wr.sg_list };

        let opcode = match wr.opcode {
            IBV_WR_RDMA_WRITE => WorkReqOpCode::RdmaWrite,
            IBV_WR_RDMA_WRITE_WITH_IMM => WorkReqOpCode::RdmaWriteWithImm,
            IBV_WR_RDMA_READ => WorkReqOpCode::RdmaRead,
            IBV_WR_SEND => WorkReqOpCode::Send,
            IBV_WR_SEND_WITH_IMM => WorkReqOpCode::SendWithImm,
            _ => return Err(RdmaError::Unimplemented("opcode not supported".into())),
        };

        Ok(Self {
            base: SendWrBase {
                wr_id: wr.wr_id,
                send_flags: wr.send_flags,
                laddr: VirtAddr::new(sge.addr),
                length: sge.length,
                lkey: sge.lkey,
                // SAFETY: imm_data is valid for operations with immediate data
                imm_data: unsafe { wr.__bindgen_anon_1.imm_data },
                opcode,
            },
            // SAFETY: rdma field is valid for RDMA operations
            raddr: RemoteAddr::new(unsafe { wr.wr.rdma.remote_addr }),
            rkey: unsafe { wr.wr.rdma.rkey },
        })
    }

    pub(crate) fn new_from_base(base: SendWrBase, raddr: RemoteAddr, rkey: u32) -> SendWrRdma {
        Self { base, raddr, rkey }
    }

    /// Returns the local address of the SGE buffer
    #[inline]
    pub(crate) fn laddr(&self) -> VirtAddr {
        self.base.laddr
    }

    /// Returns the length of the SGE buffer in bytes
    #[inline]
    pub(crate) fn length(&self) -> u32 {
        self.base.length
    }

    /// Returns the local key associated with the SGE buffer
    #[inline]
    pub(crate) fn lkey(&self) -> u32 {
        self.base.lkey
    }

    /// Returns the remote memory address for RDMA operations
    #[inline]
    pub(crate) fn raddr(&self) -> RemoteAddr {
        self.raddr
    }

    /// Returns the remote key for RDMA operations
    #[inline]
    pub(crate) fn rkey(&self) -> u32 {
        self.rkey
    }

    /// Returns the immediate data value
    #[inline]
    pub(crate) fn imm(&self) -> u32 {
        self.base.imm_data
    }

    /// Returns the send flags
    #[inline]
    pub(crate) fn send_flags(&self) -> u32 {
        self.base.send_flags
    }

    /// Returns the ID associated with this WR
    #[inline]
    pub(crate) fn wr_id(&self) -> u64 {
        self.base.wr_id
    }

    pub(crate) fn opcode(&self) -> WorkReqOpCode {
        self.base.opcode
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) struct SendWrBase {
    pub(crate) wr_id: u64,
    pub(crate) send_flags: u32,
    pub(crate) laddr: VirtAddr,
    pub(crate) length: u32,
    pub(crate) lkey: u32,
    pub(crate) imm_data: u32,
    pub(crate) opcode: WorkReqOpCode,
}

impl std::fmt::Debug for SendWrBase {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SendWrBase")
            .field("wr_id", &self.wr_id)
            .field("send_flags", &self.send_flags)
            .field("laddr", &format_args!("{:x}", self.laddr))
            .field("length", &self.length)
            .field("lkey", &self.lkey)
            .field("imm_data", &self.imm_data)
            .field("opcode", &self.opcode)
            .finish()
    }
}

impl SendWrBase {
    pub(crate) fn new(
        wr_id: u64,
        send_flags: u32,
        laddr: VirtAddr,
        length: u32,
        lkey: u32,
        imm_data: u32,
        opcode: WorkReqOpCode,
    ) -> Self {
        Self {
            wr_id,
            send_flags,
            laddr,
            length,
            lkey,
            imm_data,
            opcode,
        }
    }
}

// ValidationError has been moved to the error module

#[allow(clippy::unsafe_derive_deserialize)]
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Encode, Decode, PartialEq, Eq)]
pub(crate) struct RecvWr {
    pub(crate) wr_id: u64,
    pub(crate) addr: VirtAddr,
    pub(crate) length: u32,
    pub(crate) lkey: u32,
}

impl RecvWr {
    #[allow(unsafe_code)]
    pub(crate) fn new(wr: ibverbs_sys::ibv_recv_wr) -> Option<Self> {
        let num_sge = usize::try_from(wr.num_sge).ok()?;

        match num_sge {
            0 => {
                // Support num_sge = 0 for receiving RDMA_WRITE_WITH_IMM with immediate data only
                Some(Self {
                    wr_id: wr.wr_id,
                    addr: VirtAddr::new(0), // No buffer needed
                    length: 0,
                    lkey: 0,
                })
            }
            1 => {
                // Normal receive with buffer
                // SAFETY: sg_list is valid when num_sge > 0, which we've verified above
                let sge = unsafe { *wr.sg_list };
                Some(Self {
                    wr_id: wr.wr_id,
                    addr: VirtAddr::new(sge.addr),
                    length: sge.length,
                    lkey: sge.lkey,
                })
            }
            _ => {
                log::error!("Only 0 or 1 SGE supported, got {}", num_sge);
                None
            }
        }
    }

    pub(crate) fn to_bytes(self) -> [u8; size_of::<RecvWr>()] {
        let mut bytes = [0u8; 24];
        bytes[0..8].copy_from_slice(&self.wr_id.to_be_bytes());
        bytes[8..16].copy_from_slice(&self.addr.as_u64().to_be_bytes());
        bytes[16..20].copy_from_slice(&self.length.to_be_bytes());
        bytes[20..24].copy_from_slice(&self.lkey.to_be_bytes());
        bytes
    }

    #[allow(clippy::unwrap_used)]
    pub(crate) fn from_bytes(bytes: &[u8; size_of::<RecvWr>()]) -> Self {
        Self {
            wr_id: u64::from_be_bytes(bytes[0..8].try_into().unwrap()),
            addr: VirtAddr::new(u64::from_be_bytes(bytes[8..16].try_into().unwrap())),
            length: u32::from_be_bytes(bytes[16..20].try_into().unwrap()),
            lkey: u32::from_be_bytes(bytes[20..24].try_into().unwrap()),
        }
    }
}

#[derive(Debug)]
pub(crate) struct RecvWrQpn {
    pub(crate) wr: RecvWr,
    pub(crate) qpn: u32,
}

impl RecvWrQpn {
    pub(crate) fn new(qpn: u32, wr: RecvWr) -> Self {
        Self { wr, qpn }
    }

    pub(crate) fn to_bytes(self) -> [u8; size_of::<RecvWrQpn>()] {
        let mut bytes = [0u8; size_of::<RecvWrQpn>()];
        bytes[0..24].copy_from_slice(&self.wr.to_bytes());
        bytes[24..28].copy_from_slice(&self.qpn.to_be_bytes());
        bytes
    }

    #[allow(clippy::unwrap_used)]
    pub(crate) fn from_bytes(bytes: &[u8; size_of::<RecvWrQpn>()]) -> Self {
        let wr = RecvWr::from_bytes(&bytes[0..24].try_into().unwrap());
        let qpn = u32::from_be_bytes(bytes[24..28].try_into().unwrap());
        Self { wr, qpn }
    }
}

#[derive(Default, Clone, Copy)]
pub(crate) struct QpAttr {
    pub(crate) qp_type: u8,
    pub(crate) qpn: u32,
    pub(crate) dqpn: u32,
    pub(crate) ip: u32,
    pub(crate) dqp_ip: u32,
    pub(crate) mac_addr: u64,
    pub(crate) pmtu: u8,
    pub(crate) access_flags: u8,
    pub(crate) send_cq: Option<u32>,
    pub(crate) recv_cq: Option<u32>,
}

impl QpAttr {
    pub(crate) fn new_with_ip(ip: u32) -> Self {
        Self {
            ip,
            ..Default::default()
        }
    }
}

#[allow(unsafe_code, clippy::wildcard_imports)]
pub(crate) mod ibv_qp_attr {
    use std::net::Ipv4Addr;

    use ibverbs_sys::*;
    use log::info;

    pub(crate) struct IbvQpInitAttr {
        pub(crate) qp_type: u8,
        pub(crate) send_cq: Option<u32>,
        pub(crate) recv_cq: Option<u32>,
    }

    impl IbvQpInitAttr {
        pub(crate) fn new(attr: ibv_qp_init_attr) -> Self {
            let send_cq = unsafe { attr.send_cq.as_ref() }.map(|cq| cq.handle);
            let recv_cq = unsafe { attr.recv_cq.as_ref() }.map(|cq| cq.handle);
            Self {
                qp_type: attr.qp_type as u8,
                send_cq,
                recv_cq,
            }
        }

        pub(crate) fn new_rc() -> Self {
            Self {
                qp_type: ibv_qp_type::IBV_QPT_RC as u8,
                send_cq: None,
                recv_cq: None,
            }
        }

        pub(crate) fn qp_type(&self) -> u8 {
            self.qp_type
        }

        pub(crate) fn send_cq(&self) -> Option<u32> {
            self.send_cq
        }

        pub(crate) fn recv_cq(&self) -> Option<u32> {
            self.recv_cq
        }
    }

    #[derive(Default, Copy, Clone)]
    pub(crate) struct IbvQpAttr {
        pub(crate) qp_state: Option<ibv_qp_state::Type>,
        pub(crate) cur_qp_state: Option<ibv_qp_state::Type>,
        pub(crate) path_mtu: Option<ibv_mtu>,
        pub(crate) path_mig_state: Option<ibv_mig_state>,
        pub(crate) qkey: Option<u32>,
        pub(crate) rq_psn: Option<u32>,
        pub(crate) sq_psn: Option<u32>,
        pub(crate) dest_qp_num: Option<u32>,
        pub(crate) qp_access_flags: Option<::std::os::raw::c_uint>,
        pub(crate) cap: Option<ibv_qp_cap>,
        pub(crate) ah_attr: Option<ibv_ah_attr>,
        pub(crate) alt_ah_attr: Option<ibv_ah_attr>,
        pub(crate) pkey_index: Option<u16>,
        pub(crate) alt_pkey_index: Option<u16>,
        pub(crate) en_sqd_async_notify: Option<u8>,
        pub(crate) max_rd_atomic: Option<u8>,
        pub(crate) max_dest_rd_atomic: Option<u8>,
        pub(crate) min_rnr_timer: Option<u8>,
        pub(crate) port_num: Option<u8>,
        pub(crate) timeout: Option<u8>,
        pub(crate) retry_cnt: Option<u8>,
        pub(crate) rnr_retry: Option<u8>,
        pub(crate) alt_port_num: Option<u8>,
        pub(crate) alt_timeout: Option<u8>,
        pub(crate) rate_limit: Option<u32>,
        pub(crate) dest_qp_ip: Option<Ipv4Addr>,
    }

    impl IbvQpAttr {
        pub(crate) fn new(attr: ibv_qp_attr, attr_mask: u32) -> Self {
            // TODO: support IPv6
            let dest_qp_ip = if attr_mask & ibv_qp_attr_mask::IBV_QP_AV.0 != 0 {
                let gid = unsafe { attr.ah_attr.grh.dgid.raw };
                info!("gid: {:x}", u128::from_be_bytes(gid));

                // Format: ::ffff:a.b.c.d
                let is_ipv4_mapped =
                    gid[..10].iter().all(|&x| x == 0) && gid[10] == 0xFF && gid[11] == 0xFF;

                is_ipv4_mapped.then(|| Ipv4Addr::new(gid[12], gid[13], gid[14], gid[15]))
            } else {
                None
            };

            Self {
                qp_state: (attr_mask & ibv_qp_attr_mask::IBV_QP_STATE.0 != 0)
                    .then_some(attr.qp_state),
                cur_qp_state: (attr_mask & ibv_qp_attr_mask::IBV_QP_CUR_STATE.0 != 0)
                    .then_some(attr.cur_qp_state),
                path_mtu: (attr_mask & ibv_qp_attr_mask::IBV_QP_PATH_MTU.0 != 0)
                    .then_some(attr.path_mtu),
                path_mig_state: (attr_mask & ibv_qp_attr_mask::IBV_QP_PATH_MIG_STATE.0 != 0)
                    .then_some(attr.path_mig_state),
                qkey: (attr_mask & ibv_qp_attr_mask::IBV_QP_QKEY.0 != 0).then_some(attr.qkey),
                rq_psn: (attr_mask & ibv_qp_attr_mask::IBV_QP_RQ_PSN.0 != 0).then_some(attr.rq_psn),
                sq_psn: (attr_mask & ibv_qp_attr_mask::IBV_QP_SQ_PSN.0 != 0).then_some(attr.sq_psn),
                dest_qp_num: (attr_mask & ibv_qp_attr_mask::IBV_QP_DEST_QPN.0 != 0)
                    .then_some(attr.dest_qp_num),
                qp_access_flags: (attr_mask & ibv_qp_attr_mask::IBV_QP_ACCESS_FLAGS.0 != 0)
                    .then_some(attr.qp_access_flags),
                cap: (attr_mask & ibv_qp_attr_mask::IBV_QP_CAP.0 != 0).then_some(attr.cap),
                ah_attr: (attr_mask & ibv_qp_attr_mask::IBV_QP_AV.0 != 0).then_some(attr.ah_attr),
                alt_ah_attr: (attr_mask & ibv_qp_attr_mask::IBV_QP_ALT_PATH.0 != 0)
                    .then_some(attr.alt_ah_attr),
                pkey_index: (attr_mask & ibv_qp_attr_mask::IBV_QP_PKEY_INDEX.0 != 0)
                    .then_some(attr.pkey_index),
                alt_pkey_index: (attr_mask & ibv_qp_attr_mask::IBV_QP_ALT_PATH.0 != 0)
                    .then_some(attr.alt_pkey_index),
                en_sqd_async_notify: (attr_mask & ibv_qp_attr_mask::IBV_QP_EN_SQD_ASYNC_NOTIFY.0
                    != 0)
                    .then_some(attr.en_sqd_async_notify),
                max_rd_atomic: (attr_mask & ibv_qp_attr_mask::IBV_QP_MAX_QP_RD_ATOMIC.0 != 0)
                    .then_some(attr.max_rd_atomic),
                max_dest_rd_atomic: (attr_mask & ibv_qp_attr_mask::IBV_QP_MAX_DEST_RD_ATOMIC.0
                    != 0)
                    .then_some(attr.max_dest_rd_atomic),
                min_rnr_timer: (attr_mask & ibv_qp_attr_mask::IBV_QP_MIN_RNR_TIMER.0 != 0)
                    .then_some(attr.min_rnr_timer),
                port_num: (attr_mask & ibv_qp_attr_mask::IBV_QP_PORT.0 != 0)
                    .then_some(attr.port_num),
                timeout: (attr_mask & ibv_qp_attr_mask::IBV_QP_TIMEOUT.0 != 0)
                    .then_some(attr.timeout),
                retry_cnt: (attr_mask & ibv_qp_attr_mask::IBV_QP_RETRY_CNT.0 != 0)
                    .then_some(attr.retry_cnt),
                rnr_retry: (attr_mask & ibv_qp_attr_mask::IBV_QP_RNR_RETRY.0 != 0)
                    .then_some(attr.rnr_retry),
                alt_port_num: (attr_mask & ibv_qp_attr_mask::IBV_QP_ALT_PATH.0 != 0)
                    .then_some(attr.alt_port_num),
                alt_timeout: (attr_mask & ibv_qp_attr_mask::IBV_QP_ALT_PATH.0 != 0)
                    .then_some(attr.alt_timeout),
                rate_limit: (attr_mask & ibv_qp_attr_mask::IBV_QP_RATE_LIMIT.0 != 0)
                    .then_some(attr.rate_limit),
                dest_qp_ip,
            }
        }

        pub(crate) fn qp_state(&self) -> Option<ibv_qp_state::Type> {
            self.qp_state
        }

        pub(crate) fn cur_qp_state(&self) -> Option<ibv_qp_state::Type> {
            self.cur_qp_state
        }

        pub(crate) fn path_mtu(&self) -> Option<ibv_mtu> {
            self.path_mtu
        }

        pub(crate) fn path_mig_state(&self) -> Option<ibv_mig_state> {
            self.path_mig_state
        }

        pub(crate) fn qkey(&self) -> Option<u32> {
            self.qkey
        }

        pub(crate) fn rq_psn(&self) -> Option<u32> {
            self.rq_psn
        }

        pub(crate) fn sq_psn(&self) -> Option<u32> {
            self.sq_psn
        }

        pub(crate) fn dest_qp_num(&self) -> Option<u32> {
            self.dest_qp_num
        }

        pub(crate) fn qp_access_flags(&self) -> Option<::std::os::raw::c_uint> {
            self.qp_access_flags
        }

        pub(crate) fn cap(&self) -> Option<ibv_qp_cap> {
            self.cap
        }

        pub(crate) fn ah_attr(&self) -> Option<ibv_ah_attr> {
            self.ah_attr
        }

        pub(crate) fn alt_ah_attr(&self) -> Option<ibv_ah_attr> {
            self.alt_ah_attr
        }

        pub(crate) fn pkey_index(&self) -> Option<u16> {
            self.pkey_index
        }

        pub(crate) fn alt_pkey_index(&self) -> Option<u16> {
            self.alt_pkey_index
        }

        pub(crate) fn en_sqd_async_notify(&self) -> Option<u8> {
            self.en_sqd_async_notify
        }

        pub(crate) fn max_rd_atomic(&self) -> Option<u8> {
            self.max_rd_atomic
        }

        pub(crate) fn max_dest_rd_atomic(&self) -> Option<u8> {
            self.max_dest_rd_atomic
        }

        pub(crate) fn min_rnr_timer(&self) -> Option<u8> {
            self.min_rnr_timer
        }

        pub(crate) fn port_num(&self) -> Option<u8> {
            self.port_num
        }

        pub(crate) fn timeout(&self) -> Option<u8> {
            self.timeout
        }

        pub(crate) fn retry_cnt(&self) -> Option<u8> {
            self.retry_cnt
        }

        pub(crate) fn rnr_retry(&self) -> Option<u8> {
            self.rnr_retry
        }

        pub(crate) fn alt_port_num(&self) -> Option<u8> {
            self.alt_port_num
        }

        pub(crate) fn alt_timeout(&self) -> Option<u8> {
            self.alt_timeout
        }

        pub(crate) fn rate_limit(&self) -> Option<u32> {
            self.rate_limit
        }

        pub(crate) fn dest_qp_ip(&self) -> Option<Ipv4Addr> {
            self.dest_qp_ip
        }
    }
}
