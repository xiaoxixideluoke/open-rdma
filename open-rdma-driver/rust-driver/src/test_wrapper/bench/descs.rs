use crate::descriptors::MetaReportQueueDescBthReth;
use crate::ringbuf::DescDeserialize;

pub struct MetaReportQueueDescBthRethWrapper(MetaReportQueueDescBthReth);

impl MetaReportQueueDescBthRethWrapper {
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(MetaReportQueueDescBthReth::deserialize(bytes))
    }

    #[inline]
    #[allow(unused_results)]
    pub fn load_all(&self) {
        self.0.expected_psn();
        self.0.req_status();
        self.0.trans();
        self.0.opcode();
        self.0.dqpn();
        self.0.psn();
        self.0.solicited();
        self.0.ack_req();
        self.0.pad_cnt();
        self.0.rkey();
        self.0.va();
        self.0.dlen();
        self.0.msn();
        self.0.can_auto_ack();
    }

    #[inline]
    pub fn set_all(&mut self) {
        self.0.set_expected_psn(0);
        self.0.set_req_status(0);
        self.0.set_trans(0);
        self.0.set_opcode(0);
        self.0.set_dqpn(0);
        self.0.set_psn(0);
        self.0.set_solicited(false);
        self.0.set_ack_req(false);
        self.0.set_pad_cnt(0);
        self.0.set_rkey(0);
        self.0.set_va(0);
        self.0.set_dlen(0);
        self.0.set_msn(0);
        self.0.set_can_auto_ack(false);
    }
}
