use core::ffi::c_void;
use std::alloc::Layout;
use std::collections::HashMap;
use std::ptr::NonNull;
use std::sync::LazyLock;
use std::sync::Mutex;
use std::sync::OnceLock;

use ctor;
use libc::size_t;
use log::LevelFilter;
use log::{Metadata, Record};

struct SimpleLogger;

impl log::Log for SimpleLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= LevelFilter::Debug
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            // format! 使用 mimalloc，不会调用你的 malloc，安全
            let msg = format!("{} - {}\n", record.level(), record.args());

            // 直接系统调用，不经过 Rust 的 stdout，不会访问 thread-local
            unsafe {
                libc::write(2, msg.as_ptr() as *const libc::c_void, msg.len());
            }
        }
    }

    fn flush(&self) {}
}

static LOGGER: SimpleLogger = SimpleLogger;
static ONCE_INIT: OnceLock<()> = OnceLock::new();
#[ctor::ctor]
fn init_logger() {
    ONCE_INIT.get_or_init(|| {
        log::set_logger(&LOGGER)
            .map(|()| log::set_max_level(LevelFilter::Info))
            .unwrap();
    });
}

use buddy_system_allocator::LockedHeap;

#[global_allocator]
static A: mimalloc::MiMalloc = mimalloc::MiMalloc;

const HEAP_SIZE: usize = 1 << 28;
const HEAP_ORDER: usize = 32;
static HACK_HEAP: LazyLock<LockedHeap<HEAP_ORDER>> = LazyLock::new(|| {
    let heap = LockedHeap::empty();
    unsafe {
        let start = libc::mmap(
            std::ptr::null_mut(),
            HEAP_SIZE,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_PRIVATE | libc::MAP_ANON | libc::MAP_HUGETLB | libc::MAP_HUGE_2MB,
            -1,
            0,
        );

        if start == libc::MAP_FAILED {
            let errno = *libc::__errno_location();
            log::error!(
                "mmap failed with errno: {} (HEAP_SIZE={})",
                errno,
                HEAP_SIZE
            );
            panic!("heap init fail!");
        }

        let start_addr = start as usize;
        let end_addr = start_addr + HEAP_SIZE;

        let ppid = unsafe { libc::getppid() };
        // 输出 hugepage 堆的地址范围
        log::info!(
            "[hack_libc] HACK_HEAP: {:p} - {:p} ({}MB hugepage), pid is {}, ppid is {}",
            start as *const u8,
            end_addr as *const u8,
            HEAP_SIZE / (1024 * 1024),
            std::process::id(),
            ppid
        );

        heap.lock().init(start_addr, HEAP_SIZE);
        heap
    }
});

static ALLOC_LAYOUT: LazyLock<Mutex<HashMap<usize, Layout>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// 存储通过 hipHostMalloc 分配的地址和大小（用于 hipHostFree）
static MMAP_ALLOCS: LazyLock<Mutex<HashMap<usize, usize>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

// #[unsafe(no_mangle)]
// unsafe extern "C" fn malloc(size: size_t) -> *mut c_void {
//     // log::debug!("malloc called");
//     let layout = Layout::from_size_align(size, 16).unwrap();
//     let ptr = HACK_HEAP.lock().alloc(layout).unwrap().as_ptr() as *mut c_void;
//     ALLOC_LAYOUT.lock().unwrap().insert(ptr as usize, layout);

//     ptr
// }

// static REALLOC_SYMBOL: LazyLock<unsafe extern "C" fn(*mut c_void, size_t) -> *mut c_void> =
//     LazyLock::new(|| unsafe {
//         let sym = libc::dlsym(libc::RTLD_NEXT, b"realloc\0".as_ptr() as *const i8);
//         std::mem::transmute(sym)
//     });

// #[unsafe(no_mangle)]
// unsafe extern "C" fn realloc(ptr: *mut c_void, size: size_t) -> *mut c_void {
//     unsafe {
//         log::debug!("realloc called");

//         // 如果 ptr 是 null，realloc 等同于 malloc
//         if ptr.is_null() {
//             return malloc(size);
//         }

//         // 如果 size 是 0，realloc 等同于 free
//         if size == 0 {
//             free(ptr);
//             return std::ptr::null_mut();
//         }

//         // 检查这个指针是否是我们分配的
//         let old_layout_opt = ALLOC_LAYOUT.lock().unwrap().get(&(ptr as usize)).copied();

//         if let Some(old_layout) = old_layout_opt {
//             // 是我们分配的内存
//             let new_layout = Layout::from_size_align(size, 16).unwrap();

//             // 分配新内存
//             let new_ptr = HACK_HEAP.lock().alloc(new_layout).unwrap().as_ptr() as *mut c_void;

//             // 复制旧数据
//             let copy_size = std::cmp::min(old_layout.size(), size);
//             std::ptr::copy_nonoverlapping(ptr as *const u8, new_ptr as *mut u8, copy_size);

//             // 释放旧内存
//             ALLOC_LAYOUT.lock().unwrap().remove(&(ptr as usize));
//             HACK_HEAP
//                 .lock()
//                 .dealloc(NonNull::new(ptr as *mut u8).unwrap(), old_layout);

//             // 记录新内存
//             ALLOC_LAYOUT
//                 .lock()
//                 .unwrap()
//                 .insert(new_ptr as usize, new_layout);

//             new_ptr
//         } else {
//             // 不是我们分配的内存，使用系统的 realloc
//             log::debug!("realloc: not our allocation, using system realloc");
//             (*REALLOC_SYMBOL)(ptr, size)
//         }
//     }
// }

// #[unsafe(no_mangle)]
// unsafe extern "C" fn calloc(nmemb: size_t, size: size_t) -> *mut c_void {
//     unsafe {
//         if nmemb == 0 || size == 0 {
//             return std::ptr::null_mut();
//         }

//         let total = nmemb * size;
//         let ptr = malloc(total);
//         if !ptr.is_null() {
//             std::ptr::write_bytes(ptr as *mut u8, 0, total);
//         }
//         ptr
//     }
// }

// #[unsafe(no_mangle)]
// unsafe extern "C" fn aligned_alloc(alignment: size_t, size: size_t) -> *mut c_void {
//     unsafe {
//         let layout = Layout::from_size_align(size, alignment).unwrap();
//         let ptr = HACK_HEAP.lock().alloc(layout).unwrap().as_ptr() as *mut c_void;
//         ALLOC_LAYOUT.lock().unwrap().insert(ptr as usize, layout);

//         log::debug!(
//             "[hack_libc] aligned_alloc: size={}, align={}, ptr={:p}",
//             size,
//             alignment,
//             ptr
//         );

//         ptr
//     }
// }

// #[unsafe(no_mangle)]
// unsafe extern "C" fn memalign(alignment: size_t, size: size_t) -> *mut c_void {
//     unsafe {
//         // memalign 和 aligned_alloc 功能相同
//         aligned_alloc(alignment, size)
//     }
// }

#[unsafe(no_mangle)]
unsafe extern "C" fn posix_memalign(
    memptr: *mut *mut c_void,
    alignment: size_t,
    size: size_t,
) -> i32 {
    unsafe {
        let layout = Layout::from_size_align(size, alignment).unwrap();

        let ptr = HACK_HEAP.lock().alloc(layout).unwrap().as_ptr() as *mut c_void;

        ALLOC_LAYOUT.lock().unwrap().insert(ptr as usize, layout);

        *memptr = ptr;

        log::debug!(
            "[hack_libc] posix_memalign: size={}, align={}, ptr={:p}",
            size,
            alignment,
            ptr
        );

        0
    }
}

static FREE_SYMBOL: LazyLock<unsafe extern "C" fn(*mut c_void)> = LazyLock::new(|| unsafe {
    let sym = libc::dlsym(libc::RTLD_NEXT, b"free\0".as_ptr() as *const i8);
    std::mem::transmute(sym)
});
#[unsafe(no_mangle)]
unsafe extern "C" fn free(ptr: *mut c_void) {
    unsafe {
        if ptr.is_null() {
            return;
        }

        log::debug!("free called");

        let layout_opt = ALLOC_LAYOUT.lock().unwrap().remove(&(ptr as usize));

        if let Some(layout) = layout_opt {
            HACK_HEAP
                .lock()
                .dealloc(NonNull::new(ptr as *mut u8).unwrap(), layout);
        } else {
            // 不是我们分配的内存，使用系统的 free
            log::debug!("free: not our allocation, using system free");
            (*FREE_SYMBOL)(ptr);
        }
    }
}

// HIP function types
type HipError = i32;
const HIP_SUCCESS: HipError = 0;
const HIP_ERROR_OUT_OF_MEMORY: HipError = 2;

// hipHostMalloc flags (these match hipHostRegister flags)
// hipHostMallocDefault = 0
// hipHostMallocPortable = 1
// hipHostMallocMapped = 2
// hipHostMallocWriteCombined = 4
// hipHostMallocNumaUser = 0x20000000
// hipHostMallocCoherent = 0x40000000
// hipHostMallocNonCoherent = 0x80000000

// 原始的 hipHostRegister 函数指针
static ORIG_HIP_HOST_REGISTER: LazyLock<
    unsafe extern "C" fn(*mut c_void, size_t, u32) -> HipError,
> = LazyLock::new(|| unsafe {
    let sym = libc::dlsym(libc::RTLD_NEXT, b"hipHostRegister\0".as_ptr() as *const i8);
    if sym.is_null() {
        panic!("Failed to find hipHostRegister");
    }
    std::mem::transmute(sym)
});

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hipHostMalloc(
    ptr: *mut *mut c_void,
    size: size_t,
    flags: u32,
) -> HipError {
    unsafe {
        if ptr.is_null() {
            return HIP_ERROR_OUT_OF_MEMORY;
        }

        // 使用 mmap 分配大页内存
        let mem = libc::mmap(
            std::ptr::null_mut(),
            size,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_PRIVATE | libc::MAP_ANON | libc::MAP_HUGETLB | libc::MAP_HUGE_2MB,
            -1,
            0,
        );

        if mem == libc::MAP_FAILED {
            let errno = *libc::__errno_location();
            log::error!(
                "[hack_libc] hipHostMalloc: mmap hugepage failed with errno: {}, size={}",
                errno,
                size
            );
            return HIP_ERROR_OUT_OF_MEMORY;
        }

        // 记录这次分配
        MMAP_ALLOCS.lock().unwrap().insert(mem as usize, size);

        log::info!(
            "[hack_libc] hipHostMalloc: allocated hugepage memory at {:p}, size={} bytes, flags={:#x}",
            mem,
            size,
            flags
        );

        // 使用 hipHostRegister 注册内存，直接使用传入的 flags
        // hipHostMalloc 和 hipHostRegister 的 flags 定义是兼容的
        let result = (*ORIG_HIP_HOST_REGISTER)(mem, size, flags);

        if result != HIP_SUCCESS {
            log::error!(
                "[hack_libc] hipHostMalloc: hipHostRegister failed with error: {}",
                result
            );

            // 清理已分配的内存
            libc::munmap(mem, size);
            MMAP_ALLOCS.lock().unwrap().remove(&(mem as usize));
            return result;
        }

        log::info!(
            "[hack_libc] hipHostMalloc: successfully registered memory at {:p}",
            mem
        );

        *ptr = mem;
        HIP_SUCCESS
    }
}

// 原始的 hipHostUnregister 函数指针
static ORIG_HIP_HOST_UNREGISTER: LazyLock<unsafe extern "C" fn(*mut c_void) -> HipError> =
    LazyLock::new(|| unsafe {
        let sym = libc::dlsym(
            libc::RTLD_NEXT,
            b"hipHostUnregister\0".as_ptr() as *const i8,
        );
        if sym.is_null() {
            panic!("Failed to find hipHostUnregister");
        }
        std::mem::transmute(sym)
    });

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hipHostFree(ptr: *mut c_void) -> HipError {
    unsafe {
        if ptr.is_null() {
            return HIP_SUCCESS;
        }

        log::debug!("[hack_libc] hipHostFree: freeing memory at {:p}", ptr);

        // 检查是否是我们通过 hipHostMalloc 分配的内存
        let size_opt = MMAP_ALLOCS.lock().unwrap().remove(&(ptr as usize));

        if let Some(size) = size_opt {
            // 先注销 HIP 注册
            let result = (*ORIG_HIP_HOST_UNREGISTER)(ptr);
            if result != HIP_SUCCESS {
                log::error!(
                    "[hack_libc] hipHostFree: hipHostUnregister failed with error: {}",
                    result
                );
            }

            // 释放 mmap 分配的内存
            libc::munmap(ptr, size);

            log::info!(
                "[hack_libc] hipHostFree: freed hugepage memory at {:p}, size={}",
                ptr,
                size
            );

            HIP_SUCCESS
        } else {
            log::debug!(
                "[hack_libc] hipHostFree: memory at {:p} not allocated by us",
                ptr
            );
            HIP_SUCCESS
        }
    }
}

#[test]
fn test_lib() {}
