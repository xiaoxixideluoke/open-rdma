# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Standard build (hardware mode by default)
cargo build

# Build with specific features
cargo build --features hw      # Hardware mode (PCIe MMIO access)
cargo build --features sim     # Simulation mode (UDP communication)
cargo build --features mock    # Mock mode (pure software testing)

# Development builds
cargo build --release          # Optimized release build
cargo test                     # Run all tests
cargo bench                    # Run performance benchmarks
```

### Testing and Benchmarking

```bash
# Run specific benchmark suites
cargo bench --bench virt_to_phy  # Virtual-to-physical address translation
cargo bench --bench descriptor   # Descriptor handling performance

# Run tests (allowing for the project's specific lint allowances)
cargo test
```

## Architecture Overview

The rust-driver crate is the core RDMA driver implementation written in Rust. It operates as a library that gets loaded by the C provider layer through FFI.

### Key Modules

- **`verbs/`**: Core RDMA operations and FFI bindings
  - `core.rs`: `BlueRdmaCore` - main driver implementation
  - `ffi.rs`: C ABI exports for integration with libibverbs
  - `ctx.rs`: Context management for device operations
  - `dev.rs`: Device management and initialization

- **`csr/`**: Control and Status Register access
  - `hardware/`: Direct hardware register access via PCIe
  - `emulated/`: Simulation mode register access via UDP
  - `proxy.rs`: Abstraction layer for different access modes

- **`net/`**: Network stack implementation
  - `tap.rs`: TAP network interface for Linux networking
  - `simple_nic/`: Simple NIC emulation for testing
  - `recv_chan.rs`: Receive channel management

- **`mem/`**: Memory management subsystem
  - `dmabuf.rs`: DMA buffer handling
  - `virt_to_phy.rs`: Virtual to physical address translation
  - `page/`: Page table management (host and emulated)

- **`workers/`**: Background processing threads
  - `completion.rs`: Completion queue processing
  - `retransmit.rs`: Packet retransmission logic
  - `ack_responder.rs`: ACK handling and response generation
  - `rdma.rs`: RDMA operation workers
  - `send/`: Send operation processing
  - `meta_report/`: Metadata reporting operations

- **`descriptors/`**: Hardware descriptor formats
  - `send.rs`: Send operation descriptors
  - `cmd.rs`: Command descriptors
  - `simple_nic.rs`: Simple NIC descriptor format

### Operation Modes

The driver supports three operational modes controlled by Cargo features:

1. **Hardware Mode (`--features hw`)**
   - Direct PCIe MMIO access to hardware registers
   - Real hardware communication via `/dev/infiniband/uverbs*`
   - Production deployment mode

2. **Simulation Mode (`--features sim`)**
   - UDP-based communication with RTL simulator
   - Register access via UDP packets to ports 7701/7702
   - Hardware development and testing without physical hardware

3. **Mock Mode (`--features mock`)**
   - Pure software implementation without external dependencies
   - In-memory simulation of hardware behavior
   - Unit testing and CI/CD environments

### FFI Integration

The driver exports C-compatible functions that are dynamically loaded by the C provider layer:

```rust
// Key FFI exports
#[unsafe(export_name = "bluerdma_init")]
pub unsafe extern "C" fn init() // Global initialization

#[unsafe(export_name = "bluerdma_new")]
pub unsafe extern "C" fn new(sysfs_name: *const c_char) -> *mut c_void // Device creation
```

### Development Guidelines

- The project uses extensive linting rules defined in `lib.rs`
- All unsafe code is carefully isolated and documented
- Feature flags control hardware access patterns
- Memory safety is critical due to direct hardware access
- Performance is optimized for high-throughput RDMA operations

### Dependencies

Key external dependencies include:
- `libc`: System call bindings
- `memmap2`: Memory mapping for hardware access
- `pci-driver`: PCIe device management
- `netlink-sys`: Linux netlink for network configuration
- `crossbeam-*`: Concurrent data structures
- `bilge`: Bit-level manipulation utilities