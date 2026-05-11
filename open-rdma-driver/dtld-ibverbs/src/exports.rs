//! C FFI wrappers for verbs

use ffi::{
    ibv_context, ibv_cq, ibv_device, ibv_device_attr, ibv_gid, ibv_mr, ibv_pd, ibv_qp, ibv_qp_attr, ibv_qp_init_attr,
};

/// Get list of IB devices currently available
///
/// @num_devices: optional. if non-NULL, set to the number of devices returned in the array.
///
/// Return a NULL-terminated array of IB devices.
/// The array can be released with ibv_free_device_list().
#[unsafe(export_name = "ibv_get_device_list")]
pub unsafe extern "C" fn ibv_get_device_list(num_devices: *mut ::std::os::raw::c_int) -> *mut *mut ibv_device {
    unsafe { ffi::ibv_get_device_list(num_devices) }
}

/// Get a GID table entry
#[unsafe(export_name = "ibv_query_gid")]
pub unsafe extern "C" fn ibv_query_gid(
    context: *mut ibv_context,
    port_num: u8,
    index: ::std::os::raw::c_int,
    gid: *mut ibv_gid,
) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_query_gid(context, port_num, index, gid) }
}

/// Modify a queue pair.
#[unsafe(export_name = "ibv_modify_qp")]
pub unsafe extern "C" fn ibv_modify_qp(
    qp: *mut ibv_qp,
    attr: *mut ibv_qp_attr,
    attr_mask: ::std::os::raw::c_int,
) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_modify_qp(qp, attr, attr_mask) }
}

/// Create a queue pair.
#[unsafe(export_name = "ibv_create_qp")]
pub unsafe extern "C" fn ibv_create_qp(pd: *mut ibv_pd, qp_init_attr: *mut ibv_qp_init_attr) -> *mut ibv_qp {
    unsafe { ffi::ibv_create_qp(pd, qp_init_attr) }
}

/// Destroy a queue pair.
#[unsafe(export_name = "ibv_destroy_qp")]
pub unsafe extern "C" fn ibv_destroy_qp(qp: *mut ibv_qp) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_destroy_qp(qp) }
}

/// Get device properties
#[unsafe(export_name = "ibv_query_device")]
pub unsafe extern "C" fn ibv_query_device(
    context: *mut ibv_context,
    device_attr: *mut ibv_device_attr,
) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_query_device(context, device_attr) }
}

/// ibv_open_device - Initialize device for use
#[unsafe(export_name = "ibv_open_device")]
pub unsafe extern "C" fn ibv_open_device(device: *mut ibv_device) -> *mut ibv_context {
    unsafe { ffi::ibv_open_device(device) }
}

/// Register memory region with a virtual offset address
///
/// This version will be called if ibv_reg_mr or ibv_reg_mr_iova were called
/// with at least one optional access flag from the IBV_ACCESS_OPTIONAL_RANGE
/// bits flag range. The optional access flags will be masked if running over
/// kernel that does not support passing them.
#[unsafe(export_name = "ibv_reg_mr_iova2")]
pub unsafe extern "C" fn ibv_reg_mr_iova2(
    pd: *mut ibv_pd,
    addr: *mut ::std::os::raw::c_void,
    length: usize,
    iova: u64,
    access: ::std::os::raw::c_uint,
) -> *mut ibv_mr {
    unsafe { ffi::ibv_reg_mr_iova2(pd, addr, length, iova, access) }
}

/// Allocate a protection domain
#[unsafe(export_name = "ibv_alloc_pd")]
pub unsafe extern "C" fn ibv_alloc_pd(context: *mut ibv_context) -> *mut ibv_pd {
    unsafe { ffi::ibv_alloc_pd(context) }
}

/// Return kernel device name
#[unsafe(export_name = "ibv_get_device_name")]
pub unsafe extern "C" fn ibv_get_device_name(device: *mut ibv_device) -> *const ::std::os::raw::c_char {
    unsafe { ffi::ibv_get_device_name(device) }
}

/// Destroy a completion queue
#[unsafe(export_name = "ibv_destroy_cq")]
pub unsafe extern "C" fn ibv_destroy_cq(cq: *mut ibv_cq) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_destroy_cq(cq) }
}

/// Release device
#[unsafe(export_name = "ibv_close_device")]
pub unsafe extern "C" fn ibv_close_device(context: *mut ibv_context) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_close_device(context) }
}

/// Deregister a memory region
#[unsafe(export_name = "ibv_dereg_mr")]
pub unsafe extern "C" fn ibv_dereg_mr(mr: *mut ibv_mr) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_dereg_mr(mr) }
}

/// Free a protection domain
#[unsafe(export_name = "ibv_dealloc_pd")]
pub unsafe extern "C" fn ibv_dealloc_pd(pd: *mut ibv_pd) -> ::std::os::raw::c_int {
    unsafe { ffi::ibv_dealloc_pd(pd) }
}
