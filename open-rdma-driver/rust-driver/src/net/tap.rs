#![allow(clippy::module_name_repetitions)] // exported

use std::{io, os::fd::AsRawFd, sync::Arc};

use ipnetwork::IpNetwork;

use super::config::{MacAddress, NetworkConfig, NetworkResolver};

/// A TAP device that provides a virtual network interface.
#[derive(Clone)]
pub struct TapDevice {
    /// Inner
    inner: Arc<tun::Device>,
    /// MAC address of the tap device
    mac_addr: MacAddress,
    /// Ip network
    network: Option<IpNetwork>,
}

impl std::fmt::Debug for TapDevice {
    #[inline]
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("TapDevice").finish()
    }
}

impl TapDevice {
    /// Returns the inner tap device
    pub(crate) fn inner(&self) -> Arc<tun::Device> {
        Arc::clone(&self.inner)
    }

    /// Creates a TUN device that operates at L2
    #[allow(unused_results)] // ignore the config construction result
    pub(crate) fn create(
        mac_addr: Option<MacAddress>,
        network: Option<IpNetwork>,
    ) -> io::Result<Self> {
        let mut config = tun::Configuration::default();
        config.layer(tun::Layer::L2);
        if let Some(network) = network {
            config.address(network.ip()).netmask(network.mask());
        }
        config.up();

        #[cfg(target_os = "linux")]
        config.platform_config(|platform| {
            // requiring root privilege to acquire complete functions
            platform.ensure_root_privileges(true);
        });

        let tap = tun::create(&config)?;
        let tap_fd = tap.as_raw_fd();

        if let Some(mac_addr) = mac_addr {
            Self::set_tap_mac(tap_fd, mac_addr)?;
            Ok(Self {
                inner: Arc::new(tap),
                mac_addr,
                network,
            })
        } else {
            Ok(Self {
                inner: Arc::new(tap),
                mac_addr: Self::get_tap_mac(tap_fd)?,
                network,
            })
        }
    }

    /// Sets the MAC address tap device
    #[allow(unsafe_code, clippy::cast_possible_wrap, clippy::as_conversions)] // converting u8 to i8 for sa_data
    fn set_tap_mac(tap_fd: i32, mac_addr: MacAddress) -> io::Result<()> {
        let mut sa_data = [0i8; 14];
        sa_data
            .iter_mut()
            .zip(mac_addr.0)
            .for_each(|(d, s)| *d = s as i8);
        let mut ifreq = libc::ifreq {
            ifr_name: [0; libc::IFNAMSIZ],
            ifr_ifru: libc::__c_anonymous_ifr_ifru {
                ifru_hwaddr: libc::sockaddr {
                    sa_family: libc::ARPHRD_ETHER,
                    sa_data,
                },
            },
        };

        if unsafe { libc::ioctl(tap_fd, libc::SIOCSIFHWADDR, &mut ifreq) } == -1 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    /// Gets the MAC address of the tap device
    #[allow(unsafe_code)]
    #[allow(clippy::as_conversions, clippy::cast_sign_loss)] // converting i8 to u8 MAC address
    fn get_tap_mac(tap_fd: i32) -> io::Result<MacAddress> {
        let mut ifreq = libc::ifreq {
            ifr_name: [0; libc::IFNAMSIZ],
            ifr_ifru: libc::__c_anonymous_ifr_ifru {
                ifru_hwaddr: libc::sockaddr {
                    sa_family: libc::ARPHRD_ETHER,
                    sa_data: [0; 14],
                },
            },
        };

        if unsafe { libc::ioctl(tap_fd, libc::SIOCGIFHWADDR, &mut ifreq) } == -1 {
            return Err(io::Error::last_os_error());
        }

        let sa_data = unsafe { ifreq.ifr_ifru.ifru_hwaddr.sa_data };
        let mac = [
            sa_data[0] as u8,
            sa_data[1] as u8,
            sa_data[2] as u8,
            sa_data[3] as u8,
            sa_data[4] as u8,
            sa_data[5] as u8,
        ];
        Ok(MacAddress(mac))
    }
}

impl NetworkResolver for TapDevice {
    #[inline]
    fn resolve_dynamic(&self) -> io::Result<NetworkConfig> {
        // unimplement
        Err(io::ErrorKind::Unsupported.into())
    }
}
