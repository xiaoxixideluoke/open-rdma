use crate::types::VirtAddr;

pub(crate) fn check_addr_is_anon_hugepage(addr: VirtAddr, length: usize) -> bool {
    use pagemap::PageMap;

    let pid = std::process::id() as u64;

    // Instantiate a new pagemap::PageMap.
    let mut pm = PageMap::new(pid).unwrap();
    let me = pm
        .maps()
        .unwrap()
        .into_iter()
        .find(|me| me.memory_region().contains(addr.as_u64()))
        .expect("mapping not found");
    if addr.as_u64() + length as u64 > me.memory_region().last_address() + 1 {
        panic!("mapping length exceeds region");
    }
    log::info!(
        "[ADDR_DEBUG] addr: {addr:x}, length: {length},mapping: {}",
        me
    );
    me.path().is_some_and(|p| p.ends_with("anon_hugepage"))
}

#[test]
fn test_check_addr_is_anon_hugepage() {
    use std::ptr;

    let len = 1024 * 1024 * 4; // 4MB

    //TODO need to move unsafe code to a separate function
    #[allow(unsafe_code)]
    let ptr = unsafe {
        libc::mmap(
            ptr::null_mut(),
            len,
            libc::PROT_READ | libc::PROT_WRITE,
            libc::MAP_SHARED | libc::MAP_ANON | libc::MAP_HUGETLB | libc::MAP_HUGE_2MB,
            -1,
            0,
        )
    };

    if ptr == libc::MAP_FAILED {
        panic!("mmap failed");
    }
    let addr = VirtAddr::new(ptr as u64);
    assert!(check_addr_is_anon_hugepage(addr, len));
}
