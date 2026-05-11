/**
 * ===========================================================================
 * send_recv.c — Open-RDMA Send/Recv 双端通信测试
 * ===========================================================================
 *
 * 【测试目的】
 *   验证 RDMA Send/Recv 操作的正确性：Server 先投递一个接收请求 (Post Recv)，
 *   Client 再发送数据 (Post Send)，最后 Server 验证收到的数据是否正确。
 *
 * 【RDMA Send/Recv 语义】
 *   - Send:   发送端将本地 buffer 数据发送给对端（"推"模式）
 *             对端必须提前准备好接收 buffer（已 Post Recv）
 *   - Recv:   接收端预先投递一个接收请求，指定一个空 buffer 用于接收数据
 *             当 Send 数据到达时，硬件自动将数据 DMA 写入此 buffer
 *   - 关键约束: Recv 必须在 Send 之前投递，否则数据到达时找不到接收 buffer 会丢包
 *
 * 【运行方式】
 *   终端1 (Server):  ./send_recv <msg_len>
 *   终端2 (Client):  ./send_recv <msg_len> <server_ip>
 *   例如: 终端1:  ./send_recv 4096
 *         终端2:  ./send_recv 4096 127.0.0.1
 *
 * 【完整执行流程】
 *   ┌──────────────────────────────────────────────────────────────┐
 *   │  Server 端                        Client 端                  │
 *   │  ① 初始化 RDMA 上下文             ① 初始化 RDMA 上下文        │
 *   │     (打开设备、创建 PD/MR/CQ/QP)     (打开设备、创建 PD/MR/CQ/QP)│
 *   │                                   ② TCP 连接到 Server        │
 *   │  ② TCP 等待 Client 连接 ←────────③ TCP 连接建立               │
 *   │  ③ 通过 TCP 交换 QP 信息 ←──────→ 通过 TCP 交换 QP 信息       │
 *   │     (QP编号, rkey, buffer地址)      (QP编号, rkey, buffer地址) │
 *   │  ④ QP 状态迁移: RESET→INIT→RTR→RTS  QP 状态迁移: RESET→INIT→RTR→RTS │
 *   │  ⑤ TCP 同步 (handshake) ←────────→ TCP 同步 (handshake)     │
 *   │  ⑥ ibv_post_recv() 投递接收请求    ⑦ TCP 同步: 等待 Server 准备好  │
 *   │     ← 告诉 Client "我准备好了"        │
 *   │                                   ⑧ 填充发送 buffer ('c')     │
 *   │                                   ⑨ ibv_post_send() 发送数据  │
 *   │  ⑩ ibv_poll_cq() 等待接收完成      ⑩ ibv_poll_cq() 等待发送完成 │
 *   │  ⑪ 验证接收数据是否正确             ⑪ 检查发送状态              │
 *   │  ⑫ TCP 最终同步 ←──────────────→ ⑫ TCP 最终同步              │
 *   │  ⑬ 清理资源                        ⑬ 清理资源                 │
 *   └──────────────────────────────────────────────────────────────┘
 *
 * 【关键 RDMA 概念说明】
 *   - PD (Protection Domain):  保护域，隔离不同进程的 RDMA 资源
 *   - MR (Memory Region):      注册的内存区域，绑定 lkey/rkey
 *   - CQ (Completion Queue):   完成队列，通知操作完成
 *   - QP (Queue Pair):         队列对 (Send Queue + Receive Queue)
 *   - WR (Work Request):       工作请求，描述一次 RDMA 操作
 *   - SGE (Scatter/Gather Entry): 描述一个内存段 (地址+长度+lkey)
 *   - WC (Work Completion):    工作完成通知，包含状态和字节数
 *   - lkey: 本地访问密钥，用于硬件 DMA 读取本地内存
 *   - rkey: 远程访问密钥，对端用于 RDMA Read/Write 时访问此端内存
 *   - QP 状态机: RESET → INIT → RTR (Ready To Receive) → RTS (Ready To Send)
 *
 * ===========================================================================
 */

#include "../lib/rdma_common.h"    // RDMA 上下文管理 (设备、QP、CQ、MR)
#include "../lib/rdma_transport.h" // TCP 传输层 (同步、交换 QP 信息)
#include "../lib/rdma_debug.h"     // 调试工具 (数据校验、彩色输出)
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* =========================================================================
 * 常量定义
 * ========================================================================= */

/* Server 监听的 TCP 端口号。
 * Client 通过这个端口连接到 Server，交换 QP 信息。
 * 注意：这个 TCP 连接只用于控制面（交换元数据），不用于传输数据。
 * 实际的数据传输走 RDMA 通道。 */
#define DEFAULT_PORT 12346


/* =========================================================================
 * run_server — Server 端主逻辑
 * =========================================================================
 *
 * Server 的职责:
 *   1. 等待 Client 连接并交换 QP 信息
 *   2. 先投递 Recv 请求 (必须先于 Send)
 *   3. 等待 Client 发送数据并验证接收结果
 *
 * @param msg_len  要传输的消息长度 (字节)
 * @return         0=成功, -1=失败
 */
int run_server(int msg_len) {
    /* ---------- 变量声明 ----------
     * ctx:     RDMA 上下文，包含设备句柄、PD、QP、CQ、MR、buffer
     * config:  创建上下文的配置参数
     * transport: TCP 传输句柄 (用于控制面通信)
     * local_info:  本端的 QP 信息 (qp_num, rkey, buffer地址)
     * remote_info: 对端 (Client) 的 QP 信息，通过 TCP 交换获得
     */
    struct rdma_context ctx;
    struct rdma_config config;
    struct tcp_transport transport;
    struct qp_info local_info, remote_info;

    printf("========== SEND/RECV Server ==========\n");

    /* ---------- 步骤1: 初始化 RDMA 上下文 ----------
     * rdma_default_config() 设置默认参数:
     *   - buffer_size = msg_len (由调用方传入)
     *   - max_send_wr = 128, max_recv_wr = 128
     *   - cq_size = 512
     * rdma_init_context() 完成:
     *   ① 打开 RDMA 设备 (ibv_get_device_list → ibv_open_device)
     *   ② 分配 PD (ibv_alloc_pd)
     *   ③ 创建 CQ (ibv_create_cq)
     *   ④ 创建 QP (ibv_create_qp)
     *   ⑤ 注册 MR (ibv_reg_mr) — 让硬件能通过 lkey/rkey 访问这块内存
     *   ⑥ 分配 buffer (用于发送和接收)
     */
    rdma_default_config(&config);
    config.dev_index = 0;         // 使用第0号 RDMA 设备 (bluerdma0)
    config.buffer_size = msg_len;

    if (rdma_init_context(&ctx, &config) < 0) {
        return -1;
    }

    /* ---------- 步骤2: 启动 TCP Server 并等待 Client 连接 ----------
     * 这个 TCP 连接是"带外"控制通道，用于:
     *   - 交换 QP 信息 (qp_num, rkey, buffer地址)
     *   - 流程同步 (握手信号)
     * RDMA 本身不提供连接管理，所以用 TCP 来协调。
     */
    if (tcp_server_init(&transport, DEFAULT_PORT) < 0) {
        rdma_destroy_context(&ctx);
        return -1;
    }

    printf("[SERVER] Waiting for client connection...\n");
    if (tcp_server_accept(&transport) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤3: 通过 TCP 交换 QP 信息 ----------
     * 两个 RDMA 端点需要知道对方的信息才能通信:
     *   - qp_num:      对方的 QP 编号 (用于指定数据发到哪个 QP)
     *   - rkey:        对方 buffer 的远程访问密钥
     *   - remote_addr: 对方 buffer 的虚拟地址
     * 注意: Send/Recv 模式下不需要 rkey 和 remote_addr (只有 RDMA Write/Read 才需要)
     *       但这边统一交换了，方便代码复用。
     */
    local_info.qp_num = ctx.qp->qp_num;
    local_info.rkey = ctx.mr->rkey;
    local_info.remote_addr = (uint64_t)ctx.buffer;

    if (rdma_exchange_qp_info(transport.client_fd, &local_info, &remote_info) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤4: QP 状态迁移: RESET → RTS ----------
     * RDMA QP 必须经过严格的状态迁移才能使用:
     *   RESET → INIT → RTR (Ready To Receive) → RTS (Ready To Send)
     *
     * rdma_connect_qp() 是一个封装函数，依次调用:
     *   rdma_qp_to_init(qp)     — 设置端口、指定 QP 类型 (RC/UD 等)
     *   rdma_qp_to_rtr(qp, ...) — 指定对端 QP 编号和目标 GID (IP)
     *   rdma_qp_to_rts(qp)      — 设置超时、重试次数等参数
     *
     * dest_gid_ipv4: 对端的 IP 地址 (以 GID 格式表示)
     *   0x1122330B = 17.34.51.11 → Client 的 IP (对应 blue1)
     */
    uint32_t dest_gid_ipv4 = 0x1122330B; // client IP: 17.34.51.11
    if (rdma_connect_qp(ctx.qp, remote_info.qp_num, dest_gid_ipv4) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤5: TCP 同步 (第1次握手) ----------
     * 确保 Client 的 QP 也已经迁移到 RTS 状态，双方都准备好后继续。
     * rdma_handshake() 是一种简单的屏障同步:
     *   Server 端发送一个字节 "R"，然后等待接收一个字节。
     */
    printf("[SERVER] Synchronizing with client...\n");
    if (rdma_handshake(transport.client_fd) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤6: 清空 buffer 并投递 Recv 请求 ----------
     *
     * 这是 RDMA Send/Recv 最关键的一步: Server 必须先投递 Recv！
     *
     * 原因: RDMA 的 Recv 是"被动"的 — 硬件收到数据后，需要找到
     *       一个已经投递的 Recv WR，从中取出目标 buffer 地址和 lkey，
     *       才能把数据 DMA 写入。如果没有预投递的 Recv，数据包会被丢弃。
     *
     * ibv_recv_wr (Recv Work Request) 结构体:
     *   - sg_list:  指向 SGE 数组的指针
     *   - num_sge:  SGE 的数量 (这里为 1，即单个连续 buffer)
     *   - wr_id:    可选的请求 ID (这里未设置)
     *
     * ibv_sge (Scatter/Gather Entry) 结构体:
     *   - addr:   目标 buffer 的虚拟地址
     *   - length: buffer 长度 (字节)
     *   - lkey:   本地访问密钥 (从 MR 注册时获得)
     */
    memset(ctx.buffer, 0, msg_len);

    struct ibv_recv_wr wr = {0};
    struct ibv_recv_wr *bad_wr;
    struct ibv_sge sge = {
        .addr = (uint64_t)ctx.buffer,  // 接收数据写入这个地址
        .length = msg_len,             // 期望接收的长度
        .lkey = ctx.mr->lkey           // 硬件用 lkey 验证权限后 DMA 写入
    };
    wr.sg_list = &sge;
    wr.num_sge = 1;

    printf("[SERVER] Posting receive...\n");
    if (ibv_post_recv(ctx.qp, &wr, &bad_wr) != 0) {
        fprintf(stderr, "[ERROR] ibv_post_recv failed\n");
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤7: TCP 同步 (第2次握手) ----------
     * 通知 Client: "我已经投递了 Recv，你可以发送数据了"
     * 这确保了 Recv 一定在 Send 之前到达硬件。
     */
    if (rdma_handshake(transport.client_fd) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤8: 轮询 CQ 等待接收完成 ----------
     *
     * ibv_poll_cq() 会检查完成队列 (CQ) 是否有新的完成事件。
     * 当 Client 发送的数据被硬件 DMA 写入 buffer 后，硬件会往 CQ
     * 写入一个 Work Completion (WC)，其中包含:
     *   - status:    操作状态 (IBV_WC_SUCCESS = 成功)
     *   - byte_len:  实际接收的字节数
     *   - wr_id:     匹配的 WR ID
     *   - opcode:    完成的操作类型 (IBV_WC_RECV)
     *
     * 这里用忙轮询等待，每 1ms 检查一次。
     * 生产代码中应该用 ibv_get_cq_event() + 事件通知来避免 CPU 空转。
     */
    printf("[SERVER] Waiting for data...\n");
    struct ibv_wc wc = {0};
    int poll_count = 0;
    while (ibv_poll_cq(ctx.recv_cq, 1, &wc) < 1) {
        usleep(1000);  // 睡眠 1ms 避免 CPU 空转
        poll_count++;
        if (poll_count % 1000 == 0) {  // 每 1 秒打印一次状态
            printf("[SERVER] Still waiting... (poll_count=%d)\n", poll_count);
        }
    }

    printf("[SERVER] Receive completed: status=%d, byte_len=%u\n",
           wc.status, wc.byte_len);

    /* ---------- 步骤9: 验证接收数据 ----------
     *
     * Client 发送的数据是全部填充 'c' (0x63) 的 pattern。
     * 这里逐字节比较，统计有多少字节是正确的。
     *
     * rdma_verify_data() 使用预定义的 pattern 进行验证:
     *   RDMA_PATTERN_CHAR('c') — 期望每个字节都是 'c'
     */
    size_t error_count = 0;
    struct rdma_pattern pattern = RDMA_PATTERN_CHAR('c');
    rdma_verify_data(ctx.buffer, msg_len, &pattern, &error_count);
    int cnt_valid = msg_len - error_count;

    printf("[SERVER] Data verification: %d/%d bytes correct", cnt_valid, msg_len);
    if (error_count > 0) {
        printf(ANSI_COLOR_RED " (%zu errors)" ANSI_COLOR_RESET "\n", error_count);
        printf(ANSI_COLOR_RED "[SERVER] Test FAILED!\n" ANSI_COLOR_RESET);
    } else {
        printf(ANSI_COLOR_GREEN " (PASS)" ANSI_COLOR_RESET "\n");
        printf(ANSI_COLOR_GREEN "[SERVER] Test PASSED!\n" ANSI_COLOR_RESET);
    }

    /* ---------- 步骤10: 最终同步和清理 ----------
     * 最后再同步一次，确保 Client 也完成了所有操作，
     * 然后按逆序释放资源 (先释放后创建的)。
     */
    rdma_handshake(transport.client_fd);

    tcp_transport_close(&transport);
    rdma_destroy_context(&ctx);  // 释放 QP, CQ, MR, PD, 关闭设备

    return (cnt_valid == msg_len) ? 0 : -1;
}


/* =========================================================================
 * run_client — Client 端主逻辑
 * =========================================================================
 *
 * Client 的职责:
 *   1. 连接到 Server 并交换 QP 信息
 *   2. 等待 Server 投递 Recv 后，发送数据
 *   3. 等待发送完成确认
 *
 * @param msg_len    要发送的消息长度 (字节)
 * @param server_ip  Server 的 IP 地址 (如 "127.0.0.1")
 * @return           0=成功, -1=失败
 */
int run_client(int msg_len, const char *server_ip) {
    struct rdma_context ctx;
    struct rdma_config config;
    struct tcp_transport transport;
    struct qp_info local_info, remote_info;

    printf("========== SEND/RECV Client ==========\n");

    /* ---------- 步骤1: 初始化 RDMA 上下文 ----------
     * 注意: Client 使用 dev_index=1，即第1号 RDMA 设备 (bluerdma1)。
     * 这是因为在模拟环境中，bluerdma0 和 bluerdma1 代表
     * 两块不同的虚拟网卡，分别对应两个 QP 通道。
     * 只有真实的两端测试 (非 loopback) 才需要两个设备。
     */
    rdma_default_config(&config);
    config.dev_index = 1;  // Client 使用第1号设备 (bluerdma1)
    config.buffer_size = msg_len;

    if (rdma_init_context(&ctx, &config) < 0) {
        return -1;
    }

    /* ---------- 步骤2: TCP 连接到 Server ----------
     * Client 主动发起 TCP 连接，连接到 Server 的 DEFAULT_PORT。
     * 最多重试 30 次 (每次间隔 1 秒)，适应 Server 可能还没启动的情况。
     */
    printf("[CLIENT] Connecting to %s:%d...\n", server_ip, DEFAULT_PORT);
    if (tcp_client_connect(&transport, server_ip, DEFAULT_PORT, 30) < 0) {
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤3: 通过 TCP 交换 QP 信息 ----------
     * Client 发送自己的 QP 信息 (qp_num, rkey, addr)，
     * 同时接收 Server 的 QP 信息，存入 remote_info。
     */
    local_info.qp_num = ctx.qp->qp_num;
    local_info.rkey = ctx.mr->rkey;
    local_info.remote_addr = (uint64_t)ctx.buffer;

    if (rdma_exchange_qp_info(transport.sock_fd, &local_info, &remote_info) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    printf("[CLIENT] Remote QP: qp_num=%u, rkey=0x%x, addr=0x%lx\n",
           remote_info.qp_num, remote_info.rkey, remote_info.remote_addr);

    /* ---------- 步骤4: QP 状态迁移: RESET → RTS ----------
     * dest_gid_ipv4 = 0x1122330A = 17.34.51.10 → Server 的 IP (blue0)
     */
    uint32_t dest_gid_ipv4 = 0x1122330A; // server IP: 17.34.51.10
    if (rdma_connect_qp(ctx.qp, remote_info.qp_num, dest_gid_ipv4) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤5: TCP 同步 (第1次握手) ----------
     * 等待 Server 也完成 QP 状态迁移。
     * Client 端 rdma_handshake() 先接收再发送 (与 Server 相反)。
     */
    printf("[CLIENT] Synchronizing with server...\n");
    if (rdma_handshake(transport.sock_fd) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤6: TCP 同步 (第2次握手) ----------
     * 等待 Server 投递完 Recv 请求。
     * 这个同步至关重要: 确保 Client 的 Send 一定在 Server 的 Recv 之后。
     */
    if (rdma_handshake(transport.sock_fd) < 0) {
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤7: 准备发送数据 ----------
     * 将整个 buffer 填充为字符 'c' (0x63)。
     * Server 端通过验证是否每个字节都是 'c' 来判断传输正确性。
     */
    printf("[CLIENT] Filling buffer with 'c' pattern...\n");
    memset(ctx.buffer, 'c', msg_len);

    /* ---------- 步骤8: 构造并投递 Send 请求 ----------
     *
     * ibv_send_wr (Send Work Request) 结构体:
     *   - wr_id:      请求 ID (这里设为 7，用于在 CQ 中匹配)
     *   - sg_list:    指向 SGE 的指针 (数据来源)
     *   - num_sge:    SGE 数量
     *   - opcode:     操作类型 — IBV_WR_SEND 表示这是一个 Send 操作
     *   - send_flags: IBV_SEND_SIGNALED 表示完成后产生 CQ 事件
     *
     * Send 的数据流:
     *   ① 硬件从 SGE 描述的 buffer 中 DMA 读取数据
     *   ② 封装成 RDMA 数据包 (RoCEv2: Ethernet + IP + UDP + BTH + Payload)
     *   ③ 通过以太网发送给对端
     *   ④ 对端硬件解析数据包，根据 QP 编号找到预投递的 Recv WR
     *   ⑤ 将 Payload DMA 写入 Recv 指定的 buffer
     */
    struct ibv_sge sge = {
        .addr = (uint64_t)ctx.buffer,  // 数据来源地址
        .length = msg_len,             // 要发送的长度
        .lkey = ctx.mr->lkey           // 硬件用 lkey 验证权限后 DMA 读取
    };

    struct ibv_send_wr wr = {
        .wr_id = 7,                    // 请求 ID，在 WC 中返回用于匹配
        .sg_list = &sge,               // 数据来源描述
        .num_sge = 1,                  // 只有 1 个 SGE
        .opcode = IBV_WR_SEND,         // Send 操作 (不是 RDMA Write/Read)
        .send_flags = IBV_SEND_SIGNALED // 完成后在 CQ 中产生完成通知
    };

    struct ibv_send_wr *bad_wr;

    printf("[CLIENT] Posting send...\n");
    if (ibv_post_send(ctx.qp, &wr, &bad_wr) != 0) {
        fprintf(stderr, "[ERROR] ibv_post_send failed\n");
        tcp_transport_close(&transport);
        rdma_destroy_context(&ctx);
        return -1;
    }

    /* ---------- 步骤9: 轮询 CQ 等待发送完成 ----------
     *
     * 当硬件完成数据发送后，会往 CQ 写入一个 WC:
     *   - status:  IBV_WC_SUCCESS 表示发送成功
     *   - wr_id:   7 (与发送时的 wr_id 对应)
     *   - opcode:  IBV_WC_SEND
     *
     * 注意: 发送完成只表示数据已经发出或对端已确认 (取决于 QP 类型)，
     *       不表示对端应用已经处理了数据。
     */
    struct ibv_wc wc;
    int poll_count = 0;
    while (ibv_poll_cq(ctx.send_cq, 1, &wc) < 1) {
        usleep(1000);
        poll_count++;
        if (poll_count % 1000 == 0) {
            printf("[CLIENT] Still waiting for completion... (poll_count=%d)\n", poll_count);
        }
    }

    printf("[CLIENT] Send completed: status=%d, wr_id=%lu\n", wc.status, wc.wr_id);

    if (wc.status == IBV_WC_SUCCESS) {
        printf(ANSI_COLOR_GREEN "[CLIENT] Send SUCCESS!\n" ANSI_COLOR_RESET);
    } else {
        printf(ANSI_COLOR_RED "[CLIENT] Send FAILED (status=%d)\n" ANSI_COLOR_RESET, wc.status);
    }

    /* ---------- 步骤10: 最终同步和清理 ---------- */
    rdma_handshake(transport.sock_fd);

    tcp_transport_close(&transport);
    rdma_destroy_context(&ctx);

    return (wc.status == IBV_WC_SUCCESS) ? 0 : -1;
}


/* =========================================================================
 * main — 程序入口
 * =========================================================================
 *
 * 用法:
 *   Server 模式: ./send_recv <msg_len>
 *   Client 模式: ./send_recv <msg_len> <server_ip>
 *
 * 如何判断角色:
 *   argc == 2 → 没有 server_ip 参数 → 启动为 Server
 *   argc >= 3 → 有 server_ip 参数  → 启动为 Client
 */
int main(int argc, char *argv[]) {
    /* 禁用 stdout 缓冲，确保 printf 日志实时输出。
     * 这对调试很重要 — 如果缓冲了，可能程序崩溃时看不到最后的日志。 */
    setvbuf(stdout, NULL, _IONBF, 0);

    if (argc < 2) {
        fprintf(stderr, "Usage:\n");
        fprintf(stderr, "  Server: %s <msg_len>\n", argv[0]);
        fprintf(stderr, "  Client: %s <msg_len> <server_ip>\n", argv[0]);
        return EXIT_FAILURE;
    }

    int msg_len = atoi(argv[1]);
    if (msg_len <= 0) {
        fprintf(stderr, "Error: msg_len must be positive\n");
        return EXIT_FAILURE;
    }

    /* 根据参数个数决定运行角色:
     *   - 2 个参数 (只有 msg_len):      Server 模式
     *   - 3 个参数 (msg_len + server_ip): Client 模式 */
    if (argc == 2) {
        return run_server(msg_len);
    } else {
        return run_client(msg_len, argv[2]);
    }
}
