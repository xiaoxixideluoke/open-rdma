# coding:utf-8
import os
import gc
import socket
from ctypes import *
from enum import IntEnum
from multiprocessing import shared_memory
import threading
import time
import json
import errno
import base64
import collections

from abc import ABC, abstractmethod

from .tcpConnectionManager import TcpConnectionManager


class MockHostMem:
    def __init__(self, shared_mem_name, shared_mem_size) -> None:
        self.shared_mem_name = shared_mem_name
        self.shared_mem_size = shared_mem_size

        try:
            self.shared_mem_obj = shared_memory.SharedMemory(
                shared_mem_name, True, shared_mem_size)
            print("create new shared memory file")
        except FileExistsError:
            self.shared_mem_obj = shared_memory.SharedMemory(
                shared_mem_name, False, shared_mem_size)
            print("open exist shared memory file")

        self.buf = self.shared_mem_obj.buf

        self.buf[:] = b"\0" * shared_mem_size

    def close(self):
        gc.collect()
        self.shared_mem_obj.close()
        self.shared_mem_obj.unlink()


def open_shared_mem_to_hw_simulator(mem_size, shared_mem_file=None):
    if shared_mem_file is None:
        shared_mem_file = "/bluesim1"
    host_mem = MockHostMem(shared_mem_file, mem_size)
    return host_mem


class UserspaceDriverServer:
    def __init__(self, listen_addr, listen_port: int, csr_write_cb, csr_read_cb) -> None:
        self.listen_addr = listen_addr
        self.driver_listen_port = listen_port
        self.csr_write_cb = csr_write_cb
        self.csr_read_cb = csr_read_cb

    def run(self):
        self.stop_flag = False

        self.server_thread = threading.Thread(target=self._run, args=(
            self.listen_addr, self.driver_listen_port))
        self.server_thread.start()

    def stop(self):
        self.stop_flag = True

    def _run(self, listen_addr, listen_port):
        tcpConnection = TcpConnectionManager("1", listen_addr, listen_port)
        while not self.stop_flag:
            recv_raw = tcpConnection.receive_line()
            if not recv_raw:
                continue
            recv_req = json.loads(recv_raw)
            if recv_req["is_write"]:
                self.csr_write_cb(recv_req["addr"], recv_req["value"])
            else:
                value = self.csr_read_cb(recv_req["addr"])
                tcpConnection.send_data(
                    (json.dumps({"is_write": False, "addr": recv_req["addr"], "value": value}) + '\n').encode("utf-8"))
        tcpConnection.close()


class EthPacketRpc:
    def __init__(self, inst_id):
        self.inst_id = inst_id
        self.peer_inst_id = "1" if self.inst_id == "2" else "2"

        self.to_peer_pipe_name = f"/tmp/bluerdma-sim-eth-rpc-pipe-{self.inst_id}-to-{self.peer_inst_id}"
        self.from_peer_pipe_name = f"/tmp/bluerdma-sim-eth-rpc-pipe-{self.peer_inst_id}-to-{self.inst_id}"

        try:
            os.mkfifo(self.to_peer_pipe_name)
        except OSError as e:
            if e.errno != errno.EEXIST:  # ignore exist
                raise

        try:
            os.mkfifo(self.from_peer_pipe_name)
        except OSError as e:
            if e.errno != errno.EEXIST:  # ignore exist
                raise

        self.read_buf = collections.deque()
        self.write_buf = collections.deque()

        self.read_thread = threading.Thread(target=self._get_packet_task)
        self.write_thread = threading.Thread(target=self._put_packet_task)
        self.read_thread.start()
        self.write_thread.start()

    def send_packet(self, buf):
        self.write_buf.append(base64.standard_b64encode(buf).decode() + "\n")

    def recv_packet(self):
        if len(self.read_buf) == 0:
            return None
        return self.read_buf.popleft()

    def _get_packet_task(self):
        self.from_peer_pipe = open(self.from_peer_pipe_name, "r")
        while True:
            packet_b64 = self.from_peer_pipe.readline()
            packet_bytes = base64.standard_b64decode(packet_b64)
            self.read_buf.append(packet_bytes)

    def _put_packet_task(self):
        self.to_peer_pipe = open(self.to_peer_pipe_name, "w")
        while True:
            if len(self.write_buf) == 0:
                time.sleep(0.001)
                continue
            packet_b64 = self.write_buf.popleft()
            self.to_peer_pipe.write(packet_b64)

# TODO 会不会需要写成阻塞式的？目前在没连接时的send recv会直接丢包
# For Peer-to-peer eth packet exchange
class EthPacketTcp:
    def __init__(self, inst_id, host='127.0.0.1', port=7777):
        """
        Initialize EthPacketTcp with TCP communication

        Args:
            inst_id: "1" for server mode, "2" for client mode
            host: TCP host address (default: '127.0.0.1')
            port: TCP port number (default: 9999)
        """
        self.inst_id = inst_id
        self.peer_inst_id = "1" if self.inst_id == "2" else "2"
        self.host = host
        self.port = port

        # Buffers for packet management
        self.read_buf = collections.deque()
        self.write_buf = collections.deque()

        # Connection management
        self.socket = None
        self.connection = None
        self.conn_file = None  # File object for readline, created only once
        self.connected = False
        self.stop_flag = False

        # Setup connection and start threads
        self._setup_connection()

        self.read_thread = threading.Thread(target=self._read_task)
        self.write_thread = threading.Thread(target=self._write_task)
        self.read_thread.start()
        self.write_thread.start()

    def _setup_connection(self):
        """Establish TCP connection based on instance ID"""
        if self.inst_id == "1":
            # Server mode - listen for incoming connection
            self._setup_server()
        else:
            # Client mode - connect to server
            self._setup_client()

    def _setup_server(self):
        """Setup server to listen for incoming connection"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind((self.host, self.port))
        self.socket.listen(1)
        print(f"EthPacketTcp server listening on {self.host}:{self.port}")

        # Accept connection in a separate thread to avoid blocking
        accept_thread = threading.Thread(target=self._accept_connection)
        accept_thread.start()

    def _accept_connection(self):
        """Accept incoming connection"""
        try:
            self.connection, addr = self.socket.accept()
            self.conn_file = self.connection.makefile('r')  # Create makefile once
            self.connected = True
            print(f"EthPacketTcp server connected to {addr}")
        except Exception as e:
            print(f"EthPacketTcp server accept error: {e}")

    def _setup_client(self):
        """Setup client to connect to server"""
        while not self.connected and not self.stop_flag:
            try:
                self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self.socket.connect((self.host, self.port))
                self.connection = self.socket
                self.conn_file = self.connection.makefile('r')  # Create makefile once
                self.connected = True
                print(f"EthPacketTcp client connected to {self.host}:{self.port}")
            except Exception as e:
                print(f"EthPacketTcp client connection failed: {e}, retrying...")
                if self.socket:
                    self.socket.close()
                time.sleep(0.1)  # Wait before retry

    def send_packet(self, buf):
        """
        Send packet using base64 encoding

        Args:
            buf: Raw bytes to send
        """
        if self.connected:
            encoded_packet = base64.standard_b64encode(buf).decode() + "\n"
            self.write_buf.append(encoded_packet)

    def recv_packet(self):
        """
        Receive packet and return decoded bytes

        Returns:
            Decoded bytes if available, None otherwise
        """
        if len(self.read_buf) == 0:
            return None
        return self.read_buf.popleft()

    def _read_task(self):
        """Background task to read packets from TCP connection"""
        while not self.stop_flag:
            if not self.connected or self.conn_file is None:
                time.sleep(0.001)
                continue

            try:
                # Use the single makefile instance created during connection
                packet_b64 = self.conn_file.readline()
                if not packet_b64:
                    # Connection closed
                    self.connected = False
                    print("EthPacketTcp connection closed by peer")
                    break
                packet_bytes = base64.standard_b64decode(packet_b64.strip())
                self.read_buf.append(packet_bytes)
            except Exception as e:
                print(f"EthPacketTcp read error: {e}")
                self.connected = False
                time.sleep(0.01)  # Wait before retry

    def _write_task(self):
        """Background task to write packets to TCP connection"""
        while not self.stop_flag:
            if not self.connected or len(self.write_buf) == 0:
                time.sleep(0.001)
                continue

            try:
                packet_b64 = self.write_buf.popleft()
                if self.connection:
                    self.connection.send(packet_b64.encode())
            except Exception as e:
                print(f"EthPacketTcp write error: {e}")
                self.connected = False
                # Put packet back to buffer for retry
                self.write_buf.appendleft(packet_b64)
                time.sleep(0.01)  # Wait before retry

    def close(self):
        """Close TCP connection and stop threads"""
        self.stop_flag = True
        self.connected = False

        # Close makefile first to unblock readline()
        if self.conn_file:
            try:
                self.conn_file.close()
            except:
                pass
            self.conn_file = None

        if self.connection:
            self.connection.close()
        if self.socket:
            self.socket.close()

        # Wait for threads to finish
        if hasattr(self, 'read_thread') and self.read_thread.is_alive():
            self.read_thread.join(timeout=1)
        if hasattr(self, 'write_thread') and self.write_thread.is_alive():
            self.write_thread.join(timeout=1)


# For multi-card eth packet exchange using TCP communication
class EthSwitchTcp:
    def __init__(self, inst_id):
        self.inst_id = inst_id
        self.host = '127.0.0.1'
        
        self.write_buf = collections.deque()
        self.read_buf = collections.deque()

        self.socket = None
        self.conn_file = None
        self.stop_flag = False
        self.connected = False

        self._connect_to_switch()

        self.read_thread = threading.Thread(target=self._read_task)
        self.write_thread = threading.Thread(target=self._write_task)
        self.read_thread.start()
        self.write_thread.start()


    def _connect_to_switch(self):
        """Connect to the switch and start packet exchange"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # use self.port to connect to the switch
        self.socket.connect((self.host, 8100))
        self.conn_file = self.socket.makefile('r')
        self.socket.send(f"{self.inst_id}\n".encode())  # Send registration info to switch
        self.connected = True

    def send_packet(self, buf):
        """
        Send packet using base64 encoding

        Args:
            buf: Raw bytes to send
        """
        if self.connected:
            encoded_packet = base64.standard_b64encode(buf).decode() + "\n"
            self.write_buf.append(encoded_packet)

    def recv_packet(self):
        if self.connected and len(self.read_buf) > 0:
            return self.read_buf.popleft()
        return None

    def _write_task(self):
        """Background task to write packets to TCP connection"""
        while not self.stop_flag:
            if not self.connected or len(self.write_buf) == 0:
                time.sleep(0.001)
                continue

            try:
                packet_b64 = self.write_buf.popleft()
                print(f"EthSwitchTcp self.socket: {self.socket}, sending packet: {packet_b64.strip()}")
                if self.socket:
                    self.socket.send(packet_b64.encode())
                    print("EthSwitchTcp packet sent successfully")
            except Exception as e:
                print(f"EthSwitchTcp write error: {e}")
                self.connected = False
                # Put packet back to buffer for retry
                self.write_buf.appendleft(packet_b64)
                time.sleep(0.01)  # Wait before retry

    def _read_task(self):
        """Background task to read packets from TCP connection"""
        while not self.stop_flag:
            if not self.connected or self.conn_file is None:
                time.sleep(0.001)
                continue

            try:
                packet_b64 = self.conn_file.readline()
                if not packet_b64:
                    # Connection closed
                    print("EthSwitchTcp connection closed by switch")
                    break
                packet_bytes = base64.standard_b64decode(packet_b64.strip())
                self.read_buf.append(packet_bytes)
            except Exception as e:
                print(f"EthSwitchTcp read error: {e}")
                time.sleep(0.01)  # Wait before retry
    
    def close(self):
        self.stop_flag = True
        self.connected = False
        if self.conn_file:
            try:
                self.conn_file.close()
            except:
                pass
            self.conn_file = None
        if self.socket:
            self.socket.close()

        if hasattr(self, 'read_thread') and self.read_thread.is_alive():
            self.read_thread.join(timeout=1)
        if hasattr(self, 'write_thread') and self.write_thread.is_alive():
            self.write_thread.join(timeout=1)