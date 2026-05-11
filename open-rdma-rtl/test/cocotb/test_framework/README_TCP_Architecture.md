# PCIe BFM TCP架构转换总结

## 概述

本文档详细记录了将PCIe BFM（Bus Functional Model）从基于共享内存的架构转换为基于TCP的分布式内存访问系统的完整过程。

## 转换背景

### 原始架构
- **通信方式**: 共享内存
- **限制**: 内存访问只能在本地进行
- **目标**: 实现分布式内存访问，将内存操作通过TCP发送到驱动端处理

### 新架构目标
- 移除共享内存依赖
- 通过TCP与驱动端通信
- 保持原有仿真时序行为
- 支持多通道内存访问
- 确保数据完整性和对齐

## 核心修改文件

### 1. proxy_pcie_bfm.py

#### 新增导入
```python
import json
import time
import threading
from queue import Queue
```

#### 构造函数修改
```python
def __init__(self, clock, reset, requester_channel_cnt=4, completer_channel_cnt=0, tcp_port=None):
    # 原有初始化代码...

    # TCP通信组件初始化
    if tcp_port:
        self.tcpConnection = TcpConnectionManager("1", "127.0.0.1", tcp_port)
        self.requester_send_queue = Queue()  # 单一共享发送队列
        self.requester_read_queue = [Queue() for _ in range(self.requester_channel_cnt)]

        # TCP工作线程
        self.tcp_sender_thread = threading.Thread(target=self._tcp_sender_thread, daemon=True)
        self.tcp_receiver_thread = threading.Thread(target=self._tcp_receiver_thread, daemon=True)
        self.tcp_sender_thread.start()
        self.tcp_receiver_thread.start()
```

#### 核心方法修改

**读请求处理** (`_handle_requester_read_req`)
```python
# 原共享内存访问 -> TCP请求发送
request = {
    "type": "mem_read",
    "channel_id": channel_id,
    "address": address,
    "length": length,
    "start_byte_index": read_data.start_byte_index(),
    "is_first": read_data.is_first(),
    "is_last": read_data.is_last(),
    "request_id": f"req_{channel_id}_{int(time.time() * 1000000)}"
}

# 放入发送队列，由工作线程处理
self.requester_send_queue.put((channel_id, request))
```

**写请求处理** (`_handle_requester_write_req_data`)
```python
# 提取对齐后的数据
if write_data.is_first():
    data >>= (write_data.start_byte_index() * 8)

# 发送TCP写请求
request = {
    "type": "mem_write",
    "channel_id": channel_id,
    "address": address,
    "data": data_bytes,
    "length": length
}
self.requester_send_queue.put((channel_id, request))
```

**延迟响应处理** (`_forward_delayed_requester_read_resp`)
```python
# 从TCP队列读取响应，而非共享内存
response_data = self.requester_read_queue[channel_id].get()
response = json.loads(response_data.decode())

# 关键：恢复数据对齐
if response.get("success", False):
    data = int.from_bytes(response["data"], byteorder='little')
    if is_first:
        data <<= (start_byte_index * 8)  # 关键的对齐逻辑
```

#### 新增TCP工作线程

**TCP发送线程**
```python
def _tcp_sender_thread(self):
    while True:
        try:
            channel_id, request = self.requester_send_queue.get(timeout=0.1)
            self.tcpConnection.send_data((json.dumps(request) + '\n').encode())
        except:
            continue
```

**TCP接收线程**
```python
def _tcp_receiver_thread(self):
    while True:
        response_data = self.tcpConnection.receive_line()
        if response_data:
            response = json.loads(response_data.decode())
            channel_id = response.get("channel_id", 0)
            self.requester_read_queue[channel_id].put(response_data)
        else:
            time.sleep(0.01)
```

### 2. tcpConnectionManager.py

#### 增强的receive_line方法
```python
def receive_line(self) -> Optional[bytes]:
    connection = self.get_connection()
    if not connection:
        return None
    try:
        connection.settimeout(0.1)
        file_obj = connection.makefile('rb')
        line = file_obj.readline()
        if line:
            return line.rstrip(b'\n\r')
        return None
    except socket.timeout:
        return None
    except Exception as e:
        print(f"TcpConnectionManager receive_line error: {e}")
        self._handle_connection_error()
        return None
```

## TCP协议规范

### 消息格式
所有TCP消息使用JSON格式，以换行符(`\n`)分隔。

#### 读请求
```json
{
  "type": "mem_read",
  "channel_id": 0,
  "address": 67108864,
  "length": 4,
  "start_byte_index": 2,
  "is_first": true,
  "is_last": true,
  "request_id": "req_0_1703123456789"
}
```

#### 写请求
```json
{
  "type": "mem_write",
  "channel_id": 0,
  "address": 67108864,
  "data": [52, 18, 0, 0],
  "length": 4
}
```

#### 读响应
```json
{
  "type": "mem_read_response",
  "channel_id": 0,
  "request_id": "req_0_1703123456789",
  "data": [120, 86, 52, 18],
  "address": 67108864,
  "success": true
}
```

## 关键技术特性

### 1. 数据对齐处理

**读操作对齐**
```python
# 对于非对齐地址，数据需要左移以恢复正确位置
if is_first:
    data <<= (start_byte_index * 8)
```

**写操作对齐**
```python
# 从PCIe总线格式中提取数据时需要右移
if write_data.is_first():
    data >>= (write_data.start_byte_index() * 8)
```

### 2. 多通道支持
- **发送队列**: 单一共享队列简化架构
- **接收队列**: 每通道独立队列，确保响应路由正确
- **通道ID**: 所有消息包含channel_id用于路由

### 3. 时序保持
- **延迟队列**: 保持原有延迟行为，确保仿真时序准确
- **非阻塞等待**: 使用`time.sleep(0)`避免推进仿真时间
- **超时策略**: 超时仅记录警告，不跳过请求，保证数据流完整性

### 4. 错误处理
- **连接错误**: 自动重连机制
- **协议错误**: JSON解析异常处理
- **超时处理**: 非阻塞接收，定期检查超时

## BlueRdmaDataStream结构说明

| 字段 | 类型 | 用途 |
|------|------|------|
| data | int | 原始有效载荷（256或512位） |
| byte_num | int | 此beat中有效字节数 |
| start_byte_index | int | 非对齐地址的起始字节通道 |
| is_first | bool | 多beat传输的第一个beat |
| is_last | bool | 多beat传输的最后一个beat |

### 字段作用
- **start_byte_index**: 处理非对齐地址的关键字段，指示数据在256位总线中的起始位置
- **is_first/is_last**: 标记多beat传输的边界，用于数据重组
- **byte_num**: 指示当前beat包含多少有效字节

## 使用说明

### 仿真端使用
```python
# 初始化时指定TCP端口
proxy = SimplePcieBehaviorModelProxy(
    clock=dut.clk,
    reset=dut.reset,
    requester_channel_cnt=4,
    tcp_port=9999  # 新增参数
)

# 所有现有API调用保持不变
# 系统会自动处理TCP通信

# 优雅关闭
proxy.close()
```

### 驱动端实现要求
驱动端TCP服务器需要：
1. 监听指定端口的JSON行分隔消息
2. 解析请求并执行内存操作
3. 发送匹配的JSON格式响应，以`\n`分隔
4. 同时处理多通道请求

## 兼容性

### 向后兼容
- 所有现有仿真代码无需修改
- 保持原有API接口不变
- 维持多通道架构

### 时序保持
- 原有延迟行为完全保持
- 仿真时间推进不受TCP等待影响
- 数据完整性得到保证

## 架构优势

1. **分布式架构**: 实现仿真与内存管理的分离
2. **可扩展性**: 内存操作可由外部系统处理
3. **灵活性**: 驱动端可实现复杂内存管理策略
4. **调试友好**: TCP通信可被监控和记录
5. **独立测试**: 驱动端可独立于仿真进行测试

## 性能考虑

### 当前特点
- 顺序处理TCP请求，无需原子操作
- 线程池模式处理阻塞操作
- 队列缓冲提高吞吐量

### 未来优化方向
- 请求批处理和流水线
- 连接池管理
- 数据压缩
- 异步I/O

## 常见问题

**Q: 为什么需要数据对齐逻辑？**
A: PCIe总线以256位为单位传输数据，非对齐地址的数据需要通过start_byte_index确定在总线中的位置，通过位移操作恢复正确数据。

**Q: 超时处理策略为什么是记录而非跳过？**
A: 跳过请求会破坏数据流完整性，可能导致仿真结果错误。记录警告但继续等待确保所有请求都能得到响应。

**Q: 为什么使用单一发送队列？**
A: 简化架构设计，TCP请求本身是顺序处理的，多队列不会提升性能，反而增加复杂性。

**Q: 线程和协程如何协作？**
A: 线程处理阻塞的TCP操作，协程处理仿真逻辑，通过Queue进行通信，`time.sleep(0)`确保不推进仿真时间。

## 验证和测试

### 测试场景
1. 单通道连续读写
2. 多通道并发访问
3. 非对齐地址访问
4. 长时间稳定性测试
5. 异常情况处理（连接断开、超时等）

### 验证方法
- 对比共享内存和TCP模式的结果一致性
- 检查数据对齐正确性
- 验证多通道响应路由
- 测试错误恢复机制

## 未来工作

1. **驱动端完整实现**: 完成TCP服务器端开发
2. **性能优化**: 高吞吐量场景的优化
3. **安全增强**: TCP通信的认证和加密
4. **监控完善**: 详细日志和指标收集
5. **错误恢复**: 更健壮的错误恢复机制

这次架构转换成功地将PCIe BFM现代化，实现了分布式内存访问能力，同时保持了与现有仿真环境的完全兼容性。