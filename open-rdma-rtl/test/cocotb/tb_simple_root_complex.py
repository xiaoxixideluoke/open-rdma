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

from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.intel.rtile import RTilePcieDevice, RTileRxBus, RTileTxBus

from test_framework.common import gen_rtl_file_list, BluespecPipeIn, BluespecPipeOut, BlueRdmaDataStream256, BlueRdmaDtldStreamMemAccessMeta, BluespecPipeInNrWithQueue


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.pcie_mrrs = 512
        self.write_test_packet_cnt = 1000
        self.total_write_byte_cnt = 0

        self.read_test_packet_cnt = 100000
        self.total_read_byte_cnt = 0

        self.read_reqs_to_check = [[] for _ in range(4)]
        self.completer_read_reqs_to_check = []
        self.completer_write_reqs_to_check = []

        self.mem_pool_size = 64*1024
        self.byte_cnt_per_beat = 32

        self.device_mem_size = 1024*1024

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.requester_write_meta_pipes = []
        self.requester_write_data_pipes = []
        self.requester_read_meta_pipes = []
        self.requester_read_data_pipes = []

        for idx in range(4):
            self.requester_write_meta_pipes.append(BluespecPipeInNrWithQueue(
                dut, f"streamSlaveIfcVec_{idx}_writePipeIfc_writeMetaPipeIn", self.clock))
            self.requester_write_data_pipes.append(BluespecPipeInNrWithQueue(
                dut, f"streamSlaveIfcVec_{idx}_writePipeIfc_writeDataPipeIn", self.clock))
            self.requester_read_meta_pipes.append(BluespecPipeInNrWithQueue(
                dut, f"streamSlaveIfcVec_{idx}_readPipeIfc_readMetaPipeIn", self.clock))
            self.requester_read_data_pipes.append(BluespecPipeOut(
                dut, f"streamSlaveIfcVec_{idx}_readPipeIfc_readDataPipeOut", self.clock))

        self.completer_write_meta_pipe = BluespecPipeOut(
            dut, f"streamMasterIfc_writePipeIfc_writeMetaPipeOut", self.clock)
        self.completer_write_data_pipe = BluespecPipeOut(
            dut, f"streamMasterIfc_writePipeIfc_writeDataPipeOut", self.clock)
        self.completer_read_meta_pipe = BluespecPipeOut(
            dut, f"streamMasterIfc_readPipeIfc_readMetaPipeOut", self.clock)
        self.completer_read_data_pipe = BluespecPipeIn(
            dut, f"streamMasterIfc_readPipeIfc_readDataPipeIn", self.clock)

        # PCIe
        self.rc = RootComplex()

        self.hardware_ip_inst = RTilePcieDevice(
            # configuration options
            port_num=0,
            pcie_generation=5,
            pcie_link_width=16,
            pld_clk_frequency=500e6,
            pf_count=1,
            max_payload_size=512,
            enable_extended_tag=True,

            # signals
            # Clock and reset
            reset_status=None,
            reset_status_n=None,
            coreclkout_hip=dut.CLK,
            refclk0=None,
            refclk1=None,
            pin_perst_n=None,

            # RX interface
            rx_bus=RTileRxBus.from_prefix(dut, "rxRawIfc"),
            rx_par_err=None,

            # TX interface
            tx_bus=RTileTxBus.from_prefix(dut, "txRawIfc"),
            tx_par_err=None,
        )

        self.hardware_ip_inst.functions[0].configure_bar(
            0, self.device_mem_size)

        self.hardware_ip_inst.log.setLevel(logging.INFO)
        self.rc.make_port().connect(self.hardware_ip_inst)

        self.mem_pool = self.rc.mem_pool.alloc_region(self.mem_pool_size)
        mem_base = self.mem_pool.get_absolute_address(0)
        for idx in range(0, len(self.mem_pool), 4):
            self.mem_pool[mem_base+idx: mem_base+idx +
                          4] = idx.to_bytes(4, byteorder="little")

    # Do not use user_rst but gen rstn for bsv
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

    def genRandomWritePacket(self):
        cur_packet_size = 0
        target_packet_size = 0
        packet_start_addr = 0
        while True:
            if target_packet_size == 0:
                packet_start_addr = random.randint(0, self.mem_pool_size-1)
                # packet_start_addr = 0x6dd8

                packet_start_addr_4k_block = packet_start_addr >> 12

                # can not exceed max read request size and can not cross 4kB boundary
                packet_max_end_addr = min(
                    packet_start_addr+self.pcie_mrrs,
                    (packet_start_addr_4k_block << 12) + 4095
                )

                packet_end_addr = random.randint(
                    packet_start_addr, packet_max_end_addr)
                # packet_end_addr = packet_start_addr + 1

                target_packet_size = packet_end_addr - packet_start_addr + 1
                # self.log.debug(
                #     f"send new packet, start_addr = {hex(packet_start_addr)} size={hex(target_packet_size)}")

            byte_left = target_packet_size - cur_packet_size
            start_addr_aligned_to_4_byte = packet_start_addr & (~0x03)
            end_addr_for_this_beat = packet_start_addr + byte_left
            is_first = cur_packet_size == 0

            max_allowed_end_addr_for_this_beat = start_addr_aligned_to_4_byte + \
                self.byte_cnt_per_beat - 1

            if end_addr_for_this_beat > max_allowed_end_addr_for_this_beat:
                end_addr_for_this_beat = max_allowed_end_addr_for_this_beat
                byte_num = end_addr_for_this_beat - packet_start_addr + 1
                is_last = False
            else:
                byte_num = byte_left
                is_last = True

            data = [byte
                    for num in range(
                        start_addr_aligned_to_4_byte, start_addr_aligned_to_4_byte + self.byte_cnt_per_beat, 4)
                    for byte in num.to_bytes(4, byteorder="little")]

            head_invalid_byte_cnt = packet_start_addr % 4
            tail_invalid_byte_cnt = (
                self.byte_cnt_per_beat - head_invalid_byte_cnt - byte_num)

            if head_invalid_byte_cnt != 0:
                data[0: head_invalid_byte_cnt] = (
                    [0xFF] * head_invalid_byte_cnt)
            if tail_invalid_byte_cnt != 0:
                data[head_invalid_byte_cnt +
                     byte_num: self.byte_cnt_per_beat] = ([0xCC] * tail_invalid_byte_cnt)

            ds = BlueRdmaDataStream256(
                data=bytes(data),
                byte_num=byte_num,
                start_byte_index=head_invalid_byte_cnt,
                is_first=is_first,
                is_last=is_last
            )
            # print("target_packet_size=", target_packet_size, ", cur_packet_size=",
            #       cur_packet_size, ", byte_left=", byte_left, ", byte_num=", byte_num)
            # self.log.debug(f"gen new beat={ds}")

            packet_start_address_to_yield = packet_start_addr
            target_packet_size_to_yield = target_packet_size
            if is_last:
                cur_packet_size = 0
                target_packet_size = 0
            else:
                cur_packet_size = cur_packet_size + byte_num
                packet_start_addr += byte_num

            yield (packet_start_address_to_yield, target_packet_size_to_yield, ds)

    def genRandomReadPacket(self):
        while True:
            packet_start_addr = random.randint(0, self.mem_pool_size-1)
            # packet_start_addr = 0xc624

            packet_start_addr_4k_block = packet_start_addr >> 12

            # can not exceed max read request size and can not cross 4kB boundary
            packet_max_end_addr = min(
                packet_start_addr+self.pcie_mrrs,
                (packet_start_addr_4k_block << 12) + 4095
            )

            packet_end_addr = random.randint(
                packet_start_addr, packet_max_end_addr)
            # packet_end_addr = packet_start_addr + 0x158 - 1

            target_packet_size = packet_end_addr - packet_start_addr + 1
            # self.log.debug(
            #     f"send new packet, start_addr = {hex(packet_start_addr)} size={hex(target_packet_size)}")

            # read_meta = BlueRdmaDtldStreamMemAccessMeta(
            #     addr=packet_start_addr,
            #     total_len=target_packet_size
            # )
            read_meta = BlueRdmaDtldStreamMemAccessMeta(
                addr=1024,
                total_len=512
            )

            yield read_meta

    async def start_send_write_req(self):
        last_write_byte_cnt = 0
        last_write_time = 0
        avg_calc_factor = 0.95
        avg_speed = 0

        ds_generators = [self.genRandomWritePacket() for _ in range(4)]
        channel_stop_flags = [False for _ in range(4)]
        channel_packet_buf = ["" for _ in range(4)]
        send_packet_cnt = 0

        # cocotb.start_soon(self.calc_current_send_speed())

        while not all(channel_stop_flags):
            cur_time = cocotb.utils.get_sim_time("ns")
            for channel_idx in range(4):
                if channel_stop_flags[channel_idx] == True:
                    continue

                if await self.requester_write_data_pipes[channel_idx].not_full():

                    # if (self.cur_send_speed > self.speed_limit):
                    #     over_speed_ratio = (
                    #         self.cur_send_speed - self.speed_limit) / self.speed_limit
                    #     if (random.random() * 0.1 < over_speed_ratio):
                    #         continue

                    packet_start_address, target_packet_size, ds = next(
                        ds_generators[channel_idx])
                    if ds.is_first():
                        if send_packet_cnt >= self.write_test_packet_cnt:
                            channel_stop_flags[channel_idx] = True
                            continue
                        send_packet_cnt += 1
                        write_meta = BlueRdmaDtldStreamMemAccessMeta(
                            addr=packet_start_address,
                            total_len=target_packet_size
                        )
                        await self.requester_write_meta_pipes[channel_idx].enq(write_meta.pack())
                        self.log.info(f"send new write meta={write_meta}")

                    await self.requester_write_data_pipes[channel_idx].enq(ds.pack())
                    self.log.info(f"new write beat={ds}")

                    self.total_write_byte_cnt += ds.byte_num()

            time_delta = cur_time - last_write_time
            if time_delta > 20:
                byte_delta = self.total_write_byte_cnt - last_write_byte_cnt
                write_speed = byte_delta * 8.0 / (time_delta)
                avg_speed = avg_speed * avg_calc_factor + \
                    write_speed * (1-avg_calc_factor)
                last_write_time = cur_time
                last_write_byte_cnt = self.total_write_byte_cnt
                self.log.info(
                    f"cur write speed = {write_speed}, avg write speed = {avg_speed} Gbps, byte_delta={byte_delta}, time_delta={time_delta}")
            await RisingEdge(self.clock)

    async def start_send_read_req(self):

        ds_generators = [self.genRandomReadPacket() for _ in range(4)]
        channel_stop_flags = [False for _ in range(4)]
        channel_packet_buf = ["" for _ in range(4)]
        send_packet_cnt = 0
        send_gap_counter = 0

        # cocotb.start_soon(self.calc_current_send_speed())

        while not all(channel_stop_flags):
            send_gap_counter += 1
            # if (send_gap_counter % 3 != 0):
            #     await RisingEdge(self.clock)
            #     continue
            for channel_idx in range(4):
                if channel_stop_flags[channel_idx] == True:
                    continue
                if await self.requester_read_meta_pipes[channel_idx].not_full():

                    # if (self.cur_send_speed > self.speed_limit):
                    #     over_speed_ratio = (
                    #         self.cur_send_speed - self.speed_limit) / self.speed_limit
                    #     if (random.random() * 0.1 < over_speed_ratio):
                    #         continue

                    if send_packet_cnt >= self.read_test_packet_cnt:
                        channel_stop_flags[channel_idx] = True
                        continue
                    send_packet_cnt += 1

                    read_meta = next(ds_generators[channel_idx])

                    await self.requester_read_meta_pipes[channel_idx].enq(read_meta.pack())
                    self.read_reqs_to_check[channel_idx].append(read_meta)
                    self.log.debug(
                        f"cahnnel {channel_idx} send read request = {read_meta}")

                    self.total_read_byte_cnt += read_meta.total_len()

            await RisingEdge(self.clock)

    async def start_read_resp_check(self):
        total_recv_read_req_cnt = 0
        total_recv_byte_cnt = 0
        last_recv_byte_cnt = 0
        last_recv_time = 0
        avg_calc_factor = 0.95
        avg_speed = 0
        while total_recv_read_req_cnt < self.read_test_packet_cnt:
            cur_time = cocotb.utils.get_sim_time("ns")
            for channel_idx in range(4):
                if not await self.requester_read_data_pipes[channel_idx].not_empty():
                    continue

                if len(self.read_reqs_to_check[channel_idx]) == 0:
                    raise SystemError("should not empty")
                cur_meta = self.read_reqs_to_check[channel_idx][0]
                cur_resp_ds_raw = await self.requester_read_data_pipes[channel_idx].first()
                cur_resp_ds = BlueRdmaDataStream256.unpack(cur_resp_ds_raw)
                await self.requester_read_data_pipes[channel_idx].deq()

                if cur_resp_ds.is_first():
                    print(
                        f"channel {channel_idx} recv new packet, raw meta = {cur_meta}, cur_resp_ds={cur_resp_ds}")

                first_beat_invalid_byte_cnt = cur_meta.addr() % 4
                cur_start_addr_aligned_to_4_byte = cur_meta.addr() - first_beat_invalid_byte_cnt
                cur_end_addr_aligned_to_4_byte = cur_start_addr_aligned_to_4_byte + self.byte_cnt_per_beat
                reference_payload_array = [b
                                           for idx in range(cur_start_addr_aligned_to_4_byte, cur_end_addr_aligned_to_4_byte, 4)
                                           for b in idx.to_bytes(4, byteorder="little")]
                got_payload_array = cur_resp_ds.data()

                total_recv_byte_cnt += cur_resp_ds.byte_num()

                print(f"time={cur_time}, channel {channel_idx} recv ds =", cur_resp_ds,
                      ", total_recv_byte_cnt=", total_recv_byte_cnt)
                # print("aaaaa=", reference_payload_array)
                # print("bbbbb=", list(got_payload_array.to_bytes(
                #     self.byte_cnt_per_beat, byteorder="little")))

                for byte_idx in range(cur_resp_ds.start_byte_index(), cur_resp_ds.start_byte_index() + cur_resp_ds.byte_num()):
                    if reference_payload_array[byte_idx] != got_payload_array.to_bytes(
                            self.byte_cnt_per_beat, byteorder="little")[byte_idx]:
                        print("reference_payload_array=",
                              reference_payload_array)
                        print("      got_payload_array=", list(got_payload_array.to_bytes(
                            self.byte_cnt_per_beat, byteorder="little")))
                    assert reference_payload_array[byte_idx] == got_payload_array.to_bytes(
                        self.byte_cnt_per_beat, byteorder="little")[byte_idx]

                if cur_resp_ds.is_first():
                    assert cur_resp_ds.start_byte_index() == first_beat_invalid_byte_cnt
                    if cur_resp_ds.is_last():
                        assert cur_resp_ds.byte_num(
                        ) == self.read_reqs_to_check[channel_idx][0].total_len()
                    else:
                        assert cur_resp_ds.start_byte_index() + cur_resp_ds.byte_num() == self.byte_cnt_per_beat

                if not (cur_resp_ds.is_first() or cur_resp_ds.is_last()):
                    assert cur_resp_ds.start_byte_index() == 0
                    assert cur_resp_ds.byte_num() == self.byte_cnt_per_beat

                if cur_resp_ds.is_last():
                    if not cur_resp_ds.is_first:
                        assert cur_resp_ds.start_byte_index() == 0
                    assert cur_resp_ds.byte_num(
                    ) == self.read_reqs_to_check[channel_idx][0].total_len()
                    self.read_reqs_to_check[channel_idx].pop(0)
                    total_recv_read_req_cnt += 1
                else:
                    self.read_reqs_to_check[channel_idx][0].addr = cur_end_addr_aligned_to_4_byte
                    self.read_reqs_to_check[channel_idx][0].total_len = self.read_reqs_to_check[channel_idx][0].total_len(
                    ) - cur_resp_ds.byte_num()

            time_delta = cur_time - last_recv_time
            if time_delta > 1:

                byte_delta = total_recv_byte_cnt - last_recv_byte_cnt
                loop_back_speed = byte_delta * 8.0 / (time_delta)

                avg_speed = avg_speed * avg_calc_factor + \
                    loop_back_speed * (1-avg_calc_factor)

                last_recv_time = cur_time
                last_recv_byte_cnt = total_recv_byte_cnt

                # is_warm_up = recv_packet_cnt < 400
                # assert (is_warm_up or avg_speed >
                #         self.speed_limit * 0.95)

                self.log.info(
                    f"total_recv_read_req_cnt = {total_recv_read_req_cnt}, cur speed = {loop_back_speed}, avg read speed = {avg_speed} Gbps, byte_delta={byte_delta}, time_delta={time_delta}")

            await RisingEdge(self.clock)

    async def start_memory_content_check(self):
        while True:
            mem_base = self.mem_pool.get_absolute_address(0)
            for idx in range(0, len(self.mem_pool), 4):
                assert self.mem_pool[mem_base+idx: mem_base+idx +
                                     4] == idx.to_bytes(4, byteorder="little")

            await Timer(100, units='ns')

    async def start_completer_read_write_req_send(self):
        pcie_ep_dev = self.rc.find_device(
            self.hardware_ip_inst.functions[0].pcie_id)
        bar = pcie_ep_dev.bar_window[0]
        while True:

            # ===== send write req ==============
            write_req_addr = random.randint(
                0, self.device_mem_size-1) & 0xFFFFFFFC  # align to 4 byte
            write_req_data = random.randint(0, 2**32 - 1)

            self.completer_write_reqs_to_check.append(
                [write_req_addr, write_req_data])
            await cocotb.start(
                bar.write(write_req_addr, write_req_data.to_bytes(4, byteorder="little"), timeout=50))

            self.log.debug(
                f"bar write req: write_req_addr={hex(write_req_addr)}, write_req_data={hex(write_req_data)}")

            # ===========send read req =================
            read_req_addr = random.randint(
                0, self.device_mem_size-1) & 0xFFFFFFFC  # align to 4 byte
            expected_read_resp_data = random.randint(0, 2**32 - 1)
            self.completer_read_reqs_to_check.append(
                [read_req_addr, expected_read_resp_data])

            async def _checker_closure():
                # int is a basic type, so here should be copy by value, not by reference
                captured_expected_read_resp_data = expected_read_resp_data
                read_resp = await bar.read(read_req_addr, 4, timeout=100)
                assert int.from_bytes(
                    read_resp, byteorder="little") == captured_expected_read_resp_data

            await cocotb.start(_checker_closure())

            await RisingEdge(self.clock)
            await RisingEdge(self.clock)

    async def start_completer_read_write_req_handler(self):

        while True:
            if (await self.completer_write_meta_pipe.not_empty()) and (await self.completer_write_data_pipe.not_empty()):
                raw_write_meta = await self.completer_write_meta_pipe.first()
                await self.completer_write_meta_pipe.deq()
                raw_write_data = await self.completer_write_data_pipe.first()
                await self.completer_write_data_pipe.deq()

                write_meta = BlueRdmaDtldStreamMemAccessMeta.unpack(
                    raw_write_meta)
                write_data = BlueRdmaDataStream256.unpack(
                    raw_write_data)

                (expected_write_req_addr,
                 expected_write_req_data) = self.completer_write_reqs_to_check.pop(0)
                assert write_meta.addr() & (self.device_mem_size-1) == expected_write_req_addr
                assert write_meta.total_len() == 4

                assert write_data.data() == expected_write_req_data
                assert write_data.byte_num() == 4
                assert write_data.start_byte_index() == 0
                assert write_data.is_first() == True
                assert write_data.is_last() == True

            if (await self.completer_read_meta_pipe.not_empty()):
                raw_read_meta = await self.completer_read_meta_pipe.first()
                await self.completer_read_meta_pipe.deq()
                read_meta = BlueRdmaDtldStreamMemAccessMeta.unpack(
                    raw_read_meta)

                expected_read_req_addr, expected_read_resp_data = self.completer_read_reqs_to_check.pop(
                    0)
                assert read_meta.addr() & (self.device_mem_size-1) == expected_read_req_addr
                assert read_meta.total_len() == 4

                read_resp_ds = BlueRdmaDataStream256(
                    data=expected_read_resp_data.to_bytes(
                        4, byteorder="little"),
                    byte_num=4,
                    start_byte_index=0,
                    is_first=True,
                    is_last=True
                )
                await self.completer_read_data_pipe.enq(read_resp_ds.pack())

            await RisingEdge(self.clock)


@ cocotb.test(timeout_time=60000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)

    await tb.gen_reset()
    await tb.rc.enumerate()

    pcie_ep_dev = tb.rc.find_device(
        tb.hardware_ip_inst.functions[0].pcie_id)

    await pcie_ep_dev.enable_device()
    await pcie_ep_dev.set_master()

    cocotb.start_soon(tb.start_memory_content_check())
    cocotb.start_soon(tb.start_send_write_req())

    cocotb.start_soon(tb.start_send_read_req())
    cocotb.start_soon(tb.start_read_resp_check())

    # cocotb.start_soon(tb.start_completer_read_write_req_send())
    # cocotb.start_soon(tb.start_completer_read_write_req_handler())

    await Timer(50000, units='ns')


def test_dma():
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
    test_dma()
