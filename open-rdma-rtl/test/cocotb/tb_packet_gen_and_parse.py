#!/usr/bin/env python
import itertools
import logging
import os
import random
import queue

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.clock import Clock


from test_framework.common import *
from enums import *


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.mem = [0] * (1 << 20)
        for idx in range(0, len(self.mem), 4):
            self.mem[idx:idx+4] = idx.to_bytes(length=4, byteorder="little")

        self.pcie_bfm = SimplePcieBehaviorModel(
            dut, ["ioChannelMemoryMasterPipeIfc"], [], mem=self.mem)

        self.wqe_pipe_in = BluespecPipeIn(dut, "wqePipeIn", self.clock)

    async def gen_reset(self):
        self.resetn.value = 0
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.resetn.value = 1
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.log.info("Generated DMA RST_N")


@ cocotb.test(timeout_time=6000000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)
    await cocotb.start(Clock(tb.clock, 2, "ns").start())

    await tb.gen_reset()

    wqe = BlueRdmaWorkQueueElem(
        pkey=0,
        opcode=WorkReqOpCode.IBV_WR_RDMA_WRITE_WITH_IMM,
        flags=WorkReqSendFlag.IBV_SEND_SIGNALED | WorkReqSendFlag.IBV_SEND_SOLICITED,
        qp_type=TypeQP.IBV_QPT_RC,
        psn=0,
        pmtu=PMTU.IBV_MTU_256,
        dqp_ip=0,
        mac_addr=0,
        laddr=1,
        lkey=0,
        raddr=2,
        rkey=0,
        len=32,
        totalLen=32,
        dqpn=0,
        sqpn=0,
        is_first=True,
        is_last=True
    )

    await tb.wqe_pipe_in.enq(wqe.pack())

    await Timer(4000, units='ns')


def test_packet_gen_and_parse():
    rtl_dirs = os.getenv("COCOTB_VERILOG_DIR") or ""
    dut = os.getenv("COCOTB_DUT") or ""
    tests_dir = os.path.dirname(__file__)
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = gen_rtl_file_list(rtl_dirs)

    sim_build = os.path.join(tests_dir, "sim_build", dut)

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        timescale="1ns/1ps",
        sim_build=sim_build,
        waves=True,
    )


if __name__ == "__main__":
    test_packet_gen_and_parse()
