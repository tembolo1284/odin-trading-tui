package client

import "core:net"
import "core:c"
import "core:sys/posix"

// ============================================================================
// Multicast Receiver
//
// For subscribing to market data broadcasts from the matching engine
// Matches your multicast_subscriber.c
// ============================================================================

MULTICAST_RECV_BUFFER_SIZE :: 8192

// ============================================================================
// Multicast Receiver Handle
// ============================================================================

Multicast_Receiver :: struct {
    socket:           net.UDP_Socket,
    group:            [64]u8,
    port:             u16,
    joined:           bool,
    
    // Receive buffer
    recv_buffer:      [MULTICAST_RECV_BUFFER_SIZE]u8,
    
    // Statistics
    packets_received: u64,
    bytes_received:   u64,
}

// ============================================================================
// Lifecycle
// ============================================================================

multicast_receiver_init :: proc(m: ^Multicast_Receiver) {
    m^ = {}
}

// Join multicast group
multicast_receiver_join :: proc(
    m: ^Multicast_Receiver,
    group: string,
    port: u16,
) -> bool {
    if m.joined {
        return true
    }
    
    // Store group address
    copy_host(m.group[:], group)
    m.port = port
    
    // Create UDP socket
    sock, err := net.create_socket(.IP4, .UDP)
    if err != nil {
        return false
    }
    
    // Allow address reuse
    net.set_option(sock, .Reuse_Address, true)
    
    // Bind to port
    bind_ep := net.Endpoint{
        address = net.IP4_Any,
        port = int(port),
    }
    
    bind_err := net.bind(sock, bind_ep)
    if bind_err != nil {
        net.close(sock)
        return false
    }
    
    // Join multicast group using raw setsockopt
    // Odin's net package doesn't have multicast helpers, so we use posix
    if !join_multicast_group(sock, group) {
        net.close(sock)
        return false
    }
    
    m.socket = sock
    m.joined = true
    return true
}

// Leave multicast group
multicast_receiver_leave :: proc(m: ^Multicast_Receiver) {
    if !m.joined {
        return
    }
    
    // Leave group (optional, closing socket does this)
    net.close(m.socket)
    m.joined = false
}

// ============================================================================
// Receive
// ============================================================================

// Receive multicast packet
// Returns bytes received, 0 on timeout, -1 on error
multicast_receiver_recv :: proc(
    m: ^Multicast_Receiver,
    buffer: []u8,
    timeout_ms: int,
) -> int {
    if !m.joined {
        return -1
    }
    
    // Note: proper timeout would use poll/select
    n, _, err := net.recv_from(m.socket, buffer)
    
    if err != nil {
        if err == .Timeout {
            return 0
        }
        return -1
    }
    
    m.packets_received += 1
    m.bytes_received += u64(n)
    
    return n
}

// ============================================================================
// Utilities
// ============================================================================

multicast_receiver_is_joined :: proc(m: ^Multicast_Receiver) -> bool {
    return m.joined
}

multicast_receiver_get_stats :: proc(m: ^Multicast_Receiver) -> (packets: u64, bytes: u64) {
    return m.packets_received, m.bytes_received
}

// ============================================================================
// Low-level Multicast Join
//
// Uses POSIX setsockopt since Odin's net package doesn't expose this
// ============================================================================

// IP_ADD_MEMBERSHIP structure
IP_Mreq :: struct {
    imr_multiaddr: u32,  // Multicast group address (network byte order)
    imr_interface: u32,  // Local interface (INADDR_ANY = 0)
}

IPPROTO_IP       :: 0
IP_ADD_MEMBERSHIP :: 35  // Linux value, may differ on other platforms

join_multicast_group :: proc(sock: net.UDP_Socket, group: string) -> bool {
    // Parse multicast address
    addr, ok := net.parse_address(group)
    if !ok {
        return false
    }
    
    // Extract IPv4 address bytes
    ip4, is_ip4 := addr.(net.IP4_Address)
    if !is_ip4 {
        return false
    }
    
    // Build mreq structure
    mreq: IP_Mreq
    mreq.imr_multiaddr = (u32(ip4[0])) |
                         (u32(ip4[1]) << 8) |
                         (u32(ip4[2]) << 16) |
                         (u32(ip4[3]) << 24)
    mreq.imr_interface = 0  // INADDR_ANY
    
    // Get raw file descriptor from socket
    // Note: This is platform-specific, Odin's net.UDP_Socket wraps the fd
    fd := get_socket_fd(sock)
    
    // Call setsockopt
    result := posix.setsockopt(
        posix.FD(fd),
        posix.IPPROTO_IP,
        posix.IP_ADD_MEMBERSHIP,
        &mreq,
        size_of(IP_Mreq),
    )
    
    return result == .OK
}

// Extract raw file descriptor from Odin socket
// This is a bit of a hack - Odin's net package stores fd internally
get_socket_fd :: proc(sock: net.UDP_Socket) -> i32 {
    // net.UDP_Socket is an alias for net.Socket which wraps the fd
    // The actual implementation depends on Odin version
    // This assumes the socket struct has the fd as first field
    return i32(transmute(uintptr)sock)
}

// ============================================================================
// Multicast Address Validation
// ============================================================================

// Check if address is in multicast range (224.0.0.0 - 239.255.255.255)
is_multicast_address :: proc(addr: string) -> bool {
    parsed, ok := net.parse_address(addr)
    if !ok {
        return false
    }
    
    ip4, is_ip4 := parsed.(net.IP4_Address)
    if !is_ip4 {
        return false
    }
    
    // Multicast range: 224.x.x.x to 239.x.x.x
    return ip4[0] >= 224 && ip4[0] <= 239
}
