# RCCL Test Suite for Blue RDMA Driver

This directory contains RCCL (ROCm Collective Communications Library) test programs for testing the Blue RDMA driver with ROCm/DCU environments.

## 注意事项
hack_libc 需要较多的大页内存，目前申请了4GB内存

## Test Programs

### 1. Simple Test (`simple_test`)
- Basic RCCL initialization test with MPI
- Minimal test to verify RCCL communicator setup
- Uses MPI for multi-process coordination

### 2. Normal Test No-MPI (`normal_test_nompi`)
- RCCL test without MPI dependency
- Uses socket-based coordination between processes
- Allows separate RDMA device configuration per process
- Ideal for testing specific RDMA device assignments

## Quick Start

```bash
# Build all tests
make

# Run simple test with RDMA
make simple_rdma

# Run no-MPI test (in two terminals)
# Terminal 1:
make nompi_rank0

# Terminal 2:
make nompi_rank1
```

## Build System

All binaries are built into the `build/` directory:
```
nccl_test/
├── build/
│   ├── simple_test         # Simple test executable
│   └── normal_test_nompi   # No-MPI test executable
├── simple_test.cpp         # Source code
├── normal_test_nompi.cpp   # Source code
├── Makefile
└── README.md
```

## Prerequisites

### Required
- **ROCm/DCU**: ROCm toolkit and DCU devices
- **RCCL**: ROCm Collective Communications Library
- **MPI**: OpenMPI (for simple_test)
- **Blue RDMA Driver**: Built with the Blue RDMA driver

### Configuration

Edit the Makefile to match your environment:
```makefile
ROCM_HOME ?= /opt/rocm
DTK_HOME ?= /opt/dtk
MPI_HOME = /usr/mpi/gcc/openmpi-4.1.7rc1
```

## Building

### Build All
```bash
make
```

### Clean and Rebuild
```bash
make clean
make
```

### Show Configuration
```bash
make info
```

## Running Tests

### Simple Test

Run with RDMA (2 processes):
```bash
make simple_rdma
```

Force IB network (disable P2P and shared memory):
```bash
make simple_rdma_force
```

### Normal Test (No-MPI)

This test runs two separate processes without MPI. Each process can use a different RDMA device.

**Terminal 1 (Rank 0 - Server):**
```bash
make nompi_rank0
```

**Terminal 2 (Rank 1 - Client):**
```bash
make nompi_rank1
```

The processes will coordinate via TCP socket on port 12345.

## Makefile Targets

### Build Targets
- `all` - Build all test programs (default)
- `clean` - Remove build directory and all artifacts
- `rebuild` - Clean and rebuild everything

### Run Targets (Simple Test)
- `simple` - Run simple test with RDMA (alias for simple_rdma)
- `simple_rdma` - Run simple test with RDMA (2 DCUs)
- `simple_rdma_force` - Force IB network (disable P2P/SHM)

### Run Targets (Normal Test - No MPI)
- `nompi` - Run rank 0 server (alias for nompi_rank0)
- `nompi_rank0` - Run rank 0 with bluerdma0
- `nompi_rank1` - Run rank 1 with bluerdma1

### Info Targets
- `info` - Show build configuration
- `help` - Show help message with all targets

## Environment Variables

### NCCL Configuration
- `NCCL_DEBUG` - Debug level (INFO, TRACE, etc.)
- `NCCL_DEBUG_SUBSYS` - Debug subsystems (INIT, NET, etc.)
- `NCCL_IB_DISABLE` - Set to 0 to enable InfiniBand/RDMA
- `NCCL_IB_HCA` - Specify RDMA devices (e.g., bluerdma0,bluerdma1)
- `NCCL_NET_GDR_LEVEL` - GPU Direct RDMA level
- `NCCL_P2P_DISABLE` - Set to 1 to disable P2P
- `NCCL_SHM_DISABLE` - Set to 1 to disable shared memory

### UCX Configuration (for MPI)
- `UCX_NET_DEVICES` - Network devices (e.g., blue0,blue1)

### Blue RDMA Driver
- `RUST_LOG` - Rust logging level (debug, trace, etc.)

## Test Details

### Simple Test (`simple_test.cpp`)

**What it does:**
1. Initializes MPI for multi-process coordination
2. Sets GPU device based on rank
3. Initializes NCCL communicator
4. Allocates minimal GPU memory
5. Waits (useful for debugging/monitoring)

**Key Features:**
- Uses MPI for process management
- Minimal RCCL setup to verify basic functionality
- Long sleep for inspection during debugging

### Normal Test No-MPI (`normal_test_nompi.cpp`)

**What it does:**
1. Accepts rank as command-line argument (0 or 1)
2. Uses TCP socket to exchange NCCL unique ID
3. Each process uses explicitly configured RDMA device
4. Performs AllReduce operation
5. Verifies results

**Key Features:**
- No MPI dependency
- Socket-based coordination
- Explicit RDMA device assignment via environment variables
- Useful for testing specific device configurations

## Architecture

```
Application (simple_test / normal_test_nompi)
    ↓ RCCL API
RCCL Library (librccl.so)
    ↓ IB Verbs
Blue RDMA Driver (libbluerdma_rust.so + libibverbs.so)
    ↓
Blue RDMA Hardware/Mock
```

## Troubleshooting

### Build Errors

Check paths:
```bash
make info
```

Verify RCCL installation:
```bash
ls $DTK_HOME/include/rccl/rccl.h
ls $DTK_HOME/lib/librccl.so
```

### RCCL doesn't detect Blue RDMA device

Check device:
```bash
rdma link show
ibv_devices
```

### Runtime Errors

Enable verbose logging:
```bash
export NCCL_DEBUG=TRACE
export NCCL_DEBUG_SUBSYS=ALL
export RUST_LOG=trace
make simple_rdma
```

### No-MPI Test Connection Issues

Verify network connectivity:
```bash
# Check if port 12345 is available
netstat -an | grep 12345

# Check firewall settings
sudo iptables -L
```

## Advanced Usage

### Custom RDMA Device Assignment

For the no-MPI test, you can customize which devices each rank uses:

**Rank 0:**
```bash
export NCCL_IB_HCA=bluerdma0
export UCX_NET_DEVICES=blue0
build/normal_test_nompi 0
```

**Rank 1:**
```bash
export NCCL_IB_HCA=bluerdma1
export UCX_NET_DEVICES=blue1
build/normal_test_nompi 1
```

### Running with Different Process Counts

For simple_test, you can modify the Makefile or run manually:

```bash
export PATH=/usr/mpi/gcc/openmpi-4.1.7rc1/bin:$PATH
export LD_LIBRARY_PATH=/usr/mpi/gcc/openmpi-4.1.7rc1/lib:$LD_LIBRARY_PATH
export NCCL_IB_DISABLE=0
export NCCL_NET_GDR_LEVEL=0

mpirun -np 4 \
  -x NCCL_IB_DISABLE=0 \
  -x NCCL_NET_GDR_LEVEL=0 \
  build/simple_test
```

## Development Notes

### Adding New Tests

1. Create source file: `your_test.cpp`
2. Add to Makefile:
```makefile
YOUR_TARGET = $(BUILD_DIR)/your_test
YOUR_SOURCES = your_test.cpp

$(YOUR_TARGET): $(YOUR_SOURCES) | $(BUILD_DIR)
	$(HIPCC) $(HIPCCFLAGS) $(INCLUDES) -o $(YOUR_TARGET) $(YOUR_SOURCES) $(LDFLAGS) $(LIBS)
```
3. Add run target and update help/all targets

### Build Directory Structure

All output goes to `build/`:
- Keeps source directory clean
- Easy to clean with `make clean`
- Simplifies .gitignore

## Files

```
nccl_test/
├── build/                      # Build output directory (git-ignored)
│   ├── simple_test            # Executables
│   └── normal_test_nompi
├── scripts/                    # Helper scripts
├── simple_test.cpp            # Simple test source
├── normal_test_nompi.cpp      # No-MPI test source
├── Makefile                   # Build system
└── README.md                  # This file
```

## References

- [RCCL Documentation](https://rocmdocs.amd.com/en/latest/ROCm_Libraries/ROCm_Libraries.html#rccl)
- [Blue RDMA Driver](../README.md)
- [OpenMPI Documentation](https://www.open-mpi.org/doc/)

## Known Issues

### Previous Issues (Historical)

See README history for details on:
- CUDA driver version mismatches (WSL environments)
- NCCL version compatibility
- Segmentation faults during initialization

These issues have been resolved in the current configuration.
