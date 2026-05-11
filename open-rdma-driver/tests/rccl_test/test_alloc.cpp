#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/mman.h>
#include <arpa/inet.h>
#include <hip/hip_runtime.h>
#include <hip/hip_runtime_api.h>
#include <rccl/rccl.h>

// Define MAP_HUGE_SHIFT and MAP_HUGE_2MB if not available
#ifndef MAP_HUGE_SHIFT
#define MAP_HUGE_SHIFT 26
#endif

#ifndef MAP_HUGE_2MB
#define MAP_HUGE_2MB (21 << MAP_HUGE_SHIFT)
#endif

int main(int argc, char *argv[])
{
    printf("pid is: %d\n", getpid());
    fflush(stdout);
    // Set GPU device based on rank
    int num_devices;
    hipGetDeviceCount(&num_devices);
    int device = 0;
    hipSetDevice(device);
    size_t size = 1 << 20;

    void *hptr;
    hptr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                MAP_SHARED | MAP_ANONYMOUS | MAP_HUGETLB | MAP_POPULATE, -1, 0);

    if (hptr == MAP_FAILED)
    {
        printf("mmap fail!\n");
        fflush(stdout);
        exit(-1);
    }

    memset(hptr, 0, size);

    // lock the ptr
    int res = mlock(hptr, size);
    if (res != 0)
    {
        printf("mlock failed with error: %s (code: %d)\n",
               strerror(errno), errno);
    }

    sleep(3600);

    hipError_t err = hipHostRegister(hptr, size, hipHostRegisterMapped);
    if (err != hipSuccess)
    {
        printf("hipHostRegister failed with error: %s (code: %d)\n",
               hipGetErrorString(err), err);
        fflush(stdout);
        munmap(hptr, size);
        exit(-1);
    }
    printf("hipHostRegister succeeded\n");
    fflush(stdout);

    // Get device pointer for the registered memory
    void *dptr;
    err = hipHostGetDevicePointer(&dptr, hptr, 0);
    if (err != hipSuccess)
    {
        printf("hipHostGetDevicePointer failed with error: %s (code: %d)\n",
               hipGetErrorString(err), err);
        fflush(stdout);
    }
    else
    {
        printf("Device pointer: %p\n", dptr);
        fflush(stdout);
    }

    // hipHostMalloc(&hptr, 1<<20,
    // hipHostMallocMapped | hipHostMallocCoherent);

    printf("Host ptr is: %p\n", hptr);
    fflush(stdout);
    sleep(3600);
    return 0;
}