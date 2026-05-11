/// Routing table configurations
mod route;

/// worker handling NIC frames
mod worker;

// mod types;

#[cfg(test)]
mod tests;

pub(crate) use worker::SimpleNicController;

use std::{io, sync::Arc};

use ipnetwork::IpNetwork;

#[allow(clippy::module_name_repetitions)]
/// Configuration for the simple NIC device
#[derive(Debug, Clone, Copy)]
pub(crate) struct SimpleNicDeviceConfig {
    /// IP network assigned to the NIC
    network: IpNetwork,
}

impl SimpleNicDeviceConfig {
    /// Creates a new `SimpleNicDeviceConfig`
    #[inline]
    #[must_use]
    pub(crate) fn new(network: IpNetwork) -> Self {
        Self { network }
    }
}

/// A simple network interface device that uses TUN/TAP for network connectivity
struct SimpleNicDevice {
    /// The underlying TUN device used for network I/O
    tun_dev: Arc<tun::Device>,
    /// Config of the device
    config: SimpleNicDeviceConfig,
}

impl SimpleNicDevice {
    /// Creates a new `SimpleNicDevice`
    fn new(config: SimpleNicDeviceConfig) -> io::Result<Self> {
        let tun_dev = Arc::new(Self::create_tun(config.network)?);
        Ok(Self { tun_dev, config })
    }

    /// Creates a TUN device that operates at L2
    #[allow(unused_results)] // ignore the config construction result
    fn create_tun(network: IpNetwork) -> io::Result<tun::Device> {
        let mut config = tun::Configuration::default();
        config
            .layer(tun::Layer::L2)
            .address(network.ip())
            .netmask(network.mask())
            .up();

        #[cfg(target_os = "linux")]
        config.platform_config(|platform| {
            // requiring root privilege to acquire complete functions
            platform.ensure_root_privileges(true);
        });

        tun::create(&config).map_err(Into::into)
    }
}

/// Trait for transmitting frames
pub(crate) trait FrameTx {
    /// Send a buffer of bytes as a frame
    fn send(&mut self, buf: &[u8]) -> io::Result<()>;
}

/// Trait for receiving frames
pub(crate) trait FrameRx {
    /// Try to receive a frame, returning immediately if none available
    fn recv_nonblocking(&mut self) -> io::Result<Vec<u8>>;
}
