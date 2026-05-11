#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <hip/hip_runtime.h>
#include <hip/hip_runtime_api.h>
#include <rccl/rccl.h>
#include <mpi.h>

int main(int argc, char *argv[])
{
    int rank, world_size;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    // Set GPU device based on rank
    int num_devices;
    hipGetDeviceCount(&num_devices);
    int device = rank % num_devices;
    hipSetDevice(device);
    printf("Rank %d/%d using GPU %d, with pid %d\n", rank, world_size, device, getpid());

    // Initialize NCCL with minimal setup
    ncclUniqueId id;
    if (rank == 0)
    {
        ncclGetUniqueId(&id);
        printf("Rank 0 generated NCCL ID\n");
    }

    MPI_Bcast(&id, sizeof(id), MPI_BYTE, 0, MPI_COMM_WORLD);

    // This is where the crash happens
    printf("Rank %d about to call ncclCommInitRank\n", rank);
    ncclComm_t comm;
    ncclCommInitRank(&comm, world_size, id, rank);
    printf("Rank %d ncclCommInitRank succeeded\n", rank);

    void *mem_ptr;
    int ret = hipMalloc(&mem_ptr, 4);
    printf("[Rank %d] hipMalloc(sendbuff) => %d\n", rank, ret);

    sleep(3600);
    ncclCommDestroy(comm);
    MPI_Finalize();
    return 0;
}