#include "rdma_transport.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <errno.h>

int tcp_server_init(struct tcp_transport *transport, int port) {
    if (!transport) return -1;

    memset(transport, 0, sizeof(*transport));
    transport->is_server = true;
    transport->port = port;

    rdma_log("[TCP] Creating server socket (port=%d)\n", port);

    transport->sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (transport->sock_fd < 0) {
        fprintf(stderr, "[ERROR] Failed to create socket: %s\n", strerror(errno));
        return -1;
    }

    // Set socket options
    int opt = 1;
    if (setsockopt(transport->sock_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT,
                   &opt, sizeof(opt)) < 0) {
        fprintf(stderr, "[ERROR] setsockopt failed: %s\n", strerror(errno));
        close(transport->sock_fd);
        return -1;
    }

    // Bind
    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_addr.s_addr = INADDR_ANY,
        .sin_port = htons(port)
    };

    if (bind(transport->sock_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "[ERROR] Failed to bind socket: %s\n", strerror(errno));
        close(transport->sock_fd);
        return -1;
    }

    // Listen
    if (listen(transport->sock_fd, 1) < 0) {
        fprintf(stderr, "[ERROR] Failed to listen: %s\n", strerror(errno));
        close(transport->sock_fd);
        return -1;
    }

    rdma_log("[TCP] Server listening on port %d\n", port);
    return 0;
}

int tcp_server_accept(struct tcp_transport *transport) {
    if (!transport || !transport->is_server) return -1;

    rdma_log("[TCP] Waiting for client connection...\n");

    transport->client_fd = accept(transport->sock_fd, NULL, NULL);
    if (transport->client_fd < 0) {
        fprintf(stderr, "[ERROR] Failed to accept connection: %s\n", strerror(errno));
        return -1;
    }

    rdma_log("[TCP] Client connected (fd=%d)\n", transport->client_fd);
    return 0;
}

int tcp_client_connect(struct tcp_transport *transport, const char *server_ip, int port, int max_retries) {
    if (!transport || !server_ip) return -1;

    memset(transport, 0, sizeof(*transport));
    transport->is_server = false;
    transport->port = port;

    rdma_log("[TCP] Connecting to %s:%d (max_retries=%d)\n", server_ip, port, max_retries);

    struct sockaddr_in addr = {
        .sin_family = AF_INET,
        .sin_port = htons(port)
    };

    if (inet_pton(AF_INET, server_ip, &addr.sin_addr) <= 0) {
        fprintf(stderr, "[ERROR] Invalid server address: %s\n", server_ip);
        return -1;
    }

    for (int retry = 0; retry < max_retries; retry++) {
        transport->sock_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (transport->sock_fd < 0) {
            fprintf(stderr, "[ERROR] Failed to create socket: %s\n", strerror(errno));
            return -1;
        }

        if (connect(transport->sock_fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
            rdma_log("[TCP] Connected to %s:%d\n", server_ip, port);
            return 0;
        }

        rdma_log("[TCP] Connection attempt %d/%d failed, retrying...\n", retry + 1, max_retries);
        close(transport->sock_fd);
        transport->sock_fd = -1;

        if (retry < max_retries - 1) {
            sleep(1);
        }
    }

    fprintf(stderr, "[ERROR] Failed to connect after %d attempts\n", max_retries);
    return -1;
}

void tcp_transport_close(struct tcp_transport *transport) {
    if (!transport) return;

    if (transport->client_fd > 0) {
        close(transport->client_fd);
        transport->client_fd = -1;
    }

    if (transport->sock_fd > 0) {
        close(transport->sock_fd);
        transport->sock_fd = -1;
    }
}

int rdma_exchange_qp_info(int sock_fd, const struct qp_info *local_info, struct qp_info *remote_info) {
    if (sock_fd < 0 || !local_info || !remote_info) return -1;

    rdma_log("[RDMA] Exchanging QP info (local: qp_num=%u, rkey=0x%x, addr=0x%lx)\n",
             local_info->qp_num, local_info->rkey, local_info->remote_addr);

    // Send local info
    if (send(sock_fd, local_info, sizeof(*local_info), 0) != sizeof(*local_info)) {
        fprintf(stderr, "[ERROR] Failed to send QP info: %s\n", strerror(errno));
        return -1;
    }

    // Receive remote info
    if (recv(sock_fd, remote_info, sizeof(*remote_info), 0) != sizeof(*remote_info)) {
        fprintf(stderr, "[ERROR] Failed to receive QP info: %s\n", strerror(errno));
        return -1;
    }

    rdma_log("[RDMA] Received remote QP info (qp_num=%u, rkey=0x%x, addr=0x%lx)\n",
             remote_info->qp_num, remote_info->rkey, remote_info->remote_addr);

    return 0;
}

int rdma_handshake(int sock_fd) {
    if (sock_fd < 0) return -1;

    char dummy = 0;

    // Send handshake byte
    if (send(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy)) {
        fprintf(stderr, "[ERROR] Failed to send handshake: %s\n", strerror(errno));
        return -1;
    }

    // Receive handshake response
    if (recv(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy)) {
        fprintf(stderr, "[ERROR] Failed to receive handshake: %s\n", strerror(errno));
        return -1;
    }

    return 0;
}

int rdma_sync_client_to_server(int sock_fd) {
    if (sock_fd < 0) return -1;

    char dummy = 0;

    // Client sends ready signal
    if (send(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy)) {
        fprintf(stderr, "[ERROR] Failed to send sync signal: %s\n", strerror(errno));
        return -1;
    }

    // Client waits for ack
    if (recv(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy)) {
        fprintf(stderr, "[ERROR] Failed to receive sync ack: %s\n", strerror(errno));
        return -1;
    }

    return 0;
}

int rdma_sync_server_to_client(int sock_fd) {
    if (sock_fd < 0) return -1;

    char dummy = 0;

    // Server waits for ready signal
    if (recv(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy)) {
        fprintf(stderr, "[ERROR] Failed to receive sync signal: %s\n", strerror(errno));
        return -1;
    }

    // Server sends ack
    if (send(sock_fd, &dummy, sizeof(dummy), 0) != sizeof(dummy)) {
        fprintf(stderr, "[ERROR] Failed to send sync ack: %s\n", strerror(errno));
        return -1;
    }

    return 0;
}
