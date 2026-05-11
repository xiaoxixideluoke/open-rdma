#!/bin/bash

# send_recv 测试脚本 - 使用通用的双端 sim 测试框架
# 用法: ./test_send_recv_sim.sh [msg_len]
# 例如: ./test_send_recv_sim.sh 4096

# 设置目录路径
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 默认消息长度
MSG_LEN=${1:-4096}

# 调用通用的双端测试脚本
exec "$SCRIPT_DIR/run_dual_sim_test.sh" send_recv $MSG_LEN

