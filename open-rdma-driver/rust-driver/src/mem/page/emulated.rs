use std::io;

use crate::{
    mem::{pa_va_map::PaVaMap, DmaBuf, DmaBufAllocator, PAGE_SIZE},
    types::{PhysAddr, VirtAddr},
};

use super::{ContiguousPages, MmapMut, PageAllocator};

const DEFAULT_ALLOCATOR_SIZE: usize = 128 * 1024 * 1024; // 128 MiB

/// A page allocator for allocating pages of emulated physical memory
#[derive(Debug)]
pub(crate) struct EmulatedPageAllocator<const N: usize> {
    /// Inner
    inner: Vec<MmapMut>,
}

impl<const N: usize> EmulatedPageAllocator<N> {
    /// TODO: implements allocating multiple consecutive pages
    const _OK: () = assert!(
        N == 1,
        "allocating multiple contiguous pages is currently unsupported"
    );

    /// Creates a new `EmulatedPageAllocator`
    #[allow(clippy::as_conversions)] // usize to *mut c_void is safe
    pub(crate) fn new(size: Option<usize>, pa_va_map: &mut PaVaMap) -> Self {
        let size = size.unwrap_or(DEFAULT_ALLOCATOR_SIZE);
        let ptr = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                size, // 修复: 分配完整的 size 大小的内存
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_ANONYMOUS | libc::MAP_PRIVATE,
                -1,
                0,
            )
        };

        if ptr == libc::MAP_FAILED {
            panic!("Failed to allocate memory");
        }

        // WARN: 假设va永远不会与真实的pa重叠
        pa_va_map.insert(PhysAddr::new(ptr as u64), VirtAddr::new(ptr as u64), size);

        let inner: Vec<_> = (0..size)
            .step_by(PAGE_SIZE)
            .map(|offset| MmapMut::new(unsafe { ptr.offset(offset as isize) }, PAGE_SIZE))
            .collect();

        Self { inner }
    }
}

impl<const N: usize> PageAllocator<N> for EmulatedPageAllocator<N> {
    #[allow(unsafe_code)]
    fn alloc(&mut self) -> io::Result<ContiguousPages<N>> {
        self.inner
            .pop()
            .map(ContiguousPages::new)
            .ok_or(io::ErrorKind::OutOfMemory.into())
    }
}

impl DmaBufAllocator for EmulatedPageAllocator<1> {
    #[allow(clippy::unwrap_in_result, clippy::unwrap_used)]
    fn alloc(&mut self, _len: usize) -> io::Result<DmaBuf> {
        let buf = self
            .inner
            .pop()
            .ok_or(io::Error::from(io::ErrorKind::OutOfMemory))?;
        // WARN: 假设 DMA buffer 的 va = pa (仿真模式简化假设)
        let phys_addr = PhysAddr::new(buf.as_ptr() as u64);
        Ok(DmaBuf::new(buf, phys_addr))
    }
}

#[test]
fn test_libc_behave() {
    unsafe {
        let ptr = libc::mmap(
            std::ptr::null_mut(),
            PAGE_SIZE,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_PRIVATE | libc::MAP_ANON,
            -1,
            0,
        );

        let result = libc::mlock(ptr, PAGE_SIZE);

        println!("result is {}", result);
        let result = libc::mlock(ptr, PAGE_SIZE);

        println!("result is {}", result);

        let result = libc::munlock(ptr as *const std::ffi::c_void, PAGE_SIZE);

        println!("result is {}", result);
        let result = libc::munlock(ptr as *const std::ffi::c_void, PAGE_SIZE);

        println!("result is {}", result);
        assert_ne!(ptr, libc::MAP_FAILED);
        println!("mmap ptr: {:p}", ptr);
        println!("page size: {}", PAGE_SIZE);
        let _ = libc::munmap(ptr, PAGE_SIZE);
    }
}
