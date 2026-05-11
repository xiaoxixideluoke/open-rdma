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

#define ANSI_COLOR_RED "\x1b[31m"
#define ANSI_COLOR_GREEN "\x1b[32m"
#define ANSI_COLOR_YELLOW "\x1b[33m"
#define ANSI_COLOR_BLUE "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN "\x1b[36m"
#define ANSI_COLOR_RESET "\x1b[0m"

#define COMPILER_BARRIER() asm volatile("" ::: "memory")

#define BUF_SIZE (128UL * 1024)

const uint64_t SRC_BUFFER_OFFSET = 0;
const uint64_t DST_BUFFER_OFFSET = BUF_SIZE;

void die(const char *reason);
void printZeroRanges(char *dst_buffer, int msg_len);
void printMemoryHex(void *start_addr, size_t length);
void wait_for_enter(const char *message);
size_t memory_diff(const char *buf1, const char *buf2, size_t length);

// TODO 目前该文件没有 IBV_QPS_RTR 状态下的代码，需要补充完整，没有严格遵守 RESET -> INIT -> RTR -> RTS

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

int run_single_mr(int msg_len)
{
  struct ibv_device **dev_list;
  struct ibv_context *context;
  struct ibv_pd *pd;
  struct ibv_mr *mr;
  struct ibv_qp *qp0;
  struct ibv_qp *qp1;
  struct ibv_qp_init_attr qp_init_attr = {0};
  struct ibv_cq *send_cq;
  struct ibv_cq *recv_cq;
  char *buffer;
  volatile unsigned char *volatile src_buffer;
  volatile unsigned char *volatile dst_buffer;
  int num_devices;

  // wait_for_enter(NULL);

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
  dst_buffer = buffer + BUF_SIZE;
  printf("before ibv_get_device_list\n");
  dev_list = ibv_get_device_list(&num_devices);
  if (!dev_list)
  {
    die("Failed to get device list");
  }
  printf("Found %d RDMA devices\n", num_devices);
  if (num_devices == 0 || !dev_list[0])
  {
    fprintf(stderr, "No RDMA devices found!\n");
    fprintf(stderr, "For simulation mode, ensure libbluerdma_rust.so is in LD_LIBRARY_PATH\n");
    exit(1);
  }
  printf("Opening device: %s\n", ibv_get_device_name(dev_list[0]));
  printf("before ibv_open_device\n");
  context = ibv_open_device(dev_list[0]);

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
  qp0 = ibv_create_qp(pd, &qp_init_attr);
  qp1 = ibv_create_qp(pd, &qp_init_attr);
  struct ibv_qp_attr qp_attr = {.qp_state = IBV_QPS_INIT,
                                .pkey_index = 0,
                                .port_num = 1,
                                .qp_access_flags = IBV_ACCESS_LOCAL_WRITE |
                                                   IBV_ACCESS_REMOTE_READ |
                                                   IBV_ACCESS_REMOTE_WRITE};

  printf("before ibv_modify_qp -- init qp 0\n");
  if (ibv_modify_qp(qp0, &qp_attr,
                    IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT |
                        IBV_QP_ACCESS_FLAGS))
  {
    die("Failed to modify QP0 to INIT");
  }

  printf("before ibv_open_device -- init qp 1\n");
  if (ibv_modify_qp(qp1, &qp_attr,
                    IBV_QP_STATE | IBV_QP_PKEY_INDEX | IBV_QP_PORT |
                        IBV_QP_ACCESS_FLAGS))
  {
    die("Failed to modify QP1 to INIT");
  }

  qp_attr.qp_state = IBV_QPS_RTS;
  qp_attr.path_mtu = IBV_MTU_4096;
  qp_attr.dest_qp_num = qp1->qp_num;
  qp_attr.rq_psn = 0;
  qp_attr.ah_attr.port_num = 1;
  uint32_t ipv4_addr = 0x1122330A;
  qp_attr.ah_attr.grh.dgid.raw[10] = 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[11] = 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[12] = (ipv4_addr >> 24) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[13] = (ipv4_addr >> 16) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[14] = (ipv4_addr >> 8) & 0xFF;
  qp_attr.ah_attr.grh.dgid.raw[15] = ipv4_addr & 0xFF;

  printf("before ibv_modify_qp -- qp0 to rtr\n");
  if (ibv_modify_qp(qp0, &qp_attr,
                    IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU |
                        IBV_QP_DEST_QPN | IBV_QP_RQ_PSN |
                        IBV_QP_MAX_DEST_RD_ATOMIC | IBV_QP_MIN_RNR_TIMER))
  {
    fprintf(stderr, "Failed to modify QP0 to RTR\n");
    return 1;
  }
  qp_attr.dest_qp_num = qp0->qp_num;
  if (ibv_modify_qp(qp1, &qp_attr,
                    IBV_QP_STATE | IBV_QP_AV | IBV_QP_PATH_MTU |
                        IBV_QP_DEST_QPN | IBV_QP_RQ_PSN |
                        IBV_QP_MAX_DEST_RD_ATOMIC | IBV_QP_MIN_RNR_TIMER))
  {
    fprintf(stderr, "Failed to modify QP1 to RTR\n");
    return 1;
  }

  for (int start_byte_idx = 0; start_byte_idx < msg_len; start_byte_idx += 4)
  {
    for (int byte_in_dword_pos = 0; (start_byte_idx + byte_in_dword_pos < msg_len) && start_byte_idx < 4; byte_in_dword_pos++)
    {
      int pos = start_byte_idx + byte_in_dword_pos;
      src_buffer[pos] = (pos >> (8 * byte_in_dword_pos)) & 0xFF;
      // if (src_buffer[pos] == 0) src_buffer[pos] = 1;
    }
  }
  memset(dst_buffer, 0, msg_len);

  printf("before ibv_reg_mr\n");
  fflush(stdout);

  mr = ibv_reg_mr(pd, buffer, BUF_SIZE * 2,
                  IBV_ACCESS_LOCAL_WRITE | IBV_ACCESS_REMOTE_WRITE |
                      IBV_ACCESS_REMOTE_READ);
  struct ibv_sge sge = {
      .addr = (uint64_t)src_buffer, .length = msg_len, .lkey = mr->lkey};
  struct ibv_send_wr wr = {.sg_list = &sge,
                           .num_sge = 1,
                           .opcode = IBV_WR_RDMA_WRITE,
                           .send_flags = IBV_SEND_SIGNALED,
                           .wr_id = 17,
                           .wr.rdma.remote_addr = (uint64_t)dst_buffer,
                           .wr.rdma.rkey = mr->lkey};
  struct ibv_send_wr *bad_wr;

  // wait_for_enter("before real send");

  int cnt_valid = 0;
  int cnt_error = 0;
  char tmp_fill_cahr = 0;
  int round = 0;
  while (1)
  {
    tmp_fill_cahr++;
    round++;
    COMPILER_BARRIER();
    printf("before ibv_post_send\n");
    ibv_post_send(qp0, &wr, &bad_wr);
    printf("after ibv_post_send\n");
    struct ibv_wc wc = {0};

    COMPILER_BARRIER();

    while (ibv_poll_cq(send_cq, 1, &wc) == 0)
    {
      usleep(1000);
      COMPILER_BARRIER();
    }
    // usleep(1000);
    COMPILER_BARRIER();

    // for (int i = 0; i < msg_len; i++) {
    //     if (dst_buffer[i] == src_buffer[i]) {
    //       cnt_valid += 1;
    //     }
    // }
    printf("round: %d,", round);
    cnt_error = memory_diff(src_buffer, dst_buffer, msg_len);
    cnt_valid = msg_len - cnt_error;

    COMPILER_BARRIER();

    memset(dst_buffer, tmp_fill_cahr, msg_len);

    COMPILER_BARRIER();
    printf("wc wr_id: %lu\n", wc.wr_id);
    printf("received bytes count: %d\n", cnt_valid);

    if (cnt_valid != msg_len)
    {
      // die("Failed to read the entire message");
    }
  }

  ibv_destroy_qp(qp0);
  ibv_dereg_mr(mr);
  ibv_dealloc_pd(pd);
  ibv_close_device(context);
  ibv_free_device_list(dev_list);

  return 0;
}

void printZeroRanges(char *dst_buffer, int msg_len)
{
  int start = -1;

  for (int i = 0; i < msg_len; i++)
  {
    if (dst_buffer[i] == 0)
    {
      if (start == -1)
        start = i;
    }
    else
    {
      if (start != -1)
      {
        int length = i - start;
        printf("Zero range: %d-%d (length: %d)\n", start / 4096, i / 4096,
               length);
        start = -1;
      }
    }
  }

  if (start != -1)
  {
    int length = msg_len - start;
    printf("Zero range: %d-%d (length: %d)\n", start / 4096, msg_len / 4096,
           length);
  }
}

void printMemoryHex(void *start_addr, size_t length)
{
  if (start_addr == NULL || length == 0)
  {
    printf("Invalid parameters: start_addr=%p, length=%zu\n", start_addr, length);
    return;
  }

  unsigned char *addr = (unsigned char *)start_addr;
  const size_t bytes_per_line = 16;

  // Calculate extended range: 2 lines before and 2 lines after
  size_t extended_start_offset = (bytes_per_line * 2) > (size_t)addr ? 0 : (size_t)addr - (bytes_per_line * 2);
  unsigned char *extended_start = (unsigned char *)extended_start_offset;
  size_t extended_end_offset = (size_t)addr + length + (bytes_per_line * 2);
  unsigned char *extended_end = (unsigned char *)extended_end_offset;

  // Align to 16-byte boundary for clean output
  extended_start = (unsigned char *)((size_t)extended_start & ~(bytes_per_line - 1));

  printf("Memory dump from %p to %p (requested range: %p to %p)\n",
         extended_start, extended_end, addr, addr + length);
  printf("Legend: " ANSI_COLOR_GREEN "requested range" ANSI_COLOR_RESET ", " ANSI_COLOR_YELLOW "extended context" ANSI_COLOR_RESET "\n\n");

  for (unsigned char *current = extended_start; current < extended_end; current += bytes_per_line)
  {
    // Print address
    printf("%016lx: ", (unsigned long)current);

    // Print hex values
    for (size_t i = 0; i < bytes_per_line; i++)
    {
      unsigned char *byte_addr = current + i;

      if (byte_addr >= extended_end)
      {
        printf("   ");
        continue;
      }

      // Determine if this byte is in the requested range
      if (byte_addr >= addr && byte_addr < addr + length)
      {
        printf(ANSI_COLOR_GREEN "%02x" ANSI_COLOR_RESET " ", *byte_addr);
      }
      else
      {
        printf(ANSI_COLOR_YELLOW "%02x" ANSI_COLOR_RESET " ", *byte_addr);
      }
    }

    printf(" ");

    // Print ASCII representation
    for (size_t i = 0; i < bytes_per_line; i++)
    {
      unsigned char *byte_addr = current + i;

      if (byte_addr >= extended_end)
      {
        printf(" ");
        continue;
      }

      unsigned char c = *byte_addr;

      // Determine if this byte is in the requested range
      if (byte_addr >= addr && byte_addr < addr + length)
      {
        if (c >= 32 && c <= 126)
        {
          printf(ANSI_COLOR_GREEN "%c" ANSI_COLOR_RESET, c);
        }
        else
        {
          printf(ANSI_COLOR_GREEN "." ANSI_COLOR_RESET);
        }
      }
      else
      {
        if (c >= 32 && c <= 126)
        {
          printf(ANSI_COLOR_YELLOW "%c" ANSI_COLOR_RESET, c);
        }
        else
        {
          printf(ANSI_COLOR_YELLOW "." ANSI_COLOR_RESET);
        }
      }
    }

    printf("\n");
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

int main(int argc, char *argv[])
{
  if (argc < 2)
  {
    printf("Usage: %s <msg_len>\n", argv[0]);
    return 1;
  }
  int msg_len = atoi(argv[1]);
  run_single_mr(msg_len);
}
