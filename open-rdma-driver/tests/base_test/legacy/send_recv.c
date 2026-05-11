#include <arpa/inet.h>
#include <infiniband/verbs.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <unistd.h>

// BUF_SIZE will be set based on msg_len parameter
#define PORT 12346

struct rdma_context
{
  struct ibv_context *ctx;
  struct ibv_pd *pd;
  struct ibv_mr *mr;
  struct ibv_cq *cq;
  struct ibv_qp *qp;
  char *buffer;
};

void die(const char *reason);
void setup_ib(struct rdma_context *ctx, bool is_client, int msg_len);
void exchange_info(int sock, struct rdma_context *ctx, uint32_t *rkey,
                   uint64_t *raddr, uint32_t *dqpn);
void run_server(int msg_len);
void run_client(int msg_len, char *server_ip);
void setup_qp(struct rdma_context *ctx, uint32_t dqpn, bool is_client);

void die(const char *reason)
{
  perror(reason);
  exit(EXIT_FAILURE);
}

void setup_ib(struct rdma_context *ctx, bool is_client, int msg_len)
{
  printf("[DEBUG] setup_ib: Starting IB setup (is_client=%d)\n", is_client);

  // Check for buffer size from environment variable
  size_t buffer_size = msg_len;
  char *env_buffer_size = getenv("RDMA_BUFFER_SIZE");
  if (env_buffer_size != NULL)
  {
    buffer_size = atoi(env_buffer_size);
    printf("[DEBUG] setup_ib: Using buffer size from RDMA_BUFFER_SIZE env var: %lu bytes\n", buffer_size);
  }
  else
  {
    printf("[DEBUG] setup_ib: Using default buffer size (msg_len): %lu bytes\n", buffer_size);
  }

  struct ibv_device **dev_list = ibv_get_device_list(NULL);
  printf("[DEBUG] setup_ib: ibv_get_device_list returned %p\n", (void *)dev_list);
  if (!dev_list)
    die("Failed to get IB devices list");

  // List all available devices
  int dev_count = 0;
  for (int i = 0; dev_list[i]; i++)
  {
    printf("[DEBUG] setup_ib: Device[%d]: %s\n", i, ibv_get_device_name(dev_list[i]));
    dev_count++;
  }
  printf("[DEBUG] setup_ib: Found %d IB devices\n", dev_count);

  int dev_index = is_client ? 1 : 0;
  printf("[DEBUG] setup_ib: Opening device index %d\n", dev_index);

  ctx->ctx = ibv_open_device(dev_list[dev_index]);

  printf("[DEBUG] setup_ib: ibv_open_device returned ctx=%p\n", (void *)ctx->ctx);
  if (!ctx->ctx)
    die("Failed to open IB device");

  printf("[DEBUG] setup_ib: Allocating PD...\n");
  ctx->pd = ibv_alloc_pd(ctx->ctx);
  printf("[DEBUG] setup_ib: ibv_alloc_pd returned pd=%p\n", (void *)ctx->pd);
  if (!ctx->pd)
    die("Failed to allocate PD");

  printf("[DEBUG] setup_ib: Allocating buffer (size=%lu bytes)...\n", buffer_size);
  ctx->buffer = mmap(NULL, buffer_size, PROT_READ | PROT_WRITE,
                     MAP_SHARED | MAP_ANONYMOUS | MAP_HUGETLB | MAP_POPULATE, -1, 0);
  if (ctx->buffer == MAP_FAILED)
  {
    printf("[DEBUG] setup_ib: mmap with MAP_HUGETLB failed, retrying without it\n");
    // Retry without MAP_HUGETLB for simulator compatibility
    ctx->buffer = mmap(NULL, buffer_size, PROT_READ | PROT_WRITE,
                       MAP_SHARED | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
    if (ctx->buffer == MAP_FAILED)
      die("Failed to mmap buffer");
  }
  printf("[DEBUG] setup_ib: Buffer allocated at %p\n", ctx->buffer);

  printf("[DEBUG] setup_ib: Registering MR (addr=%p, size=%lu)...\n", ctx->buffer, buffer_size);
  ctx->mr = ibv_reg_mr(ctx->pd, ctx->buffer, buffer_size,
                       IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE |
                           IBV_ACCESS_REMOTE_READ);
  printf("[DEBUG] setup_ib: ibv_reg_mr returned mr=%p\n", (void *)ctx->mr);
  if (!ctx->mr)
    die("Failed to register MR");
  printf("[DEBUG] setup_ib: MR registered - lkey=0x%x, rkey=0x%x\n",
         ctx->mr->lkey, ctx->mr->rkey);

  printf("[DEBUG] setup_ib: Creating CQ...\n");
  ctx->cq = ibv_create_cq(ctx->ctx, 1, NULL, NULL, 0);
  printf("[DEBUG] setup_ib: ibv_create_cq returned cq=%p\n", (void *)ctx->cq);
  if (!ctx->cq)
    die("Failed to create CQ");

  printf("[DEBUG] setup_ib: Creating QP...\n");
  struct ibv_qp_init_attr qp_attr = {.send_cq = ctx->cq,
                                     .recv_cq = ctx->cq,
                                     .cap = {.max_send_wr = 1,
                                             .max_recv_wr = 1,
                                             .max_send_sge = 1,
                                             .max_recv_sge = 1},
                                     .qp_type = IBV_QPT_RC};
  ctx->qp = ibv_create_qp(ctx->pd, &qp_attr);
  printf("[DEBUG] setup_ib: ibv_create_qp returned qp=%p\n", (void *)ctx->qp);
  if (!ctx->qp)
    die("Failed to create QP");
  printf("[DEBUG] setup_ib: QP created - qp_num=%u\n", ctx->qp->qp_num);

  printf("[DEBUG] setup_ib: Freeing device list\n");
  ibv_free_device_list(dev_list);
  printf("[DEBUG] setup_ib: IB setup completed successfully\n");
}

void setup_qp(struct rdma_context *ctx, uint32_t dqpn, bool is_client)
{
  printf("[DEBUG] setup_qp: Starting QP setup (qp=%p, dqpn=%u, is_client=%d)\n",
         (void *)ctx->qp, dqpn, is_client);

  printf("[DEBUG] setup_qp: Transitioning to INIT state...\n");
  struct ibv_qp_attr attr = {.qp_state = IBV_QPS_INIT,
                             .pkey_index = 0,
                             .port_num = 1,
                             .qp_access_flags = IBV_ACCESS_LOCAL_WRITE |
                                                IBV_ACCESS_REMOTE_WRITE |
                                                IBV_ACCESS_REMOTE_READ};

  if (ibv_modify_qp(ctx->qp, &attr,
                    IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT |
                        IBV_QP_ACCESS_FLAGS))
    die("Failed to transition QP to INIT");
  printf("[DEBUG] setup_qp: QP transitioned to INIT state\n");

  printf("[DEBUG] setup_qp: Transitioning to RTR state (dest_qp_num=%u)...\n", dqpn);
  memset(&attr, 0, sizeof(attr));
  attr.qp_state = IBV_QPS_RTR;
  attr.path_mtu = IBV_MTU_4096;
  attr.dest_qp_num = dqpn;
  attr.rq_psn = 0;
  attr.max_dest_rd_atomic = 1;
  attr.min_rnr_timer = 12;
  attr.ah_attr.is_global = 0;
  attr.ah_attr.dlid = 0;
  attr.ah_attr.sl = 0;
  attr.ah_attr.src_path_bits = 0;
  attr.ah_attr.port_num = 1;

  if (ibv_modify_qp(ctx->qp, &attr,
                    IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU |
                        IBV_QP_DEST_QPN | IBV_QP_RQ_PSN |
                        IBV_QP_MAX_DEST_RD_ATOMIC | IBV_QP_MIN_RNR_TIMER))
    die("Failed to transition QP to RTR");
  printf("[DEBUG] setup_qp: QP transitioned to RTR state\n");

  printf("[DEBUG] setup_qp: Transitioning to RTS state...\n");
  memset(&attr, 0, sizeof(attr));
  attr.qp_state = IBV_QPS_RTS;
  attr.timeout = 14;
  attr.retry_cnt = 7;
  attr.rnr_retry = 7;
  attr.sq_psn = 0;
  attr.max_rd_atomic = 1;

  // Client: 17.34.51.10 (0x1122330A), Server:
  uint32_t ipv4_addr = 0x0;
  printf("[DEBUG] setup_qp: Setting GID with IPv4 address 0x%08x (is_client=%d)\n",
         ipv4_addr, is_client);
  attr.ah_attr.grh.dgid.raw[10] = 0x0;
  attr.ah_attr.grh.dgid.raw[11] = 0x0;
  attr.ah_attr.grh.dgid.raw[12] = (ipv4_addr >> 24) & 0xFF;
  attr.ah_attr.grh.dgid.raw[13] = (ipv4_addr >> 16) & 0xFF;
  attr.ah_attr.grh.dgid.raw[14] = (ipv4_addr >> 8) & 0xFF;
  attr.ah_attr.grh.dgid.raw[15] = ipv4_addr & 0xFF;

  if (ibv_modify_qp(ctx->qp, &attr,
                    IBV_QP_STATE | IBV_QP_AV | IBV_QP_TIMEOUT |
                        IBV_QP_RETRY_CNT | IBV_QP_RNR_RETRY | IBV_QP_SQ_PSN |
                        IBV_QP_MAX_QP_RD_ATOMIC))
    die("Failed to transition QP to RTS");
  printf("[DEBUG] setup_qp: QP transitioned to RTS state\n");
  printf("[DEBUG] setup_qp: QP setup completed successfully\n");
}

void exchange_info(int sock, struct rdma_context *ctx, uint32_t *rkey,
                   uint64_t *raddr, uint32_t *dqpn)
{
  printf("[DEBUG] exchange_info: Starting info exchange\n");

  uint32_t lkey = ctx->mr->rkey;
  uint64_t addr = (uint64_t)ctx->buffer;
  uint32_t qpn = ctx->qp->qp_num;

  printf("[DEBUG] exchange_info: Local info - lkey=0x%x, addr=%p, qpn=%u\n",
         lkey, (void *)addr, qpn);

  printf("[DEBUG] exchange_info: Sending local info...\n");
  if (send(sock, &lkey, sizeof(lkey), 0) < 0 ||
      (send(sock, &addr, sizeof(addr), 0) < 0 ||
       send(sock, &qpn, sizeof(qpn), 0) < 0))
    die("Failed to send MR info");
  printf("[DEBUG] exchange_info: Local info sent successfully\n");

  printf("[DEBUG] exchange_info: Receiving remote info...\n");
  if (recv(sock, rkey, sizeof(*rkey), 0) < 0 ||
      (recv(sock, raddr, sizeof(*raddr), 0) < 0 ||
       recv(sock, dqpn, sizeof(*dqpn), 0) < 0))
    die("Failed to receive MR info");

  printf("[DEBUG] exchange_info: Remote info - rkey=0x%x, raddr=%p, dqpn=%u\n",
         *rkey, (void *)*raddr, *dqpn);
  printf("[DEBUG] exchange_info: Info exchange completed\n");
}

void handshake(int sock)
{
  printf("[DEBUG] handshake: Starting handshake (sock=%d)\n", sock);
  char dummy = 0;

  printf("[DEBUG] handshake: Sending handshake byte...\n");
  if (send(sock, &dummy, sizeof(dummy), 0) < 0)
    die("Failed to send handshake");

  printf("[DEBUG] handshake: Waiting for handshake response...\n");
  if (recv(sock, &dummy, sizeof(dummy), 0) < 0)
    die("Failed to receive handshake");

  printf("[DEBUG] handshake: Handshake completed successfully\n");
}

void run_server(int msg_len)
{
  printf("[DEBUG] run_server: ========== SERVER STARTING (msg_len=%d) ==========\n", msg_len);

  struct rdma_context ctx;
  printf("[DEBUG] run_server: rdma_context allocated on stack at %p\n", (void *)&ctx);

  printf("[DEBUG] run_server: Calling setup_ib (is_client=false)...\n");
  setup_ib(&ctx, false, msg_len);
  printf("[DEBUG] run_server: setup_ib completed\n");

  printf("[DEBUG] run_server: Creating TCP socket...\n");
  int sock = socket(AF_INET, SOCK_STREAM, 0);
  printf("[DEBUG] run_server: socket() returned %d\n", sock);
  if (sock < 0)
    die("Failed to create socket");

  int opt = 1;
  printf("[DEBUG] run_server: Setting SO_REUSEPORT...\n");
  if (setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt)) == -1)
  {
    die("setsockopt");
  }

  struct sockaddr_in addr = {.sin_family = AF_INET,
                             .sin_addr.s_addr = INADDR_ANY,
                             .sin_port = htons(PORT)};
  printf("[DEBUG] run_server: Binding to port %d...\n", PORT);
  if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0)
  {
    die("failed to bind to addr");
  }

  printf("[DEBUG] run_server: Listening for connections...\n");
  listen(sock, 1);

  printf("Server waiting for connection...\n");
  int client_sock = accept(sock, NULL, NULL);
  printf("[DEBUG] run_server: Client connected (client_sock=%d)\n", client_sock);

  printf("[DEBUG] run_server: Zeroing buffer at %p (size=%d)\n", ctx.buffer, msg_len);

  // Check if buffer pointer is valid
  if (ctx.buffer == NULL)
  {
    printf("[ERROR] run_server: Buffer is NULL!\n");
    die("Invalid buffer pointer");
  }

  printf("[DEBUG] run_server: Buffer pointer validated, starting memset...\n");
  fflush(stdout); // Ensure log is written before potential crash

  memset(ctx.buffer, 0, msg_len);

  printf("[DEBUG] run_server: Buffer cleared successfully\n");

  uint32_t rkey;
  uint64_t raddr;
  uint32_t dqpn;

  printf("[DEBUG] run_server: Exchanging QP info with client...\n");
  exchange_info(client_sock, &ctx, &rkey, &raddr, &dqpn);
  printf("[DEBUG] run_server: Info exchanged - setting up QP with dqpn=%u, raddr=%p\n", dqpn, (void *)raddr);

  setup_qp(&ctx, dqpn, false); // server: is_client=false
  printf("[DEBUG] run_server: QP setup completed\n");

  printf("[DEBUG] run_server: Performing handshake (ensure client QP is ready)...\n");
  handshake(client_sock);
  printf("[DEBUG] run_server: Handshake completed - both QPs are in RTS state\n");

  printf("[DEBUG] run_server: Preparing receive work request...\n");

  struct ibv_recv_wr wr = {0};
  struct ibv_recv_wr *bad_wr;
  struct ibv_sge sge = {
      .addr = (uint64_t)ctx.buffer, .length = msg_len, .lkey = ctx.mr->lkey};
  wr.sg_list = &sge;
  wr.num_sge = 1;

  printf("[DEBUG] run_server: Posting receive (addr=0x%lx, len=%lu, lkey=0x%x)...\n",
         sge.addr, sge.length, sge.lkey);
  if (ibv_post_recv(ctx.qp, &wr, &bad_wr) != 0)
  {
    printf("[ERROR] run_server: ibv_post_recv failed!\n");
    die("ibv_post_recv failed");
  }
  printf("[DEBUG] run_server: Receive posted successfully\n");

  // TODO 这一次同步有必要吗？
  printf("[DEBUG] run_server: Performing handshake (ensure recv is send to client)...\n");
  handshake(client_sock);

  long long cnt_valid = 0;
  struct ibv_wc wc = {0};

  printf("[DEBUG] run_server: Polling CQ for completion...\n");
  int poll_count = 0;
  while (ibv_poll_cq(ctx.cq, 1, &wc) < 1)
  {
    usleep(1000);
    poll_count++;
    if (poll_count % 1000 == 0)
    {
      printf("[DEBUG] run_server: Still polling CQ (count=%d)...\n", poll_count);
    }
  }
  printf("[DEBUG] run_server: CQ poll completed after %d iterations\n", poll_count);
  printf("[DEBUG] run_server: WC status=%d, opcode=%d, byte_len=%u\n",
         wc.status, wc.opcode, wc.byte_len);

  printf("[DEBUG] run_server: Validating received data...\n");
  for (int i = 0; i < msg_len; i++)
  {
    if (ctx.buffer[i] == 'c')
    {
      cnt_valid++;
    }
  }

  printf("received bytes count: %lld\n", cnt_valid);
  printf("[DEBUG] run_server: ========== SERVER COMPLETED ==========\n");

  printf("[DEBUG] run_server: Performing final handshake...\n");
  handshake(client_sock);

  close(client_sock);
  close(sock);
}

void run_client(int msg_len, char *server_ip)
{
  printf("[DEBUG] run_client: ========== CLIENT STARTING (msg_len=%d, server=%s) ==========\n",
         msg_len, server_ip);

  struct rdma_context ctx;
  printf("[DEBUG] run_client: rdma_context allocated on stack at %p\n", (void *)&ctx);

  printf("[DEBUG] run_client: Calling setup_ib (is_client=true)...\n");
  setup_ib(&ctx, true, msg_len);
  printf("[DEBUG] run_client: setup_ib completed\n");

  printf("[DEBUG] run_client: Creating TCP socket...\n");
  int sock = socket(AF_INET, SOCK_STREAM, 0);
  printf("[DEBUG] run_client: socket() returned %d\n", sock);
  if (sock < 0)
    die("Failed to create socket");

  struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(PORT)};
  printf("[DEBUG] run_client: Converting server IP '%s' to binary...\n", server_ip);
  inet_pton(AF_INET, server_ip, &addr.sin_addr);

  printf("[DEBUG] run_client: Connecting to server %s:%d...\n", server_ip, PORT);

  // Retry connection up to 30 times (6 seconds between retries = 180 seconds total)
  int max_retries = 30;
  int retry_delay = 6; // seconds
  int connected = 0;

  for (int retry = 0; retry < max_retries; retry++)
  {
    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) == 0)
    {
      connected = 1;
      break;
    }

    if (retry < max_retries - 1)
    {
      printf("[DEBUG] run_client: Connection failed (attempt %d/%d), retrying in %d seconds...\n",
             retry + 1, max_retries, retry_delay);
      sleep(retry_delay);

      // Need to create a new socket for the next retry attempt
      close(sock);
      sock = socket(AF_INET, SOCK_STREAM, 0);
      if (sock < 0)
        die("Failed to create socket for retry");
    }
  }

  if (!connected)
  {
    die("failed to connect after all retries");
  }

  printf("[DEBUG] run_client: Connected to server successfully\n");

  uint32_t rkey;
  uint64_t raddr;
  uint32_t dqpn;

  printf("[DEBUG] run_client: Exchanging QP info with server...\n");
  exchange_info(sock, &ctx, &rkey, &raddr, &dqpn);

  printf("info exchange success\n");
  printf("dqpn: %d, raddr: 0x%lx\n", dqpn, raddr);
  printf("[DEBUG] run_client: Info exchanged - setting up QP with dqpn=%u, raddr=%p\n", dqpn, (void *)raddr);
  setup_qp(&ctx, dqpn, true); // client: is_client=true
  printf("[DEBUG] run_client: QP setup completed\n");

  printf("[DEBUG] run_client: Filling buffer with pattern 'a' (length=%d)...\n", msg_len);
  memset(ctx.buffer, 'c', msg_len);
  printf("[DEBUG] run_client: Buffer filled\n");

  printf("[DEBUG] run_client: Preparing send work request...\n");
  struct ibv_sge sge = {
      .addr = (uint64_t)ctx.buffer, .length = msg_len, .lkey = ctx.mr->lkey};
  printf("[DEBUG] run_client: SGE - addr=0x%lx, len=%u, lkey=0x%x\n",
         sge.addr, sge.length, sge.lkey);

  struct ibv_send_wr wr = {.wr_id = 7,
                           .sg_list = &sge,
                           .num_sge = 1,
                           .imm_data = 11,
                           .opcode = IBV_WR_SEND,
                           .send_flags = IBV_SEND_SIGNALED};
  wr.wr.rdma.remote_addr = raddr;
  wr.wr.rdma.rkey = rkey;

  printf("[DEBUG] run_client: Send WR - wr_id=%lu, opcode=%d, imm_data=%u\n",
         wr.wr_id, wr.opcode, wr.imm_data);
  printf("[DEBUG] run_client: Remote - addr=0x%lx, rkey=0x%x\n",
         wr.wr.rdma.remote_addr, wr.wr.rdma.rkey);

  struct ibv_send_wr *bad_wr;

  printf("[DEBUG] run_client: Performing handshake before send...\n");
  handshake(sock);
  printf("[DEBUG] run_client: Handshake completed\n");

  printf("[DEBUG] run_client: Performing handshake (ensure client get recv...)...\n");
  handshake(sock);
  printf("[DEBUG] run_client: Handshake completed - \n");

  // sleep(1000); // Ensure server is ready to receive

  printf("[DEBUG] run_client: Posting send (qp=%p)...\n", (void *)ctx.qp);
  int ret = ibv_post_send(ctx.qp, &wr, &bad_wr);
  if (ret != 0)
  {
    printf("[ERROR] run_client: ibv_post_send failed with ret=%d, bad_wr=%p\n",
           ret, (void *)bad_wr);
    die("ibv_post_send failed");
  }
  printf("[DEBUG] run_client: Send posted successfully\n");

  printf("[DEBUG] run_client: Polling CQ for send completion...\n");
  struct ibv_wc wc;
  int poll_count = 0;
  while (ibv_poll_cq(ctx.cq, 1, &wc) < 1)
  {
    usleep(1000);
    poll_count++;
    if (poll_count % 1000 == 0)
    {
      printf("[DEBUG] run_client: Still polling CQ (count=%d)...\n", poll_count);
    }
  }
  printf("[DEBUG] run_client: CQ poll completed after %d iterations\n", poll_count);
  printf("[DEBUG] run_client: WC - status=%d, opcode=%d, wr_id=%lu\n",
         wc.status, wc.opcode, wc.wr_id);

  printf("[DEBUG] run_client: ========== CLIENT COMPLETED ==========\n");

  printf("[DEBUG] run_server: Performing final handshake...\n");
  handshake(sock);

  close(sock);
}

int main(int argc, char *argv[])
{
  // 禁用 stdout 缓冲，确保日志立即输出（特别是重定向到文件时）
  setvbuf(stdout, NULL, _IONBF, 0);

  printf("[DEBUG] main: ========== PROGRAM START ==========\n");
  printf("[DEBUG] main: argc=%d\n", argc);
  for (int i = 0; i < argc; i++)
  {
    printf("[DEBUG] main: argv[%d]='%s'\n", i, argv[i]);
  }

  if (argc == 2)
  {
    int msg_len = atoi(argv[1]);
    printf("[DEBUG] main: Mode=SERVER, msg_len=%d\n", msg_len);
    run_server(msg_len);
  }
  else if (argc == 3)
  {
    int msg_len = atoi(argv[1]);
    printf("[DEBUG] main: Mode=CLIENT, msg_len=%d, server_ip='%s'\n", msg_len, argv[2]);
    run_client(msg_len, argv[2]);
  }
  else
  {
    fprintf(stderr, "Usage: %s <msg_len> [server_ip]\n", argv[0]);
    fprintf(stderr, "  Run without arguments to start as server\n");
    fprintf(stderr, "  Run with server_ip to connect as client\n");
    return EXIT_FAILURE;
  }

  printf("[DEBUG] main: Sleeping for 1 second before exit...\n");
  sleep(1);

  printf("[DEBUG] main: ========== PROGRAM EXIT ==========\n");
  return EXIT_SUCCESS;
}
