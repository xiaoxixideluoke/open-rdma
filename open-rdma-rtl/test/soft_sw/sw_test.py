import socket
import ipaddress
import base64
import time
import threading
import random
import signal
import sys
import atexit

base_ip = ipaddress.IPv4Address("17.34.51.10")

def gen_packet(src_ip: ipaddress.IPv4Address, dest_ip: ipaddress.IPv4Address):
    payload = f"Hello from {src_ip} to {dest_ip} at {time.time()}"
    # 生成一个简单的以太网帧，包含 IP 头和负载
    eth_header = b'\x00\x00\x00\x00\x00\x00' + b'\x00\x00\x00\x00\x00\x00' + b'\x08\x00'  # 以太网头（目的 MAC + 源 MAC + 类型）
    ip_header = b'\x45\x00' + (20 + len(payload)).to_bytes(2, byteorder='big') + b'\x00\x00' + b'\x40\x01' + b'\x41\x12' + b'\x12\x34'  # IP 头（版本+IHL+总长度+标识+标志+TTL+协议+校验和）
    ip_header += src_ip.packed + dest_ip.packed  # 源 IP 和目的 IP
    packet = eth_header + ip_header + payload.encode()  # 完整的以太网帧
    return base64.standard_b64encode(packet).decode() + "\n"  # 返回包

def parse_packet(packet):
    packet_bytes = base64.standard_b64decode(packet.strip())
    src_ip_bytes = packet_bytes[26:30]
    dest_ip_bytes = packet_bytes[30:34]
    src_ip = ipaddress.IPv4Address(src_ip_bytes)
    dest_ip = ipaddress.IPv4Address(dest_ip_bytes)
    payload = packet_bytes[34:].decode()
    return src_ip, dest_ip, payload
    
class hostClient:
    def __init__(self, inst_id):
        self.src_ip = ipaddress.IPv4Address(int(base_ip) + inst_id - 1)
        self.port = 8100 + inst_id
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)  # 允许端口重用
        self.socket.bind(('127.0.0.1', self.port))
        self.socket.connect(('127.0.0.1', 8100))
        self.conn_file = self.socket.makefile('r')
        self.running = True
        self.recv_thread = threading.Thread(target=self._recv_packet, daemon=True)
        self.recv_thread.start()

    def send_packet(self, packet):
        if self.running:
            try:
                self.socket.send(packet.encode())
            except Exception as e:
                print(f"Host {self.src_ip} send error: {e}")

    def _recv_packet(self):
        while self.running:
            try:
                packet = self.conn_file.readline()
                if packet:
                    data = parse_packet(packet)
                    print(f"Host {self.src_ip} received packet: \n{data}\n")
                else:
                    print(f"Host {self.src_ip} connection closed by server.")
                    break
            except Exception as e:
                if self.running:
                    print(f"Host {self.src_ip} recv error: {e}")
                break

    def close(self):
        """关闭连接和清理资源"""
        self.running = False
        try:
            self.conn_file.close()
        except:
            pass
        try:
            self.socket.shutdown(socket.SHUT_RDWR)
        except:
            pass
        try:
            self.socket.close()
        except:
            pass
        print(f"Host {self.src_ip} closed.")


# 全局客户端列表，用于清理
clients = []

def cleanup():
    """清理所有客户端连接"""
    print("\n正在清理资源...")
    for client in clients:
        try:
            client.close()
        except Exception as e:
            print(f"清理客户端时出错: {e}")
    print("资源清理完成")

def signal_handler(signum, frame):
    """处理中断信号"""
    print(f"\n接收到信号 {signum}，正在退出...")
    cleanup()
    sys.exit(0)

if __name__ == '__main__':
    # 注册信号处理器
    signal.signal(signal.SIGINT, signal_handler)   # Ctrl+C
    signal.signal(signal.SIGTERM, signal_handler)  # kill命令
    
    # 注册退出处理器
    atexit.register(cleanup)
    
    host_num = 4
    
    try:
        # 创建客户端
        for i in range(host_num):
            client = hostClient(i + 1)
            clients.append(client)
        
        print(f"成功创建 {host_num} 个客户端")
        
        # 主循环
        src = dest = 0
        while True:
            src = random.randint(0, host_num - 1)
            dest = random.randint(0, host_num - 1)
            if src == dest:
                continue
            packet = gen_packet(clients[src].src_ip, clients[dest].src_ip)
            clients[src].send_packet(packet)
            print(f"Host {clients[src].src_ip} sent packet to {clients[dest].src_ip}")
            time.sleep(5)
            
    except KeyboardInterrupt:
        print("\n接收到键盘中断")
    except Exception as e:
        print(f"\n程序异常: {e}")
        import traceback
        traceback.print_exc()
    finally:
        # 确保资源被清理
        cleanup()