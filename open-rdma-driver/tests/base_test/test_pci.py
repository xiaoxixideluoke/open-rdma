import ctypes
import os
import random
import mmap
import struct
import time

def va_to_pa(va):
    page_size = os.sysconf(os.sysconf_names['SC_PAGESIZE'])
    # page_size = 2*1024*1024
    page_offset = va % page_size
    pagemap_entry_offset = (va // page_size) * 8  # 每个条目8字节

    try:
        with open('/proc/self/pagemap', 'rb') as f:
            f.seek(pagemap_entry_offset)
            entry_bytes = f.read(8)
            if len(entry_bytes) != 8:
                raise ValueError("Invalid pagemap entry")

            entry = int.from_bytes(entry_bytes, byteorder='little')
            if not (entry & (1 << 63)):  # 检查页面是否在内存中
                raise ValueError("Page not present in physical memory")

            pfn = entry & 0x7FFFFFFFFFFFFF  # 提取PFN
            print(f"pfn={hex(pfn)}")
            return (pfn * page_size) + page_offset

    except IOError as e:
        raise RuntimeError(f"Failed to access pagemap: {e}")


# 定义 mmap 相关常量
PROT_READ = 1
PROT_WRITE = 2
MAP_SHARED = 0x01
MAP_HUGETLB = 0x40000  # 巨页内存标志
MAP_LOCKED = 0x02000
MAP_ANONYMOUS = 0x20

# 定义 mmap 函数
libc = ctypes.CDLL("libc.so.6")
cmmap = libc.mmap
cmmap.restype = ctypes.c_void_p
cmmap.argtypes = (
    ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_int, ctypes.c_int,
    ctypes.c_int, ctypes.c_long
)

# 申请 2MB 巨页内存
size = 2 * 1024 * 1024  # 2MB
addr = cmmap(
    0, size,
    PROT_READ | PROT_WRITE,
    MAP_SHARED | MAP_ANONYMOUS | MAP_HUGETLB | MAP_LOCKED,
    -1, 0
)

if addr == -1:
    raise OSError("Failed to allocate huge page memory")

os.system("setpci  -s 01:00.0 COMMAND=0x02")
os.system("setpci  -s 01:00.0 98.b=0x16")  # 98 = 0x70(base) + 0x28(DevCtl2 offset), 0x16 means disable completion timeout
os.system("setpci  -s 01:00.0 CAP_EXP+28.w=0x1000")  # enable 10 bit tag


# 使用内存（示例）

va_src = addr
va_dst = addr + 1024*1024

src_buffer = (ctypes.c_char * size).from_address(va_src)
dst_buffer = (ctypes.c_char * size).from_address(va_dst)


def test_throughput():
    for offset in range(0, 1024*1024, 4):
        src_buffer[offset:offset + 4] = (offset//4).to_bytes(4, byteorder="little")
        dst_buffer[offset:offset + 4] = (0).to_bytes(4, byteorder="little")
    
    
    src_buffer[:5] = b'Hello'  # 写入数据
    print(src_buffer[:10])       # 读取数据
    dst_buffer[:5] = b'world'  # 写入数据
    print(dst_buffer[:10])
    
    pa_src = va_to_pa(addr) # + 2
    
    pa_dst = va_to_pa(addr + 1024*1024) # + 3
    
    req_size = 4096
    stride_size = 0
    stride_cnt = 32

    double_channel_offset = 1024*512 # double channel test enabled
    # double_channel_offset = 0 # double channel test disabled
    
    with open('/sys/bus/pci/devices/0000:01:00.0/resource1', 'r+b') as f:
        # 将文件映射到内存
        with mmap.mmap(f.fileno(), 0) as mm:
    
            struct.pack_into('<I', mm, 0x4, pa_src & 0xFFFFFFFF)
            struct.pack_into('<I', mm, 0x8, pa_src >> 32)
            struct.pack_into('<I', mm, 0xc, pa_dst & 0xFFFFFFFF)
            struct.pack_into('<I', mm, 0x10, pa_dst >> 32)
            struct.pack_into('<I', mm, 0x14, req_size)
            struct.pack_into('<I', mm, 0x1c, stride_size)
            struct.pack_into('<I', mm, 0x20, stride_cnt)
            struct.pack_into('<I', mm, 0x24, 0b000_000)

            struct.pack_into('<I', mm, 0x28, double_channel_offset)  

            # struct.pack_into('<I', mm, 0x2C, 0b00)  # read write test
            # struct.pack_into('<I', mm, 0x2C, 0b01)  # read only test
            struct.pack_into('<I', mm, 0x2C, 0b10)  # write only test
    
            print(hex(struct.unpack_from('<I', mm, offset=0x4)[0]))
            print(hex(struct.unpack_from('<I', mm, offset=0x8)[0]))
            print(hex(struct.unpack_from('<I', mm, offset=0xc)[0]))
            print(hex(struct.unpack_from('<I', mm, offset=0x10)[0]))
            print(hex(struct.unpack_from('<I', mm, offset=0x14)[0]))
            
    
    
            last_time = time.time()
            iter_last_a = 1
            iter_now_a = 2
            iter_last_b = 1
            iter_now_b = 2
            for _ in range(1):
                struct.pack_into('<I', mm, 0x18, 0x1ffffff)
                iter_last_a = struct.unpack_from('<I', mm, offset=0x18)[0]
                iter_last_b = struct.unpack_from('<I', mm, offset=0x30)[0]
                while iter_last_a != 0 or iter_last_b != 0:
                
                    time.sleep(1)
                    iter_now_a = struct.unpack_from('<I', mm, offset=0x18)[0]
                    iter_now_b = struct.unpack_from('<I', mm, offset=0x30)[0]

                    now_time = time.time()
                
                    time_delta = now_time - last_time
                    iter_delta_a = iter_last_a - iter_now_a
                    iter_delta_b = iter_last_b - iter_now_b
                    iter_delta = iter_delta_a + iter_delta_b
                    speed = (iter_delta * req_size * 8) / time_delta / 1024 / 1024 / 1024
    
                    print(f"speed = {speed} Gbps, iter_left_a={iter_last_a}, iter_left_b={iter_last_b}")
                    iter_last_a = iter_now_a
                    iter_last_b = iter_now_b
                    last_time = now_time
    
    time.sleep(0.1)
    
    print(dst_buffer[:10])



def test_correct():
    for offset in range(0, 1024*1024, 1):
        src_buffer[offset] = offset % 256
        dst_buffer[offset] = 0
    
    
    
    pa_src = va_to_pa(addr)
    
    pa_dst = va_to_pa(addr + 1024*1024)
    
    
    with open('/sys/bus/pci/devices/0000:01:00.0/resource0', 'r+b') as f:
        # 将文件映射到内存
        with mmap.mmap(f.fileno(), 0) as mm:


            iter_last = struct.unpack_from('<I', mm, offset=0x18)[0]
            print(hex(iter_last))

            raise SystemExit




            last_time = time.time()
            iter_last = 1
            iter_now = 2
            for iter_idx in range(100):

                print(f"iter={iter_idx}")

                while True:
                    req_size = random.randint(1, 512)
                    stride_size = 0 #req_size
                    stride_cnt = 0 # random.randint(1, 8)

                    src_offset = random.randint(0, 511)
                    dst_offset = src_offset # random.randint(0, 1024*512)

                    if (req_size + src_offset <= 512):
                        break
                req_cnt = stride_cnt


                # req_size = 8 # random.randint(1, 4096)
                # stride_size = req_size
                # stride_cnt = 1 # random.randint(1, 8)
                
                # src_offset = 0 # random.randint(0, 1024*128)
                # dst_offset =  1 # random.randint(0, 1024*512)

                # req_cnt = stride_cnt

                struct.pack_into('<I', mm, 0x4, (pa_src + src_offset) & 0xFFFFFFFF)
                struct.pack_into('<I', mm, 0x8, pa_src >> 32)
                struct.pack_into('<I', mm, 0xc, (pa_dst + dst_offset) & 0xFFFFFFFF)
                struct.pack_into('<I', mm, 0x10, pa_dst >> 32)
                struct.pack_into('<I', mm, 0x14, req_size)
                struct.pack_into('<I', mm, 0x1c, stride_size)
                struct.pack_into('<I', mm, 0x20, stride_cnt)
                struct.pack_into('<I', mm, 0x24, 0b000)
                struct.pack_into('<I', mm, 0x28, 0b000)
                struct.pack_into('<I', mm, 0x2C, 0b000)   # read write
                struct.pack_into('<I', mm, 0x30, 0b000)

    
                print("srcAddrLowReg=", hex(struct.unpack_from('<I', mm, offset=0x4)[0]))
                print("srcAddrHighReg=", hex(struct.unpack_from('<I', mm, offset=0x8)[0]))
                print("dstAddrLowReg=", hex(struct.unpack_from('<I', mm, offset=0xc)[0]))
                print("dstAddrHighReg=", hex(struct.unpack_from('<I', mm, offset=0x10)[0]))
                print("lengthReg=", hex(struct.unpack_from('<I', mm, offset=0x14)[0]))
                print("batchTestCounterAReg=", hex(struct.unpack_from('<I', mm, offset=0x18)[0]))
                print("strideSizeReg=", hex(struct.unpack_from('<I', mm, offset=0x1C)[0]))
                print("maxStrideCntReg=", hex(struct.unpack_from('<I', mm, offset=0x20)[0]))
                print("attrReg=", hex(struct.unpack_from('<I', mm, offset=0x24)[0]))
                print("doubleChannelTestOffsetReg=", hex(struct.unpack_from('<I', mm, offset=0x28)[0]))
                print("testModeCtlReg=", hex(struct.unpack_from('<I', mm, offset=0x2C)[0]))
                print("batchTestCounterBReg=", hex(struct.unpack_from('<I', mm, offset=0x30)[0]))

                print(f"src_offset = {hex(src_offset)}, dst_offset = {hex(dst_offset)}, req_size={hex(req_size)}, stride_cnt={hex(stride_cnt)}, src_addr={hex(pa_src + src_offset)}, dst_addr={hex(pa_dst + dst_offset)}")
                # input("press enter to continue")
                struct.pack_into('<I', mm, 0x18, req_cnt)


                while iter_last != 0:
                    # time.sleep(1)
                    # input("press enter to continue")
                    iter_last = struct.unpack_from('<I', mm, offset=0x18)[0]
                    print(hex(iter_last))
                #input()
                #time.sleep(1)
                total_bytes_copy = req_size * req_cnt
    

                for offset in range(0, dst_offset, 1):
                    if dst_buffer[offset] != b'\x00':
                        print(f"should not be modified, dst_buffer[{hex(offset)})={hex(int.from_bytes(dst_buffer[offset], byteorder='little'))}")
                        # raise SystemExit

                
                for (s_offset, d_offset) in zip(range(src_offset, src_offset + total_bytes_copy, 1), range(dst_offset, dst_offset + total_bytes_copy, 1)):
                    if dst_buffer[d_offset] != src_buffer[s_offset]:
                        time.sleep(0.1) 
                        if dst_buffer[d_offset] != src_buffer[s_offset]:
                            print(f"not match, dst_buffer[{hex(d_offset)}]={hex(int.from_bytes(dst_buffer[d_offset], byteorder='little'))}, src_buffer[{hex(s_offset)}]={hex(int.from_bytes(src_buffer[s_offset],byteorder='little'))}")
                            # raise SystemExit
                    dst_buffer[d_offset] = 0

                for offset in range(dst_offset + total_bytes_copy, 1024 * 256, 1):
                    if dst_buffer[offset] != b'\x00':
                        print(f"should not be modified, dst_buffer[{hex(offset)})={hex(int.from_bytes(dst_buffer[offset], byteorder='little'))}")
                        # raise SystemExit



def pcie_p2p():

    for offset in range(0, 1024*1024, 1):
        src_buffer[offset] = 0
        dst_buffer[offset] = 0

    # pa_src = va_to_pa(addr)
    # pa_dst = 0xfb800000
    # src_offset =  0x00
    # dst_offset =  0x1048
    

    pa_src = 0xfb800000
    pa_dst = va_to_pa(addr + 1024*1024)
    src_offset =  0x1048
    dst_offset =  0x00

    with open('/sys/bus/pci/devices/0000:01:00.0/resource1', 'r+b') as f:
        # 将文件映射到内存
        with mmap.mmap(f.fileno(), 0) as mm:

            req_size =  4
            stride_size = 1
            stride_cnt =  1
            
            req_cnt = stride_cnt

            struct.pack_into('<I', mm, 0x4, (pa_src + src_offset) & 0xFFFFFFFF)
            struct.pack_into('<I', mm, 0x8, pa_src >> 32)
            struct.pack_into('<I', mm, 0xc, (pa_dst + dst_offset) & 0xFFFFFFFF)
            struct.pack_into('<I', mm, 0x10, pa_dst >> 32)
            struct.pack_into('<I', mm, 0x14, req_size)
            struct.pack_into('<I', mm, 0x1c, stride_size)
            struct.pack_into('<I', mm, 0x20, stride_cnt)

            print(f"src_offset = {hex(src_offset)}, dst_offset = {hex(dst_offset)}, req_size={hex(req_size)}, stride_cnt={hex(stride_cnt)}, src_addr={hex(pa_src + src_offset)}, dst_addr={hex(pa_dst + dst_offset)}")

            struct.pack_into('<I', mm, 0x18, req_cnt)

            time.sleep(0.01)

            total_bytes_copy = req_size * req_cnt

            print(f'read result =  {hex(int.from_bytes(dst_buffer[0:4],byteorder="little"))}')
    

def dump_csr():
    with open('/sys/bus/pci/devices/0000:01:00.0/resource0', 'r+b') as f:
        # 将文件映射到内存
        with mmap.mmap(f.fileno(), 0) as mm:
            print("CSR_WQE_RINGBUF_HEAD=", hex(struct.unpack_from('<I', mm, offset=(0x0002 << 2))[0]))
            print("CSR_WQE_RINGBUF_TAIL=", hex(struct.unpack_from('<I', mm, offset=(0x0003 << 2))[0]))

            print("CSR_META_REPORT_RINGBUF_HEAD=", hex(struct.unpack_from('<I', mm, offset=(0x0006 << 2))[0]))
            print("CSR_META_REPORT_RINGBUF_TAIL=", hex(struct.unpack_from('<I', mm, offset=(0x0007 << 2))[0]))


            for ch_idx in range(4):
                channel_offset = 0x0100 * ch_idx
                print(f"CSR_CH{ch_idx}_ETH_IO_DISCARD_PACKET_CNT=   ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0120) << 2))[0]))
                print(f"CSR_CH{ch_idx}_ETH_IO_SIMPLE_NIC_PACKET_CNT=", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0121) << 2))[0]))
                print(f"CSR_CH{ch_idx}_ETH_IO_RDMA_PACKET_CNT=      ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0122) << 2))[0]))
                print(f"CSR_CH{ch_idx}_ETH_IO_NOT_READY_PACKET_CNT= ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0123) << 2))[0]))

                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_INV_QP_ACCESS_FLAG_CNT= ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0100) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_INV_OPCODE_CNT=         ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0101) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_INV_MR_KEY_CNT=         ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0102) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_MEM_OOB_CNT=            ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0103) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_INV_MR_ACCESS_FLAG_CNT= ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0104) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_INV_HEADER_CNT=         ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0105) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_INV_QP_CTX_CNT=         ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0106) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_PKT_LEN_ERR_CNT=        ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0107) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_PACKET_VERIFY_UNKNOWN_ERR_CNT=        ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0108) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_DEBUG_COUNTER_1=                      ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x0109) << 2))[0]))
                print(f"CSR_CH{ch_idx}_RQ_DEBUG_QUEUE_FULL_FLAG=                ", hex(struct.unpack_from('<I', mm, offset=((channel_offset + 0x010a) << 2))[0]))


dump_csr()
# test_correct()
# test_throughput()
# pcie_p2p()


# 释放内存
libc.munmap(addr, size)

