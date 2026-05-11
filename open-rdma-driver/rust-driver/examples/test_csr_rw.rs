use blue_rdma_driver::test_wrapper::test_csr_rw::TestDevice;

fn main() {
    TestDevice::init_emulated().unwrap();
}
