//! User memory handler implementations
//!
//! Provides two implementations:
//! - `HostUmemHandler`: Real hardware environment
//! - `EmulatedUmemHandler`: Simulation environment

mod host;
mod emulated;

pub(crate) use host::HostUmemHandler;
pub(crate) use emulated::EmulatedUmemHandler;
