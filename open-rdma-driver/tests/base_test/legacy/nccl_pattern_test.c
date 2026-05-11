#define _GNU_SOURCE
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

#define PORT 12347
#define MAX_RECV_WR 10
#define MAX_SEND_WR 10

struct rdma_context
{
  struct ibv_context *ctx;
  struct ibv_pd *pd;
  struct ibv_mr *mr;
  struct ibv_cq *cq;
  struct ibv_qp *qp;
  char *buffer;
  size_t buffer_size;
};

void die(const char *reason);
void setup_ib(struct rdma_context *ctx, bool is_client, size_t buffer_size);
void exchange_info(int sock, struct rdma_context *ctx, uint32_t *rkey,
                   uint64_t *raddr, uint32_t *dqpn);
void setup_qp(struct rdma_context *ctx, uint32_t dqpn, bool is_client);
void run_server();
void run_client(char *server_ip);
void handshake(int sock);

void die(const char *reason)
{
  perror(reason);
  exit(EXIT_FAILURE);
}

void setup_ib(struct rdma_context *ctx, bool is_client, size_t buffer_size)
{
  printf("[DEBUG] setup_ib: Starting (is_client=%d, buffer_size=%zu)\n", is_client, buffer_size);

  struct ibv_device **dev_list = ibv_get_device_list(NULL);
  if (!dev_list)
    die("Failed to get IB devices list");

  int dev_index = is_client ? 1 : 0;
  printf("[DEBUG] setup_ib: Opening device index %d\n", dev_index);

  ctx->ctx = ibv_open_device(dev_list[dev_index]);
  if (!ctx->ctx)
    die("Failed to open IB device");

  ctx->pd = ibv_alloc_pd(ctx->ctx);
  if (!ctx->pd)
    die("Failed to allocate PD");

  ctx->buffer_size = buffer_size;
  ctx->buffer = mmap(NULL, buffer_size, PROT_READ | PROT_WRITE,
                     MAP_SHARED | MAP_ANONYMOUS | MAP_HUGETLB | MAP_POPULATE, -1, 0);
  if (ctx->buffer == MAP_FAILED)
  {
    ctx->buffer = mmap(NULL, buffer_size, PROT_READ | PROT_WRITE,
                       MAP_SHARED | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
    if (ctx->buffer == MAP_FAILED)
      die("Failed to mmap buffer");
  }
  printf("[DEBUG] setup_ib: Buffer allocated at %p (size=%zu)\n", ctx->buffer, buffer_size);

  ctx->mr = ibv_reg_mr(ctx->pd, ctx->buffer, buffer_size,
                       IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE |
                           IBV_ACCESS_REMOTE_READ);
  if (!ctx->mr)
    die("Failed to register MR");
  printf("[DEBUG] setup_ib: MR registered - lkey=0x%x, rkey=0x%x\n",
         ctx->mr->lkey, ctx->mr->rkey);

  ctx->cq = ibv_create_cq(ctx->ctx, MAX_SEND_WR + MAX_RECV_WR, NULL, NULL, 0);
  if (!ctx->cq)
    die("Failed to create CQ");

  struct ibv_qp_init_attr qp_attr = {
      .send_cq = ctx->cq,
      .recv_cq = ctx->cq,
      .cap = {
          .max_send_wr = MAX_SEND_WR,
          .max_recv_wr = MAX_RECV_WR,
          .max_send_sge = 1,
          .max_recv_sge = 1},
      .qp_type = IBV_QPT_RC};
  ctx->qp = ibv_create_qp(ctx->pd, &qp_attr);
  if (!ctx->qp)
    die("Failed to create QP");
  printf("[DEBUG] setup_ib: QP created - qp_num=%u\n", ctx->qp->qp_num);

  ibv_free_device_list(dev_list);
}

void setup_qp(struct rdma_context *ctx, uint32_t dqpn, bool is_client)
{
  printf("[DEBUG] setup_qp: Transitioning to INIT (dqpn=%u)\n", dqpn);

  struct ibv_qp_attr attr = {
      .qp_state = IBV_QPS_INIT,
      .pkey_index = 0,
      .port_num = 1,
      .qp_access_flags = IBV_ACCESS_LOCAL_WRITE |
                         IBV_ACCESS_REMOTE_WRITE |
                         IBV_ACCESS_REMOTE_READ};

  if (ibv_modify_qp(ctx->qp, &attr,
                    IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT | IBV_QP_ACCESS_FLAGS))
    die("Failed to transition QP to INIT");

  printf("[DEBUG] setup_qp: Transitioning to RTR\n");
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

  printf("[DEBUG] setup_qp: Transitioning to RTS\n");
  memset(&attr, 0, sizeof(attr));
  attr.qp_state = IBV_QPS_RTS;
  attr.timeout = 14;
  attr.retry_cnt = 7;
  attr.rnr_retry = 7;
  attr.sq_psn = 0;
  attr.max_rd_atomic = 1;

  if (ibv_modify_qp(ctx->qp, &attr,
                    IBV_QP_STATE | IBV_QP_TIMEOUT |
                        IBV_QP_RETRY_CNT | IBV_QP_RNR_RETRY | IBV_QP_SQ_PSN |
                        IBV_QP_MAX_QP_RD_ATOMIC))
    die("Failed to transition QP to RTS");

  printf("[DEBUG] setup_qp: QP in RTS state\n");
}

void exchange_info(int sock, struct rdma_context *ctx, uint32_t *rkey,
                   uint64_t *raddr, uint32_t *dqpn)
{
  uint32_t lkey = ctx->mr->rkey;
  uint64_t addr = (uint64_t)ctx->buffer;
  uint32_t qpn = ctx->qp->qp_num;

  printf("[DEBUG] exchange_info: Sending local info - qpn=%u, addr=%p, rkey=0x%x\n",
         qpn, (void *)addr, lkey);

  if (send(sock, &lkey, sizeof(lkey), 0) < 0 ||
      send(sock, &addr, sizeof(addr), 0) < 0 ||
      send(sock, &qpn, sizeof(qpn), 0) < 0)
    die("Failed to send info");

  if (recv(sock, rkey, sizeof(*rkey), 0) < 0 ||
      recv(sock, raddr, sizeof(*raddr), 0) < 0 ||
      recv(sock, dqpn, sizeof(*dqpn), 0) < 0)
    die("Failed to receive info");

  printf("[DEBUG] exchange_info: Remote info - dqpn=%u, raddr=%p, rkey=0x%x\n",
         *dqpn, (void *)*raddr, *rkey);
}

void handshake(int sock)
{
  char dummy = 0;
  if (send(sock, &dummy, sizeof(dummy), 0) < 0)
    die("Failed to send handshake");
  if (recv(sock, &dummy, sizeof(dummy), 0) < 0)
    die("Failed to receive handshake");
}

void run_server()
{
  printf("[DEBUG] ========== SERVER STARTING ==========\n");

  struct rdma_context ctx;
  setup_ib(&ctx, false, 4096); // 4KB buffer

  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0)
    die("Failed to create socket");

  int opt = 1;
  setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));

  struct sockaddr_in addr = {
      .sin_family = AF_INET,
      .sin_addr.s_addr = INADDR_ANY,
      .sin_port = htons(PORT)};

  if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0)
    die("Failed to bind");

  listen(sock, 1);
  printf("Server waiting for connection...\n");

  int client_sock = accept(sock, NULL, NULL);
  printf("[DEBUG] Client connected\n");

  uint32_t rkey;
  uint64_t raddr;
  uint32_t dqpn;

  exchange_info(client_sock, &ctx, &rkey, &raddr, &dqpn);
  setup_qp(&ctx, dqpn, false);
  handshake(client_sock);

  // Mimic NCCL pattern: Interleave post_recv and post_send
  printf("\n[DEBUG] SERVER: Starting NCCL pattern (recv + send interleaved)...\n");

  // First: post recv (zero-length) + post send (RDMA Write, 64 bytes)
  struct ibv_recv_wr recv_wr1 = {.wr_id = 0};
  struct ibv_recv_wr *bad_recv_wr;
  if (ibv_post_recv(ctx.qp, &recv_wr1, &bad_recv_wr) != 0)
    die("ibv_post_recv #1 failed");
  printf("[DEBUG] SERVER: Posted recv wr_id=0 (length=0)\n");

  // Post RDMA Write (normal, no IMM)
  memset(ctx.buffer, 'X', 64);
  struct ibv_sge send_sge1 = {
      .addr = (uint64_t)ctx.buffer,
      .length = 64,
      .lkey = ctx.mr->lkey};
  struct ibv_send_wr send_wr1 = {
      .wr_id = 0, // Match log pattern
      .sg_list = &send_sge1,
      .num_sge = 1,
      .opcode = IBV_WR_RDMA_WRITE,
      .send_flags = IBV_SEND_SIGNALED};
  send_wr1.wr.rdma.remote_addr = raddr;
  send_wr1.wr.rdma.rkey = rkey;

  struct ibv_send_wr *bad_send_wr;
  if (ibv_post_send(ctx.qp, &send_wr1, &bad_send_wr) != 0)
    die("ibv_post_send #1 failed");
  printf("[DEBUG] SERVER: Posted send RDMA_WRITE #1 (64 bytes, wr_id=0)\n");

  // Second: post recv (zero-length) + post send (RDMA Write, 64 bytes, NO SIGNAL)
  struct ibv_recv_wr recv_wr2 = {.wr_id = 1};
  if (ibv_post_recv(ctx.qp, &recv_wr2, &bad_recv_wr) != 0)
    die("ibv_post_recv #2 failed");
  printf("[DEBUG] SERVER: Posted recv wr_id=1 (length=0)\n");

  // Post recv again with same wr_id (mimic log pattern)
  struct ibv_recv_wr recv_wr3 = {.wr_id = 1};
  if (ibv_post_recv(ctx.qp, &recv_wr3, &bad_recv_wr) != 0)
    die("ibv_post_recv #3 failed");
  printf("[DEBUG] SERVER: Posted recv wr_id=1 again (length=0)\n");

  memset(ctx.buffer + 64, 'Y', 64);
  struct ibv_sge send_sge2 = {
      .addr = (uint64_t)(ctx.buffer + 64),
      .length = 64,
      .lkey = ctx.mr->lkey};
  struct ibv_send_wr send_wr2 = {
      .wr_id = 0, // Same wr_id as first send
      .sg_list = &send_sge2,
      .num_sge = 1,
      .opcode = IBV_WR_RDMA_WRITE,
      .send_flags = 0}; // NO IBV_SEND_SIGNALED
  send_wr2.wr.rdma.remote_addr = raddr + 64;
  send_wr2.wr.rdma.rkey = rkey;

  if (ibv_post_send(ctx.qp, &send_wr2, &bad_send_wr) != 0)
    die("ibv_post_send #2 failed");
  printf("[DEBUG] SERVER: Posted send RDMA_WRITE #2 (64 bytes, NO SIGNAL, wr_id=0)\n");

  // Signal client to start
  handshake(client_sock);

  // Poll for send completions (only 1 expected, since 2nd send has no SIGNALED flag)
  printf("\n[DEBUG] SERVER: Polling for send completions...\n");
  struct ibv_wc wc[8];
  int send_completions = 0;
  int poll_count = 0;

  while (send_completions < 1) // Only 1 send completion expected
  {
    int n = ibv_poll_cq(ctx.cq, 8, wc);
    if (n < 0)
      die("ibv_poll_cq failed");

    for (int i = 0; i < n; i++)
    {
      if (wc[i].status != IBV_WC_SUCCESS)
      {
        printf("[ERROR] WC failed: status=%d\n", wc[i].status);
        continue;
      }

      if (wc[i].opcode == IBV_WC_RDMA_WRITE)
      {
        printf("[DEBUG] SERVER: Send completion #%d - wr_id=%lu\n",
               send_completions + 1, wc[i].wr_id);
        send_completions++;
      }
    }

    if (n > 0)
      poll_count = 0;
    else
    {
      usleep(1000);
      poll_count++;
      if (poll_count % 1000 == 0)
        printf("[DEBUG] SERVER: Still polling sends (count=%d)...\n", poll_count);
    }
  }

  printf("[DEBUG] SERVER: Send completion received (only 1, as 2nd send has no SIGNALED)\n");

  // Poll for recv completions (RecvRdmaWithImm)
  printf("\n[DEBUG] SERVER: Polling for recv completions...\n");
  int recv_completions = 0;
  poll_count = 0;

  while (recv_completions < 2)
  {
    int n = ibv_poll_cq(ctx.cq, 8, wc);
    if (n < 0)
      die("ibv_poll_cq failed");

    for (int i = 0; i < n; i++)
    {
      if (wc[i].status != IBV_WC_SUCCESS)
      {
        printf("[ERROR] WC failed: status=%d\n", wc[i].status);
        continue;
      }

      if (wc[i].opcode == IBV_WC_RECV_RDMA_WITH_IMM)
      {
        printf("[DEBUG] SERVER: Recv completion #%d - wr_id=%lu",
               recv_completions + 1, wc[i].wr_id);

        if (wc[i].wc_flags & IBV_WC_WITH_IMM)
        {
          printf(", imm_data=0x%x", ntohl(wc[i].imm_data));
        }
        printf("\n");

        recv_completions++;
      }
    }

    if (n > 0)
      poll_count = 0;
    else
    {
      usleep(1000);
      poll_count++;
      if (poll_count % 1000 == 0)
        printf("[DEBUG] SERVER: Still polling recvs (count=%d)...\n", poll_count);
    }
  }

  printf("\n[DEBUG] SERVER: All completions received (1 send + 2 recvs)\n");
  printf("[DEBUG] ========== SERVER COMPLETED ==========\n");

  handshake(client_sock);
  close(client_sock);
  close(sock);
}

void run_client(char *server_ip)
{
  printf("[DEBUG] ========== CLIENT STARTING ==========\n");

  struct rdma_context ctx;
  setup_ib(&ctx, true, 4096); // 4KB buffer

  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0)
    die("Failed to create socket");

  struct sockaddr_in addr = {
      .sin_family = AF_INET,
      .sin_port = htons(PORT)};
  inet_pton(AF_INET, server_ip, &addr.sin_addr);

  printf("[DEBUG] Connecting to server %s:%d...\n", server_ip, PORT);

  int max_retries = 30;
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
      printf("[DEBUG] Connection failed, retrying in 6 seconds...\n");
      sleep(6);
      close(sock);
      sock = socket(AF_INET, SOCK_STREAM, 0);
      if (sock < 0)
        die("Failed to create socket for retry");
    }
  }

  if (!connected)
    die("Failed to connect after all retries");

  printf("[DEBUG] Connected to server\n");

  uint32_t rkey;
  uint64_t raddr;
  uint32_t dqpn;

  exchange_info(sock, &ctx, &rkey, &raddr, &dqpn);
  setup_qp(&ctx, dqpn, true);
  handshake(sock);

  // Wait for server to post receives
  handshake(sock);

  // Mimic NCCL pattern: Interleave post_recv and post_send
  printf("\n[DEBUG] CLIENT: Starting NCCL pattern (recv + send interleaved)...\n");

  // First: post recv (zero-length) + post send (RDMA Write with IMM)
  struct ibv_recv_wr recv_wr1 = {.wr_id = 0};
  struct ibv_recv_wr *bad_recv_wr;
  if (ibv_post_recv(ctx.qp, &recv_wr1, &bad_recv_wr) != 0)
    die("ibv_post_recv #1 failed");
  printf("[DEBUG] CLIENT: Posted recv wr_id=0 (length=0)\n");

  // First RDMA Write with IMM (32 bytes, imm=32)
  memset(ctx.buffer, 'A', 32);
  struct ibv_sge sge1 = {
      .addr = (uint64_t)ctx.buffer,
      .length = 32,
      .lkey = ctx.mr->lkey};

  struct ibv_send_wr wr1 = {
      .wr_id = 0, // Match log pattern
      .sg_list = &sge1,
      .num_sge = 1,
      .opcode = IBV_WR_RDMA_WRITE_WITH_IMM,
      .send_flags = IBV_SEND_SIGNALED,
      .imm_data = htonl(32)};
  wr1.wr.rdma.remote_addr = raddr;
  wr1.wr.rdma.rkey = rkey;

  struct ibv_send_wr *bad_wr;
  printf("[DEBUG] CLIENT: Posting RDMA_WRITE_WITH_IMM #1 (32 bytes, imm=32, wr_id=0)\n");
  if (ibv_post_send(ctx.qp, &wr1, &bad_wr) != 0)
    die("ibv_post_send #1 failed");

  // Second: post recv (zero-length) + post send (RDMA Write with IMM, NO SIGNAL)
  struct ibv_recv_wr recv_wr2 = {.wr_id = 1};
  if (ibv_post_recv(ctx.qp, &recv_wr2, &bad_recv_wr) != 0)
    die("ibv_post_recv #2 failed");
  printf("[DEBUG] CLIENT: Posted recv wr_id=1 (length=0)\n");

  // Post recv again with same wr_id (mimic log pattern)
  struct ibv_recv_wr recv_wr3 = {.wr_id = 1};
  if (ibv_post_recv(ctx.qp, &recv_wr3, &bad_recv_wr) != 0)
    die("ibv_post_recv #3 failed");
  printf("[DEBUG] CLIENT: Posted recv wr_id=1 again (length=0)\n");

  // Second RDMA Write with IMM (32 bytes, imm=64, NO SIGNAL)
  memset(ctx.buffer + 32, 'B', 32);
  struct ibv_sge sge2 = {
      .addr = (uint64_t)(ctx.buffer + 32),
      .length = 32,
      .lkey = ctx.mr->lkey};

  struct ibv_send_wr wr2 = {
      .wr_id = 0, // Same wr_id as first send
      .sg_list = &sge2,
      .num_sge = 1,
      .opcode = IBV_WR_RDMA_WRITE_WITH_IMM,
      .send_flags = 0, // NO IBV_SEND_SIGNALED
      .imm_data = htonl(64)};
  wr2.wr.rdma.remote_addr = raddr + 64;
  wr2.wr.rdma.rkey = rkey;

  printf("[DEBUG] CLIENT: Posting RDMA_WRITE_WITH_IMM #2 (32 bytes, imm=64, NO SIGNAL, wr_id=0)\n");
  if (ibv_post_send(ctx.qp, &wr2, &bad_wr) != 0)
    die("ibv_post_send #2 failed");

  // Poll for send completions (only 1 expected, since 2nd send has no SIGNALED flag)
  printf("\n[DEBUG] CLIENT: Polling for send completions...\n");
  struct ibv_wc wc[8];
  int send_completions = 0;
  int poll_count = 0;

  while (send_completions < 1) // Only 1 send completion expected
  {
    int n = ibv_poll_cq(ctx.cq, 8, wc);
    if (n < 0)
      die("ibv_poll_cq failed");

    for (int i = 0; i < n; i++)
    {
      if (wc[i].status != IBV_WC_SUCCESS)
      {
        printf("[ERROR] WC failed: status=%d\n", wc[i].status);
        continue;
      }

      if (wc[i].opcode == IBV_WC_RDMA_WRITE)
      {
        printf("[DEBUG] CLIENT: Send completion #%d - wr_id=%lu\n",
               send_completions + 1, wc[i].wr_id);
        send_completions++;
      }
    }

    if (n > 0)
      poll_count = 0;
    else
    {
      usleep(1000);
      poll_count++;
      if (poll_count % 1000 == 0)
        printf("[DEBUG] CLIENT: Still polling sends (count=%d)...\n", poll_count);
    }
  }

  printf("[DEBUG] CLIENT: Send completion received (only 1, as 2nd send has no SIGNALED)\n");

  // Poll for recv completions (RecvRdmaWithImm)
  printf("\n[DEBUG] CLIENT: Polling for recv completions...\n");
  int recv_completions = 0;
  poll_count = 0;

  while (recv_completions < 2)
  {
    int n = ibv_poll_cq(ctx.cq, 8, wc);
    if (n < 0)
      die("ibv_poll_cq failed");

    for (int i = 0; i < n; i++)
    {
      if (wc[i].status != IBV_WC_SUCCESS)
      {
        printf("[ERROR] WC failed: status=%d\n", wc[i].status);
        continue;
      }

      if (wc[i].opcode == IBV_WC_RECV_RDMA_WITH_IMM)
      {
        printf("[DEBUG] CLIENT: Recv completion #%d - wr_id=%lu",
               recv_completions + 1, wc[i].wr_id);

        if (wc[i].wc_flags & IBV_WC_WITH_IMM)
        {
          printf(", imm_data=0x%x", ntohl(wc[i].imm_data));
        }
        printf("\n");

        recv_completions++;
      }
    }

    if (n > 0)
      poll_count = 0;
    else
    {
      usleep(1000);
      poll_count++;
      if (poll_count % 1000 == 0)
        printf("[DEBUG] CLIENT: Still polling recvs (count=%d)...\n", poll_count);
    }
  }

  printf("\n[DEBUG] CLIENT: All completions received (1 send + 2 recvs)\n");
  printf("[DEBUG] ========== CLIENT COMPLETED ==========\n");

  handshake(sock);
  close(sock);
}

int main(int argc, char *argv[])
{
  setvbuf(stdout, NULL, _IONBF, 0);

  printf("[DEBUG] ========== NCCL PATTERN TEST ==========\n");

  if (argc == 1)
  {
    printf("[DEBUG] Running as SERVER\n");
    run_server();
  }
  else if (argc == 2)
  {
    printf("[DEBUG] Running as CLIENT (server=%s)\n", argv[1]);
    run_client(argv[1]);
  }
  else
  {
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "  %s              # Run as server\n", argv[0]);
    fprintf(stderr, "  %s <server_ip>  # Run as client\n", argv[0]);
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
