import socket
import json
import threading


import mock_host


class SingleCardLoopbackTestServer:
    def __init__(self, listen_addr, nic, listen_port: int) -> None:
        self.listen_addr = listen_addr
        if isinstance(nic, mock_host.EmulatorMockNicAndHost):
            self.driver_listen_port_a = listen_port
            self.simulator_listen_port_a = listen_port + 1

        self.mock_nic = nic

    def run(self):
        mock_host.NicManager.do_self_loopback(self.mock_nic)
        self.mock_nic.run()

        self.stop_flag = False

        self.server_thread_a = threading.Thread(target=self._run, args=(
            self.listen_addr, self.driver_listen_port_a, self.mock_nic))
        self.server_thread_a.start()

    def stop(self):
        self.mock_nic.stop()
        self.stop_flag = True

    def _run(self, listen_addr, listen_port,
             mock_nic: mock_host.EmulatorMockNicAndHost):
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind((listen_addr, listen_port))

        while not self.stop_flag:

            recv_raw, resp_addr = server_socket.recvfrom(1024)
            recv_req = json.loads(recv_raw)

            if recv_req["is_write"]:
                mock_nic.write_csr_blocking(
                    recv_req["addr"], recv_req["value"])
            else:
                value = mock_nic.read_csr_blocking(recv_req["addr"])
                server_socket.sendto(json.dumps(
                    {"value": value, "addr": recv_req["addr"], "is_write": False}).encode("utf-8"), resp_addr)


if __name__ == "__main__":
    host_mem = mock_host.MockHostMem("/bluesim1", 1024 * 1024 * 64)
    listen_addr = "0.0.0.0"
    listen_driver_port = 9873
    listen_simulator_port = listen_driver_port + 1

    mock_nic = mock_host.EmulatorMockNicAndHost(
        host_mem,
        host=listen_addr,
        port=listen_simulator_port)

    server = SingleCardLoopbackTestServer(
        listen_addr,
        mock_nic,
        listen_driver_port)
    server.run()
