use blue_rdma_driver::test_wrapper::bench::descs::MetaReportQueueDescBthRethWrapper;
use criterion::{black_box, criterion_group, criterion_main, Criterion};

#[allow(clippy::unit_arg)]
fn benchmark_descriptor_load(c: &mut Criterion) {
    let desc = MetaReportQueueDescBthRethWrapper::from_bytes([1; 32]);
    c.bench_function("desc load", |b| b.iter(|| black_box(desc.load_all())));
}

#[allow(clippy::unit_arg)]
fn benchmark_descriptor_set(c: &mut Criterion) {
    let mut desc = MetaReportQueueDescBthRethWrapper::from_bytes([1; 32]);
    c.bench_function("desc set", |b| b.iter(|| black_box(desc.set_all())));
}

criterion_group!(benches, benchmark_descriptor_load, benchmark_descriptor_set);
criterion_main!(benches);
