use std::collections::BTreeMap;

use crate::mem::{UmemHandler, PAGE_SIZE, PAGE_SIZE_BITS};
use crate::types::addr::VirtAddr;
use std::ops::Range;
pub(crate) struct MrRegionManager(BTreeMap<usize, usize>);

fn phy_page_start(addr: usize) -> usize {
    (addr >> PAGE_SIZE_BITS) << PAGE_SIZE_BITS
}
impl MrRegionManager {
    pub(crate) fn new() -> Self {
        Self(BTreeMap::new())
    }

    pub(crate) fn insert(&mut self, addr: VirtAddr, length: usize, umem_handle: &impl UmemHandler) {
        let pin_range_maybe = self.insert_and_get_pin_range(addr, length);
        if let Some(pin_range) = pin_range_maybe {
            log::debug!("pin_range: {:?}", pin_range);
            umem_handle
                .pin_pages(
                    VirtAddr::new(pin_range.start as u64),
                    pin_range.end - pin_range.start,
                )
                .unwrap();
        }
    }

    pub(crate) fn remove(&mut self, addr: VirtAddr, length: usize, umem_handle: &impl UmemHandler) {
        let pin_range_maybe = self.remove_and_get_unpin_range(addr, length);

        // If start >= end, the physical pages are still being used by other regions
        // in the same page (e.g., multiple small regions within a 2MB huge page).
        // In this case, we should not unpin the pages.
        if let Some(pin_range) = pin_range_maybe {
            umem_handle
                .unpin_pages(
                    VirtAddr::new(pin_range.start as u64),
                    pin_range.end - pin_range.start,
                )
                .unwrap()
        }
    }

    fn get_pin_range(&self, start: usize, end: usize) -> Option<Range<usize>> {
        assert!(start < end);

        let start_page = phy_page_start(start);
        // inclusive
        let end_page = phy_page_start(end - 1);

        // mlock_start 是第一个包含的页
        let mlock_start = if let Some((tmp_start, tmp_len)) = self.0.range(..=start).last() {
            let tmp_end = tmp_start + tmp_len;
            // asset is not overlap
            assert!(tmp_end <= start);

            if phy_page_start(tmp_end - 1) == start_page {
                start_page + PAGE_SIZE
            } else {
                start_page
            }
        } else {
            start_page
        };

        // mlock_end is exclusive 本身位于的页不包含
        let mlock_end = if let Some((tmp_start, tmp_len)) = self.0.range(end..).next() {
            // asset is not overlap
            assert!(*tmp_start >= end);

            if phy_page_start(*tmp_start) == end_page {
                end_page
            } else {
                end_page + PAGE_SIZE
            }
        } else {
            end_page + PAGE_SIZE
        };

        if mlock_start >= mlock_end {
            None
        } else {
            Some(mlock_start..mlock_end)
        }
    }

    fn insert_and_get_pin_range(&mut self, addr: VirtAddr, length: usize) -> Option<Range<usize>> {
        let start = addr.as_u64() as usize;

        let end = start + length;

        // asset is not overlap
        assert!(self.0.range(start..end).next().is_none());

        let result = self.get_pin_range(start, end);

        //插入
        let replace = self.0.insert(start, length);
        assert!(replace.is_none());

        result
    }

    fn remove_and_get_unpin_range(
        &mut self,
        addr: VirtAddr,
        length: usize,
    ) -> Option<Range<usize>> {
        let start = addr.as_u64() as usize;

        let end = start + length;

        // 移除并判断相等
        let removed_len = self.0.remove(&start);
        assert!(removed_len.unwrap() == length);

        self.get_pin_range(start, end)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::verbs::mock::MockUmemHandler;

    #[test]
    fn test_new_manager() {
        let manager = MrRegionManager::new();
        assert!(manager.0.is_empty());
    }

    #[test]
    fn test_phy_page_start() {
        // Test 2MB page alignment (current configuration)
        assert_eq!(phy_page_start(0x0), 0x0);
        assert_eq!(phy_page_start(0x20_0000), 0x20_0000);
        assert_eq!(phy_page_start(0x21_0000), 0x20_0000);
        assert_eq!(phy_page_start(0x3F_FFFF), 0x20_0000);
        assert_eq!(phy_page_start(0x40_0000), 0x40_0000);

        // Test unaligned addresses
        assert_eq!(phy_page_start(0x12345), 0x0);
        assert_eq!(phy_page_start(0x200100), 0x200000);
    }

    #[test]
    fn test_insert_and_get_pin_range() {
        let mut manager = MrRegionManager::new();

        let addr = VirtAddr::new(0x20_0000);
        let length = PAGE_SIZE * 2;
        let range = manager.insert_and_get_pin_range(addr, length).unwrap();

        // Verify the region was inserted
        assert_eq!(manager.0.len(), 1);
        assert_eq!(manager.0.get(&(addr.as_u64() as usize)), Some(&length));

        // Verify the pin range
        assert_eq!(range.start, phy_page_start(addr.as_u64() as usize));
        assert_eq!(
            range.end,
            phy_page_start((addr.as_u64() as usize) + length - 1) + PAGE_SIZE
        );
    }

    #[test]
    #[should_panic]
    fn test_insert_overlapping_regions_panics() {
        let mut manager = MrRegionManager::new();

        // Insert first region
        let addr1 = VirtAddr::new(0x20_0000);
        let length1 = PAGE_SIZE * 4;
        let _ = manager.insert_and_get_pin_range(addr1, length1);

        // Try to insert overlapping region - should panic
        let addr2 = VirtAddr::new(0x60_0000); // Middle of first region
        let length2 = PAGE_SIZE;
        let _ = manager.insert_and_get_pin_range(addr2, length2);
    }

    #[test]
    #[should_panic(expected = "assertion failed")]
    fn test_insert_adjacent_overlapping_regions_panics() {
        let mut manager = MrRegionManager::new();

        // Insert first region
        let addr1 = VirtAddr::new(0x20_0000);
        let length1 = PAGE_SIZE;
        let _ = manager.insert_and_get_pin_range(addr1, length1);

        // Try to insert region at the same address - should panic
        let addr2 = VirtAddr::new(0x20_0000);
        let length2 = PAGE_SIZE;
        let _ = manager.insert_and_get_pin_range(addr2, length2);
    }

    #[test]
    fn test_get_pin_range_single_page() {
        let manager = MrRegionManager::new();

        // Test with no existing regions
        let start = 0x20_0000;
        let end = start + PAGE_SIZE;
        let range = manager.get_pin_range(start, end).unwrap();

        // Should pin the whole page
        assert_eq!(range.start, phy_page_start(start));
        assert_eq!(range.end, phy_page_start(start) + PAGE_SIZE);
    }

    #[test]
    fn test_get_pin_range_multiple_pages() {
        let manager = MrRegionManager::new();

        // Test range spanning multiple pages
        let start = 0x20_0000;
        let end = start + PAGE_SIZE * 3;
        let range = manager.get_pin_range(start, end).unwrap();

        assert_eq!(range.start, phy_page_start(start));
        assert_eq!(range.end, phy_page_start(end - 1) + PAGE_SIZE);
    }

    #[test]
    fn test_get_pin_range_with_existing_regions() {
        let mut manager = MrRegionManager::new();

        // Insert existing regions
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x20_0000), PAGE_SIZE);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x80_0000), PAGE_SIZE);

        // Test range that overlaps with first region
        let start = 0x40_0000;
        let end = start + PAGE_SIZE;
        let range = manager.get_pin_range(start, end).unwrap();

        // Should start from the next page after the existing region
        assert_eq!(range.start, phy_page_start(start));
        assert_eq!(range.end, phy_page_start(end - 1) + PAGE_SIZE);
    }

    #[test]
    fn test_get_pin_range_spanning_existing_regions() {
        let mut manager = MrRegionManager::new();

        // Insert existing regions with a gap
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x20_0000), PAGE_SIZE); // Page 32
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x80_0000), PAGE_SIZE); // Page 128

        // Test range that spans from before first region to after second region
        let start = 0x00_0000;
        let end = 0xA0_0000;
        let range = manager.get_pin_range(start, end).unwrap();

        // Should calculate range excluding existing regions
        // Start should be page-aligned
        // End should be after the last existing region
        assert_eq!(range.start, phy_page_start(start));
        assert_eq!(range.end, phy_page_start(end - 1) + PAGE_SIZE);
    }

    #[test]
    fn test_remove_and_get_unpin_range() {
        let mut manager = MrRegionManager::new();

        // Insert a region
        let addr = VirtAddr::new(0x20_0000);
        let length = PAGE_SIZE * 2;
        let _ = manager.insert_and_get_pin_range(addr, length);

        // Remove it
        let range = manager.remove_and_get_unpin_range(addr, length).unwrap();

        // Verify it was removed
        assert_eq!(manager.0.len(), 0);

        // Verify the unpin range
        assert_eq!(range.start, phy_page_start(addr.as_u64() as usize));
        assert_eq!(
            range.end,
            phy_page_start((addr.as_u64() as usize) + length - 1) + PAGE_SIZE
        );
    }

    #[test]
    #[should_panic]
    fn test_remove_nonexistent_region_panics() {
        let mut manager = MrRegionManager::new();

        // Try to remove non-existent region - should panic with unwrap on None
        manager.remove_and_get_unpin_range(VirtAddr::new(0x20_0000), PAGE_SIZE);
    }

    #[test]
    #[should_panic(expected = "assertion failed")]
    fn test_remove_with_wrong_length_panics() {
        let mut manager = MrRegionManager::new();

        // Insert a region
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x20_0000), PAGE_SIZE);

        // Try to remove with wrong length
        manager.remove_and_get_unpin_range(VirtAddr::new(0x20_0000), PAGE_SIZE * 2);
    }

    #[test]
    fn test_edge_case_zero_length() {
        let mut manager = MrRegionManager::new();

        // Insert region with minimal length
        let addr = VirtAddr::new(0x20_0000);
        let length = 1;
        let range = manager.insert_and_get_pin_range(addr, length).unwrap();

        // Should still pin the whole page
        assert_eq!(range.start, phy_page_start(addr.as_u64() as usize));
        assert_eq!(
            range.end,
            phy_page_start(addr.as_u64() as usize) + PAGE_SIZE
        );
    }

    #[test]
    fn test_edge_case_page_boundary() {
        let mut manager = MrRegionManager::new();

        // Insert region exactly at page boundary
        let addr = VirtAddr::new(PAGE_SIZE as u64);
        let length = PAGE_SIZE;
        let range = manager.insert_and_get_pin_range(addr, length).unwrap();

        assert_eq!(range.start, addr.as_u64() as usize);
        assert_eq!(range.end, (addr.as_u64() as usize) + PAGE_SIZE);
    }

    #[test]
    fn test_edge_case_unaligned_address() {
        let mut manager = MrRegionManager::new();

        // Insert region with unaligned address (within a 2MB page)
        // 0x21_1234 should align to 0x20_0000 (2MB boundary)
        let addr = VirtAddr::new(0x21_1234);
        let length = PAGE_SIZE;
        let range = manager.insert_and_get_pin_range(addr, length).unwrap();

        // Since addr is at 0x21_1234 (within 2MB page starting at 0x20_0000),
        // and length is PAGE_SIZE (2MB), the region spans:
        // - From 0x21_1234 to 0x21_1234 + 0x20_0000 = 0x41_1234
        // - This crosses page boundary, so it covers pages 0x20_0000 and 0x40_0000
        // - Total pin range is from 0x20_0000 to 0x60_0000 (3 pages)

        assert_eq!(range.start, 0x20_0000); // First page
        assert_eq!(range.end, 0x60_0000); // After last page
        assert_eq!(range.end - range.start, PAGE_SIZE * 2); // 2 pages total
    }

    #[test]
    fn test_large_region() {
        let mut manager = MrRegionManager::new();

        // Insert a very large region (2GB)
        let addr = VirtAddr::new(0x00_0000);
        let length = PAGE_SIZE * 1024;
        let range = manager.insert_and_get_pin_range(addr, length).unwrap();

        assert_eq!(range.start, phy_page_start(addr.as_u64() as usize));
        assert_eq!(
            range.end,
            phy_page_start((addr.as_u64() as usize) + length - 1) + PAGE_SIZE
        );
    }

    #[test]
    fn test_multiple_regions_with_gaps() {
        let mut manager = MrRegionManager::new();

        // Insert regions with specific gaps (2MB aligned)
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x20_0000), PAGE_SIZE); // Region 1
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x80_0000), PAGE_SIZE); // Region 2
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x100_0000), PAGE_SIZE * 2); // Region 3

        // Test pin range that spans across gaps
        let start = 0x00_0000;
        let end = 0x180_0000;
        let range = manager.get_pin_range(start, end).unwrap();

        // Should calculate range excluding existing regions
        assert_eq!(range.start, phy_page_start(start));
        assert_eq!(range.end, phy_page_start(end - 1) + PAGE_SIZE);
    }

    #[test]
    fn test_region_at_max_address() {
        let mut manager = MrRegionManager::new();

        // Insert region near maximum address - align to page boundary
        let max_page = phy_page_start(usize::MAX - PAGE_SIZE);
        let addr = VirtAddr::new(max_page as u64);
        let length = PAGE_SIZE;

        let range = manager.insert_and_get_pin_range(addr, length).unwrap();

        assert_eq!(range.start, phy_page_start(max_page));
        assert_eq!(range.end, phy_page_start(max_page) + PAGE_SIZE);
    }

    #[test]
    fn test_get_pin_range_exact_page_alignment() {
        let manager = MrRegionManager::new();

        // Test with exactly page-aligned addresses (2MB)
        let start = 0x20_0000;
        let end = 0x40_0000;
        let range = manager.get_pin_range(start, end).unwrap();

        assert_eq!(range.start, start);
        assert_eq!(range.end, end);
    }

    #[test]
    fn test_get_pin_range_spanning_single_page() {
        let manager = MrRegionManager::new();

        // Test range within a single page (2MB)
        let start = 0x20_1000;
        let end = 0x20_2000;
        let range = manager.get_pin_range(start, end).unwrap();

        assert_eq!(range.start, phy_page_start(start));
        assert_eq!(range.end, phy_page_start(start) + PAGE_SIZE);
    }

    #[test]
    fn test_btree_map_ordering() {
        let mut manager = MrRegionManager::new();

        // Insert regions in random order (2MB aligned)
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0xA0_0000), PAGE_SIZE);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x20_0000), PAGE_SIZE);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x60_0000), PAGE_SIZE);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x40_0000), PAGE_SIZE);

        // Verify BTreeMap maintains sorted order
        let keys: Vec<_> = manager.0.keys().copied().collect();
        assert_eq!(keys, vec![0x20_0000, 0x40_0000, 0x60_0000, 0xA0_0000]);
    }

    #[test]
    fn test_consecutive_regions() {
        let mut manager = MrRegionManager::new();

        // Insert consecutive regions (2MB aligned)
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x20_0000), PAGE_SIZE); // Page 32
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(0x40_0000), PAGE_SIZE); // Page 64

        assert_eq!(manager.0.len(), 2);

        // Test pin range that doesn't overlap with existing regions
        // Test a range before the first region
        let range1 = manager.get_pin_range(0x00_0000, 0x20_0000).unwrap();
        assert_eq!(range1.start, 0x00_0000);
        assert_eq!(range1.end, 0x20_0000);

        // Test a range between the two regions
        let range2 = manager.get_pin_range(0x60_0000, 0x80_0000).unwrap();
        assert_eq!(range2.start, 0x60_0000);
        assert_eq!(range2.end, 0x80_0000);

        // Test a range after the second region
        let range3 = manager.get_pin_range(0xC0_0000, 0xE0_0000).unwrap();
        assert_eq!(range3.start, 0xC0_0000);
        assert_eq!(range3.end, 0xE0_0000);
    }

    #[test]
    fn test_insert_multiple_non_overlapping_regions() {
        let mut manager = MrRegionManager::new();

        // Insert multiple non-overlapping regions directly (2MB aligned)
        manager.0.insert(0x20_0000, PAGE_SIZE);
        manager.0.insert(0x40_0000, PAGE_SIZE * 2);
        manager.0.insert(0x80_0000, PAGE_SIZE);
        manager.0.insert(0xA0_0000, PAGE_SIZE * 3);

        assert_eq!(manager.0.len(), 4);

        // Verify they are stored correctly
        assert_eq!(manager.0.get(&0x20_0000), Some(&PAGE_SIZE));
        assert_eq!(manager.0.get(&0x40_0000), Some(&(PAGE_SIZE * 2)));
        assert_eq!(manager.0.get(&0x80_0000), Some(&PAGE_SIZE));
        assert_eq!(manager.0.get(&0xA0_0000), Some(&(PAGE_SIZE * 3)));
    }

    #[test]
    fn test_get_pin_range_with_mixed_regions() {
        let mut manager = MrRegionManager::new();

        // Insert regions with various sizes and gaps (2MB aligned)
        manager.0.insert(0x20_0000, PAGE_SIZE); // Region 1
        manager.0.insert(0x40_0000, PAGE_SIZE); // Region 2
        manager.0.insert(0x80_0000, PAGE_SIZE * 4); // Region 3

        // Test pin range in the middle
        let start = 0x60_0000;
        let end = 0x70_0000;
        let range = manager.get_pin_range(start, end).unwrap();

        // Should calculate correctly with existing regions
        assert_eq!(range.start, phy_page_start(start));
        assert_eq!(range.end, phy_page_start(end - 1) + PAGE_SIZE);
    }

    #[test]
    fn test_remove_middle_region_same_page() {
        let mut manager = MrRegionManager::new();

        // Insert three small regions within the same 2MB page
        let page_base = 0x20_0000;
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(page_base), 0x1000);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(page_base + 0x2000), 0x1000);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(page_base + 0x1000), 0x1000);

        assert_eq!(manager.0.len(), 3);

        // Remove the middle region - should not panic
        let range_opt =
            manager.remove_and_get_unpin_range(VirtAddr::new(page_base + 0x1000), 0x1000);

        // The returned range should indicate that no unpinning is needed
        // because the page is still used by regions A and C
        // In this case, None is returned or start >= end
        if let Some(range) = range_opt {
            assert!(
                range.start >= range.end,
                "Expected start >= end when page is shared, got start={:#x}, end={:#x}",
                range.start,
                range.end
            );
        }

        assert_eq!(manager.0.len(), 2);
    }

    #[test]
    fn test_remove_all_regions_same_page() {
        let mut manager = MrRegionManager::new();

        // Insert three small regions within the same 2MB page
        let page_base = 0x20_0000;
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(page_base), 0x1000);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(page_base + 0x1000), 0x1000);
        let _ = manager.insert_and_get_pin_range(VirtAddr::new(page_base + 0x2000), 0x1000);

        // Remove middle region first
        let _ = manager.remove_and_get_unpin_range(VirtAddr::new(page_base + 0x1000), 0x1000);

        // Remove last region
        let _ = manager.remove_and_get_unpin_range(VirtAddr::new(page_base + 0x2000), 0x1000);

        // Remove first region - now the page should be unpinned
        let range = manager
            .remove_and_get_unpin_range(VirtAddr::new(page_base), 0x1000)
            .unwrap();

        // Should return a valid range to unpin the entire page
        assert!(range.start < range.end);
        assert_eq!(range.start, page_base as usize);
        assert_eq!(range.end, page_base as usize + PAGE_SIZE);
    }

    // Tests for public insert/remove methods with UmemHandler

    #[test]
    fn test_public_insert_and_remove() {
        let mut manager = MrRegionManager::new();
        let umem = MockUmemHandler;

        // Insert a region using public method
        let addr = VirtAddr::new(0x20_0000);
        let length = PAGE_SIZE * 2;
        manager.insert(addr, length, &umem);

        // Verify the region was inserted
        assert_eq!(manager.0.len(), 1);
        assert_eq!(manager.0.get(&(addr.as_u64() as usize)), Some(&length));

        // Remove the region using public method
        manager.remove(addr, length, &umem);

        // Verify it was removed
        assert_eq!(manager.0.len(), 0);
    }

    #[test]
    fn test_public_insert_multiple_regions() {
        let mut manager = MrRegionManager::new();
        let umem = MockUmemHandler;

        // Insert multiple non-overlapping regions
        manager.insert(VirtAddr::new(0x20_0000), PAGE_SIZE, &umem);
        manager.insert(VirtAddr::new(0x40_0000), PAGE_SIZE, &umem);
        manager.insert(VirtAddr::new(0x80_0000), PAGE_SIZE * 2, &umem);

        assert_eq!(manager.0.len(), 3);

        // Remove them in different order
        manager.remove(VirtAddr::new(0x40_0000), PAGE_SIZE, &umem);
        assert_eq!(manager.0.len(), 2);

        manager.remove(VirtAddr::new(0x80_0000), PAGE_SIZE * 2, &umem);
        assert_eq!(manager.0.len(), 1);

        manager.remove(VirtAddr::new(0x20_0000), PAGE_SIZE, &umem);
        assert_eq!(manager.0.len(), 0);
    }

    #[test]
    fn test_public_insert_remove_same_page() {
        let mut manager = MrRegionManager::new();
        let umem = MockUmemHandler;

        // Insert three small regions within the same 2MB page
        let page_base = 0x20_0000;
        manager.insert(VirtAddr::new(page_base), 0x1000, &umem);
        manager.insert(VirtAddr::new(page_base + 0x1000), 0x1000, &umem);
        manager.insert(VirtAddr::new(page_base + 0x2000), 0x1000, &umem);

        assert_eq!(manager.0.len(), 3);

        // Remove middle region first - page should still be pinned
        manager.remove(VirtAddr::new(page_base + 0x1000), 0x1000, &umem);
        assert_eq!(manager.0.len(), 2);

        // Remove last region - page should still be pinned
        manager.remove(VirtAddr::new(page_base + 0x2000), 0x1000, &umem);
        assert_eq!(manager.0.len(), 1);

        // Remove first region - now the page should be unpinned
        manager.remove(VirtAddr::new(page_base), 0x1000, &umem);
        assert_eq!(manager.0.len(), 0);
    }

    #[test]
    #[should_panic]
    fn test_public_remove_nonexistent() {
        let mut manager = MrRegionManager::new();
        let umem = MockUmemHandler;

        // Try to remove non-existent region - should panic
        manager.remove(VirtAddr::new(0x20_0000), PAGE_SIZE, &umem);
    }

    #[test]
    #[should_panic(expected = "assertion failed")]
    fn test_public_remove_wrong_length() {
        let mut manager = MrRegionManager::new();
        let umem = MockUmemHandler;

        // Insert a region
        manager.insert(VirtAddr::new(0x20_0000), PAGE_SIZE, &umem);

        // Try to remove with wrong length
        manager.remove(VirtAddr::new(0x20_0000), PAGE_SIZE * 2, &umem);
    }
}
