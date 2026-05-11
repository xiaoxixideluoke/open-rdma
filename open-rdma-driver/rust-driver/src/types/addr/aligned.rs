//! Aligned address types with compile-time alignment guarantees
//!
//! This module provides aligned variants of VirtAddr and PhysAddr that
//! enforce alignment requirements at compile time using const generics.

use std::fmt;

use serde::{Deserialize, Serialize};

use super::basic::{PhysAddr, VirtAddr};

// ============================================================================
// Aligned Address Types (Compile-time Alignment Guarantee)
// ============================================================================

/// Aligned virtual address with compile-time alignment guarantee
///
/// The generic parameter `N` specifies the alignment in **bits** (not bytes).
/// The actual alignment is `2^N` bytes.
///
/// # Examples
///
/// ```
/// use types::addr::{VirtAddr, AlignedVirtAddr};
///
/// // Create a 4KB-aligned virtual address (2^12 = 4096 bytes)
/// let addr = VirtAddr::new(0x1000);
/// let aligned = AlignedVirtAddr::<12>::new_checked(addr)?;
///
/// // Type-safe: compiler knows this address is 4KB-aligned
/// assert_eq!(aligned.as_u64(), 0x1000);
/// ```
///
/// # Type Safety
///
/// This type guarantees at compile time that:
/// - The address is aligned to `2^N` bytes
/// - Only 2^N alignments are allowed (enforced by bit shift)
/// - The alignment bits N must be <= 63 (max address space)
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[repr(transparent)]
pub(crate) struct AlignedVirtAddr<const N: u8>(VirtAddr);

impl<const N: u8> AlignedVirtAddr<N> {
    // Compile-time check: N must be valid (0 < N <= 63)
    const _ALIGNMENT_RANGE_CHECK: () =
        assert!(N > 0 && N <= 63, "Alignment bits must be in range 1..=63");

    /// Alignment in bytes (2^N)
    pub(crate) const ALIGNMENT_BYTES: u64 = 1u64 << N;

    /// Alignment mask for fast alignment operations
    const ALIGNMENT_MASK: u64 = Self::ALIGNMENT_BYTES - 1;

    /// Creates an aligned virtual address, checking alignment at runtime
    ///
    /// Returns `None` if the address is not aligned to `2^N` bytes.
    #[inline]
    pub(crate) const fn new_checked(addr: VirtAddr) -> Option<Self> {
        if addr.is_aligned_to(Self::ALIGNMENT_BYTES) {
            Some(Self(addr))
        } else {
            None
        }
    }

    /// Creates an aligned virtual address from a raw u64 value
    #[inline]
    pub(crate) const fn from_u64(val: u64) -> Option<Self> {
        Self::new_checked(VirtAddr::new(val))
    }

    /// Creates an aligned virtual address from a pointer
    #[inline]
    pub(crate) fn from_ptr<T>(ptr: *const T) -> Option<Self> {
        Self::new_checked(VirtAddr::from_ptr(ptr))
    }

    /// Creates an aligned virtual address without checking alignment
    ///
    /// # Safety
    ///
    /// The caller must ensure that `addr` is aligned to `2^N` bytes.
    /// Violating this may lead to undefined behavior in downstream code
    /// that relies on the alignment guarantee.
    #[inline]
    #[allow(unsafe_code)]
    pub(crate) const unsafe fn new_unchecked(addr: VirtAddr) -> Self {
        // Note: debug_assert! cannot be used in const fn
        // Callers must ensure alignment manually
        Self(addr)
    }

    /// Aligns down to the nearest aligned address
    ///
    /// This always succeeds and returns a valid aligned address.
    #[inline]
    pub(crate) const fn align_down(addr: VirtAddr) -> Self {
        let raw = addr.as_u64();
        let aligned = raw & !Self::ALIGNMENT_MASK;
        Self(VirtAddr::new(aligned))
    }

    /// Attempts to align up to the nearest aligned address
    ///
    /// Returns `None` if alignment would cause overflow.
    #[inline]
    pub(crate) const fn align_up(addr: VirtAddr) -> Option<Self> {
        let raw = addr.as_u64();
        let aligned = match raw.checked_add(Self::ALIGNMENT_MASK) {
            Some(val) => val & !Self::ALIGNMENT_MASK,
            None => return None,
        };
        Some(Self(VirtAddr::new(aligned)))
    }

    /// Returns the underlying unaligned virtual address
    #[inline]
    pub(crate) const fn into_inner(self) -> VirtAddr {
        self.0
    }

    /// Returns the raw address value
    #[inline]
    pub(crate) const fn as_u64(self) -> u64 {
        self.0.as_u64()
    }

    /// Converts to a raw pointer
    #[inline]
    pub(crate) fn as_ptr<T>(self) -> *const T {
        self.0.as_ptr()
    }

    /// Converts to a mutable raw pointer
    #[inline]
    pub(crate) fn as_mut_ptr<T>(self) -> *mut T {
        self.0.as_mut_ptr()
    }

    /// Adds an aligned offset, maintaining alignment guarantee
    ///
    /// The offset must be a multiple of `2^N` bytes to maintain alignment.
    /// Returns `None` if overflow occurs.
    #[inline]
    #[allow(unsafe_code)]
    pub(crate) fn offset_aligned(self, offset: u64) -> Option<Self> {
        debug_assert!(
            offset % Self::ALIGNMENT_BYTES == 0,
            "Offset 0x{:x} is not aligned to {} bytes",
            offset,
            Self::ALIGNMENT_BYTES
        );
        let new_addr = self.0.offset(offset)?;
        // SAFETY: Both base and offset are aligned to 2^N
        Some(unsafe { Self::new_unchecked(new_addr) })
    }

    /// Adds an unaligned offset, losing alignment guarantee
    ///
    /// Returns an unaligned `VirtAddr` since the result may not be aligned.
    #[inline]
    pub(crate) fn offset(self, offset: u64) -> Option<VirtAddr> {
        self.0.offset(offset)
    }
}

impl<const N: u8> fmt::Display for AlignedVirtAddr<N> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "AlignedVirtAddr<{}>(0x{:x})", N, self.0.as_u64())
    }
}

impl<const N: u8> fmt::LowerHex for AlignedVirtAddr<N> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::LowerHex::fmt(&self.0, f)
    }
}

impl<const N: u8> fmt::UpperHex for AlignedVirtAddr<N> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::UpperHex::fmt(&self.0, f)
    }
}

/// Aligned physical address with compile-time alignment guarantee
///
/// The generic parameter `N` specifies the alignment in **bits** (not bytes).
/// The actual alignment is `2^N` bytes.
///
/// # Examples
///
/// ```
/// use types::addr::{PhysAddr, AlignedPhysAddr};
///
/// // Create a 2MB-aligned physical address (2^21 = 2097152 bytes)
/// let addr = PhysAddr::new(0x20_0000);
/// let aligned = AlignedPhysAddr::<21>::new_checked(addr)?;
///
/// // Split for hardware register writes
/// let (lo, hi) = aligned.split();
/// ```
///
/// # Type Safety
///
/// This type is critical for:
/// - DMA buffer allocation (requires page alignment)
/// - Hardware register writes (CSR base addresses)
/// - Memory translation table (MTT/PGT) entries
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[repr(transparent)]
pub(crate) struct AlignedPhysAddr<const N: u8>(PhysAddr);

impl<const N: u8> AlignedPhysAddr<N> {
    const _ALIGNMENT_RANGE_CHECK: () =
        assert!(N > 0 && N <= 63, "Alignment bits must be in range 1..=63");

    pub(crate) const ALIGNMENT_BYTES: u64 = 1u64 << N;
    const ALIGNMENT_MASK: u64 = Self::ALIGNMENT_BYTES - 1;

    #[inline]
    pub(crate) const fn new_checked(addr: PhysAddr) -> Option<Self> {
        if addr.is_aligned_to(Self::ALIGNMENT_BYTES) {
            Some(Self(addr))
        } else {
            None
        }
    }

    #[inline]
    pub(crate) const fn from_u64(val: u64) -> Option<Self> {
        Self::new_checked(PhysAddr::new(val))
    }

    #[inline]
    #[allow(unsafe_code)]
    pub(crate) const unsafe fn new_unchecked(addr: PhysAddr) -> Self {
        // Note: debug_assert! cannot be used in const fn
        // Callers must ensure alignment manually
        Self(addr)
    }

    #[inline]
    pub(crate) const fn align_down(addr: PhysAddr) -> Self {
        let raw = addr.as_u64();
        let aligned = raw & !Self::ALIGNMENT_MASK;
        Self(PhysAddr::new(aligned))
    }

    #[inline]
    pub(crate) const fn align_up(addr: PhysAddr) -> Option<Self> {
        let raw = addr.as_u64();
        let aligned = match raw.checked_add(Self::ALIGNMENT_MASK) {
            Some(val) => val & !Self::ALIGNMENT_MASK,
            None => return None,
        };
        Some(Self(PhysAddr::new(aligned)))
    }

    #[inline]
    pub(crate) const fn into_inner(self) -> PhysAddr {
        self.0
    }

    #[inline]
    pub(crate) const fn as_u64(self) -> u64 {
        self.0.as_u64()
    }

    /// Splits into low and high 32-bit parts (for CSR register writes)
    #[inline]
    pub(crate) fn split(self) -> (u32, u32) {
        self.0.split()
    }

    #[inline]
    #[allow(unsafe_code)]
    pub(crate) fn offset_aligned(self, offset: u64) -> Option<Self> {
        debug_assert!(
            offset % Self::ALIGNMENT_BYTES == 0,
            "Offset 0x{:x} is not aligned to {} bytes",
            offset,
            Self::ALIGNMENT_BYTES
        );
        let new_addr = self.0.offset(offset)?;
        Some(unsafe { Self::new_unchecked(new_addr) })
    }

    #[inline]
    pub(crate) fn offset(self, offset: u64) -> Option<PhysAddr> {
        self.0.offset(offset)
    }
}

impl<const N: u8> fmt::Display for AlignedPhysAddr<N> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "AlignedPhysAddr<{}>(0x{:x})", N, self.0.as_u64())
    }
}

impl<const N: u8> fmt::LowerHex for AlignedPhysAddr<N> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::LowerHex::fmt(&self.0, f)
    }
}

impl<const N: u8> fmt::UpperHex for AlignedPhysAddr<N> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::UpperHex::fmt(&self.0, f)
    }
}

// ============================================================================
// Type Aliases for Common Alignments
// ============================================================================

// Page-aligned addresses (depends on feature flag)
#[cfg(feature = "page_size_4k")]
pub(crate) type PageAlignedVirtAddr = AlignedVirtAddr<12>; // 2^12 = 4096 bytes
#[cfg(feature = "page_size_4k")]
pub(crate) type PageAlignedPhysAddr = AlignedPhysAddr<12>;

#[cfg(feature = "page_size_2m")]
pub(crate) type PageAlignedVirtAddr = AlignedVirtAddr<21>; // 2^21 = 2MB
#[cfg(feature = "page_size_2m")]
pub(crate) type PageAlignedPhysAddr = AlignedPhysAddr<21>;

// Explicit size aliases (independent of feature flags)
pub(crate) type HugePageAlignedVirtAddr = AlignedVirtAddr<21>; // 2MB
pub(crate) type HugePageAlignedPhysAddr = AlignedPhysAddr<21>;

pub(crate) type GigaPageAlignedVirtAddr = AlignedVirtAddr<30>; // 1GB
pub(crate) type GigaPageAlignedPhysAddr = AlignedPhysAddr<30>;

pub(crate) type Aligned4KVirtAddr = AlignedVirtAddr<12>; // 4KB
pub(crate) type Aligned4KPhysAddr = AlignedPhysAddr<12>;

// Cache line alignment (common for DMA descriptors)
pub(crate) type CacheAlignedVirtAddr = AlignedVirtAddr<6>; // 2^6 = 64 bytes
pub(crate) type CacheAlignedPhysAddr = AlignedPhysAddr<6>;
