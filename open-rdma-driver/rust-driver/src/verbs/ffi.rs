use parking_lot::Mutex;
use parking_lot::{lock_api::MutexGuard, RawMutex};

#[cfg(feature = "hw")]
use crate::verbs::dev::PciHwDevice;

#[cfg(feature = "sim")]
use crate::verbs::dev::EmulatedHwDevice;

#[cfg(feature = "mock")]
use crate::verbs::mock::MockDeviceCtx;

#[cfg(any(feature = "hw", feature = "sim"))]
use super::ctx::HwDeviceCtx;

use super::ctx::VerbsOps;

use std::sync::OnceLock;

/// RDMA context operations for Blue-RDMA driver.
///
/// # Safety
/// Implementors must ensure all FFI and RDMA verbs specification requirements are met,
pub unsafe trait RdmaCtxOps {
    fn init();

    #[allow(clippy::new_ret_no_self)]
    /// Safety: caller must ensure `sysfs_name` is a valid pointer
    fn new(sysfs_name: *const std::ffi::c_char) -> *mut std::ffi::c_void;

    fn free(driver_data: *const std::ffi::c_void);

    fn alloc_pd(blue_context: *mut ibverbs_sys::ibv_context) -> *mut ibverbs_sys::ibv_pd;

    fn dealloc_pd(pd: *mut ibverbs_sys::ibv_pd) -> ::std::os::raw::c_int;

    fn query_device_ex(
        blue_context: *mut ibverbs_sys::ibv_context,
        _input: *const ibverbs_sys::ibv_query_device_ex_input,
        device_attr: *mut ibverbs_sys::ibv_device_attr,
        _attr_size: usize,
    ) -> ::std::os::raw::c_int;

    fn query_port(
        blue_context: *mut ibverbs_sys::ibv_context,
        port_num: u8,
        port_attr: *mut ibverbs_sys::ibv_port_attr,
    ) -> ::std::os::raw::c_int;

    fn create_cq(
        blue_context: *mut ibverbs_sys::ibv_context,
        cqe: core::ffi::c_int,
        channel: *mut ibverbs_sys::ibv_comp_channel,
        comp_vector: core::ffi::c_int,
    ) -> *mut ibverbs_sys::ibv_cq;

    fn destroy_cq(cq: *mut ibverbs_sys::ibv_cq) -> ::std::os::raw::c_int;

    fn create_qp(
        pd: *mut ibverbs_sys::ibv_pd,
        init_attr: *mut ibverbs_sys::ibv_qp_init_attr,
    ) -> *mut ibverbs_sys::ibv_qp;

    fn destroy_qp(qp: *mut ibverbs_sys::ibv_qp) -> ::std::os::raw::c_int;

    fn modify_qp(
        qp: *mut ibverbs_sys::ibv_qp,
        attr: *mut ibverbs_sys::ibv_qp_attr,
        attr_mask: core::ffi::c_int,
    ) -> ::std::os::raw::c_int;

    fn query_qp(
        qp: *mut ibverbs_sys::ibv_qp,
        attr: *mut ibverbs_sys::ibv_qp_attr,
        attr_mask: core::ffi::c_int,
        init_attr: *mut ibverbs_sys::ibv_qp_init_attr,
    ) -> ::std::os::raw::c_int;

    fn reg_mr(
        pd: *mut ibverbs_sys::ibv_pd,
        addr: *mut ::std::os::raw::c_void,
        length: usize,
        _hca_va: u64,
        access: core::ffi::c_int,
    ) -> *mut ibverbs_sys::ibv_mr;

    fn dereg_mr(mr: *mut ibverbs_sys::ibv_mr) -> ::std::os::raw::c_int;

    fn post_send(
        qp: *mut ibverbs_sys::ibv_qp,
        wr: *mut ibverbs_sys::ibv_send_wr,
        bad_wr: *mut *mut ibverbs_sys::ibv_send_wr,
    ) -> ::std::os::raw::c_int;

    fn post_recv(
        qp: *mut ibverbs_sys::ibv_qp,
        wr: *mut ibverbs_sys::ibv_recv_wr,
        bad_wr: *mut *mut ibverbs_sys::ibv_recv_wr,
    ) -> ::std::os::raw::c_int;

    fn poll_cq(cq: *mut ibverbs_sys::ibv_cq, num_entries: i32, wc: *mut ibverbs_sys::ibv_wc)
        -> i32;
}

#[repr(C)]
// this struct represent the `bluerdma_device` struct in `bluerdma.h` at `rdma-core/providers/bluerdma/`
// the padding size should match the C's definition.
struct BlueRdmaDevice {
    pad: [u8; 712],
    driver: *mut core::ffi::c_void,
    abi_version: core::ffi::c_int,
}

//TODO need to deal with error correct
// add lazy init to deal nccl's action: nccl with open all devices at first
pub(super) fn get_device(
    context: *mut ibverbs_sys::ibv_context,
) -> MutexGuard<'static, RawMutex, impl VerbsOps> {
    let dev_ptr = unsafe { *context }.device.cast::<BlueRdmaDevice>();
    let driver_ptr = unsafe { (*dev_ptr).driver };
    // log::debug!(
    //     "receive ptr is:{:?},at pid: {}",
    //     driver_ptr,
    //     std::process::id()
    // );

    // Extract device name from ibv_context
    let ibv_dev_ptr = unsafe { (*context).device };
    let device_name = unsafe {
        let name_ptr = (*ibv_dev_ptr).dev_name.as_ptr();
        std::ffi::CStr::from_ptr(name_ptr)
            .to_string_lossy()
            .into_owned()
    };
    // log::debug!("device name is:{}", device_name);

    #[cfg(feature = "hw")]
    {
        let device: &'static OnceLock<Mutex<HwDeviceCtx<PciHwDevice>>> = unsafe {
            driver_ptr
                .cast::<OnceLock<Mutex<HwDeviceCtx<PciHwDevice>>>>()
                .as_ref()
                .expect("Invalid driver pointer")
        };
        device
            .get_or_init(|| {
                let ctx = super::core::BlueRdmaCore::new_hw(&device_name)
                    .unwrap_or_else(|err| panic!("Failed to initialize hw context: {err}"));
                Mutex::new(ctx)
            })
            .lock()
    }

    #[cfg(feature = "sim")]
    {
        let device: &'static OnceLock<Mutex<HwDeviceCtx<EmulatedHwDevice>>> = unsafe {
            driver_ptr
                .cast::<OnceLock<Mutex<HwDeviceCtx<EmulatedHwDevice>>>>()
                .as_ref()
                .expect("Invalid driver pointer")
        };
        device
            .get_or_init(|| {
                let ctx = super::core::BlueRdmaCore::new_emulated(&device_name)
                    .unwrap_or_else(|err| panic!("Failed to initialize emulated context: {err}"));
                Mutex::new(ctx)
            })
            .lock()
    }

    #[cfg(feature = "mock")]
    {
        let device: &'static OnceLock<Mutex<MockDeviceCtx>> = unsafe {
            driver_ptr
                .cast::<OnceLock<Mutex<MockDeviceCtx>>>()
                .as_ref()
                .expect("Invalid driver pointer")
        };
        device
            .get_or_init(|| {
                let ctx = super::core::BlueRdmaCore::new_mock(&device_name)
                    .unwrap_or_else(|err| panic!("Failed to initialize mock context: {err}"));
                Mutex::new(ctx)
            })
            .lock()
    }
}
