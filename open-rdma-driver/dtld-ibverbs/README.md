```bash
sudo apt install -y libibverbs1 ibverbs-utils librdmacm1 libibumad3 ibverbs-providers rdma-core libibverbs-dev iproute2 perftest build-essential net-tools git librdmacm-dev rdmacm-utils cmake libprotobuf-dev protobuf-compiler clang curl
sudo modprobe rdma_rxe
sudo rdma link add rxe_0 type rxe netdev eth0

rdma link
ib_send_bw -d rxe_0
ib_send_bw -d rxe_0 localhost

pkg-config --libs libibverbs

ib_write_bw --size 65536 --bidirectional --duration 5 --qp 3
ib_write_bw --size 65536 --bidirectional --duration 5 --qp 3 localhost

ltrace -c --library "libibverbs*" -- ib_write_bw --size 65536 --bidirectional --duration 5 --qp 3
ltrace -c --library "libibverbs*" -- ib_write_bw --size 65536 --bidirectional --duration 5 --qp 3 localhost

ltrace -c --library "libibverbs*" -- ibv_rc_pingpong --ib-dev bluerdma0 --gid-idx 0
ltrace -c --library "libibverbs*" -- ibv_rc_pingpong --ib-dev bluerdma1 --gid-idx 0 localhost
```

- [x] perftest
- [x] LD_PRELOAD
- [ ] hand code bindgen
