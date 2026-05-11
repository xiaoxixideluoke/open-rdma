#ifndef RDMA_TRANSPORT_H
#define RDMA_TRANSPORT_H

#include "rdma_common.h"
#include <stdint.h>

#define DEFAULT_TCP_PORT 12345

// QP information exchange structure
struct qp_info {
    uint32_t qp_num;
    uint32_t rkey;
    uint64_t remote_addr;
};

// TCP transport context
struct tcp_transport {
    int sock_fd;
    int client_fd;  // Only used by server
    int port;
    bool is_server;
};

// Initialize TCP transport (server side)
int tcp_server_init(struct tcp_transport *transport, int port);

// Wait for client connection (server side)
int tcp_server_accept(struct tcp_transport *transport);

// Connect to server (client side)
int tcp_client_connect(struct tcp_transport *transport, const char *server_ip, int port, int max_retries);

// Close transport
void tcp_transport_close(struct tcp_transport *transport);

// Exchange QP information
int rdma_exchange_qp_info(int sock_fd, const struct qp_info *local_info, struct qp_info *remote_info);

// Synchronization primitives
int rdma_handshake(int sock_fd);
int rdma_sync_client_to_server(int sock_fd);  // Client notifies server
int rdma_sync_server_to_client(int sock_fd);  // Server waits for client

#endif // RDMA_TRANSPORT_H
