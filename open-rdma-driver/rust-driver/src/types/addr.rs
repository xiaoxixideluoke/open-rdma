//! Type-safe address abstractions
//!
//! This module provides newtype wrappers for different address spaces used in the driver:
//! - `VirtAddr`: User-space virtual addresses (local process)
//! - `PhysAddr`: Physical addresses for DMA operations
//! - `RemoteAddr`: Remote virtual addresses for RDMA operations
//! - `CsrOffset`: Control and Status Register offsets
//! - `AlignedVirtAddr<N>`: Page-aligned virtual addresses (compile-time guarantee)
//! - `AlignedPhysAddr<N>`: Page-aligned physical addresses (compile-time guarantee)
//!
//! These types prevent accidental mixing of address spaces at compile time,
//! which could lead to serious hardware errors like DMA writing to wrong addresses,
//! using local addresses in RDMA operations, or invalid register accesses.

mod aligned;
mod basic;

#[cfg(test)]
mod tests;

// Re-export basic address types
pub(crate) use basic::{PhysAddr, RemoteAddr, VirtAddr};

// Re-export aligned address types and type aliases

// Re-export page-aligned types (feature-dependent)
#[cfg(feature = "page_size_4k")]
pub(crate) use aligned::{PageAlignedPhysAddr, PageAlignedVirtAddr};

#[cfg(feature = "page_size_2m")]
pub(crate) use aligned::{PageAlignedPhysAddr, PageAlignedVirtAddr};
