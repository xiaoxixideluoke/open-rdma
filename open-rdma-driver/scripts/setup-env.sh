#!/bin/bash

# Blue RDMA Driver - Environment Setup Script
#
# This script sets up the LD_LIBRARY_PATH environment variable required
# to run Blue RDMA examples and applications.
#
# Usage:
#   source ./scripts/setup-env.sh
#
# Note: This script must be sourced (not executed directly) to modify
# the current shell's environment variables.

# Detect the absolute path to the project root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define library paths (absolute paths)
RUST_LIB_PATH="$PROJECT_ROOT/dtld-ibverbs/target/debug"
RDMA_CORE_LIB_PATH="$PROJECT_ROOT/dtld-ibverbs/rdma-core-55.0/build/lib"

# Check if paths exist
MISSING_PATHS=()

if [ ! -d "$RUST_LIB_PATH" ]; then
    MISSING_PATHS+=("$RUST_LIB_PATH")
fi

if [ ! -d "$RDMA_CORE_LIB_PATH" ]; then
    MISSING_PATHS+=("$RDMA_CORE_LIB_PATH")
fi

# Display warnings for missing paths
if [ ${#MISSING_PATHS[@]} -gt 0 ]; then
    echo "警告: 以下库路径不存在："
    for path in "${MISSING_PATHS[@]}"; do
        echo "  - $path"
    done
    echo ""

    if [ ! -d "$RUST_LIB_PATH" ]; then
        echo "提示: Rust 库尚未编译，请运行："
        echo "  cd $PROJECT_ROOT/dtld-ibverbs"
        echo "  cargo build"
        echo ""
    fi

    if [ ! -d "$RDMA_CORE_LIB_PATH" ]; then
        echo "提示: rdma-core 尚未编译，请运行："
        echo "  cd $PROJECT_ROOT/dtld-ibverbs/rdma-core-55.0"
        echo "  ./build.sh"
        echo ""
    fi

    echo "环境变量已设置，但某些路径缺失，运行时可能出错。"
    echo ""
fi

# Set LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$RUST_LIB_PATH:$RDMA_CORE_LIB_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Display result
echo "Blue RDMA 环境变量设置成功！"
echo ""
echo "LD_LIBRARY_PATH 已设置为："
echo "  $LD_LIBRARY_PATH"
echo ""
echo "现在可以运行示例程序了，例如："
echo "  cd $PROJECT_ROOT/examples"
echo "  make"
echo "  RUST_LOG=debug ./loopback 8192"
echo ""
