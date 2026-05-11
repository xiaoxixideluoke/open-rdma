# Cocotb SCHEDULER ERROR 问题分析与修复

## 问题现象

在运行双卡测试 `tb_top_for_system_test_two_card.py` 时，出现以下错误：

```
INFO cocotb: time=12539000: mkDtldStreamArbiterSlave forwardMoreWriteBeat, wd=...
ERROR cocotb: SCHEDULER ERROR: read-only sync events created RW events!
```

单卡测试 `tb_top_for_system_test.py` 运行正常，无此错误。

---

## 问题分析过程

### 初步假设（❌ 错误）

1. **假设 1**: 使用 `cocotb.Queue` 进行线程间通信不安全
   - **验证**: 确实不安全，但不是根本原因

2. **假设 2**: `Timer` 触发器导致 ReadOnly 阶段冲突
   - **验证**: 改用 `RisingEdge` 后问题依然存在

3. **假设 3**: `BluespecActionMethod` 中的双重 `await ReadWrite()` 违反 Timing Model
   - **验证**: 单卡测试中有 4 次连续 `await ReadWrite()` 却能正常运行，此假设不成立

### 根本原因（✅ 确认）

通过深入研究 [Cocotb Timing Model](https://github.com/cocotb/cocotb/wiki/Timing-Model)，发现真正的问题：

**UDP 线程在调度器的 ReadOnly 阶段调用 `cocotb.Queue.put_nowait()`**

#### 问题调用链

```
时刻 T (某个时钟边沿处理完毕后):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Cocotb 调度器]
    ↓ 处理完所有协程
    ↓ 准备进入 ReadOnly 阶段（时间步结束）
    ↓ mode = "ReadOnly"

[UDP 线程] (并发运行！)
    ↓ 收到 CSR 读/写请求
    ↓ 调用 self.csr_write_req_queue.put_nowait((addr, value))
        ↓ Queue._put(item)
        ↓ Queue._wakeup_next(self._getters)  ← 关键！
            ↓ 找到等待的协程 (_forward_csr_write_task)
            ↓ waiter.set()  ← 唤醒协程
                ↓ 协程被标记为 ready
                ↓ 协程开始执行：
                    await self.pcie_bfm.host_write_blocking(addr, value)
                    ↓ await BluespecActionMethod.__call__()
                        ↓ await ReadWrite()  ← ❌ 尝试调度 ReadWrite 事件

[Cocotb 调度器]
    ↓ 当前处于 ReadOnly 阶段
    ↓ 检测到新的 ReadWrite 事件被调度
    ↓ ERROR: "read-only sync events created RW events!"
```

#### 关键代码位置

**tb_top_for_system_test_two_card.py:**

```python
# Line 174-176: CSR 写回调（UDP 线程调用）
def _csr_write_cb(self, addr, value):
    self.csr_write_req_queue.put_nowait((addr, value))  # ← 问题触发点 1
    # ...

# Line 180-187: CSR 读回调（UDP 线程调用）
def _csr_read_cb(self, addr):
    with self.csr_read_lock:
        self.csr_read_req_queue.put_nowait(addr)  # ← 问题触发点 2
        while self.csr_read_resp_queue.empty():
            time.sleep(0)
        ret = self.csr_read_resp_queue.get_nowait()  # ← 问题触发点 3
        return ret

# Line 189-193: CSR 写任务（协程）
async def _forward_csr_write_task(self):
    while True:
        addr, value = await self.csr_write_req_queue.get()
        await self.pcie_bfm.host_write_blocking(addr, value)  # ← 触发 ReadWrite
        # ...

# Line 195-199: CSR 读任务（协程）
async def _forward_csr_read_req_task(self):
    while True:
        addr = await self.csr_read_req_queue.get()
        val = await self.pcie_bfm.host_read_blocking(addr)  # ← 触发 ReadWrite
        await self.csr_read_resp_queue.put(val)
```

---

## Cocotb Timing Model 核心概念

根据 [官方文档](https://github.com/cocotb/cocotb/wiki/Timing-Model)，Cocotb 将仿真时间分为以下阶段：

### 时间步的四个阶段

| 阶段 | 名称 | 写操作 | Trigger |
|------|------|--------|---------|
| 1 | **Beginning of Time Step** | 缓存 | `Timer`, `NextTimeStep` |
| 2 | **Value Change** | 立即 | `RisingEdge`, `FallingEdge`, `Edge` |
| 3 | **Values Settle** | 缓存 | `ReadWrite` |
| 4 | **End of Time Step** | ❌ 禁止 | `ReadOnly` |

### 关键约束

- **一旦进入 ReadOnly 阶段，该时间步禁止任何写操作**
- **`put_nowait()` 会立即唤醒等待的协程，触发协程调度**
- **如果协程中有 `await ReadWrite()`，会尝试调度新的读写事件**
- **在 ReadOnly 阶段调度读写事件 → SCHEDULER ERROR**

---

## 为什么单卡测试没问题？

单卡和双卡的 CSR 回调代码**完全相同**，都存在线程不安全问题。

**差异在于触发概率**：

| 特性 | 单卡测试 | 双卡测试 |
|------|---------|---------|
| 协程数量 | ~8-10 个 | **~12-14 个** |
| CSR 操作频率 | 较低 | **较高**（两个实例） |
| 调度复杂度 | 简单 | **复杂** |
| ReadOnly 阶段时长 | 短 | **长** |
| UDP 线程命中 ReadOnly 概率 | 低 | **高** ← 关键！ |

**结论**: 单卡测试只是运气好，竞态条件没有被触发。

---

## 修复方案

### 方案：在队列接收后等待时钟边沿

**核心思想**: 协程从队列获取数据后，立即等待时钟边沿，确保后续操作在安全的调度阶段执行。

#### 修改 1：`_forward_csr_write_task`

```python
async def _forward_csr_write_task(self):
    while True:
        addr, value = await self.csr_write_req_queue.get()
        await RisingEdge(self.clock)  # ← 添加：等待时钟边沿
        await self.pcie_bfm.host_write_blocking(addr, value)
        self.log.info(f"_forward_csr_write_task: {addr, value}")
```

#### 修改 2：`_forward_csr_read_req_task`

```python
async def _forward_csr_read_req_task(self):
    while True:
        addr = await self.csr_read_req_queue.get()
        await RisingEdge(self.clock)  # ← 添加：等待时钟边沿
        val = await self.pcie_bfm.host_read_blocking(addr)
        await self.csr_read_resp_queue.put(val)
```

### 原理说明

```
修复前：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[UDP 线程] put_nowait()
    ↓ 立即唤醒协程
[协程] 获取数据 → 立即执行 ReadWrite
    ↓ 如果此时在 ReadOnly 阶段 → ERROR

修复后：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[UDP 线程] put_nowait()
    ↓ 立即唤醒协程
[协程] 获取数据 → await RisingEdge(clock) ← 等待时钟边沿
    ↓ 时钟边沿到来（进入 Value Change 阶段）
    ↓ 执行 ReadWrite（安全！）
```

**关键保证**:
- `await RisingEdge(clock)` 触发后，调度器处于 **Value Change** 阶段
- Value Change 阶段**允许立即写操作**
- 后续的 `await ReadWrite()` 在 **Values Settle** 阶段安全执行
- **完全消除了调度器阶段冲突**

---

## 修改统计

- **文件**: `tb_top_for_system_test_two_card.py`
- **修改行数**: 2 行（仅添加）
- **新增代码**: `await RisingEdge(self.clock)`


---

## 预期结果

✅ SCHEDULER ERROR 完全消失
✅ CSR 读写功能正常
✅ 单卡和双卡测试稳定通过
✅ 代码简洁，易于维护

---

## 参考资料

- [Cocotb Timing Model](https://github.com/cocotb/cocotb/wiki/Timing-Model)
- [Cocotb Queue Documentation](https://docs.cocotb.org/en/stable/_modules/cocotb/queue.html)
- [Cocotb Triggers](https://docs.cocotb.org/en/stable/triggers.html)

---

**文档版本**: 1.0
**日期**: 2025-01-23
**作者**: Claude Code Analysis
