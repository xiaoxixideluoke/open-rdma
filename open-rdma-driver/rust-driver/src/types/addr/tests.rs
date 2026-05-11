//! Tests for address types

use super::aligned::*;
use super::basic::*;

#[test]
fn test_virt_addr_basic() {
    let addr = VirtAddr::new(0x1000);
    assert_eq!(addr.as_u64(), 0x1000);
}

#[test]
fn test_virt_addr_alignment() {
    let addr = VirtAddr::new(0x1000);
    assert!(addr.is_aligned_to(0x1000));
    assert!(addr.is_aligned_to(0x100));
    assert!(!addr.is_aligned_to(0x2000));
}

#[test]
fn test_phys_addr_split() {
    let addr = PhysAddr::new(0x1234_5678_9ABC_DEF0);
    let (lo, hi) = addr.split();
    assert_eq!(lo, 0x9ABC_DEF0);
    assert_eq!(hi, 0x1234_5678);
    assert_eq!(PhysAddr::from_parts(lo, hi), addr);
}

#[test]
fn test_offset() {
    let virt = VirtAddr::new(0x1000);
    assert_eq!(virt.offset(0x100), Some(VirtAddr::new(0x1100)));

    let phys = PhysAddr::new(0x2000);
    assert_eq!(phys.offset(0x200), Some(PhysAddr::new(0x2200)));

    let csr = CsrOffset::new(0x100);
    assert_eq!(csr.offset(0x10), Some(CsrOffset::new(0x110)));
}

#[test]
fn test_offset_overflow() {
    let virt = VirtAddr::new(u64::MAX);
    assert_eq!(virt.offset(1), None);

    let csr = CsrOffset::new(usize::MAX);
    assert_eq!(csr.offset(1), None);
}

#[test]
fn test_remote_addr_basic() {
    let addr = RemoteAddr::new(0x7000_0000);
    assert_eq!(addr.as_u64(), 0x7000_0000);
}

#[test]
fn test_remote_addr_offset() {
    let addr = RemoteAddr::new(0x1000);
    assert_eq!(addr.offset(0x500), Some(RemoteAddr::new(0x1500)));

    let addr_max = RemoteAddr::new(u64::MAX);
    assert_eq!(addr_max.offset(1), None);
}

#[test]
fn test_remote_addr_alignment() {
    let addr = RemoteAddr::new(0x4000);
    assert!(addr.is_aligned_to(0x1000));
    assert!(addr.is_aligned_to(0x4000));
    assert!(!addr.is_aligned_to(0x8000));
}

// ========================================================================
// Aligned Address Type Tests
// ========================================================================

#[test]
fn test_aligned_virt_addr_new_checked() {
    // 4KB aligned (2^12 = 4096)
    type Aligned4K = AlignedVirtAddr<12>;

    // Aligned address should succeed
    let addr = VirtAddr::new(0x1000);
    assert!(Aligned4K::new_checked(addr).is_some());

    // Unaligned address should fail
    let addr = VirtAddr::new(0x1001);
    assert!(Aligned4K::new_checked(addr).is_none());

    // Zero is aligned to everything
    let addr = VirtAddr::new(0);
    assert!(Aligned4K::new_checked(addr).is_some());
}

#[test]
fn test_aligned_phys_addr_new_checked() {
    // 2MB aligned (2^21)
    type Aligned2M = AlignedPhysAddr<21>;

    let addr = PhysAddr::new(0x20_0000);
    assert!(Aligned2M::new_checked(addr).is_some());

    let addr = PhysAddr::new(0x20_0001);
    assert!(Aligned2M::new_checked(addr).is_none());
}

#[test]
fn test_aligned_addr_align_down() {
    type Aligned4K = AlignedVirtAddr<12>;

    // Already aligned - no change
    let addr = VirtAddr::new(0x1000);
    let aligned = Aligned4K::align_down(addr);
    assert_eq!(aligned.as_u64(), 0x1000);

    // Unaligned - round down
    let addr = VirtAddr::new(0x1234);
    let aligned = Aligned4K::align_down(addr);
    assert_eq!(aligned.as_u64(), 0x1000);

    let addr = VirtAddr::new(0x1FFF);
    let aligned = Aligned4K::align_down(addr);
    assert_eq!(aligned.as_u64(), 0x1000);
}

#[test]
fn test_aligned_addr_align_up() {
    type Aligned4K = AlignedVirtAddr<12>;

    // Already aligned - no change
    let addr = VirtAddr::new(0x1000);
    let aligned = Aligned4K::align_up(addr).unwrap();
    assert_eq!(aligned.as_u64(), 0x1000);

    // Unaligned - round up
    let addr = VirtAddr::new(0x1001);
    let aligned = Aligned4K::align_up(addr).unwrap();
    assert_eq!(aligned.as_u64(), 0x2000);

    let addr = VirtAddr::new(0x1FFF);
    let aligned = Aligned4K::align_up(addr).unwrap();
    assert_eq!(aligned.as_u64(), 0x2000);

    // Overflow check
    let addr = VirtAddr::new(u64::MAX);
    assert!(Aligned4K::align_up(addr).is_none());
}

#[test]
fn test_aligned_addr_conversions() {
    type Aligned4K = AlignedVirtAddr<12>;

    let addr = VirtAddr::new(0x1000);
    let aligned = Aligned4K::new_checked(addr).unwrap();

    // Test conversions
    assert_eq!(aligned.as_u64(), 0x1000);
    assert_eq!(aligned.into_inner(), addr);

    // Test from_u64
    let aligned2 = Aligned4K::from_u64(0x2000).unwrap();
    assert_eq!(aligned2.as_u64(), 0x2000);

    assert!(Aligned4K::from_u64(0x2001).is_none());
}

#[test]
fn test_aligned_phys_addr_split() {
    type Aligned2M = AlignedPhysAddr<21>;

    let addr = PhysAddr::new(0x1234_5678_0020_0000);
    let aligned = Aligned2M::new_checked(addr).unwrap();

    let (lo, hi) = aligned.split();
    assert_eq!(lo, 0x0020_0000);
    assert_eq!(hi, 0x1234_5678);
}

#[test]
fn test_aligned_addr_offset_aligned() {
    type Aligned4K = AlignedVirtAddr<12>;

    let base = Aligned4K::from_u64(0x1000).unwrap();

    // Aligned offset maintains alignment
    let next = base.offset_aligned(0x1000).unwrap();
    assert_eq!(next.as_u64(), 0x2000);

    // Multiple pages
    let next = base.offset_aligned(0x3000).unwrap();
    assert_eq!(next.as_u64(), 0x4000);

    // Overflow check
    let base = Aligned4K::from_u64(u64::MAX - 0xFFF).unwrap();
    assert!(base.offset_aligned(0x1000).is_none());
}

#[test]
#[should_panic(expected = "is not aligned")]
#[cfg(debug_assertions)]
fn test_aligned_addr_offset_aligned_unaligned_panic() {
    type Aligned4K = AlignedVirtAddr<12>;
    let base = Aligned4K::from_u64(0x1000).unwrap();
    // Unaligned offset should panic in debug mode
    let _ = base.offset_aligned(0x1001);
}

#[test]
fn test_aligned_addr_offset_unaligned() {
    type Aligned4K = AlignedVirtAddr<12>;

    let base = Aligned4K::from_u64(0x1000).unwrap();

    // Unaligned offset returns VirtAddr (not aligned)
    let result = base.offset(0x100).unwrap();
    assert_eq!(result.as_u64(), 0x1100);
    assert!(!result.is_aligned_to(0x1000));
}

#[test]
fn test_page_aligned_type_aliases() {
    // Test that type aliases compile and work correctly
    #[cfg(feature = "page_size_4k")]
    {
        let addr = PageAlignedVirtAddr::from_u64(0x1000).unwrap();
        assert_eq!(addr.as_u64(), 0x1000);
        assert_eq!(PageAlignedVirtAddr::ALIGNMENT_BYTES, 4096);
    }

    #[cfg(feature = "page_size_2m")]
    {
        let addr = PageAlignedVirtAddr::from_u64(0x20_0000).unwrap();
        assert_eq!(addr.as_u64(), 0x20_0000);
        assert_eq!(PageAlignedVirtAddr::ALIGNMENT_BYTES, 2 * 1024 * 1024);
    }

    // Explicit aliases always work
    let huge = HugePageAlignedVirtAddr::from_u64(0x20_0000).unwrap();
    assert_eq!(huge.as_u64(), 0x20_0000);
    assert_eq!(HugePageAlignedVirtAddr::ALIGNMENT_BYTES, 2 * 1024 * 1024);
}

#[test]
fn test_cache_aligned_addresses() {
    // 64-byte cache line alignment (2^6)
    let addr = CacheAlignedVirtAddr::from_u64(0x40).unwrap();
    assert_eq!(addr.as_u64(), 0x40);
    assert_eq!(CacheAlignedVirtAddr::ALIGNMENT_BYTES, 64);

    // Unaligned to cache line
    assert!(CacheAlignedVirtAddr::from_u64(0x41).is_none());
}

#[test]
fn test_different_alignment_levels() {
    // Test that different alignment levels are distinct types
    let addr4k = Aligned4KVirtAddr::from_u64(0x1000).unwrap();
    let addr2m = HugePageAlignedVirtAddr::from_u64(0x20_0000).unwrap();
    let addr1g = GigaPageAlignedVirtAddr::from_u64(0x4000_0000).unwrap();

    assert_eq!(addr4k.as_u64(), 0x1000);
    assert_eq!(addr2m.as_u64(), 0x20_0000);
    assert_eq!(addr1g.as_u64(), 0x4000_0000);

    assert_eq!(Aligned4KVirtAddr::ALIGNMENT_BYTES, 4096);
    assert_eq!(HugePageAlignedVirtAddr::ALIGNMENT_BYTES, 2 * 1024 * 1024);
    assert_eq!(GigaPageAlignedVirtAddr::ALIGNMENT_BYTES, 1024 * 1024 * 1024);
}

#[test]
fn test_aligned_addr_display() {
    type Aligned4K = AlignedVirtAddr<12>;
    let addr = Aligned4K::from_u64(0x1000).unwrap();
    let s = format!("{}", addr);
    assert!(s.contains("AlignedVirtAddr"));
    assert!(s.contains("12"));
    assert!(s.contains("0x1000"));
}
