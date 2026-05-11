# Open-RDMA 全链路学习路线图

> 从测试程序到硬件 RTL，从应用到驱动的完整学习路径

---

## 一、项目总览

Open-RDMA 是一个开源 RDMA（Remote Direct Memory Access）网卡项目，包含两个子项目：

```
open-rdma/
├── open-rdma-rtl/          # 硬件 RTL（FPGA/ASIC 设计）
│   ├── src/                # Bluespec SystemVerilog 源码
│   ├── backend/            # FPGA 后端（Vivado/Quartus/Achronix）
│   ├── test/               # 测试框架（cocotb + Verilator）
│   └── docs/               # 硬件架构图
│
└── open-rdma-driver/       # 软件驱动
    ├── kernel-driver/      # Linux 内核驱动（bluerdma.ko）
    ├── rust-driver/        # Rust 用户态核心驱动
    ├── dtld-ibverbs/       # 修改版 rdma-core（libibverbs + C Provider）
    │   ├── src/            # Rust FFI 导出层
    │   └── rdma-core-55.0/ # 上游 rdma-core（含 bluerdma provider）
    ├── examples/           # 示例测试程序
    ├── tests/              # 测试框架
    │   ├── base_test/      # C 语言测试框架（重构版）
    │   └── rccl_test/      # RCCL 集合通信测试
    ├── docs/               # 大量中文学习文档（强烈建议先读）
    └── third_party/        # 三方依赖（udmabuf 等）
```

---

## 二、三种运行模式

Open-RDMA 支持三种开发/测试模式，复杂度依次递增：

| 模式 | Feature Flag | 依赖 | 适用场景 |
|------|-------------|------|---------|
| **Mock** | `--features mock` | 无 | 快速功能验证、CI/CD |
| **Sim** | `--features sim` | RTL 仿真器（Verilator + cocotb） | 硬件验证、驱动调试 |
| **HW** | `--features hw` | 真实 FPGA/ASIC 硬件 | 生产部署 |

---

## 三、全链路数据流（发送路径为例）

```
┌──────────────────────────────────────────────────────────────────────┐
│                       从应用到硬件的完整调用链                          │
└──────────────────────────────────────────────────────────────────────┘

【第1层】测试程序（C 语言）
  ┌─────────────────────────────────────────┐
  │ examples/loopback.c                     │
  │ tests/base_test/tests/send_recv.c       │
  │                                         │
  │ ibv_post_send(qp, wr, bad_wr)           │  ← 标准 libibverbs API
  └────────────────┬────────────────────────┘
                   │
【第2层】libibverbs + Provider（C 语言）      │
  ┌────────────────▼────────────────────────┐
  │ dtld-ibverbs/rdma-core-55.0/            │
  │   libibverbs/verbs.c                    │
  │     → verbs_post_send()                 │
  │   providers/bluerdma/bluerdma.c         │
  │     → dlopen("libbluerdma_rust.so")     │  ← 动态加载 Rust 驱动
  │     → dlsym("bluerdma_post_send")       │
  └────────────────┬────────────────────────┘
                   │
【第3层】Rust FFI 层（Rust 语言）             │
  ┌────────────────▼────────────────────────┐
  │ dtld-ibverbs/src/rxe/ctx_ops.rs          │
  │   #[export_name = "bluerdma_post_send"]  │
  │   → BlueRdmaCore::post_send()           │
  └────────────────┬────────────────────────┘
                   │
【第4层】Rust 核心驱动（Rust 语言）           │
  ┌────────────────▼────────────────────────┐
  │ rust-driver/src/verbs/ctx.rs             │
  │   HwDeviceCtx::post_send()              │
  │   ├─ 解析 Send WR (Work Request)        │
  │   ├─ 生成硬件描述符                      │
  │   ├─ 写入 Send Ring Buffer (DMA)        │
  │   └─ 通知 SendWorker 后台线程            │
  │                                         │
  │ rust-driver/src/workers/send/worker.rs   │
  │   SendWorker                            │
  │   ├─ 从 Ring Buffer 读取描述符           │
  │   ├─ DMA 读取用户数据                    │
  │   └─ 更新硬件 CSR (tail pointer)        │
  └────────────────┬────────────────────────┘
                   │
            ┌──────┴──────┐
            │ CSR 访问方式 │
            └──────┬──────┘
                   │
     ┌─────────────┼─────────────┐
     │             │             │
【HW】          【Sim】        【Mock】
 PCIe MMIO      TCP JSON-RPC   内存模拟
 /dev/mem       127.0.0.1:7701
     │             │
     │    ┌────────▼──────────────────────────┐
     │    │ 第5层：Cocotb 测试台（Python）      │
     │    │ test/cocotb/                       │
     │    │   UserspaceDriverServer            │
     │    │   ├─ TCP 监听 127.0.0.1:7701       │
     │    │   ├─ 接收 JSON CSR 请求            │
     │    │   └─ 转发给 RTL 模型               │
     │    │                                    │
     │    │   CSR 请求 → cocotb Queue          │
     │    │   → 时钟同步 → SimplePcieBFM       │
     │    │   → 写入 DUT (Device Under Test)   │
     │    │                                    │
     │    │   SimplePcieBehaviorModel          │
     │    │   ├─ host_write_blocking()         │
     │    │   ├─ host_read_blocking()          │
     │    │   └─ 模拟 PCIe BAR 空间访问        │
     │    └────────┬──────────────────────────┘
     │             │
     └──────┬──────┘
            │
【第6层】硬件 RTL（Bluespec/Verilog）
  ┌─────────▼────────────────────────────────┐
  │ src/Top.bsv → mkBsvTopWithoutHardIpInstance│
  │                                           │
  │  ┌─ CsrRootConnector (CSR 寄存��路由) ──┐ │
  │  │   将 BAR 地址映射到各模块寄存器      │ │
  │  └──────────────────────────────────────┘ │
  │                                           │
  │  ┌─ RingbufAndDescriptorHandler ─────────┐ │
  │  │   ├─ WQE Ringbuf (工作队列 DMA 读取)  │ │
  │  │   ├─ CQ Ringbuf (完成队列 DMA 写入)   │ │
  │  │   ├─ CMD Ringbuf (命令队列)           │ │
  │  │   └─ WorkQueueDescParser (描述符解析)  │ │
  │  └───────────────────────────────────────┘ │
  │                                           │
  │  ┌─ QpMrPgtQpc (核心 RDMA 协议引擎) ────┐ │
  │  │   ├─ QP Context (队列对上下文)       │ │
  │  │   ├─ MR Table (内存区域表/lkey/rkey) │ │
  │  │   ├─ AddressTranslator (VA→PA 转换)  │ │
  │  │   ├─ SQ[4] (发送队列，4通道)         │ │
  │  │   ├─ RQ[4] (接收队列，4通道)         │ │
  │  │   ├─ PayloadGen (Payload 读取/DMA)   │ │
  │  │   ├─ PayloadCon (Payload 写入/DMA)   │ │
  │  │   ├─ PacketGen (数据包生成)          │ │
  │  │   ├─ PacketParse (数据包解析)        │ │
  │  │   ├─ AutoAckGenerator (自动ACK/NAK)  │ │
  │  │   └─ CnpPacketGen (拥塞通知)        │ │
  │  └───────────────────────────────────────┘ │
  │                                           │
  │  ┌─ TopLevelDmaChannelMux ───────────────┐ │
  │  │   多路复用各类 DMA 请求到 PCIe 通道   │ │
  │  └───────────────────────────────────────┘ │
  └───────────────────────────────────────────┘
                   │
【第7层】物理接口
  ┌───────────────▼───────────────────────────┐
  │  PCIe IP (RTilePcie)  → 主机内存 (DMA)    │
  │  Ethernet IP (FTileMac) → 网络             │
  └───────────────────────────────────────────┘
```

---

## 四、三阶段学习路线

### 阶段一：Mock 模式快速上手（1-2天）

**目标**：不依赖任何硬件和仿真器，跑通第一个 RDMA 程序。

**前置知识**：
- 基本的 RDMA/InfiniBand 概念（QP, CQ, MR, PD, WR）
- C 语言基础
- 明白什么是 libibverbs API

**学习步骤**：

1. **环境搭建**（参考 `docs/zh-CN/installation.md`）
   ```bash
   # 在 open-rdma-driver 目录下
   make && sudo make install                    # 编译加载内核驱动
   cd dtld-ibverbs
   cargo build --no-default-features --features mock  # 编译 Mock 模式
   cd ../rdma-core-55.0 && ./build.sh && cd ../..     # 编译 rdma-core
   # 设置 LD_LIBRARY_PATH（参考文档）
   ```

2. **运行示例测试**
   ```bash
   cd examples && make
   ./loopback 8192                              # 单卡 loopback
   # 双终端：
   # 终端1: ./send_recv 8192                    # server
   # 终端2: ./send_recv 8192 127.0.0.1          # client
   ```

3. **阅读测试代码**
   - 从最简单的开始：`examples/loopback.c`
   - 理解 RDMA 编程模式：`tests/base_test/lib/rdma_common.c`
   - 重构版测试：`tests/base_test/tests/`

4. **核心概念文档**
   - RDMA 基本操作流程：设备打开 → PD 分配 → MR 注册 → QP 创建 → post_send → poll_cq

**关键文件速查**：
- `examples/loopback.c` — 最简 loopback 测试
- `tests/base_test/tests/send_recv.c` — 重构版 send/recv
- `tests/base_test/lib/rdma_common.c` — RDMA 公共操作库
- `tests/base_test/lib/rdma_transport.c` — TCP 传输层（交换 QP 信息）

---

### 阶段二：理解软件驱动全链路（3-5天）

**目标**：理解从 `ibv_post_send()` 调用到硬件 CSR 写入的完整路径。

**前置知识**：
- Rust 语言基础
- 理解 FFI (Foreign Function Interface)
- 理解 dlopen/dlsym 动态加载机制

**学习步骤**：

1. **理解组件架构**（必读 `docs/zh-CN/introduction.md`）
   ```
   应用 → libibverbs → C Provider → dlopen → Rust Driver → CSR → 硬件
   ```

2. **Provider 桥接层**（C → Rust 如何连接）
   - `dtld-ibverbs/rdma-core-55.0/providers/bluerdma/bluerdma.c`
   - 关键：`dlopen("libbluerdma_rust.so")` + `dlsym()` 加载所有 verbs 函数

3. **Rust FFI 导出层**
   - `dtld-ibverbs/src/rxe/ctx_ops.rs` — C ABI 导出函数
   - 追踪 `bluerdma_post_send` → `BlueRdmaCore::post_send`

4. **核心驱动逻辑**
   - `rust-driver/src/verbs/ctx.rs` — HwDeviceCtx（设备上下文）
   - `rust-driver/src/verbs/core.rs` — BlueRdmaCore（入口）
   - `rust-driver/src/verbs/ffi.rs` — FFI 导出实现

5. **后台 Worker 线程**（驱动如何异步处理）
   - `rust-driver/src/workers/send/worker.rs` — 发送处理
   - `rust-driver/src/workers/completion.rs` — 完成队列处理
   - `rust-driver/src/workers/retransmit.rs` — 重传逻辑
   - `rust-driver/src/workers/ack_responder.rs` — ACK 响应

6. **Ring Buffer 系统**（驱动与硬件的通信接口）
   - `rust-driver/src/ring/` — 环形缓冲区抽象
   - `rust-driver/src/ring/csr/` — CSR 访问抽象层
   - `rust-driver/src/ring/csr/backends/emulated.rs` — Sim 模式（TCP RPC）
   - `rust-driver/src/ring/csr/backends/hardware.rs` — HW 模式（PCIe MMIO）
   - `rust-driver/src/ring/descriptors/` — 硬件描述符格式

**关键设计模式**：
- `DeviceAdaptor` trait：统一 CSR 读写接口（支持 HW/Sim/Mock 三种后端）
- `Ring<Dev, Spec>` 泛型：类型安全的环形缓冲区（编译时区分读写方向）

---

### 阶段三：硬件 RTL 与软硬件联合调试（1-2周）

**目标**：理解 RTL 设计，能独立运行 RTL 仿真和软硬件联调。

**前置知识**：
- 数字电路基础（时序逻辑、组合逻辑）
- 基本的 Verilog/SystemVerilog 语法
- RDMA 协议基础（RoCEv2：BTH/RETH/AETH 等报文头）

**学习步骤**：

#### 3.1 搭建 RTL 仿真环境

```bash
# 在 open-rdma-rtl 目录下
./setup.sh                                    # 安装 BSC 编译器
sudo apt install iverilog verilator zlib1g-dev tcl8.6
pip install cocotb==1.9.2 cocotb-test cocotbext-pcie cocotbext-axi scapy
cd test/cocotb && make verilog                # 编译 RTL → Verilog
```

#### 3.2 理解 RTL 架构（必读）

**总体架构文档**（强烈推荐先读这些）：
- `open-rdma-driver/docs/zh-CN/learn/00-硬件(RTL)分析/00-硬件架构/RDMA硬件架构完整教程.md` — 总体架构和数据流
- `open-rdma-driver/docs/zh-CN/learn/00-硬件(RTL)分析/00-硬件架构/模块关系快速参考.md` — 模块关系速查

**分模块深入学习**：
1. **报文生成 (PacketGen)** — 位于 `learn/00-硬件/01-报文生成-PacketGen/`
2. **Payload 处理** — 位于 `learn/00-硬件/02-Payload处理/`
3. **接收队列 (RQ)** — 位于 `learn/00-硬件/03-队列管理-RQ/`
4. **内存管理 (MR/Page Table)** — 位于 `learn/00-硬件/04-内存管理/`
5. **接口协议 (ClientP/PipeInB0)** — 位于 `learn/00-硬件/05-接口协议/`

**关键 Bluespec 源文件**：
- `open-rdma-rtl/src/Top.bsv` — 顶层模块
- `open-rdma-rtl/src/SQ.bsv` — 发送队列
- `open-rdma-rtl/src/RQ.bsv` — 接收队列
- `open-rdma-rtl/src/PacketGenAndParse.bsv` — 报文生成/解析
- `open-rdma-rtl/src/PayloadGenAndCon.bsv` — Payload 生成/消费
- `open-rdma-rtl/src/MemRegionAndAddressTranslate.bsv` — MR 和地址转换
- `open-rdma-rtl/src/QPContext.bsv` — QP 上下文
- `open-rdma-rtl/src/CsrFramework.bsv` — CSR 寄存器框架
- `open-rdma-rtl/src/Ringbuf.bsv` — 环形缓冲区

#### 3.3 理解测试基础设施（cocotb）

**Cocotb 测试框架文件**：
- `open-rdma-rtl/test/cocotb/Makefile` — 测试 Makefile
- `open-rdma-rtl/test/cocotb/tb_top_for_system_test.py` — 单卡 loopback 测试
- `open-rdma-rtl/test/cocotb/tb_top_for_system_test_two_card.py` — 双卡联调测试

**测试框架核心组件**：
- `open-rdma-rtl/test/cocotb/test_framework/common.py` — Bluespec 类型映射 + 数据流定义
- `open-rdma-rtl/test/cocotb/test_framework/mock_host.py` — 模拟主机（CSR Server + 共享内存）
- `open-rdma-rtl/test/cocotb/test_framework/pcie_bfm.py` — PCIe 行为模型
- `open-rdma-rtl/test/cocotb/test_framework/eth_bfm.py` — 以太网行为模型

**Cocotb 测试台工作流程**：
```
UserspaceDriverServer (TCP Server, port 7701)
    ↓ 接收 JSON CSR 请求
    ↓ 放入 cocotb Queue
    ↓
_forward_csr_write_task() [异步]
    ↓ 等待时钟边沿 (RisingEdge)
    ↓
SimplePcieBehaviorModelProxy.host_write_blocking()
    ↓ 将值写入 DUT 的特定信号
    ↓
RTL 硬件逻辑处理（时钟驱动）
    ↓
SimpleEthBehaviorModel (以太网行为模型)
    ↓ loopback 模式下：TX→RX 直接回环
    ↓ 双卡模式下：TX → EthPacketTcp → 对端 RX
```

#### 3.4 运行 RTL 仿真

**纯 RTL 测试（不需要 Rust 驱动）**：
```bash
cd open-rdma-rtl/test/cocotb
make run_system_test_server_loopback           # 单卡 loopback
# 双卡（两个终端）：
# 终端1: make run_system_test_server_1
# 终端2: make run_system_test_server_2
```

**软硬件联合调试（RTL + Rust 驱动）**：
```bash
# 终端1：启动仿真器
cd open-rdma-rtl/test/cocotb
make run_system_test_server_loopback

# 终端2：运行 Rust 驱动测试
cd open-rdma-driver/examples
make
RUST_LOG=debug ./loopback 8192

# 或者使用自动化脚本：
cd open-rdma-driver/tests/base_test/scripts
./test_loopback_sim.sh 4096
./test_send_recv_sim.sh 4096
./test_rdma_write_sim.sh 4096 5
```

#### 3.5 跨层专题深入

- **RDMA 重传机制**：`open-rdma-driver/docs/zh-CN/learn/02-跨层综合/RDMA重传机制完整解析.md`（82KB，重点文档）
- **RCCL 集成**：`open-rdma-driver/docs/zh-CN/learn/01-软件(Driver)分析/06-RCCL集成/`
- **Bug 分析**：`open-rdma-driver/docs/zh-CN/learn/01-软件(Driver)分析/07-Bug分析/`

---

## 五、调试方法详解

### 5.1 Mock 模式调试

**优点**：最快、最简单，无需任何外部依赖。
**局限**：不走真实硬件/仿真器逻辑，不能验证 RTL。

```bash
# 编译 Mock 模式
cd dtld-ibverbs && cargo build --features mock && cd ..

# 开启详细日志
RUST_LOG=debug ./examples/loopback 8192
```

**调试技巧**：
- 在 Rust 代码中加 `log::debug!()` / `log::info!()` 宏
- 用 `RUST_LOG=trace` 获取最详细日志
- Mock 模式下所有 CSR 操作在内存中完成，可以加断点调试

### 5.2 Sim 模式调试（RTL 联合调试）

**优点**：可以同时调试软件和硬件，观察完整的软硬件交互。
**局限**：仿真速度慢（~500MHz 时钟的 RTL 在 Verilator 上可能只有 kHz 级别）。

**调试流程**：

```
┌──────────────────────┐     TCP:7701     ┌──────────────────────────┐
│  Rust Driver (Sim)    │ ←──────────────→ │  Cocotb Testbench        │
│                       │   JSON RPC       │  UserspaceDriverServer   │
│  RUST_LOG=debug       │                  │  log = DEBUG             │
│  ./loopback 8192      │                  │                          │
└──────────────────────┘                  │  ┌────────────────────┐  │
                                          │  │ Verilator DUT      │  │
                                          │  │ (RTL 硬件模型)      │  │
                      共享内存              │  └────────────────────┘  │
                    ←──────────→           │                          │
                    DMA 访问               │  SimplePcieBFM           │
                                           │  SimpleEthBFM            │
                                           └──────────────────────────┘
```

**关键观察点**：
1. **Rust 驱动日志**：CSR 读写内容、Ring Buffer 操作、完成事件
2. **Cocotb 日志**：`test/cocotb/log/` 目录下的 `.loopback` 文件
3. **CSR 通信**：TCP 端口 7701 上的 JSON 消息（可用 tcpdump/wireshark 抓包）
4. **共享内存**：`/bluesim1`（256MB），包含 DMA 缓冲区

**自动化调试脚本**（推荐）：
```bash
cd open-rdma-driver/tests/base_test/scripts
./test_loopback_sim.sh 4096
# 日志输出在 log/sim/ 目录
cat log/sim/rtl-loopback.log
```

### 5.3 硬件 RTL 单步调试

**Verilator 波形查看**：
```bash
# 测试运行后会在 sim_build/ 目录生成 .vcd 波形文件
# 使用 GTKWave 查看：
gtkwave sim_build/mkBsvTopWithoutHardIpInstance/dump.vcd
```

**Cocotb 代码中加入断点**：
```python
# 在 cocotb 测试代码中
import pdb; pdb.set_trace()    # Python 断点
await Timer(100, units='ns')   # 等待 100ns
```

**关键信号追踪**：
- `CLK`, `RST_N` — 时钟和复位
- `dmaSlavePipeIfc_*` — PCIe Slave 接口（驱动 → 硬件）
- `dmaMasterPipeIfcVec_*` — PCIe Master 接口（硬件 → 驱动）
- `qpEthDataStreamIfcVec_*_dataPipeOut` — 以太网发送
- `qpEthDataStreamIfcVec_*_dataPipeIn` — 以太网接收
- CSR 相关信号以模块名为前缀

### 5.4 调试技巧总结

| 场景 | 工具/方法 | 命令 |
|------|----------|------|
| Rust 驱动日志 | RUST_LOG 环境变量 | `RUST_LOG=trace ./loopback 8192` |
| Cocotb 日志 | Python logging | 代码中 `self.log.setLevel(logging.DEBUG)` |
| 仿真波形 | GTKWave + Verilator VCD | 测试自动生成 |
| CSR 通信抓包 | tcpdump | `tcpdump -i lo -A port 7701` |
| 共享内存查看 | Python ctypes | 读取 `/bluesim1` |
| 内核驱动日志 | dmesg | `dmesg \| grep bluerdma` |
| IB 设备状态 | sysfs | `ls /sys/class/infiniband/` |
| RDMA 设备列表 | ibv_devinfo | `ibv_devinfo`（需要 LD_LIBRARY_PATH） |

---

## 六、推荐学习路径（按优先级）

### 新手入门（第1周）
```
Day 1-2: Mock 模式环境搭建 + 跑通 loopback/send_recv
Day 3-4: 阅读 introduction.md + 理解完整调用链
Day 5:   阅读测试代码（examples/ + tests/base_test/）
Day 6-7: 阅读硬件架构文档（RDMA硬件架构完整教程.md）
```

### 深入驱动（第2-3周）
```
Week 2: Rust 驱动核心模块（ctx.rs → core.rs → workers/）
Week 3: Ring Buffer 系统 + CSR 访问层 + FFI 层
```

### 深入硬件（第4-5周）
```
Week 4: RTL 环境搭建 + 纯 RTL 仿真 + 模块文档阅读
Week 5: 软硬件联调 + 跨层专题（重传、RCCL）+ Bug 分析
```

---

## 七、关键文件速查表

### 测试程序入口
| 文件 | 说明 |
|------|------|
| `open-rdma-driver/examples/loopback.c` | 最简 loopback |
| `open-rdma-driver/examples/send_recv.c` | 双端 send/recv |
| `open-rdma-driver/tests/base_test/tests/loopback.c` | 重构版 loopback |
| `open-rdma-driver/tests/base_test/lib/rdma_common.c` | RDMA 公共操作 |

### 软件驱动核心
| 文件 | 说明 |
|------|------|
| `open-rdma-driver/rust-driver/src/verbs/core.rs` | BlueRdmaCore 入口 |
| `open-rdma-driver/rust-driver/src/verbs/ctx.rs` | HwDeviceCtx 上下文 |
| `open-rdma-driver/rust-driver/src/ring/csr/backends/emulated.rs` | Sim 模式 CSR |
| `open-rdma-driver/rust-driver/src/ring/csr/backends/hardware.rs` | HW 模式 CSR |
| `open-rdma-driver/dtld-ibverbs/src/rxe/ctx_ops.rs` | FFI 导出 |
| `open-rdma-driver/dtld-ibverbs/rdma-core-55.0/providers/bluerdma/bluerdma.c` | C Provider |

### 硬件 RTL 核心
| 文件 | 说明 |
|------|------|
| `open-rdma-rtl/src/Top.bsv` | 顶层模块 |
| `open-rdma-rtl/src/SQ.bsv` | 发送队列 |
| `open-rdma-rtl/src/RQ.bsv` | 接收队列 |
| `open-rdma-rtl/src/PacketGenAndParse.bsv` | 报文处理 |
| `open-rdma-rtl/src/PayloadGenAndCon.bsv` | Payload 处理 |
| `open-rdma-rtl/src/MemRegionAndAddressTranslate.bsv` | MR/地址转换 |
| `open-rdma-rtl/src/CsrFramework.bsv` | CSR 框架 |
| `open-rdma-rtl/src/Ringbuf.bsv` | 环形缓冲区 |

### 测试基础设施
| 文件 | 说明 |
|------|------|
| `open-rdma-rtl/test/cocotb/Makefile` | 测试 Makefile |
| `open-rdma-rtl/test/cocotb/tb_top_for_system_test.py` | 单卡测试 |
| `open-rdma-rtl/test/cocotb/tb_top_for_system_test_two_card.py` | 双卡测试 |
| `open-rdma-rtl/test/cocotb/test_framework/mock_host.py` | 模拟主机 + CSR Server |
| `open-rdma-rtl/test/cocotb/test_framework/common.py` | 类型定义 + 总线模型 |

### 文档入口
| 文件 | 说明 |
|------|------|
| `open-rdma-driver/docs/zh-CN/learn/README.md` | 文档总目录 |
| `open-rdma-driver/docs/zh-CN/introduction.md` | 项目介绍 + 完整调用链 |
| `open-rdma-driver/docs/zh-CN/installation.md` | 安装指南 |
| `open-rdma-driver/docs/zh-CN/rtl-simulation.md` | RTL 仿真指南 |
| `open-rdma-driver/docs/zh-CN/learn/00-硬件(RTL)分析/00-硬件架构/RDMA硬件架构完整教程.md` | 硬件架构 |

---

## 八、常见问题

### Q1: 应该从哪个模式开始学习？
Mock 模式。它不需要任何硬件或仿真器，可以快速理解 RDMA 编程模型和驱动架构。

### Q2: 如何切换三种模式？
通过 Cargo features 控制：
```bash
cd dtld-ibverbs
cargo build --no-default-features --features mock   # Mock
cargo build --no-default-features --features sim    # Sim
cargo build --no-default-features --features hw     # HW
```

### Q3: 测试失败了怎么调试？
1. `RUST_LOG=debug` 查看 Rust 驱动日志
2. 查看 cocotb 日志：`cat log/sim/rtl-loopback.log`
3. 用 GTKWave 查看 VCD 波形
4. 在 Rust 代码中用 `log::debug!()` 加日志
5. 在 cocotb 代码中用 `self.log.info()` 加日志

### Q4: 硬件测试驱动和 Rust 驱动的关系？
- **纯 RTL 测试**：cocotb Python 代码直接驱动 RTL，不需要 Rust 驱动
- **Sim 模式**：Rust 驱动通过 TCP 连到 cocotb 测试台，cocotb 再驱动 RTL
- **HW 模式**：Rust 驱动直接通过 PCIe 访问硬件寄存器

### Q5: 学习文档在哪里？
中文学习文档非常齐全，入口在：
`open-rdma-driver/docs/zh-CN/learn/README.md`
包含 36+ 篇技术文档，覆盖硬件 RTL、软件驱动、跨层专题。

---

> 最后更新：2026-05-10
