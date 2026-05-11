# Day 1 — 环境搭建 + 第一个 RDMA 程序

> 日期：2026-05-11（周一）
> 目标：不依赖任何硬件，跑通第一个 RDMA 程序

---

## 任务清单

### 上午：概念预热 + 环境检查

- [ ] **1.1 阅读项目简介**（15min）
  - 文件：`open-rdma-driver/docs/zh-CN/introduction.md`
  - 目的：建立项目整体认知 — 三层架构、三种模式

- [ ] **1.2 了解 RDMA 基础概念**（30min）
  - 核心概念速记（不需要全懂，有个印象即可）：
    - **PD** (Protection Domain) — 安全域，隔离不同进程
    - **MR** (Memory Region) — 注册一块内存让网卡可以 DMA
    - **QP** (Queue Pair) — 队列对 = Send Queue + Receive Queue
    - **CQ** (Completion Queue) — 完成队列，通知应用"操作做完了"
    - **WR** (Work Request) — 工作请求，描述一次 RDMA 操作
    - **lkey / rkey** — 本地/远端内存访问密钥
  - 文件：`open-rdma-driver/docs/zh-CN/learn/README.md`

- [ ] **1.3 检查环境**（10min）
  ```bash
  lsmod | grep bluerdma         # 内核模块是否加载
  ls /sys/class/infiniband/     # RDMA 设备是否存在（应该看到 bluerdma0~3）
  which cargo                   # Rust 工具链
  ```

### 下午：编译 + 跑通测试

- [ ] **1.4 编译内核驱动**（如果有问题先看安装文档）（20min）
  ```bash
  cd /root/open-rdma/open-rdma-driver
  make && sudo make install
  # 确认: lsmod | grep bluerdma
  ```
  - 参考：`docs/zh-CN/installation.md`

- [ ] **1.5 编译 Mock 模式 Rust 驱动**（30min）
  ```bash
  cd /root/open-rdma/open-rdma-driver/dtld-ibverbs
  cargo build --no-default-features --features mock
  ```
  - 预期产物：`target/debug/libbluerdma_rust.so`
  - ⚠️ 如果磁盘空间不足，先清理（见 LEARN 部分）

- [ ] **1.6 编译 rdma-core**（30min）
  ```bash
  cd /root/open-rdma/open-rdma-driver/dtld-ibverbs/rdma-core-55.0
  ./build.sh
  ```
  - 预期产物：`build/lib/libibverbs.so`
  - ⚠️ 如果卡在 cmake 下载，走代理

- [ ] **1.7 设置库路径 + 编译测试程序**（10min）
  ```bash
  export LD_LIBRARY_PATH=/root/open-rdma/open-rdma-driver/dtld-ibverbs/target/debug:/root/open-rdma/open-rdma-driver/dtld-ibverbs/rdma-core-55.0/build/lib
  cd /root/open-rdma/open-rdma-driver/examples
  make
  ```

- [ ] **1.8 🎯 里程碑：运行第一个 RDMA 程序**（10min）
  ```bash
  ./loopback 8192
  ```
  - 预期输出：循环打印 "No differences found between the two memory regions"
  - 按 Ctrl-C 停止

- [ ] **1.9 运行 send_recv 双端测试**（15min）
  ```bash
  # 终端1（服务端）：
  ./send_recv 4096
  # 终端2（客户端）：
  ./send_recv 4096 127.0.0.1
  ```
  - 服务端预期：`[SERVER] Test PASSED!`
  - 客户端预期：`[CLIENT] Send SUCCESS!`

### 晚上：初步阅读

- [ ] **1.10 阅读 loopback.c 源码**（30min）
  - 文件：`open-rdma-driver/examples/loopback.c`
  - 关注：ibv_get_device_list → ibv_open_device → ibv_reg_mr → ibv_create_qp → ibv_post_send → ibv_poll_cq 这条主线
  - 试着画出调用流程图

- [ ] **1.11 用日志模式再跑一次**（10min）
  ```bash
  RUST_LOG=debug ./loopback 8192 2>&1 | head -100
  ```
  - 观察 Rust 驱动输出了什么日志
  - 尝试找出 "post_send" 相关的日志行

---

## 今日产出

- [x] 项目跑起来了（loopback 测试通过）
- [ ] 能说出 RDMA 编程的 5 个核心步骤
- [ ] 画了一张 loopback.c 的调用流程图

## 遇到问题？

| 问题 | 参考 |
|------|------|
| 编译报错 "No space left" | 清理 cargo target 目录 |
| 找不到 RDMA 设备 | 重新 `make install` 加载内核模块 |
| cargo build 卡住 | 检查代理是否启动 |
| 链接错误 | 确认 LD_LIBRARY_PATH 包含两个路径 |
