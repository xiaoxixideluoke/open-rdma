#!/usr/bin/env python3
# coding:utf-8

"""
Test script for EthPacketTcp class
"""

import sys
import os
import time
import threading
import base64

# Add the test_framework directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), 'test_framework'))

from mock_host import EthPacketTcp


def test_server_client():
    """Test basic server-client communication"""
    print("=== Testing EthPacketTcp Server-Client Communication ===")

    # Test data
    test_packets = [
        b"Hello, World!",
        b"This is a test packet",
        b"\x00\x01\x02\x03\x04\x05",  # Binary data
        b"A" * 1000,  # Large packet
    ]

    # Create server and client
    server = EthPacketTcp("1", host='127.0.0.1', port=19999)
    time.sleep(0.1)  # Give server time to start
    client = EthPacketTcp("2", host='127.0.0.1', port=19999)

    # Wait for connection to establish
    time.sleep(0.5)

    # Test client to server communication
    print("\n--- Client -> Server ---")
    for i, packet in enumerate(test_packets):
        print(f"Sending packet {i+1}: {packet[:30]}{'...' if len(packet) > 30 else ''}")
        client.send_packet(packet)

    # Receive packets on server
    time.sleep(0.2)  # Give time for packets to be transferred
    received_count = 0
    while True:
        recv_packet = server.recv_packet()
        if recv_packet is None:
            break
        print(f"Received packet {received_count+1}: {recv_packet[:30]}{'...' if len(recv_packet) > 30 else ''}")

        # Verify packet matches
        if recv_packet == test_packets[received_count]:
            print(f"✓ Packet {received_count+1} matches original")
        else:
            print(f"✗ Packet {received_count+1} does NOT match original")

        received_count += 1
        if received_count >= len(test_packets):
            break

    print(f"\nClient->Server: {received_count}/{len(test_packets)} packets received successfully")

    # Test server to client communication
    print("\n--- Server -> Client ---")
    for i, packet in enumerate(test_packets):
        print(f"Sending packet {i+1}: {packet[:30]}{'...' if len(packet) > 30 else ''}")
        server.send_packet(packet)

    # Receive packets on client
    time.sleep(0.2)  # Give time for packets to be transferred
    received_count = 0
    while True:
        recv_packet = client.recv_packet()
        if recv_packet is None:
            break
        print(f"Received packet {received_count+1}: {recv_packet[:30]}{'...' if len(recv_packet) > 30 else ''}")

        # Verify packet matches
        if recv_packet == test_packets[received_count]:
            print(f"✓ Packet {received_count+1} matches original")
        else:
            print(f"✗ Packet {received_count+1} does NOT match original")

        received_count += 1
        if received_count >= len(test_packets):
            break

    print(f"\nServer->Client: {received_count}/{len(test_packets)} packets received successfully")

    # Clean up
    print("\n--- Cleanup ---")
    server.close()
    client.close()
    print("Test completed!")


def test_base64_encoding():
    """Test that base64 encoding works correctly"""
    print("\n=== Testing Base64 Encoding ===")

    test_data = [
        b"Simple text",
        b"\x00\xff\x80\x7f",  # Binary data with edge cases
        b"",  # Empty data
        b"A" * 100,  # Repeated character
    ]

    server = EthPacketTcp("1", host='127.0.0.1', port=29999)
    time.sleep(0.1)
    client = EthPacketTcp("2", host='127.0.0.1', port=29999)

    # Wait for connection
    time.sleep(0.5)

    for i, data in enumerate(test_data):
        print(f"Test {i+1}: {data[:20]}{'...' if len(data) > 20 else ''}")

        # Send from client to server
        client.send_packet(data)

        # Receive on server
        time.sleep(0.1)
        received = server.recv_packet()

        if received == data:
            print(f"✓ Base64 encoding/decoding successful")
        else:
            print(f"✗ Base64 encoding/decoding failed")
            print(f"  Original: {data}")
            print(f"  Received: {received}")

    server.close()
    client.close()


if __name__ == "__main__":
    try:
        test_server_client()
        test_base64_encoding()
        print("\n🎉 All tests completed!")
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    except Exception as e:
        print(f"\n❌ Test failed with error: {e}")
        import traceback
        traceback.print_exc()