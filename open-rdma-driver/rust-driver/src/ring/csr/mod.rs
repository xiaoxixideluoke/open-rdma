//! Control and Status Register (CSR) Access Layer
//!
//! This module provides a hardware abstraction layer for accessing device Control and Status
//! Registers (CSRs) through different backends (hardware PCIe, emulated UDP).
//!
//! # Architecture
//!
//! ```text
//! Application Layer (cmd, workers, net)
//!           ↓ uses
//! Ring Specifications (ring_specs.rs)
//!           ↓ builds
//! Generic Ring<Dev, Spec> (device_adaptor.rs)
//!           ↓ uses
//! DeviceAdaptor trait (device_adaptor.rs)
//!           ↓ implemented by
//! Hardware/Emulated/Mock Backends (hardware.rs, emulated.rs)
//! ```
//!
//! # Key Concepts
//!
//! ## DeviceAdaptor
//! Core trait providing low-level CSR read/write operations. Implemented by:
//! - `SysfsPciCsrAdaptor` - PCIe access via sysfs mmap (hardware)
//! - `VfioPciCsrAdaptor` - PCIe access via VFIO framework (hardware)
//! - `EmulatedDevice` - UDP RPC to RTL simulator (emulation)
//!
//! ## Ring<Dev, Spec>
//! Generic ring buffer control structure parameterized by:
//! - `Dev`: Device adaptor implementation (hardware/emulated)
//! - `Spec`: Ring specification (SendRingSpec, CmdReqSpec, etc.)
//!
//! ## Direction Safety
//! Rings are categorized by data flow direction:
//! - `RingSpecToCard` - Host produces, card consumes (impl `WriterOps`)
//! - `RingSpecToHost` - Card produces, host consumes (impl `ReaderOps`)
//!
//! Type system enforces correct operations at compile time:
//! ```rust,ignore
//! let send_ring: SendRing<Dev> = ...;  // ToCard
//! send_ring.write_head(10);  // ✅ OK - impl WriterOps
//! send_ring.write_tail(5);   // ❌ Compile error - no ReaderOps
//! ```
//!
//! # Ring Types
//!
//! | Ring Type | Direction | Producer | Consumer | Use Case |
//! |-----------|-----------|----------|----------|----------|
//! | SendRing | ToCard | Host | Card | Send work requests |
//! | MetaReportRing | ToHost | Card | Host | Packet metadata |
//! | CmdReqRing | ToCard | Host | Card | Management commands |
//! | CmdRespRing | ToHost | Card | Host | Command responses |
//! | SimpleNicTxRing | ToCard | Host | Card | Raw packet TX |
//! | SimpleNicRxRing | ToHost | Card | Host | Raw packet RX |
//!
//! # Example
//!
//! ```rust,ignore
//! use crate::csr::{EmulatedDevice, build_send_rings, Mode, WriterOps};
//!
//! // Create device adaptor
//! let dev = EmulatedDevice::new("uverbs0")?;
//!
//! // Build rings based on device mode
//! let send_rings = build_send_rings(dev.clone(), Mode::Mode400G);
//! assert_eq!(send_rings.len(), 4);  // 4 channels in 400G mode
//!
//! // Use ring operations
//! send_rings[0].write_head(32)?;  // Update producer pointer
//! let tail = send_rings[0].read_tail()?;  // Read consumer progress
//! ```

#![allow(clippy::todo)] // FIXME: implement
#![allow(clippy::missing_errors_doc)] // FIXME: add error docs
#![allow(unused_imports)] // TODO

/// Core device adaptor trait and ring abstractions
pub(crate) mod ring_csr;

mod backends;

/// Device operating mode configuration (100G/200G/400G)
pub(crate) mod mode;

/// Memory-mapped I/O addresses of device registers
pub(crate) mod constants;

pub(crate) use backends::*;
// Re-export core types for convenient access
pub(crate) use ring_csr::*;
