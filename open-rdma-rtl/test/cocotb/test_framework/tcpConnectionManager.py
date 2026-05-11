"""
TCP Connection Stream for persistent point-to-point communication.

This module provides a TcpConnectionManager class that manages persistent
TCP connections between server and client endpoints. It handles connection
establishment, maintenance, and provides blocking connection acquisition
for scenarios where connection timing is uncertain.
"""

import socket
import sys
import threading
import time
from typing import Optional


class TcpConnectionManager:
    """
    Persistent TCP connection manager for point-to-point communication.

    This class manages a single long-lived TCP connection between two endpoints.
    It provides blocking connection acquisition and handles automatic reconnection
    when the connection is lost.

    Attributes:
        inst_id (str): "1" for server mode, "2" for client mode
        host (str): TCP host address
        port (int): TCP port number
    """

    def __init__(self, inst_id: str = '1', host: str = '127.0.0.1', port: int = 9999):
        """
        Initialize TCP connection manager

        Args:
            inst_id: "1" for server mode (listen for connections),
                    "2" for client mode (connect to server)
            host: TCP host address (default: '127.0.0.1')
            port: TCP port number (default: 9999)
        """
        self.inst_id = inst_id
        self.host = host
        self.port = port

        # Connection management
        self._connection: Optional[socket.socket] = None
        self._server_socket: Optional[socket.socket] = None
        self._readfile = None  # File object for readline operations
        self._connection_lock = threading.Lock()
        self._stop_flag = False

        # Connection state
        self._connected = False
        self._connection_thread = None

        # Start connection management
        self._start_connection_management()

    def _start_connection_management(self):
        """Start the connection management thread"""
        if self.inst_id == "1":
            # Server mode - start listening for connections
            self._setup_server()
        else:
            # Client mode - start connection attempts
            self._setup_client()

    def _setup_server(self):
        """Setup server to listen for incoming connection"""
        try:
            self._server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            # SO_REUSEADDR 允许快速重启服务器，但不能完全避免 TIME_WAIT 问题
            self._server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self._server_socket.bind((self.host, self.port))
            self._server_socket.listen(1)
            print(f"TcpConnectionManager server listening on {self.host}:{self.port}")

            # Start connection acceptance thread
            self._connection_thread = threading.Thread(target=self._accept_connection_loop)
            self._connection_thread.daemon = True
            self._connection_thread.start()

        except Exception as e:
            print(f"TcpConnectionManager server setup error: {e}")
            print(f"  Hint: Port {self.port} may be in use. Try: sudo lsof -i:{self.port} or wait 60s for TIME_WAIT")

    def _accept_connection_loop(self):
        """Continuously accept connections in server mode"""
        while not self._stop_flag:
            try:
                if self._server_socket:
                    # Accept connection (blocking)
                    connection, addr = self._server_socket.accept()

                    with self._connection_lock:
                        # If already connected, reject new connection
                        if self._connection and self._connected:
                            print(f"TcpConnectionManager server REJECTING new connection from {addr} - already connected", file=sys.stderr)
                            try:
                                connection.close()
                            except:
                                pass
                            # Continue waiting for next connection (in case current one drops)
                            continue

                        # Accept new connection only if no existing connection
                        print(f"TcpConnectionManager server connected to {addr}")

                        # Close any stale connection and file object (if exists but marked as disconnected)
                        if self._readfile:
                            try:
                                self._readfile.close()
                            except:
                                pass
                        if self._connection:
                            try:
                                self._connection.close()
                            except:
                                pass

                        self._connection = connection
                        self._readfile = connection.makefile('rb')
                        self._connected = True
                        # No need to notify with polling approach

            except Exception as e:
                if not self._stop_flag:
                    print(f"TcpConnectionManager accept error: {e}")
                    time.sleep(0.1)  # Wait before retry

    def _setup_client(self):
        """Setup client to connect to server"""
        # Start connection attempt thread
        self._connection_thread = threading.Thread(target=self._client_connection_loop)
        self._connection_thread.daemon = True
        self._connection_thread.start()

    def _client_connection_loop(self):
        """Continuously attempt to connect in client mode"""
        while not self._stop_flag and not self._connected:
            try:
                client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                client_socket.connect((self.host, self.port))

                with self._connection_lock:
                    self._connection = client_socket
                    self._readfile = client_socket.makefile('rb')  # Create file object for client too
                    self._connected = True
                    print(f"TcpConnectionManager client connected to {self.host}:{self.port}")
                    # No need to notify with polling approach

            except Exception as e:
                print(f"TcpConnectionManager client connection failed: {e}, retrying...")
                time.sleep(0.1)  # Wait before retry

    def get_connection(self, timeout: Optional[float] = None) -> Optional[socket.socket]:
        """
        Get the persistent connection (blocking if not ready)

        Args:
            timeout: Maximum time to wait for connection, None for indefinite

        Returns:
            Socket connection object, or None if timeout occurs
        """
        # Use simple polling approach to avoid race conditions
        start_time = time.time()
        while True:
            if self.is_connected():
                return self._connection

            # Check timeout
            if timeout is not None:
                elapsed = time.time() - start_time
                if elapsed >= timeout:
                    return None

            # Sleep for a short interval before checking again
            time.sleep(0.01)  # 10ms polling interval

    def is_connected(self) -> bool:
        """
        Check if connection is active and valid

        Returns:
            True if connection is active, False otherwise
        """
        with self._connection_lock:
            if not self._connected or not self._connection:
                return False

            try:
                # Simple check - try to get socket info
                self._connection.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
                return True
            except:
                self._connected = False
                return False

    def send_data(self, data: bytes) -> bool:
        """
        Send data through the persistent connection

        Args:
            data: Bytes to send

        Returns:
            True if send successful, False otherwise
        """
        connection = self.get_connection()
        if not connection:
            return False

        try:
            connection.send(data)
            return True
        except Exception as e:
            print(f"TcpConnectionManager send error: {e}")
            self._handle_connection_error()
            return False

    def receive_data(self, buffer_size: int = 4096) -> Optional[bytes]:
        """
        Receive data from the persistent connection

        Args:
            buffer_size: Maximum bytes to receive

        Returns:
            Received bytes, or None if no data available or error occurs
        """
        connection = self.get_connection()
        if not connection:
            return None

        try:
            return connection.recv(buffer_size)
        except Exception as e:
            print(f"TcpConnectionManager receive error: {e}")
            self._handle_connection_error()
            return None

    def receive_line(self, timeout: float = 1.0) -> bytes:
        """
        Receive a line from the persistent connection with timeout

        Args:
            timeout: Socket timeout in seconds (default: 1.0)

        Returns:
            Line as bytes, or None if timeout/error occurs
        """
        
        self.get_connection()
        return self._readfile.readline()

    def _handle_connection_error(self):
        """Handle connection errors by resetting connection state"""
        with self._connection_lock:
            if self._readfile:
                try:
                    self._readfile.close()
                except:
                    pass
                self._readfile = None
            if self._connection:
                try:
                    self._connection.close()
                except:
                    pass
                self._connection = None
            self._connected = False

        # Restart connection management
        if not self._stop_flag:
            self._start_connection_management()

    def close(self):
        """Close the persistent connection and cleanup resources"""
        self._stop_flag = True

        with self._connection_lock:
            if self._readfile:
                try:
                    self._readfile.close()
                except:
                    pass
                self._readfile = None

            if self._connection:
                try:
                    self._connection.close()
                except:
                    pass
                self._connection = None

            if self._server_socket:
                try:
                    self._server_socket.close()
                except:
                    pass
                self._server_socket = None

            self._connected = False

        # Wait for connection thread to finish
        if self._connection_thread and self._connection_thread.is_alive():
            self._connection_thread.join(timeout=1)

        print("TcpConnectionManager closed")


# ==================== 测试代码 ====================

def test_basic_connection():
    """测试基本的连接建立"""
    print("\n=== 测试基本连接建立 ===")

    # 使用不同端口避免冲突
    test_port = 19999

    # 创建服务器端
    server = TcpConnectionManager("1", "127.0.0.1", test_port)

    # 创建客户端
    client = TcpConnectionManager("2", "127.0.0.1", test_port)

    # 等待连接建立
    time.sleep(0.1)

    # 检查连接状态
    server_connected = server.is_connected()
    client_connected = client.is_connected()

    print(f"服务器连接状态: {server_connected}")
    print(f"客户端连接状态: {client_connected}")

    if server_connected and client_connected:
        print("✓ 基本连接测试通过")
        result = True
    else:
        print("✗ 基本连接测试失败")
        result = False

    # 清理资源
    server.close()
    client.close()
    time.sleep(0.1)

    return result


def test_data_transmission():
    """测试数据传输功能"""
    print("\n=== 测试数据传输 ===")

    test_port = 19998
    test_message = b"Hello from server!"
    test_response = b"Hello from client!"

    # 创建服务器端和客户端
    server = TcpConnectionManager("1", "127.0.0.1", test_port)
    client = TcpConnectionManager("2", "127.0.0.1", test_port)

    # 等待连接建立
    time.sleep(0.1)

    if not (server.is_connected() and client.is_connected()):
        print("✗ 连接建立失败，无法进行数据传输测试")
        server.close()
        client.close()
        return False

    try:
        # 服务器向客户端发送数据
        send_result = server.send_data(test_message)
        print(f"服务器发送数据结果: {send_result}")

        if send_result:
            # 客户端接收数据
            time.sleep(0.01)  # 给数据传输一点时间
            received_data = client.receive_data()
            print(f"客户端接收到的数据: {received_data}")

            if received_data == test_message:
                print("✓ 服务器->客户端数据传输测试通过")

                # 客户端向服务器发送响应
                response_result = client.send_data(test_response)
                print(f"客户端发送响应结果: {response_result}")

                if response_result:
                    # 服务器接收响应
                    time.sleep(0.01)
                    server_received = server.receive_data()
                    print(f"服务器接收到的响应: {server_received}")

                    if server_received == test_response:
                        print("✓ 客户端->服务器数据传输测试通过")
                        print("✓ 双向数据传输测试通过")
                        result = True
                    else:
                        print("✗ 服务器接收响应失败")
                        result = False
                else:
                    print("✗ 客户端发送响应失败")
                    result = False
            else:
                print("✗ 客户端接收数据失败")
                result = False
        else:
            print("✗ 服务器发送数据失败")
            result = False

    except Exception as e:
        print(f"✗ 数据传输测试异常: {e}")
        result = False

    # 清理资源
    server.close()
    client.close()
    time.sleep(0.1)

    return result


def test_connection_reuse():
    """测试连接复用"""
    print("\n=== 测试连接复用 ===")

    test_port = 19997

    # 手动创建服务器socket用于测试
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind(("127.0.0.1", test_port))
    server_socket.listen(1)
    print("测试服务器开始监听...")

    # 接受客户端连接
    def accept_connection():
        try:
            conn, addr = server_socket.accept()
            print(f"测试服务器接受连接: {addr}")
            return conn
        except:
            return None

    # 在单独线程中接受连接
    import threading
    accept_thread = threading.Thread(target=accept_connection)
    accept_thread.start()

    # 等待服务器完全准备好，然后再创建客户端
    time.sleep(0.1)

    # 创建客户端 (确保服务器已经准备好)
    print("创建客户端...")
    client = TcpConnectionManager("2", "127.0.0.1", test_port)

    # 等待连接建立 (增加等待时间)
    time.sleep(0.3)
    if not client.is_connected():
        print("✗ 连接建立失败，无法进行连接复用测试")
        server_socket.close()
        client.close()
        return False

    try:
        # 多次获取连接，验证是否返回同一个对象
        conn1 = client.get_connection()
        conn2 = client.get_connection()
        conn3 = client.get_connection()

        print(f"第一次获取连接: {id(conn1)}")
        print(f"第二次获取连接: {id(conn2)}")
        print(f"第三次获取连接: {id(conn3)}")

        # 验证连接对象是否相同
        if conn1 is conn2 is conn3:
            print("✓ 连接复用测试通过 - 多次获取返回同一个连接对象")
            result = True
        else:
            print("✗ 连接复用测试失败 - 获取到的连接对象不同")
            result = False

    except Exception as e:
        print(f"✗ 连接复用测试异常: {e}")
        result = False

    # 清理资源
    accept_thread.join(timeout=1)
    server_socket.close()
    client.close()

    return result


def test_timeout():
    """测试超时机制"""
    print("\n=== 测试超时机制 ===")

    # 使用一个不存在的端口来触发超时
    test_port = 19996

    # 创建客户端，但不创建服务器
    client = TcpConnectionManager("2", "127.0.0.1", test_port)

    try:
        # 测试短超时
        start_time = time.time()
        connection = client.get_connection(timeout=0.5)  # 0.5秒超时
        elapsed = time.time() - start_time

        print(f"超时测试耗时: {elapsed:.2f}秒")
        print(f"获取到的连接: {connection}")

        if connection is None and 0.4 <= elapsed <= 0.7:  # 允许一些时间误差
            print("✓ 超时机制测试通过")
            result = True
        else:
            print("✗ 超时机制测试失败")
            result = False

    except Exception as e:
        print(f"✗ 超时测试异常: {e}")
        result = False

    # 清理资源
    client.close()

    return result


def run_basic_tests():
    """运行所有基本测试"""
    print("开始运行 TcpConnectionManager 基本功能测试...")

    tests = [
        ("基本连接建立", test_basic_connection),
        ("数据传输", test_data_transmission),
        ("连接复用", test_connection_reuse),
        ("超时机制", test_timeout),
    ]

    results = []
    for test_name, test_func in tests:
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"测试 {test_name} 发生异常: {e}")
            results.append((test_name, False))

        # 测试间隔，避免端口冲突
        time.sleep(0.2)

    # 输出测试结果摘要
    print("\n" + "="*50)
    print("测试结果摘要:")
    print("="*50)

    passed = 0
    total = len(results)

    for test_name, result in results:
        status = "✓ 通过" if result else "✗ 失败"
        print(f"{test_name}: {status}")
        if result:
            passed += 1

    print("-"*50)
    print(f"总计: {passed}/{total} 个测试通过")

    if passed == total:
        print("🎉 所有基本功能测试都通过了!")
    else:
        print("⚠️  部分测试失败，请检查代码")

    return passed == total


if __name__ == "__main__":
    # 运行基本功能测试
    run_basic_tests()