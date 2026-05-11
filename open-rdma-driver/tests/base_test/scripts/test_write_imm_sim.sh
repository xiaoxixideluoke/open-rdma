#!/bin/bash

# write_imm 测试脚本 - 使用通用的双端 sim 测试框架
# 用法: ./test_write_imm_sim.sh [msg_len] [num_ops]
# 默认: msg_len=4096, num_ops=10

# 设置目录路径
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

# 默认消息长度和操作次数
MSG_LEN=${1:-4096}

# 调用通用的双端测试脚本
# 传递参数格式: write_imm <msg_len> <num_ops>
# run_dual_sim_test.sh 会自动为 client 追加 127.0.0.1
exec "$SCRIPT_DIR/run_dual_sim_test.sh" write_with_imm $MSG_LEN
