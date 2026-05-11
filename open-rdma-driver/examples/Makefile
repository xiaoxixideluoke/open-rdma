CC = gcc
CFLAGS = -Wall -Wextra -g
LDFLAGS =
LIBS = -libverbs
# TODO 需要实现完整的 CI 测试
# Support for additional compiler flags if needed
ifneq ($(EXTRA_CFLAGS),)
CFLAGS += $(EXTRA_CFLAGS)
endif

TARGETS = loopback send_recv rdma_client_server

all: $(TARGETS)

loopback: loopback.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LIBS)

send_recv: send_recv.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LIBS)

rdma_client_server: rdma_client_server.c
	$(CC) $(CFLAGS) $< -o $@ $(LDFLAGS) $(LIBS)

clean:
	rm -f $(TARGETS)

run_loopback: loopback
	echo 1 > /sys/bus/pci/devices/0000\:01\:00.0/remove ; \
	echo 1 > /sys/bus/pci/rescan ; \
	setpci  -s 01:00.0 COMMAND=0x02 && \
	setpci  -s 01:00.0 98.b=0x16 && \
	setpci  -s 01:00.0 CAP_EXP+28.w=0x1000 && \
	export LD_LIBRARY_PATH=../dtld-ibverbs/target/debug:../dtld-ibverbs/rdma-core-55.0/build/lib && \
	RUST_LOG=debug ./loopback 1
	

.PHONY: all clean loopback send_recv rdma_client_server
