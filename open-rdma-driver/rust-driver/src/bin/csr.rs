#![allow(warnings)]

use std::{
    env,
    fmt::Debug,
    fs, io,
    net::{SocketAddr, UdpSocket},
    path::{Path, PathBuf},
    sync::Arc,
};

use pci_info::PciInfo;
use serde::{Deserialize, Serialize};

const VENDER_ID: u16 = 0x10ee;
const DEVICE_ID: u16 = 0x903f;
const PCI_SYSFS_BUS_PATH: &str = "/sys/bus/pci/devices";
trait FetchDebugInfo {
    // Constants for register addresses
    const RQ_FIFO: usize = 0x4000;
    const INPUT_PACKET_CLASSIFIER_FIFO: usize = 0x4400;
    const INPUT_PACKET_CLASSIFIER_1: usize = 0x4404;
    const RDMA_HEADER_EXTRACTOR_FIFO: usize = 0x4480;
    const PAYLODGEN_FIFO: usize = 0x4800;
    const AUTOACKGEN_FIFO: usize = 0x4c00;
    const DMA_ENGINE_FIFO: usize = 0x8000;

    // Method declarations
    fn get_rq_fifo_status(&self) -> u32;
    fn get_input_packet_classifier_fifo_status(&self) -> u32;
    fn get_input_packet_classifier_1_status(&self) -> u32;
    fn get_rdma_header_extractor_fifo_status(&self) -> u32;
    fn get_payloadgen_fifo_status(&self) -> u32;
    fn get_autoackgen_fifo_status(&self) -> u32;
    fn get_dma_engine_fifo_status(&self) -> u32;
}

pub(crate) struct PciHwDevice {
    sysfs_path: PathBuf,
}

impl PciHwDevice {
    pub(crate) fn open_default() -> io::Result<Self> {
        let build_err = || io::Error::new(io::ErrorKind::Other, "Failed to open device");
        let info = PciInfo::enumerate_pci().map_err(|_err| build_err())?;
        let device = info
            .iter()
            .flatten()
            .find(|d| d.vendor_id() == VENDER_ID && d.device_id() == DEVICE_ID)
            .ok_or_else(build_err)?;
        let location = device.location().map_err(|_err| build_err())?;
        let sysfs_path = PathBuf::from(PCI_SYSFS_BUS_PATH).join(location.to_string());

        Ok(Self { sysfs_path })
    }
}

pub(crate) struct DebugInfoFetcher {
    bar: memmap2::MmapMut,
}

impl DebugInfoFetcher {
    pub(crate) fn new(sysfs_path: impl AsRef<Path>) -> io::Result<Self> {
        let bar_path = sysfs_path.as_ref().join(format!("resource0"));
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&bar_path)?;
        let mmap = unsafe { memmap2::MmapOptions::new().map_mut(&file)? };

        Ok(Self { bar: mmap })
    }
}

impl FetchDebugInfo for DebugInfoFetcher {
    fn get_rq_fifo_status(&self) -> u32 {
        unsafe {
            self.bar
                .as_ptr()
                .add(Self::RQ_FIFO)
                .cast::<u32>()
                .read_volatile()
        }
    }

    fn get_input_packet_classifier_fifo_status(&self) -> u32 {
        unsafe {
            self.bar
                .as_ptr()
                .add(Self::INPUT_PACKET_CLASSIFIER_FIFO)
                .cast::<u32>()
                .read_volatile()
        }
    }

    fn get_input_packet_classifier_1_status(&self) -> u32 {
        unsafe {
            self.bar
                .as_ptr()
                .add(Self::INPUT_PACKET_CLASSIFIER_1)
                .cast::<u32>()
                .read_volatile()
        }
    }

    fn get_rdma_header_extractor_fifo_status(&self) -> u32 {
        unsafe {
            self.bar
                .as_ptr()
                .add(Self::RDMA_HEADER_EXTRACTOR_FIFO)
                .cast::<u32>()
                .read_volatile()
        }
    }

    fn get_payloadgen_fifo_status(&self) -> u32 {
        unsafe {
            self.bar
                .as_ptr()
                .add(Self::PAYLODGEN_FIFO)
                .cast::<u32>()
                .read_volatile()
        }
    }

    fn get_autoackgen_fifo_status(&self) -> u32 {
        unsafe {
            self.bar
                .as_ptr()
                .add(Self::AUTOACKGEN_FIFO)
                .cast::<u32>()
                .read_volatile()
        }
    }

    fn get_dma_engine_fifo_status(&self) -> u32 {
        unsafe {
            self.bar
                .as_ptr()
                .add(Self::DMA_ENGINE_FIFO)
                .cast::<u32>()
                .read_volatile()
        }
    }
}

impl FetchDebugInfo for EmulatedDevice {
    fn get_rq_fifo_status(&self) -> u32 {
        self.read_csr(Self::RQ_FIFO)
            .expect("failed to read RQ FIFO status")
    }

    fn get_input_packet_classifier_fifo_status(&self) -> u32 {
        self.read_csr(Self::INPUT_PACKET_CLASSIFIER_FIFO)
            .expect("failed to read input packet classifier FIFO status")
    }

    fn get_input_packet_classifier_1_status(&self) -> u32 {
        self.read_csr(Self::INPUT_PACKET_CLASSIFIER_1)
            .expect("failed to read input packet classifier 1 status")
    }

    fn get_rdma_header_extractor_fifo_status(&self) -> u32 {
        self.read_csr(Self::RDMA_HEADER_EXTRACTOR_FIFO)
            .expect("failed to read RDMA header extractor FIFO status")
    }

    fn get_payloadgen_fifo_status(&self) -> u32 {
        self.read_csr(Self::PAYLODGEN_FIFO)
            .expect("failed to read payload generator FIFO status")
    }

    fn get_autoackgen_fifo_status(&self) -> u32 {
        self.read_csr(Self::AUTOACKGEN_FIFO)
            .expect("failed to read auto ack generator FIFO status")
    }

    fn get_dma_engine_fifo_status(&self) -> u32 {
        self.read_csr(Self::DMA_ENGINE_FIFO)
            .expect("failed to read DMA engine FIFO status")
    }
}

#[derive(Debug, Clone)]
struct RpcClient(Arc<UdpSocket>);

#[derive(Debug, Serialize, Deserialize)]
struct CsrAccessRpcMessage {
    is_write: bool,
    addr: usize,
    value: u32,
}

impl RpcClient {
    fn new(server_addr: SocketAddr) -> io::Result<Self> {
        let socket = UdpSocket::bind("0.0.0.0:0")?;
        socket.connect(server_addr)?;
        Ok(Self(socket.into()))
    }

    fn read_csr(&self, addr: usize) -> io::Result<u32> {
        let msg = CsrAccessRpcMessage {
            is_write: false,
            addr,
            value: 0,
        };

        let send_buf = serde_json::to_vec(&msg)?;
        let _: usize = self.0.send(&send_buf)?;

        let mut recv_buf = [0; 128];
        let (recv_cnt, _addr) = self.0.recv_from(&mut recv_buf)?;
        // the length of CsrAccessRpcMessage is fixed,
        #[allow(clippy::indexing_slicing)]
        let response = serde_json::from_slice::<CsrAccessRpcMessage>(&recv_buf[..recv_cnt])?;

        Ok(response.value)
    }

    fn write_csr(&self, addr: usize, data: u32) -> io::Result<()> {
        let msg = CsrAccessRpcMessage {
            is_write: true,
            addr,
            value: data,
        };

        let send_buf = serde_json::to_vec(&msg)?;
        let _: usize = self.0.send(&send_buf)?;
        Ok(())
    }
}

#[non_exhaustive]
#[derive(Clone, Debug)]
pub(crate) struct EmulatedDevice(RpcClient);

impl EmulatedDevice {
    #[allow(clippy::expect_used)]
    pub(crate) fn new_with_addr(addr: &str) -> Self {
        EmulatedDevice(
            RpcClient::new(addr.parse().expect("invalid socket addr"))
                .expect("failed to connect to emulator"),
        )
    }

    fn read_csr(&self, addr: usize) -> io::Result<u32> {
        self.0.read_csr(addr)
    }

    fn write_csr(&self, addr: usize, data: u32) -> io::Result<()> {
        self.0.write_csr(addr, data)
    }
}

struct InfoPrinter<T>(T);

impl<T: FetchDebugInfo> InfoPrinter<T> {
    fn print_binary(&self) {
        println!("FIFO Status Values (Binary):");
        println!("--------------------------");

        let rq_status = self.0.get_rq_fifo_status();
        println!("RQ FIFO:                    {:#034b}", rq_status);

        let ipc_status = self.0.get_input_packet_classifier_fifo_status();
        println!("Input Packet Classifier:    {:#034b}", ipc_status);

        let ipc1_status = self.0.get_input_packet_classifier_1_status();
        println!("Input Packet Classifier 1:  {:#034b}", ipc1_status);

        let rdma_status = self.0.get_rdma_header_extractor_fifo_status();
        println!("RDMA Header Extractor:      {:#034b}", rdma_status);

        let payload_status = self.0.get_payloadgen_fifo_status();
        println!("Payload Generator:          {:#034b}", payload_status);

        let autoack_status = self.0.get_autoackgen_fifo_status();
        println!("Auto ACK Generator:         {:#034b}", autoack_status);

        let dma_status = self.0.get_dma_engine_fifo_status();
        println!("DMA Engine:                 {:#034b}", dma_status);

        println!("--------------------------");
    }
}

pub(crate) struct RateLimitConfigurator {
    bar: memmap2::MmapMut,
}

impl RateLimitConfigurator {
    const LIMIT_ADDR: usize = 0x10000;
    const RATE_ADDR: usize = 0x10001;

    pub(crate) fn new(sysfs_path: impl AsRef<Path>) -> io::Result<Self> {
        let bar_path = sysfs_path.as_ref().join(format!("resource1"));
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&bar_path)?;
        let mmap = unsafe { memmap2::MmapOptions::new().map_mut(&file)? };

        Ok(Self { bar: mmap })
    }

    pub(crate) fn set(&mut self, rate: u32, limit: u32) {
        unsafe {
            self.bar
                .as_mut_ptr()
                .add(Self::RATE_ADDR)
                .cast::<u32>()
                .write_volatile(rate);
            self.bar
                .as_mut_ptr()
                .add(Self::LIMIT_ADDR)
                .cast::<u32>()
                .write_volatile(limit);
        }
    }
}

pub(crate) struct SimRateLimitConfigurator {
    bar: EmulatedDevice,
}

impl SimRateLimitConfigurator {
    const LIMIT_ADDR: usize = 0x4000;
    const RATE_ADDR: usize = 0x4004;

    pub(crate) fn new(bar: EmulatedDevice) -> Self {
        Self { bar }
    }

    pub(crate) fn set(&mut self, rate: u32, limit: u32) {
        self.bar.write_csr(Self::RATE_ADDR, rate);
        self.bar.write_csr(Self::LIMIT_ADDR, limit);
    }
}

fn run_hw() {
    let dev = PciHwDevice::open_default().unwrap();
    let fetcher = DebugInfoFetcher::new(dev.sysfs_path).unwrap();
    let printer = InfoPrinter(fetcher);
    printer.print_binary();
}

fn run_hw1() {
    let rate_str = env::var("RATE").unwrap();
    let limit_str = env::var("LIMIT").unwrap();
    let rate: u32 = rate_str.parse().unwrap();
    let limit: u32 = limit_str.parse().unwrap();
    let dev = PciHwDevice::open_default().unwrap();
    let mut c = RateLimitConfigurator::new(dev.sysfs_path).unwrap();
    c.set(rate, limit);
}

fn run_sim() {
    let dev = EmulatedDevice::new_with_addr("127.0.0.1:7701".into());
    let printer = InfoPrinter(dev);
    for _ in 0..11 {
        printer.print_binary();
    }
}

fn run_sim1() {
    let dev = EmulatedDevice::new_with_addr("127.0.0.1:7701".into());
    let mut c = SimRateLimitConfigurator::new(dev);
    for _ in 0..11 {
        c.set(3, 5);
    }
}

fn main() {
    run_sim1();
}
