#!/bin/bash

# rdma_write 测试脚本 - 使用通用的双端 sim 测试框架
# 用法: ./test_rdma_write_sim.sh [msg_len] [num_rounds]
# 例如: ./test_rdma_write_sim.sh 4096 5

# 设置目录路径
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 默认消息长度和轮数
MSG_LEN=${1:-4096}
NUM_ROUNDS=${2:-5}

# 调用通用的双端测试脚本
exec "$SCRIPT_DIR/run_dual_sim_test.sh" rdma_write $MSG_LEN $NUM_ROUNDS
