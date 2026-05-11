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

        self.req_pipes = []
        self.resp_pipes = []

        for idx in range(4):
            self.req_pipes.append(BluespecPipeIn(
                dut, f"reqPipeInVec_{idx}", self.clock))
        for idx in range(2):
            self.resp_pipes.append(BluespecPipeOut(
                dut, f"respPipeOutVec_{idx}", self.clock))

        self.reset_req_pipe = BluespecPipeIn(
            dut, f"resetReqPipeIn", self.clock)
        self.reset_resp_pipe = BluespecPipeOut(
            dut, f"resetRespPipeOut", self.clock, is_zero_width_signal=True)

    def _psn_seq_generator(self, idx):
        window_left_bound = 0
        window_size = 128
        stride_size = 16
        next_psn_to_put_in_random_buf = window_size - 2 * stride_size
        available_psns = [idx for idx in range(next_psn_to_put_in_random_buf)]

        tmp_window = [False for _ in range(window_size)]
        recent_psns = [0, 0, 0]
        for _ in range(2 ** 25):
            try_cnt = 0
            while True:
                try_cnt += 1
                if (try_cnt > 10):
                    cur_psn = min(available_psns)
                else:
                    cur_psn = random.choice(available_psns)

                if max(max(recent_psns), cur_psn) - min(min(recent_psns), cur_psn) < window_size - stride_size:
                    recent_psns.pop(0)
                    recent_psns.append(cur_psn)
                    break
            yield cur_psn

            available_psns.remove(cur_psn)
            tmp_window[cur_psn-window_left_bound] = True
            while all(tmp_window[0:stride_size]):
                tmp_window = tmp_window[stride_size:]
                tmp_window.extend([False for _ in range(stride_size)])
                available_psns.extend(
                    [next_psn_to_put_in_random_buf + idx for idx in range(stride_size)])
                next_psn_to_put_in_random_buf += stride_size
                window_left_bound += stride_size

    async def start_gen_input_data(self):
        qp_cnt = 4
        qp_seq_gens = [self._psn_seq_generator(idx) for idx in range(qp_cnt)]
        while True:
            cur_time = cocotb.utils.get_sim_time("ns")

            req_for_this_beats = [None, None, None, None]
            for channel_idx in range(4):
                if random.random() < 0.2:
                    continue
                if await self.req_pipes[channel_idx].not_full():
                    qpn = random.randint(0, qp_cnt-1)
                    psn = next(qp_seq_gens[qpn])

                    req_for_this_beats[channel_idx] = (qpn, psn)

                    req = BlueRdmaFourChannelPsnBitmapPreMergeReq(
                        psn=psn,
                        qpn=get_qpn(qpn, 0)
                    )
                    await self.req_pipes[channel_idx].enq(req.pack())
            self.log.debug(
                f"req_for_this_beats={req_for_this_beats}")

            await RisingEdge(self.clock)
            # break

    async def start_check_output_data(self):
        shift_counter = [0, 0]
        while True:
            for channel_idx in range(2):
                if await self.resp_pipes[channel_idx].not_empty():
                    raw_resp = await self.resp_pipes[channel_idx].first()
                    await self.resp_pipes[channel_idx].deq()
                    resp_maybe = BlueRdmaBitmapWindowStorageUpdateRespMaybe.unpack(
                        raw_resp)
                    if resp := resp_maybe.get_by_tag_default("valid"):

                        if resp.isShiftWindow() == True:
                            if resp.windowShiftedOutData() != 0xffffffffffffffffffffffffffffffff:
                                print(resp)
                                assert resp.windowShiftedOutData() == 0xffffffffffffffffffffffffffffffff
                            shift_counter[channel_idx] += 1
                            if (shift_counter[channel_idx] % 100 == 0):
                                print("shift_counter=", shift_counter)
            await RisingEdge(self.clock)

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

    await cocotb.start(tb.start_gen_input_data())
    await cocotb.start(tb.start_check_output_data())

    await Timer(40000, units='ns')


def test_psn_per_merge_and_storage():
    rtl_dirs = os.getenv("COCOTB_VERILOG_DIR") or ""
    dut = os.getenv("COCOTB_DUT") or ""
    tests_dir = os.path.dirname(__file__)
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = gen_rtl_file_list(rtl_dirs)

    sim_build = os.path.join(tests_dir, "sim_build", dut)

    copy_mem_file_to_sim_build_dir(rtl_dirs, sim_build)

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
    test_psn_per_merge_and_storage()
