// TODO: old code to delete, Host physical page allocator
// mod host_old;

/// Emulated page allocator
mod emulated;
pub(crate) mod host;

pub(crate) use emulated::EmulatedPageAllocator;

use std::{
    ffi::c_void,
    io,
    ops::{Deref, DerefMut},
    ptr,
};

/// A trait for allocating contiguous physical memory pages.
///
/// The generic parameter `N` specifies the number of contiguous pages to allocate.
pub(crate) trait PageAllocator<const N: usize> {
    /// Allocates N contiguous physical memory pages.
    ///
    /// # Returns
    ///
    /// Returns a `Result` containing either:
    /// - `Ok(ContiguousPages<N>)` - The allocated contiguous pages
    /// - `Err(e)` - An I/O error if allocation fails
    fn alloc(&mut self) -> io::Result<ContiguousPages<N>>;
}

/// A wrapper around mapped memory that ensures physical memory pages are consecutive.
pub(crate) struct ContiguousPages<const N: usize> {
    /// Mmap handle
    pub(super) inner: MmapMut,
}

impl<const N: usize> ContiguousPages<N> {
    /// Returns the start address
    #[allow(clippy::as_conversions)] // converting *mut c_void to u64
    pub(crate) fn addr(&self) -> u64 {
        self.inner.ptr as u64
    }

    /// Creates a new `ContiguousPages`
    pub(super) fn new(inner: MmapMut) -> Self {
        Self { inner }
    }
}

impl<const N: usize> Deref for ContiguousPages<N> {
    type Target = MmapMut;

    fn deref(&self) -> &Self::Target {
        &self.inner
    }
}

impl<const N: usize> DerefMut for ContiguousPages<N> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.inner
    }
}

/// Memory-mapped region of host memory.
#[derive(Debug)]
pub(crate) struct MmapMut {
    /// Raw pointer to the start of the mapped memory region
    pub(crate) ptr: *mut c_void,
    /// Length of the mapped memory region in bytes
    pub(crate) len: usize,
}

impl MmapMut {
    /// Creates a new `MmapMut`
    pub(crate) fn new(ptr: *mut c_void, len: usize) -> Self {
        Self { ptr, len }
    }

    pub(crate) fn len(&self) -> usize {
        self.len
    }

    // TODO: optimize read/write performance
    #[allow(clippy::needless_pass_by_ref_mut)]
    pub(crate) fn copy_from(&mut self, offset: usize, src: &[u8]) {
        assert!(
            offset.saturating_add(src.len()) <= self.len,
            "copy beyond mmap boundaries"
        );
        let ptr = self.ptr.cast::<u8>();
        for (i, x) in src.iter().enumerate() {
            unsafe {
                let ptr = ptr.add(offset + i);
                ptr::write_volatile(ptr, *x);
            }
        }
    }

    pub(crate) fn get(&self, offset: usize, len: usize) -> Vec<u8> {
        assert!(
            offset.saturating_add(len) <= self.len,
            "get beyond mmap boundaries"
        );
        let mut buf = Vec::with_capacity(len);
        let ptr = self.ptr.cast::<u8>();
        for i in offset..(offset + len) {
            unsafe {
                let ptr = ptr.add(i);
                buf.push(ptr::read_volatile(ptr));
            }
        }
        buf
    }

    pub(crate) fn as_ptr(&self) -> *const c_void {
        self.ptr
    }
}

#[allow(unsafe_code)]
#[allow(clippy::as_conversions, clippy::ptr_as_ptr)] // converting among different pointer types
/// Implementations of `MmapMut`
mod mmap_mut_impl {
    use super::MmapMut;

    impl Drop for MmapMut {
        fn drop(&mut self) {
            let _ignore = unsafe { libc::munmap(self.ptr, self.len) };
        }
    }

    unsafe impl Sync for MmapMut {}
    #[allow(unsafe_code)]
    unsafe impl Send for MmapMut {}
}
