use std::{
    net::{Ipv4Addr, UdpSocket},
    sync::{atomic::AtomicBool, Arc},
};

use ipnetwork::IpNetwork;

use super::{worker::SimpleNicWorker, FrameRx, FrameTx, SimpleNicDevice, SimpleNicDeviceConfig};

struct FrameTxSocket(UdpSocket);

impl FrameTx for FrameTxSocket {
    fn send(&mut self, buf: &[u8]) -> std::io::Result<()> {
        UdpSocket::send(&self.0, buf).map(|_| ())
    }
}

struct FrameRxSocket {
    buffer: Vec<u8>,
    socket: UdpSocket,
}

impl FrameRx for FrameRxSocket {
    fn recv_nonblocking(&mut self) -> std::io::Result<Vec<u8>> {
        let len = self.buffer.len();
        self.buffer.resize(len + 2048, 0);
        let n = self.socket.recv(&mut self.buffer[len..])?;
        Ok(self.buffer[len..len + n].to_vec())
    }
}

#[test]
#[allow(clippy::print_stderr)]
fn worker_loopback() {
    let network = IpNetwork::new(Ipv4Addr::new(172, 16, 0, 0).into(), 24).unwrap();
    let config = SimpleNicDeviceConfig::new(network);
    // Requires root
    let Ok(dev) = SimpleNicDevice::new(config) else {
        eprintln!("WARN: test 'worker_loopback' was skipped as it needs to be run as root");
        return;
    };
    let socket_tx = UdpSocket::bind("127.0.0.1:0").unwrap();
    let socket_rx = UdpSocket::bind("127.0.0.1:0").unwrap();
    socket_tx.connect(socket_rx.local_addr().unwrap()).unwrap();
    socket_rx.set_nonblocking(true).unwrap();
    let frame_tx = FrameTxSocket(socket_tx);
    let frame_rx = FrameRxSocket {
        buffer: Vec::new(),
        socket: socket_rx,
    };
    let shutdown = Arc::new(AtomicBool::new(false));
    let worker = SimpleNicWorker::new(dev.tun_dev, frame_tx, frame_rx, Arc::clone(&shutdown));
    let handle = worker.run();
}
