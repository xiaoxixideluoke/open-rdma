use std::{
    collections::HashMap,
    collections::VecDeque,
    io::{self, Read, Write},
    net::{Ipv4Addr, TcpListener, TcpStream},
    sync::Arc,
    thread,
};

use log::debug;
use parking_lot::Mutex;

use crate::verbs::ctx::try_match_pendings;
use crate::{
    rdma_utils::{
        qp::{QpTable, QpTableShared},
        types::{QpAttr, RecvWr, RecvWrQpn, SendWr},
    },
    workers::{rdma::RdmaWriteTask, spawner::TaskTx},
    RdmaError,
};

use core::net::SocketAddr;

// Deprecated
const BASE_PORT: u16 = 60000;
const PORT_RANGE: u32 = 5535; // 使用端口范围 60000-65534

pub(crate) const RECV_WORKER_PORT: u16 = 60000;

use socket2::{Domain, Protocol, Socket, Type};

pub(crate) struct TcpChannelTx {
    inner: Option<TcpStream>,
}

impl TcpChannelTx {
    pub(crate) fn connect(local_ip: Ipv4Addr, dest_ip: Ipv4Addr, port: u16) -> io::Result<Self> {
        let socket = Socket::new(Domain::IPV4, Type::STREAM, Some(Protocol::TCP))?;
        // bind local address to avoid port conflict
        socket.bind(&SocketAddr::new(local_ip.into(), 0).into())?;
        socket.connect(&SocketAddr::new(dest_ip.into(), port).into())?;
        let stream = socket.into();
        Ok(Self {
            inner: Some(stream),
        })
    }

    pub(crate) fn send(&mut self, tx_msg: RecvWrQpn) -> io::Result<()> {
        if self.inner.is_none() {
            unreachable!("TcpChannelTx not connected");
        }
        let stream = self.inner.as_mut().unwrap_or_else(|| unreachable!());
        stream.write_all(&tx_msg.to_bytes())?;

        Ok(())
    }
}

pub(crate) struct TcpChannelRx {
    stream: Option<TcpStream>,
    addr: Option<Ipv4Addr>,
    buf: [u8; size_of::<RecvWrQpn>()],
}

impl TcpChannelRx {
    fn new(stream: TcpStream, addr: Ipv4Addr) -> io::Result<Self> {
        Ok(Self {
            stream: Some(stream),
            addr: Some(addr),
            buf: [0; size_of::<RecvWrQpn>()],
        })
    }

    fn recv(&mut self) -> io::Result<RecvWrQpn> {
        if self.stream.is_none() || self.addr.is_none() {
            unreachable!("TcpChannelRx not connected");
        }
        let stream = self.stream.as_mut().unwrap_or_else(|| unreachable!());
        stream.read_exact(self.buf.as_mut())?;
        Ok(RecvWrQpn::from_bytes(&self.buf))
    }
}

pub(crate) type SharedTcpChannelTx = Arc<Mutex<TcpChannelTx>>;

pub(crate) struct PostRecvTxTable<Tx = SharedTcpChannelTx> {
    inner: QpTable<Option<Tx>>,
}

// TODO 需要进行析构
impl<Tx> PostRecvTxTable<Tx> {
    pub(crate) fn new() -> Self {
        Self {
            inner: QpTable::new(),
        }
    }

    pub(crate) fn insert(&mut self, qpn: u32, tx: Tx) {
        let _ignore = self.inner.replace(qpn, Some(tx));
    }

    pub(crate) fn get_qp_mut(&mut self, qpn: u32) -> Option<&mut Tx> {
        self.inner.get_qp_mut(qpn).and_then(Option::as_mut)
    }

    pub(crate) fn get_qp(&self, qpn: u32) -> Option<&Tx> {
        self.inner.get_qp(qpn).and_then(Option::as_ref)
    }
}

pub(crate) struct IpTxTable {
    inner: HashMap<Ipv4Addr, SharedTcpChannelTx>,
}

impl IpTxTable {
    pub(crate) fn new() -> Self {
        Self {
            inner: HashMap::new(),
        }
    }

    pub(crate) fn get(&self, ip: Ipv4Addr) -> Option<SharedTcpChannelTx> {
        self.inner.get(&ip).cloned()
    }

    pub(crate) fn insert(&mut self, ip: Ipv4Addr, tx: SharedTcpChannelTx) {
        match self.inner.insert(ip, tx) {
            Some(_) => debug!("IpTxTable: replaced existing TcpChannelTx for IP {}", ip),
            None => (),
        }
    }

    pub(crate) fn get_or_connect(
        &mut self,
        local_ip: Ipv4Addr,
        dest_ip: Ipv4Addr,
        port: u16,
    ) -> io::Result<SharedTcpChannelTx> {
        if let Some(tx) = self.inner.get(&dest_ip) {
            return Ok(tx.clone());
        }

        let tx = Arc::new(Mutex::new(TcpChannelTx::connect(local_ip, dest_ip, port)?));
        match self.inner.insert(dest_ip, tx.clone()) {
            Some(_) => debug!(
                "IpTxTable: replaced existing TcpChannelTx for IP {}",
                dest_ip
            ),
            None => (),
        }
        Ok(tx)
    }
}

pub(crate) type SharedRecvWrQueue = Arc<Mutex<VecDeque<RecvWr>>>;

pub(crate) struct RecvWrQueueTable {
    inner: QpTable<SharedRecvWrQueue>,
}

impl RecvWrQueueTable {
    pub(crate) fn new() -> Self {
        Self {
            inner: QpTable::new(),
        }
    }

    pub(crate) fn clone_recv_wr_queue(&self, qpn: u32) -> Option<SharedRecvWrQueue> {
        self.inner.get_qp(qpn).cloned()
    }

    pub(crate) fn pop(&self, qpn: u32) -> Option<RecvWr> {
        let queue = self.inner.get_qp(qpn)?;
        queue.lock().pop_front()
    }

    pub(crate) fn push_front(&self, qpn: u32, recv_wr: RecvWr) -> Result<(), RdmaError> {
        if let Some(queue) = self.inner.get_qp(qpn) {
            queue.lock().push_back(recv_wr);
            Ok(())
        } else {
            Err(RdmaError::NotFound(format!(
                "Receive WR queue for QP {} not found",
                qpn
            )))
        }
    }
}

impl Clone for RecvWrQueueTable {
    fn clone(&self) -> Self {
        Self {
            inner: self.inner.clone(),
        }
    }
}

// ============ Pending Send Queue Implementation ============

/// Pending send queue capacity constant
pub(crate) const PENDING_SEND_QUEUE_CAPACITY: usize = 128;

/// Single QP's pending send queue
pub(crate) type SharedPendingSendQueue = Arc<Mutex<VecDeque<SendWr>>>;

/// Manages pending send queues for all QPs
pub(crate) struct PendingSendQueueTable {
    inner: QpTable<SharedPendingSendQueue>,
}

impl PendingSendQueueTable {
    pub(crate) fn new() -> Self {
        Self {
            inner: QpTable::new(),
        }
    }

    /// Get the pending send queue for a specific QP (for sharing with RecvWorker)
    pub(crate) fn clone_queue(&self, qpn: u32) -> Option<SharedPendingSendQueue> {
        self.inner.get_qp(qpn).cloned()
    }

    /// Try to push a pending send, returns false if queue is full
    pub(crate) fn try_push(&self, qpn: u32, wr: SendWr) -> bool {
        if let Some(queue) = self.inner.get_qp(qpn) {
            let mut locked_queue = queue.lock();
            if locked_queue.len() >= PENDING_SEND_QUEUE_CAPACITY {
                return false; // Queue is full
            }
            locked_queue.push_back(wr);
            true
        } else {
            false
        }
    }

    /// Get current queue length (for logging/debugging)
    pub(crate) fn len(&self, qpn: u32) -> usize {
        self.inner.get_qp(qpn).map(|q| q.lock().len()).unwrap_or(0)
    }
}

impl Clone for PendingSendQueueTable {
    fn clone(&self) -> Self {
        Self {
            inner: self.inner.clone(),
        }
    }
}

pub(crate) struct RecvWorker {
    rx: TcpChannelRx,
    qp_attr_table: QpTableShared<QpAttr>,
    recv_wr_queue_table: RecvWrQueueTable,
    pending_send_queue_table: PendingSendQueueTable,
    rdma_write_tx: TaskTx<RdmaWriteTask>,
}

impl RecvWorker {
    pub(crate) fn new(
        rx: TcpChannelRx,
        qp_attr_table: QpTableShared<QpAttr>,
        recv_wr_queue_table: RecvWrQueueTable,
        pending_send_queue_table: PendingSendQueueTable,
        rdma_write_tx: TaskTx<RdmaWriteTask>,
    ) -> Self {
        Self {
            rx,
            qp_attr_table,
            recv_wr_queue_table,
            pending_send_queue_table,
            rdma_write_tx,
        }
    }

    // TODO: use tokio
    pub(crate) fn spawn(self) {
        let _handle = thread::Builder::new()
            .name("recv-worker".into())
            .spawn(move || self.run())
            .unwrap_or_else(|err| unreachable!("Failed to spawn rx thread: {err}"));
    }

    #[allow(clippy::needless_pass_by_value)] // consume the flag
    /// Run the handler loop
    fn run(mut self) {
        debug!("RecvWorker: started recv worker");
        while let Ok(rx_msg) = self.rx.recv() {
            let addr = self.rx.addr.expect("RecvWorker: rx.addr must be set");
            debug!(
                "RecvWorker: received RecvWr for QP {} from {}",
                rx_msg.qpn, addr
            );
            let recv_wr = rx_msg.wr;
            let dqpn = rx_msg.qpn;
            let qp_attr = self
                .qp_attr_table
                .query(|current| dqpn == current.dqpn && addr.to_bits() == current.dqp_ip);

            let qpn = match qp_attr {
                Some(attr) => attr.qpn,
                None => {
                    debug!(
                        "RecvWorker: received WR for unknown QP (dqpn: {}, addr: {})",
                        dqpn, addr
                    );
                    continue;
                }
            };
            self.recv_wr_queue_table
                .clone_recv_wr_queue(qpn)
                .unwrap_or_else(|| {
                    panic!("RecvWorker: Receive WR queue for QP {} not found", qpn);
                })
                .lock()
                .push_back(recv_wr);

            try_match_pendings(
                qpn,
                &self
                    .pending_send_queue_table
                    .clone_queue(qpn)
                    .unwrap_or_else(|| {
                        panic!("RecvWorker: Pending send queue for QP {} not found", qpn);
                    }),
                &self
                    .recv_wr_queue_table
                    .clone_recv_wr_queue(qpn)
                    .unwrap_or_else(|| {
                        panic!("RecvWorker: Receive WR queue for QP {} not found", qpn);
                    }),
                &self.rdma_write_tx,
            )
            .unwrap_or_else(|e| {
                panic!(
                    "RecvWorker: failed to match pending send WRs for QP {}: {}",
                    qpn, e
                );
            });
        }
    }
}

pub(crate) struct RecvWorkers {
    local_addr: Ipv4Addr,
    port: u16,
    qp_attr_table: QpTableShared<QpAttr>,
    recv_wr_queue_table: RecvWrQueueTable,
    pending_send_queue_table: PendingSendQueueTable,
    rdma_write_tx: TaskTx<RdmaWriteTask>,
}

impl RecvWorkers {
    pub(crate) fn new(
        local_addr: Ipv4Addr,
        port: u16,
        qp_attr_table: QpTableShared<QpAttr>,
        recv_wr_queue_table: RecvWrQueueTable,
        pending_send_queue_table: PendingSendQueueTable,
        rdma_write_tx: TaskTx<RdmaWriteTask>,
    ) -> Self {
        Self {
            local_addr,
            port,
            qp_attr_table,
            recv_wr_queue_table,
            pending_send_queue_table,
            rdma_write_tx,
        }
    }

    pub(crate) fn spawn(self) {
        let _handle = thread::Builder::new()
            .name("recv-workers".into())
            .spawn(move || self.run())
            .unwrap_or_else(|err| unreachable!("Failed to spawn rx thread: {err}"));
    }

    pub(crate) fn run(&self) {
        log::info!(
            "RecvWorkers: listening on {}:{}",
            self.local_addr,
            self.port
        );
        let listener = TcpListener::bind((self.local_addr, self.port)).unwrap_or_else(|e| {
            panic!("Error binding listener: {}, port is {}", e, self.port);
        });

        loop {
            match listener.accept() {
                Ok((stream, addr)) => {
                    log::info!("RecvWorkers: accepted connection from {}", addr);
                    let addr = match addr {
                        SocketAddr::V4(addr_v4) => addr_v4.ip().to_owned(),
                        SocketAddr::V6(_) => unreachable!(),
                    };
                    RecvWorker::new(
                        TcpChannelRx::new(stream, addr).unwrap(),
                        self.qp_attr_table.clone(),
                        self.recv_wr_queue_table.clone(),
                        self.pending_send_queue_table.clone(),
                        self.rdma_write_tx.clone(),
                    )
                    .spawn();
                }
                Err(e) => println!("Connection failed: {}", e),
            }
        }
    }
}
