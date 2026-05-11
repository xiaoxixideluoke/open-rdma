use core::ffi::{c_char, c_void};

use blue_rdma_driver::{BlueRdmaCore, RdmaCtxOps};

// const RXE_DEVICE_NAME: &str = "rxe_0";

#[unsafe(export_name = "bluerdma_init")]
pub unsafe extern "C" fn init() {
    let _ = env_logger::builder().format_timestamp(Some(env_logger::TimestampPrecision::Nanos)).try_init();
}

/// Safety: caller must ensure `sysfs_name` is a valid pointer.
#[unsafe(export_name = "bluerdma_new")]
pub unsafe extern "C" fn new(sysfs_name: *const c_char) -> *mut c_void {
    BlueRdmaCore::new(sysfs_name)
}

#[unsafe(export_name = "bluerdma_free")]
pub extern "C" fn free(driver_data: *const c_void) {
    BlueRdmaCore::free(driver_data)
}

#[unsafe(export_name = "bluerdma_alloc_pd")]
pub unsafe extern "C" fn alloc_pd(blue_context: *mut ffi::ibv_context) -> *mut ffi::ibv_pd {
    log::info!("Allocating protection domain");
    BlueRdmaCore::alloc_pd(blue_context)
}

#[unsafe(export_name = "bluerdma_dealloc_pd")]
pub unsafe extern "C" fn dealloc_pd(pd: *mut ffi::ibv_pd) -> ::std::os::raw::c_int {
    log::info!("Deallocating protection domain");
    BlueRdmaCore::dealloc_pd(pd)
}

#[unsafe(export_name = "bluerdma_query_device_ex")]
pub unsafe extern "C" fn query_device_ex(
    blue_context: *mut ffi::ibv_context,
    input: *const ffi::ibv_query_device_ex_input,
    device_attr: *mut ffi::ibv_device_attr,
    attr_size: usize,
) -> ::std::os::raw::c_int {
    log::info!("Querying device attributes");
    BlueRdmaCore::query_device_ex(blue_context, input, device_attr, attr_size)
}

#[unsafe(export_name = "bluerdma_query_port")]
pub unsafe extern "C" fn query_port(
    blue_context: *mut ffi::ibv_context,
    port_num: u8,
    port_attr: *mut ffi::ibv_port_attr,
) -> ::std::os::raw::c_int {
    log::info!("Querying port attributes");
    BlueRdmaCore::query_port(blue_context, port_num, port_attr)
}

#[unsafe(export_name = "bluerdma_create_cq")]
pub unsafe extern "C" fn create_cq(
    blue_context: *mut ffi::ibv_context,
    cqe: core::ffi::c_int,
    channel: *mut ffi::ibv_comp_channel,
    comp_vector: core::ffi::c_int,
) -> *mut ffi::ibv_cq {
    log::info!("Creating completion queue");
    BlueRdmaCore::create_cq(blue_context, cqe, channel, comp_vector)
}

#[unsafe(export_name = "bluerdma_destroy_cq")]
pub unsafe extern "C" fn destroy_cq(cq: *mut ffi::ibv_cq) -> ::std::os::raw::c_int {
    log::info!("Destroying completion queue");
    BlueRdmaCore::destroy_cq(cq)
}

#[unsafe(export_name = "bluerdma_create_qp")]
pub unsafe extern "C" fn create_qp(pd: *mut ffi::ibv_pd, init_attr: *mut ffi::ibv_qp_init_attr) -> *mut ffi::ibv_qp {
    log::info!("Creating queue pair");
    BlueRdmaCore::create_qp(pd, init_attr)
}

#[unsafe(export_name = "bluerdma_destroy_qp")]
pub unsafe extern "C" fn destroy_qp(qp: *mut ffi::ibv_qp) -> ::std::os::raw::c_int {
    log::info!("Destroying queue pair");
    BlueRdmaCore::destroy_qp(qp)
}

#[unsafe(export_name = "bluerdma_modify_qp")]
pub unsafe extern "C" fn modify_qp(
    qp: *mut ffi::ibv_qp,
    attr: *mut ffi::ibv_qp_attr,
    attr_mask: core::ffi::c_int,
) -> ::std::os::raw::c_int {
    log::info!("Modifying queue pair");
    BlueRdmaCore::modify_qp(qp, attr, attr_mask)
}

#[unsafe(export_name = "bluerdma_query_qp")]
pub unsafe extern "C" fn query_qp(
    qp: *mut ffi::ibv_qp,
    attr: *mut ffi::ibv_qp_attr,
    attr_mask: core::ffi::c_int,
    init_attr: *mut ffi::ibv_qp_init_attr,
) -> ::std::os::raw::c_int {
    log::info!("Querying queue pair");
    BlueRdmaCore::query_qp(qp, attr, attr_mask, init_attr)
}

#[unsafe(export_name = "bluerdma_reg_mr")]
pub unsafe extern "C" fn reg_mr(
    pd: *mut ffi::ibv_pd,
    addr: *mut ::std::os::raw::c_void,
    length: usize,
    hca_va: u64,
    access: core::ffi::c_int,
) -> *mut ffi::ibv_mr {
    log::info!("Registering memory region");
    BlueRdmaCore::reg_mr(pd, addr, length, hca_va, access)
}

#[unsafe(export_name = "bluerdma_dereg_mr")]
pub unsafe extern "C" fn dereg_mr(mr: *mut ffi::ibv_mr) -> ::std::os::raw::c_int {
    log::info!("Deregistering memory region");
    BlueRdmaCore::dereg_mr(mr)
}

#[unsafe(export_name = "bluerdma_post_send")]
pub unsafe extern "C" fn post_send(
    qp: *mut ffi::ibv_qp,
    wr: *mut ffi::ibv_send_wr,
    bad_wr: *mut *mut ffi::ibv_send_wr,
) -> ::std::os::raw::c_int {
    log::trace!("Posting send work request");
    BlueRdmaCore::post_send(qp, wr, bad_wr)
}

#[unsafe(export_name = "bluerdma_post_recv")]
pub unsafe extern "C" fn post_recv(
    qp: *mut ffi::ibv_qp,
    wr: *mut ffi::ibv_recv_wr,
    bad_wr: *mut *mut ffi::ibv_recv_wr,
) -> ::std::os::raw::c_int {
    log::trace!("Posting receive work request");
    BlueRdmaCore::post_recv(qp, wr, bad_wr)
}

#[unsafe(export_name = "bluerdma_poll_cq")]
pub unsafe extern "C" fn poll_cq(cq: *mut ffi::ibv_cq, num_entries: i32, wc: *mut ffi::ibv_wc) -> i32 {
    log::trace!("Polling completion queue");
    BlueRdmaCore::poll_cq(cq, num_entries, wc)
}
