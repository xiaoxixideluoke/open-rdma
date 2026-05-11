# Open-RDMA 学习计划 — 第1周

> 目标：从零开始理解 RDMA 基础，跑通 Mock 模式测试，建立项目全局视野。

## 本周总目标

- [ ] 搭建 Mock 模式开发环境，跑通 loopback 和 send_recv 测试
- [ ] 理解 RDMA 核心概念（QP, CQ, MR, PD, WR）
- [ ] 跟踪一次完整的 ibv_post_send() 调用链
- [ ] 了解硬件 RTL 架构概貌

## 日程安排

| 天 | 主题 | 核心产出 |
|----|------|---------|
| Day 1 | 环境搭建 + 第一个 RDMA 程序 | 跑通 loopback 8192 |
| Day 2 | RDMA 编程模型入门 | 手写 send_recv 理解 QP/MR/CQ |
| Day 3 | 软件架构全景 | 画出 ibv_post_send → CSR 完整调用链 |
| Day 4 | Rust 驱动核心：ctx.rs | 理解 HwDeviceCtx 如何实现 verbs |
| Day 5 | 测试代码深读 | 读懂 rdma_common.c + rdma_transport.c |
| Day 6 | 硬件 RTL 架构 | 读完 RDMA硬件架构完整教程.md |
| Day 7 | 回顾 + 整理笔记 | 输出一篇学习总结 |

## 每日惯例

- 早上 10 分钟回顾前一天内容
- 每读完一个模块画一张简图
- 每天结束时更新 TODO

---

详细日计划见：`DAY1.md` ~ `DAY7.md`
