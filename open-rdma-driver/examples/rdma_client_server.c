#include <assert.h>
#include <stddef.h>
#include <endian.h>
#include <infiniband/verbs.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <arpa/inet.h>
#include <sys/socket.h>

#define ANSI_COLOR_RED "\x1b[31m"
#define ANSI_COLOR_GREEN "\x1b[32m"
#define ANSI_COLOR_YELLOW "\x1b[33m"
#define ANSI_COLOR_BLUE "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN "\x1b[36m"
#define ANSI_COLOR_RESET "\x1b[0m"

#define COMPILER_BARRIER() asm volatile("" ::: "memory")

#define BUF_SIZE (256UL * 1024)
#define MSG_LEN (0x1000 - 1023)
#define TCP_PORT 12345
#define MAX_ROUNDS 5 // 最大测试轮数

const uint64_t SRC_BUFFER_OFFSET = 0;
const uint64_t DST_BUFFER_OFFSET = BUF_SIZE;

// QP exchange info structure
struct qp_info
{
  uint32_t qp_num;
  uint32_t rkey;
  uint64_t remote_addr;
};

void die(const char *reason);
void printZeroRanges(char *dst_buffer, int msg_len);
void printMemoryHex(void *start_addr, size_t length);
void wait_for_enter(const char *message);
size_t memory_diff(const char *buf1, const char *buf2, size_t length);
int run_server(int msg_len, int dev_index);
int run_client(int msg_len, char *server_ip, int dev_index);

void die(const char *reason)
{
  perror(reason);
  exit(EXIT_FAILURE);
}

void wait_for_enter(const char *message)
{
  printf("\n%s", message);
  printf("Press Enter to continue...");
  fflush(stdout);

  struct termios oldt, newt;
  tcgetattr(STDIN_FILENO, &oldt);
  newt = oldt;
  newt.c_lflag &= ~(ICANON | ECHO);
  tcsetattr(STDIN_FILENO, TCSANOW, &newt);

  int ch;
  while ((ch = getchar()) != '\n' && ch != EOF)
    ;

  tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
  printf("\n");
}

void sync_with_client(int sock_fd)
{
  char dummy = 0;

  // Receive ready signal from client
  if (recv(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy))
  {
    die("Failed to receive sync signal");
  }

  // Send ack back to client
  if (send(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy))
  {
    die("Failed to send sync ack");
  }
}

void sync_with_server(int sock_fd)
{
  char dummy = 0;

  // Send ready signal to server
  if (send(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy))
  {
    die("Failed to send sync signal");
  }

  // Wait for ack from server
  if (recv(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy))
  {
    die("Failed to receive sync ack");
  }
}

void print_hex_line(const char *buf, size_t offset, size_t length,
                    const char *diff_mask, const char *color)
{
  printf("0x%08lx: ", (unsigned long)offset);

  for (size_t i = 0; i < length; i++)
  {
    if (diff_mask && diff_mask[i])
    {
      printf("%s%02x%s ", color, (unsigned char)buf[i], ANSI_COLOR_RESET);
    }
    else
    {
      printf("%02x ", (unsigned char)buf[i]);
    }
  }

  for (size_t i = length; i < 16; i++)
  {
    printf("   ");
  }
}

void create_diff_mask(const char *buf1, const char *buf2, size_t offset, size_t length, char *diff_mask)
{
  for (size_t j = 0; j < length; j++)
  {
    if (buf1[offset + j] != buf2[offset + j])
    {
      diff_mask[j] = 1;
    }
    else
    {
      diff_mask[j] = 0;
    }
  }
}

size_t memory_diff(const char *buf1, const char *buf2, size_t length)
{
  int has_differences = 0;
  size_t bytes_per_line = 16;
  size_t total_diff_bytes = 0;

  for (size_t i = 0; i < length; i += bytes_per_line)
  {
    char diff_mask[16] = {0};
    int line_has_diff = 0;
    size_t line_length = (i + bytes_per_line <= length) ? bytes_per_line : length - i;

    for (size_t j = 0; j < line_length; j++)
    {
      if (buf1[i + j] != buf2[i + j])
      {
        diff_mask[j] = 1;
        line_has_diff = 1;
        has_differences = 1;
        total_diff_bytes++;
      }
    }

    if (line_has_diff)
    {
      if (i >= bytes_per_line)
      {
        char prev_diff_mask[16] = {0};
        size_t prev_line_length = bytes_per_line;
        create_diff_mask(buf1, buf2, i - bytes_per_line, prev_line_length, prev_diff_mask);

        printf("\n");
        print_hex_line(buf1 + i - bytes_per_line, i - bytes_per_line,
                       prev_line_length, prev_diff_mask, ANSI_COLOR_RED);
        printf("    ");
        print_hex_line(buf2 + i - bytes_per_line, i - bytes_per_line,
                       prev_line_length, prev_diff_mask, ANSI_COLOR_GREEN);
        printf("\n");
      }

      print_hex_line(buf1 + i, i, line_length, diff_mask, ANSI_COLOR_RED);
      printf("    ");
      print_hex_line(buf2 + i, i, line_length, diff_mask, ANSI_COLOR_GREEN);
      printf("\n");

      if (i + bytes_per_line < length)
      {
        char next_diff_mask[16] = {0};
        size_t next_line_length = (i + 2 * bytes_per_line <= length) ? bytes_per_line : length - (i + bytes_per_line);
        create_diff_mask(buf1, buf2, i + bytes_per_line, next_line_length, next_diff_mask);

        print_hex_line(buf1 + i + bytes_per_line, i + bytes_per_line,
                       next_line_length, next_diff_mask, ANSI_COLOR_RED);
        printf("    ");
        print_hex_line(buf2 + i + bytes_per_line, i + bytes_per_line,
                       next_line_length, next_diff_mask, ANSI_COLOR_GREEN);
        printf("\n");
      }

      printf("\n");
    }
  }

  if (!has_differences)
  {
    printf("No differences found between the two memory regions.\n");
  }
  return total_diff_bytes;
}

int run_server(int msg_len, int dev_index)
{
  struct ibv_device **dev_list;
  struct ibv_context *context;
  struct ibv_pd *pd;
  struct ibv_mr *mr;
  struct ibv_qp *qp;
  struct ibv_qp_init_attr qp_init_attr = {0};
  struct ibv_cq *send_cq;
  struct ibv_cq *recv_cq;
  char *buffer;
  volatile unsigned char *volatile dst_buffer;
  int num_devices;
  int sock_fd, client_fd;
  struct sockaddr_in server_addr;
  struct qp_info local_info, remote_info;

  printf("[Server] Starting RDMA server (device index: %d)...\n", dev_index);

  buffer = mmap(NULL, BUF_SIZE * 2, PROT_READ | PROT_WRITE,
                MAP_SHARED | MAP_ANONYMOUS | MAP_HUGETLB | MAP_POPULATE, -1, 0);
  if (buffer == MAP_FAILED)
  {
    die("Map failed");
  }

#ifdef COMPILE_FOR_RTL_SIMULATOR_TEST
  buffer = (char *)0x7f7e8e600000;
#endif

  dst_buffer = buffer + BUF_SIZE;
  printf("before ibv_get_device_list\n");
  dev_list = ibv_get_device_list(&num_devices);
  if (!dev_list)
  {
    die("Failed to get device list");
  }
  printf("Found %d RDMA devices\n", num_devices);
  if (num_devices == 0 || num_devices <= dev_index || !dev_list[dev_index])
  {
    fprintf(stderr, "Device index %d not available! Only %d devices found.\n",
            dev_index, num_devices);
    fprintf(stderr, "For simulation mode, ensure libbluerdma_rust.so is in LD_LIBRARY_PATH\n");
    exit(1);
  }
  printf("Opening device: %s\n", ibv_get_device_name(dev_list[dev_index]));
  printf("before ibv_open_device\n");
  context = ibv_open_device(dev_list[dev_index]);

  printf("before ibv_alloc_pd\n");
  pd = ibv_alloc_pd(context);

  printf("before ibv_create_cq\n");
  send_cq = ibv_create_cq(context, 512, NULL, NULL, 0);
  recv_cq = ibv_create_cq(context, 512, NULL, NULL, 0);

  if (!send_cq || !recv_cq)
  {
    die("Error creating CQ");
  }

  qp_init_attr.qp_type = IBV_QPT_RC;
  qp_init_attr.cap.max_send_wr = 100;
  qp_init_attr.cap.max_recv_wr = 100;
  qp_init_attr.cap.max_send_sge = 100;
  qp_init_attr.cap.max_recv_sge = 100;
  qp_init_attr.send_cq = send_cq;
  qp_init_attr.recv_cq = recv_cq;

  printf("before ibv_create_qp\n");
  qp = ibv_create_qp(pd, &qp_init_attr);

  memset((void *)dst_buffer, 0, msg_len);

  printf("before ibv_reg_mr\n");
  fflush(stdout);

  mr = ibv_reg_mr(pd, buffer, BUF_SIZE * 2,
                  IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE |
                      IBV_ACCESS_REMOTE_READ);

  // Setup TCP server
  printf("[Server] Setting up TCP server on port %d...\n", TCP_PORT);
  sock_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (sock_fd < 0)
  {
    die("Failed to create socket");
  }

  int opt = 1;
  if (setsockopt(sock_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT,
                 &opt, sizeof(opt)) < 0)
  {
    die("setsockopt failed");
  }

  memset(&server_addr, 0, sizeof(server_addr));
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = INADDR_ANY;
  server_addr.sin_port = htons(TCP_PORT);

  if (bind(sock_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0)
  {
    die("Failed to bind socket");
  }

  if (listen(sock_fd, 1) < 0)
  {
    die("Failed to listen");
  }

  printf(ANSI_COLOR_GREEN "[Server] Waiting for client connection...\n" ANSI_COLOR_RESET);
  client_fd = accept(sock_fd, NULL, NULL);
  if (client_fd < 0)
  {
    die("Failed to accept connection");
  }
  printf(ANSI_COLOR_GREEN "[Server] Client connected!\n" ANSI_COLOR_RESET);

  // Exchange QP information
  local_info.qp_num = qp->qp_num;
  local_info.rkey = mr->rkey;
  local_info.remote_addr = (uint64_t)dst_buffer;

  printf("[Server] Sending QP info (QPN=%u, rkey=%u, addr=0x%lx)...\n",
         local_info.qp_num, local_info.rkey, local_info.remote_addr);

  if (send(client_fd, &local_info, sizeof(local_info), 0) != sizeof(local_info))
  {
    die("Failed to send QP info");
  }

  if (recv(client_fd, &remote_info, sizeof(remote_info), 0) != sizeof(remote_info))
  {
    die("Failed to receive QP info");
  }

  printf("[Server] Received client QP info (QPN=%u)...\n", remote_info.qp_num);

  struct ibv_qp_attr qp_attr = {.qp_state = IBV_QPS_INIT,
                                .pkey_index = 0,
                                .port_num = 1,
                                .qp_access_flags = IBV_ACCESS_LOCAL_WRITE |
                                                   IBV_ACCESS_REMOTE_READ |
                                                   IBV_ACCESS_REMOTE_WRITE};

  printf("before ibv_modify_qp -- init qp\n");
  if (ibv_modify_qp(qp, &qp_attr,
                    IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT |
                        IBV_QP_ACCESS_FLAGS))
  {
    die("Failed to modify QP to INIT");
  }

  qp_attr.qp_state = IBV_QPS_RTS;
  qp_attr.path_mtu = IBV_MTU_4096;
  qp_attr.dest_qp_num = remote_info.qp_num;
  qp_attr.rq_psn = 0;
  qp_attr.ah_attr.port_num = 1;
  uint32_t ipv4_addr = 0x1122330A;
  qp_attr.ah_attr.grh.dgid.raw[10] = 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[11] = 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[12] = (ipv4_addr >> 24) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[13] = (ipv4_addr >> 16) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[14] = (ipv4_addr >> 8) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[15] = ipv4_addr & 0xFF;

  printf("before ibv_modify_qp -- qp to rtr\n");
  if (ibv_modify_qp(qp, &qp_attr,
                    IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU |
                        IBV_QP_DEST_QPN | IBV_QP_RQ_PSN |
                        IBV_QP_MAX_DEST_RD_ATOMIC | IBV_QP_MIN_RNR_TIMER))
  {
    fprintf(stderr, "Failed to modify QP to RTR\n");
    return 1;
  }

  printf("[Server] QP is ready! Waiting for RDMA WRITE operations...\n");

  // Main loop - passively receive RDMA writes
  int round = 0;
  char expected_pattern[msg_len];

  // Generate expected pattern (same as client will send)
  for (int i = 0; i < msg_len; i++)
  {
    expected_pattern[i] = i & 0xFF;
  }

  while (round < MAX_ROUNDS)
  {
    round++;

    printf("[Server] Round %d: waiting for client to complete RDMA WRITE...\n", round);

    // Wait for client to complete RDMA WRITE and send sync signal
    sync_with_client(client_fd);

    COMPILER_BARRIER();

    // Check received data
    int cnt_error = memory_diff(expected_pattern, (const char *)dst_buffer, msg_len);
    int cnt_valid = msg_len - cnt_error;

    printf("[Server] Round %d: received %d/%d bytes correctly",
           round, cnt_valid, msg_len);

    if (cnt_error > 0)
    {
      printf(ANSI_COLOR_RED " (%d errors)" ANSI_COLOR_RESET "\n", cnt_error);
    }
    else
    {
      printf(ANSI_COLOR_GREEN " (perfect!)" ANSI_COLOR_RESET "\n");
    }

    COMPILER_BARRIER();

    // Clear buffer for next round
    memset((void *)dst_buffer, 0, msg_len);

    COMPILER_BARRIER();
  }

  printf(ANSI_COLOR_GREEN "\n[Server] Test completed! Total rounds: %d\n" ANSI_COLOR_RESET, round);

  // Cleanup (unreachable in infinite loop)
  close(client_fd);
  close(sock_fd);
  ibv_destroy_qp(qp);
  ibv_dereg_mr(mr);
  ibv_dealloc_pd(pd);
  ibv_close_device(context);
  ibv_free_device_list(dev_list);

  return 0;
}

int run_client(int msg_len, char *server_ip, int dev_index)
{
  struct ibv_device **dev_list;
  struct ibv_context *context;
  struct ibv_pd *pd;
  struct ibv_mr *mr;
  struct ibv_qp *qp;
  struct ibv_qp_init_attr qp_init_attr = {0};
  struct ibv_cq *send_cq;
  struct ibv_cq *recv_cq;
  char *buffer;
  volatile unsigned char *volatile src_buffer;
  int num_devices;
  int sock_fd;
  struct sockaddr_in server_addr;
  struct qp_info local_info, remote_info;

  printf("[Client] Starting RDMA client (device index: %d)...\n", dev_index);

  // Allocate memory buffer
  buffer = mmap(NULL, BUF_SIZE * 2, PROT_READ | PROT_WRITE,
                MAP_SHARED | MAP_ANONYMOUS | MAP_HUGETLB | MAP_POPULATE, -1, 0);
  if (buffer == MAP_FAILED)
  {
    die("Map failed");
  }

#ifdef COMPILE_FOR_RTL_SIMULATOR_TEST
  buffer = (char *)0x7f7e8e600000;
#endif

  src_buffer = buffer;
  printf("before ibv_get_device_list\n");
  dev_list = ibv_get_device_list(&num_devices);
  if (!dev_list)
  {
    die("Failed to get device list");
  }
  printf("Found %d RDMA devices\n", num_devices);
  if (num_devices == 0 || num_devices <= dev_index || !dev_list[dev_index])
  {
    fprintf(stderr, "Device index %d not available! Only %d devices found.\n",
            dev_index, num_devices);
    fprintf(stderr, "For simulation mode, ensure libbluerdma_rust.so is in LD_LIBRARY_PATH\n");
    exit(1);
  }
  printf("Opening device: %s\n", ibv_get_device_name(dev_list[dev_index]));
  printf("before ibv_open_device\n");
  context = ibv_open_device(dev_list[dev_index]);

  printf("before ibv_alloc_pd\n");
  pd = ibv_alloc_pd(context);

  printf("before ibv_create_cq\n");
  send_cq = ibv_create_cq(context, 512, NULL, NULL, 0);
  recv_cq = ibv_create_cq(context, 512, NULL, NULL, 0);

  if (!send_cq || !recv_cq)
  {
    die("Error creating CQ");
  }

  qp_init_attr.qp_type = IBV_QPT_RC;
  qp_init_attr.cap.max_send_wr = 100;
  qp_init_attr.cap.max_recv_wr = 100;
  qp_init_attr.cap.max_send_sge = 100;
  qp_init_attr.cap.max_recv_sge = 100;
  qp_init_attr.send_cq = send_cq;
  qp_init_attr.recv_cq = recv_cq;

  printf("before ibv_create_qp\n");
  qp = ibv_create_qp(pd, &qp_init_attr);

  // Generate data pattern (same as server expects)
  for (int i = 0; i < msg_len; i++)
  {
    src_buffer[i] = i & 0xFF;
  }

  printf("before ibv_reg_mr\n");
  fflush(stdout);

  mr = ibv_reg_mr(pd, buffer, BUF_SIZE * 2,
                  IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE |
                      IBV_ACCESS_REMOTE_READ);

  // Connect to server
  printf("[Client] Connecting to server %s:%d...\n", server_ip, TCP_PORT);
  sock_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (sock_fd < 0)
  {
    die("Failed to create socket");
  }

  memset(&server_addr, 0, sizeof(server_addr));
  server_addr.sin_family = AF_INET;
  server_addr.sin_port = htons(TCP_PORT);

  if (inet_pton(AF_INET, server_ip, &server_addr.sin_addr) <= 0)
  {
    die("Invalid server address");
  }

  // Retry connection logic
  int retry_count = 0;
  const int max_retries = 10;

  while (connect(sock_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0)
  {
    retry_count++;
    if (retry_count >= max_retries)
    {
      die("Failed to connect to server after 10 attempts");
    }
    printf("[Client] Connection failed, retrying in 1 second... (%d/%d)\n", retry_count, max_retries);
    sleep(1);
  }

  printf(ANSI_COLOR_GREEN "[Client] Connected to server!\n" ANSI_COLOR_RESET);

  // Exchange QP information
  local_info.qp_num = qp->qp_num;
  local_info.rkey = mr->rkey;
  local_info.remote_addr = (uint64_t)src_buffer;

  if (recv(sock_fd, &remote_info, sizeof(remote_info), 0) != sizeof(remote_info))
  {
    die("Failed to receive QP info");
  }

  printf("[Client] Received server QP info (QPN=%u, rkey=%u, addr=0x%lx)...\n",
         remote_info.qp_num, remote_info.rkey, remote_info.remote_addr);

  if (send(sock_fd, &local_info, sizeof(local_info), 0) != sizeof(local_info))
  {
    die("Failed to send QP info");
  }

  struct ibv_qp_attr qp_attr = {.qp_state = IBV_QPS_INIT,
                                .pkey_index = 0,
                                .port_num = 1,
                                .qp_access_flags = IBV_ACCESS_LOCAL_WRITE |
                                                   IBV_ACCESS_REMOTE_READ |
                                                   IBV_ACCESS_REMOTE_WRITE};

  printf("before ibv_modify_qp -- init qp\n");
  if (ibv_modify_qp(qp, &qp_attr,
                    IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT |
                        IBV_QP_ACCESS_FLAGS))
  {
    die("Failed to modify QP to INIT");
  }

  qp_attr.qp_state = IBV_QPS_RTS;
  qp_attr.path_mtu = IBV_MTU_4096;
  qp_attr.dest_qp_num = remote_info.qp_num;
  qp_attr.rq_psn = 0;
  qp_attr.ah_attr.port_num = 1;
  uint32_t ipv4_addr = 0x1122330A;
  qp_attr.ah_attr.grh.dgid.raw[10] = 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[11] = 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[12] = (ipv4_addr >> 24) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[13] = (ipv4_addr >> 16) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[14] = (ipv4_addr >> 8) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[15] = ipv4_addr & 0xFF;

  printf("before ibv_modify_qp -- qp to rtr\n");
  if (ibv_modify_qp(qp, &qp_attr,
                    IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU |
                        IBV_QP_DEST_QPN | IBV_QP_RQ_PSN |
                        IBV_QP_MAX_DEST_RD_ATOMIC | IBV_QP_MIN_RNR_TIMER))
  {
    fprintf(stderr, "Failed to modify QP to RTR\n");
    return 1;
  }

  printf("[Client] QP is ready! Starting RDMA WRITE loop...\n");

  // Prepare RDMA WRITE operation
  struct ibv_sge sge = {
      .addr = (uint64_t)src_buffer,
      .length = msg_len,
      .lkey = mr->lkey};

  struct ibv_send_wr wr = {
      .sg_list = &sge,
      .num_sge = 1,
      .opcode = IBV_WR_RDMA_WRITE,
      .send_flags = IBV_SEND_SIGNALED,
      .wr_id = 17,
      .wr.rdma.remote_addr = remote_info.remote_addr,
      .wr.rdma.rkey = remote_info.rkey};

  struct ibv_send_wr *bad_wr;

  // Main loop - send RDMA writes
  int round = 0;
  while (round < MAX_ROUNDS)
  {
    round++;
    COMPILER_BARRIER();

    printf("[Client] Round %d: posting RDMA WRITE (%d bytes)...\n", round, msg_len);

    if (ibv_post_send(qp, &wr, &bad_wr))
    {
      die("Failed to post send");
    }

    struct ibv_wc wc = {0};

    // Wait for completion
    while (ibv_poll_cq(send_cq, 1, &wc) == 0)
    {
      usleep(1000);
      COMPILER_BARRIER();
    }

    COMPILER_BARRIER();

    if (wc.status != IBV_WC_SUCCESS)
    {
      fprintf(stderr, ANSI_COLOR_RED "[Client] Work completion failed! Status: %d (%s)\n" ANSI_COLOR_RESET,
              wc.status, ibv_wc_status_str(wc.status));
    }
    else
    {
      printf(ANSI_COLOR_GREEN "[Client] RDMA WRITE completed successfully! (wr_id=%lu)\n" ANSI_COLOR_RESET,
             wc.wr_id);
    }

    // Sync with server - notify that RDMA WRITE is complete
    printf("[Client] Notifying server to check data...\n");
    sync_with_server(sock_fd);
    printf("[Client] Server acknowledged data check\n");

    // Regenerate data pattern for next round
    for (int i = 0; i < msg_len; i++)
    {
      src_buffer[i] = i & 0xFF;
    }
  }

  printf(ANSI_COLOR_GREEN "\n[Client] Test completed! Total rounds: %d\n" ANSI_COLOR_RESET, round);

  // Cleanup (unreachable in infinite loop)
  close(sock_fd);
  ibv_destroy_qp(qp);
  ibv_dereg_mr(mr);
  ibv_dealloc_pd(pd);
  ibv_close_device(context);
  ibv_free_device_list(dev_list);

  return 0;
}

int main(int argc, char *argv[])
{
  if (argc < 3)
  {
    printf("Usage:\n");
    printf("  Server: %s <msg_len> server [dev_index]\n", argv[0]);
    printf("  Client: %s <msg_len> client <server_ip> [dev_index]\n", argv[0]);
    printf("\nExample:\n");
    printf("  Server: %s 8192 server 1\n", argv[0]);
    printf("  Client: %s 8192 client 127.0.0.1 0\n", argv[0]);
    return 1;
  }

  int msg_len = atoi(argv[1]);
  char *mode = argv[2];

  if (strcmp(mode, "server") == 0)
  {
    int dev_index = (argc >= 4) ? atoi(argv[3]) : 1; // Default: dev[1]
    run_server(msg_len, dev_index);
  }
  else if (strcmp(mode, "client") == 0)
  {
    if (argc < 4)
    {
      fprintf(stderr, "Error: Client mode requires server IP address\n");
      return 1;
    }
    char *server_ip = argv[3];
    int dev_index = (argc >= 5) ? atoi(argv[4]) : 0; // Default: dev[0]
    run_client(msg_len, server_ip, dev_index);
  }
  else
  {
    fprintf(stderr, "Error: Invalid mode '%s'. Use 'server' or 'client'\n", mode);
    return 1;
  }

  return 0;
}
