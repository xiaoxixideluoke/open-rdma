import asyncio
import ipaddress
import base64
import sys

routing_table = {}
base_ip = ipaddress.IPv4Address("17.34.51.10")

async def handle_host(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    addr = writer.get_extra_info('peername')
    print(f"新 Host 连接: {addr}")

    inst_id = await reader.readline()
    print(f"instance id is: {inst_id.strip()}")

    src_ip_int = int(base_ip) + int(inst_id) - 1
    src_ip = ipaddress.IPv4Address(src_ip_int)
    routing_table[src_ip_int] = writer
    print(f"Host  已注册到交换机: {src_ip}")
    
    try:
        # 持续监听该 Host 发来的数据包
        while True:
            print(f"等待来自 {src_ip} 的数据包...")
            packet = await reader.readline()
            if not packet:
                break
            
            packet_bytes = base64.standard_b64decode(packet.strip())

            src_ip_bytes = packet_bytes[26:30]
            if src_ip_bytes != src_ip_int.to_bytes(4, byteorder='big'):
                print(f"[Warning]: 收到的包源 IP 与注册 IP 不匹配, src_ip_bytes={src_ip_bytes}, expected={src_ip_int.to_bytes(4, byteorder='big')}")
                sys.stdout.flush()

            dest_ip_bytes = packet_bytes[30:34]
            dest_ip_int = int.from_bytes(dest_ip_bytes, byteorder='big')
            dest_ip = ipaddress.IPv4Address(dest_ip_int)
            
            
            sys.stdout.flush()
            # 转发
            while dest_ip_int not in routing_table:
                print(f"目标 IP {dest_ip} 不在线，等待中...")
                await asyncio.sleep(1)

            print(f"转发包: {src_ip} -> {dest_ip}, 大小: {len(packet)}")
            routing_table[dest_ip_int].write(packet)
            await routing_table[dest_ip_int].drain()

                
    except Exception as e:
        print(f"连接中断: {e}")
    finally:
        # 清理连接
        writer.close()
        await writer.wait_closed()

async def main():
    server = await asyncio.start_server(handle_host, '127.0.0.1', 8100)
    print("软交换机启动在 127.0.0.1:8100")
    async with server:
        await server.serve_forever()

if __name__ == '__main__':
    print("启动软交换机...")
    asyncio.run(main())