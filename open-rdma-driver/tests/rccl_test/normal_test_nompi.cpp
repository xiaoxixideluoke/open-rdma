/**
 * Normal RCCL Test without MPI for Blue RDMA Driver
 *
 * This test uses separate processes (not MPI) with socket-based coordination.
 * Each process can use different RDMA devices via environment variables.
 *
 * Usage:
 *   Terminal 1: ./normal_test_nompi 0    # Server (rank 0)
 *   Terminal 2: ./normal_test_nompi 1    # Client (rank 1)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <hip/hip_runtime.h>
#include <hip/hip_runtime_api.h>
#include <rccl/rccl.h>

#define HIPCHECK(cmd)                                         \
    do                                                        \
    {                                                         \
        hipError_t e = cmd;                                   \
        if (e != hipSuccess)                                  \
        {                                                     \
            printf("Failed: HIP error %s:%d '%s'\n",          \
                   __FILE__, __LINE__, hipGetErrorString(e)); \
            exit(EXIT_FAILURE);                               \
        }                                                     \
    } while (0)

#define NCCLCHECK(cmd)                                         \
    do                                                         \
    {                                                          \
        ncclResult_t r = cmd;                                  \
        if (r != ncclSuccess)                                  \
        {                                                      \
            printf("Failed, NCCL error %s:%d '%s'\n",          \
                   __FILE__, __LINE__, ncclGetErrorString(r)); \
            exit(EXIT_FAILURE);                                \
        }                                                      \
    } while (0)

#define PORT 12345

// Exchange NCCL ID via TCP socket
void exchangeNcclId(int rank, ncclUniqueId *id)
{
    if (rank == 0)
    {
        // Server: generate ID and send to client
        NCCLCHECK(ncclGetUniqueId(id));
        printf("[Rank 0] Generated NCCL Unique ID\n");

        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        address.sin_port = htons(PORT);

        bind(server_fd, (struct sockaddr *)&address, sizeof(address));
        listen(server_fd, 1);

        printf("[Rank 0] Waiting for client connection on port %d...\n", PORT);

        int client_fd = accept(server_fd, NULL, NULL);
        send(client_fd, id, sizeof(ncclUniqueId), 0);

        printf("[Rank 0] NCCL ID sent to client\n");

        close(client_fd);
        close(server_fd);
    }
    else
    {
        // Client: receive ID from server
        printf("[Rank 1] Connecting to server on localhost:%d...\n", PORT);

        int sock = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_port = htons(PORT);
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);

        // Retry connection for up to 10 seconds
        int connected = 0;
        for (int i = 0; i < 20; i++)
        {
            if (connect(sock, (struct sockaddr *)&address, sizeof(address)) == 0)
            {
                connected = 1;
                break;
            }
            usleep(500000); // 0.5 second
        }

        if (!connected)
        {
            printf("[Rank 1] Failed to connect to server\n");
            exit(1);
        }

        recv(sock, id, sizeof(ncclUniqueId), 0);
        printf("[Rank 1] NCCL ID received from server\n");

        close(sock);
    }
}

// Synchronize processes at the end via TCP socket
void finalSynchronize(int rank)
{
    const int SYNC_PORT = PORT + 1; // Use a different port for final sync

    if (rank == 0)
    {
        // Server: wait for client to signal completion
        printf("[Rank 0] Waiting for final sync with client...\n");

        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        address.sin_port = htons(SYNC_PORT);

        bind(server_fd, (struct sockaddr *)&address, sizeof(address));
        listen(server_fd, 1);

        int client_fd = accept(server_fd, NULL, NULL);

        // Exchange sync signals
        char sync_msg = 'S';
        send(client_fd, &sync_msg, 1, 0);
        recv(client_fd, &sync_msg, 1, 0);

        printf("[Rank 0] Final synchronization completed\n");

        close(client_fd);
        close(server_fd);
    }
    else
    {
        // Client: signal server and wait for acknowledgment
        printf("[Rank 1] Performing final sync with server...\n");

        int sock = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_port = htons(SYNC_PORT);
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);

        // Retry connection
        int connected = 0;
        for (int i = 0; i < 20; i++)
        {
            if (connect(sock, (struct sockaddr *)&address, sizeof(address)) == 0)
            {
                connected = 1;
                break;
            }
            usleep(500000); // 0.5 second
        }

        if (!connected)
        {
            printf("[Rank 1] Failed to connect for final sync\n");
            exit(1);
        }

        // Exchange sync signals
        char sync_msg = 'S';
        recv(sock, &sync_msg, 1, 0);
        send(sock, &sync_msg, 1, 0);

        printf("[Rank 1] Final synchronization completed\n");

        close(sock);
    }
}

int main(int argc, char *argv[])
{
    // Disable stdout buffering for proper output redirection
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    if (argc != 2)
    {
        printf("Usage: %s <rank>\n", argv[0]);
        printf("  rank: 0 (server) or 1 (client)\n");
        return 1;
    }

    int rank = atoi(argv[1]);
    if (rank != 0 && rank != 1)
    {
        printf("Invalid rank: %d (must be 0 or 1)\n", rank);
        return 1;
    }

    int world_size = 2;
    size_t size = 4; // Number of elements (same as normal_test.cpp)
    int ret;

    printf("=== Normal RCCL Test without MPI for Blue RDMA ===\n");
    printf("Rank: %d, World Size: %d, PID: %d\n\n", rank, world_size, getpid());

    // Set GPU device based on rank
    int num_devices;
    hipGetDeviceCount(&num_devices);
    int device = rank % num_devices;
    ret = hipSetDevice(device);
    printf("Rank %d using GPU %d, hipSetDevice() => %d\n", rank, device, ret);

    // Exchange NCCL unique ID via socket
    ncclUniqueId id;
    exchangeNcclId(rank, &id);

    // Initialize NCCL communicator
    ncclComm_t comm;
    ret = ncclCommInitRank(&comm, world_size, id, rank);
    printf("[Rank %d] ncclCommInitRank() => %d\n", rank, ret);

    // Allocate device buffers
    float *sendbuff, *recvbuff;
    hipStream_t s;

    ret = hipMalloc(&sendbuff, size * sizeof(float));
    printf("[Rank %d] hipMalloc(sendbuff) => %d\n", rank, ret);
    ret = hipMalloc(&recvbuff, size * sizeof(float));
    printf("[Rank %d] hipMalloc(recvbuff) => %d\n", rank, ret);
    ret = hipStreamCreate(&s);
    printf("[Rank %d] hipStreamCreate() => %d\n", rank, ret);

    // Initialize host buffer with rank+1 (same as normal_test.cpp)
    float hostBuff[size];
    for (int i = 0; i < size; i++)
    {
        hostBuff[i] = rank + 1;
    }
    printf("[Rank %d] Initialized send buffer with value %.1f\n", rank, hostBuff[0]);

    // Copy data to device
    ret = hipMemcpy(sendbuff, hostBuff, size * sizeof(float), hipMemcpyHostToDevice);
    printf("[Rank %d] hipMemcpy(H2D) => %d\n", rank, ret);

    // Perform AllReduce (sum operation)
    printf("[Rank %d] Starting ncclAllReduce...\n", rank);
    ret = ncclAllReduce(sendbuff, recvbuff, size, ncclFloat, ncclSum, comm, s);
    printf("[Rank %d] ncclAllReduce() => %d\n", rank, ret);

    // Synchronize stream
    ret = hipStreamSynchronize(s);
    printf("[Rank %d] hipStreamSynchronize() => %d\n", rank, ret);

    // Copy result back to host
    float result[size];
    ret = hipMemcpy(result, recvbuff, size * sizeof(float), hipMemcpyDeviceToHost);
    printf("[Rank %d] hipMemcpy(D2H) => %d\n", rank, ret);

    // Verify result
    // Rank 0 sends 1.0, Rank 1 sends 2.0, AllReduce sum should be 3.0
    float expected = 3.0f; // (rank0 + 1) + (rank1 + 1) = 1 + 2 = 3
    bool success = true;
    for (int i = 0; i < size; i++)
    {
        if (result[i] != expected)
        {
            printf("[Rank %d] ✗ Verification failed at index %d: expected %.1f, got %.1f\n",
                   rank, i, expected, result[i]);
            success = false;
            break;
        }
    }

    if (success)
    {
        printf("[Rank %d] ✓ Test PASSED: result[0] = %.1f (expected %.1f)\n",
               rank, result[0], expected);
    }
    else
    {
        printf("[Rank %d] ✗ Test FAILED\n", rank);
    }

    // Final synchronization between processes
    finalSynchronize(rank);
    // sleep(4);
    // Cleanup
    printf("[Rank %d] Cleaning up...\n", rank);
    ret = hipFree(sendbuff);
    printf("[Rank %d] hipFree(sendbuff) => %d\n", rank, ret);
    ret = hipFree(recvbuff);
    printf("[Rank %d] hipFree(recvbuff) => %d\n", rank, ret);

    ncclCommDestroy(comm);

    // Ensure all output is printed before exiting
    printf("[Rank %d] Test completed\n", rank);

    return success ? 0 : 1;
}
