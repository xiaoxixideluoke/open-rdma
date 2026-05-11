#!/usr/bin/env python
import itertools
import logging
import os
import random
import queue

import cocotb.binary
import cocotb.triggers
import cocotb.utils
import cocotb_test.simulator
import pytest

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ReadWrite
from cocotb.regression import TestFactory
from cocotb.clock import Clock


from test_framework.common import gen_rtl_file_list, BluespecPipeIn, BluespecPipeOut, BlueRdmaDataStream256, BluespecPipeInNrWithQueue


class TB(object):
    def __init__(self, dut, test_cnt=100, speed_limit=490):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.INFO)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.txChannels = []
        self.rxChannels = []
        for idx in range(4):
            self.txChannels.append(BluespecPipeInNrWithQueue(
                dut, f"ftilemacTxStreamPipeInVec_{idx}", self.clock))
            self.rxChannels.append(BluespecPipeOut(
                dut, f"ftilemacRxStreamPipeOutVec_{idx}", self.clock))

        self.resetn.setimmediatevalue(0)

        self.test_packet_cnt = test_cnt
        self.total_send_byte_cnt = 0
        self.speed_limit = speed_limit
        self.packets_inflight = set()
        self.cur_send_speed = 0

    async def gen_reset(self):
        self.resetn.value = 0
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.resetn.value = 1
        await RisingEdge(self.clock)
        self.log.info("Generated FTile RST_N")

    def genRandomPacket(self):
        cur_packet_size = 0
        target_packet_size = 0
        while True:
            if target_packet_size == 0:
                target_packet_size = random.randint(64, 5120)
                self.log.debug(f"send new packet, size={target_packet_size}")

            byte_left = target_packet_size - cur_packet_size
            byte_num = min(32, byte_left)
            is_first = cur_packet_size == 0
            is_last = byte_left <= 32

            ds = BlueRdmaDataStream256(
                data=bytes([random.randint(0, 255) for _ in range(byte_num)]),
                byte_num=byte_num,
                start_byte_index=0,
                is_first=is_first,
                is_last=is_last
            )
            # print("target_packet_size=", target_packet_size, ", cur_packet_size=",
            #       cur_packet_size, ", byte_left=", byte_left, ", byte_num=", byte_num)
            # print("gen new packet=", ds)

            if is_last:
                cur_packet_size = 0
                target_packet_size = 0
            else:
                cur_packet_size = cur_packet_size + byte_num

            yield ds

    async def calc_current_send_speed(self):
        last_speed_calc_time = 0
        last_total_send_byte = 0

        average_factor = 0.9
        while True:
            cur_time = cocotb.utils.get_sim_time("ns")
            delta_time = cur_time - last_speed_calc_time
            delta_byte = self.total_send_byte_cnt - last_total_send_byte
            new_send_speed = delta_byte * 8.0 / delta_time
            self.cur_send_speed = self.cur_send_speed * average_factor + \
                new_send_speed * (1-average_factor)
            last_total_send_byte = self.total_send_byte_cnt
            last_speed_calc_time = cur_time

            await RisingEdge(self.clock)

    async def gen_send_packet(self):

        ds_generators = [self.genRandomPacket() for _ in range(4)]
        channel_stop_flags = [False for _ in range(4)]
        channel_packet_buf = ["" for _ in range(4)]
        send_packet_cnt = 0

        cocotb.start_soon(self.calc_current_send_speed())

        while not all(channel_stop_flags):
            for channel_idx in range(4):
                if channel_stop_flags[channel_idx] == True:
                    continue

                if await self.txChannels[channel_idx].not_full():

                    if (self.cur_send_speed > self.speed_limit):
                        over_speed_ratio = (
                            self.cur_send_speed - self.speed_limit) / self.speed_limit
                        if (random.random() * 0.1 < over_speed_ratio):
                            continue

                    ds = next(ds_generators[channel_idx])
                    if ds.is_first():
                        if send_packet_cnt >= self.test_packet_cnt:
                            channel_stop_flags[channel_idx] = True
                            continue
                        send_packet_cnt += 1

                    await self.txChannels[channel_idx].enq(ds.pack())
                    channel_packet_buf[channel_idx] += hex(ds.data())
                    self.total_send_byte_cnt += ds.byte_num()

                    if ds.is_last():
                        self.packets_inflight.add(
                            channel_packet_buf[channel_idx])
                        channel_packet_buf[channel_idx] = ""
            await RisingEdge(self.clock)

    async def recv_and_check(self):
        recv_packet_cnt = 0
        recv_channel_packet_buf = ["" for _ in range(4)]

        total_recv_byte_cnt = 0

        last_recv_time = 0
        last_recv_byte_cnt = 0
        avg_calc_factor = 0.8
        avg_speed = 0

        while recv_packet_cnt < self.test_packet_cnt:
            for channel_idx in range(4):
                if await self.rxChannels[channel_idx].not_empty():
                    ds_raw = await self.rxChannels[channel_idx].first()
                    # print("ds_raw=", ds_raw)
                    await self.rxChannels[channel_idx].deq()
                    ds = BlueRdmaDataStream256.unpack(ds_raw)
                    recv_channel_packet_buf[channel_idx] += hex(ds.data())
                    total_recv_byte_cnt += ds.byte_num()

                    if ds.is_last():
                        recv_packet_cnt += 1
                        self.packets_inflight.remove(
                            recv_channel_packet_buf[channel_idx])
                        recv_channel_packet_buf[channel_idx] = ""
                        if recv_packet_cnt % 20 == 0:
                            cur_time = cocotb.utils.get_sim_time("ns")

                            loop_back_speed = (
                                total_recv_byte_cnt - last_recv_byte_cnt) * 8.0 / (cur_time - last_recv_time)

                            avg_speed = avg_speed * avg_calc_factor + \
                                loop_back_speed * (1-avg_calc_factor)

                            last_recv_time = cur_time
                            last_recv_byte_cnt = total_recv_byte_cnt

                            is_warm_up = recv_packet_cnt < 400
                            assert (is_warm_up or avg_speed >
                                    self.speed_limit * 0.95)

                            self.log.info(
                                f"current loop back speed = {avg_speed} Gbps")
            await RisingEdge(self.clock)


@cocotb.test(timeout_time=800000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut, test_cnt=10000)

    await cocotb.start(Clock(tb.clock, 2, "ns").start())
    await tb.gen_reset()

    cocotb.start_soon(tb.gen_send_packet())
    await tb.recv_and_check()


def test_ftile_mac():
    rtl_dirs = os.getenv("COCOTB_VERILOG_DIR") or ""
    dut = os.getenv("COCOTB_DUT") or ""
    tests_dir = os.path.dirname(__file__)
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = gen_rtl_file_list(rtl_dirs)

    sim_build = os.path.join(tests_dir, "sim_build", dut)

    cocotb.binary.resolve_x_to = cocotb.binary._ResolveXToValue.ZEROS

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        timescale="1ns/1ps",
        sim_build=sim_build,
        waves=True
    )


if __name__ == "__main__":
    test_ftile_mac()
