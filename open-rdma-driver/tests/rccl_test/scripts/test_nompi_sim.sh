#!/bin/bash

# 设置目录路径
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
DRIVER_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)

# 设置日志目录
mkdir -p $SCRIPT_DIR/../log/sim
LOG_DIR=$(cd "$SCRIPT_DIR/../log/sim" && pwd)

# Source 共同函数库
source $SCRIPT_DIR/../../common/test_common.sh



# 设置信号处理
setup_signal_handler

# 打印测试开始信息
print_test_start "RCCL nompi sim"

# 初始化测试环境
init_test_environment

# 编译 Rust 驱动
build_rust_driver "sim"

# 启动 RTL 模拟器（2个实例）
start_rtl_simulators 2 "rccl"

# 编译 hack_libc
cd "$SCRIPT_DIR/../../hack_libc"
cargo build

# 编译测试程序
build_test_program "$SCRIPT_DIR/.."

# 运行 RCCL 测试
cd $SCRIPT_DIR/..

echo "Current directory: $(pwd)"

# 启动 Rank 0 (先启动，让它完成设备初始化)
RUST_LOG=debug make nompi_hack_rank0 &> $LOG_DIR/rccl-1.log &
RANK0_PID=$!

# 启动 Rank 1
RUST_LOG=debug make nompi_hack_rank1 &> $LOG_DIR/rccl-2.log &
RANK1_PID=$!

echo "Rank 0 PID: $RANK0_PID"
echo "Rank 1 PID: $RANK1_PID"

# 只等待测试程序，不等待 RTL 进程
wait $RANK0_PID $RANK1_PID

# 打印测试结束信息
print_test_end "RCCL nompi sim"

