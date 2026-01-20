package client
// =============================================================================
// Multicast Receiver
//
// For subscribing to market data multicast feeds.
// =============================================================================
import "core:fmt"
import "core:net"

// =============================================================================
// Multicast Receiver State
// =============================================================================
Multicast_Receiver :: struct {
    socket:     net.UDP_Socket,
    group:      [64]u8,
    port:       u16,
    joined:     bool,
    // Receive buffer
    recv_buffer: [TRANSPORT_RECV_BUFFER_SIZE]u8,
    // Statistics
    packets_received: u64,
    bytes_received:   u64,
}

// =============================================================================
// Multicast API
// =============================================================================
multicast_receiver_init :: proc(m: ^Multicast_Receiver) {
    m^ = {}
    m.joined = false
}

// Join multicast group
multicast_receiver_join :: proc(m: ^Multicast_Receiver, group: string, port: u16) -> bool {
    copy_symbol(m.group[:], group)
    m.port = port

    // Create bound UDP socket
    bind_addr := net.IP4_Address{0, 0, 0, 0}
    sock, err := net.make_bound_udp_socket(bind_addr, int(port))
    if err != nil {
        fmt.eprintln("multicast socket/bind error")
        return false
    }

    // Allow multiple subscribers
    net.set_option(sock, .Reuse_Address, true)

    // Join multicast group would require platform-specific setsockopt
    // This is a simplified implementation
    // In production, use IP_ADD_MEMBERSHIP via foreign bindings

    m.socket = sock
    m.joined = true
    return true
}

// Leave multicast group
multicast_receiver_leave :: proc(m: ^Multicast_Receiver) {
    if m.joined {
        net.close(m.socket)
        m.joined = false
    }
}

// Receive multicast packet
multicast_receiver_recv :: proc(
    m: ^Multicast_Receiver,
    buffer: []u8,
    timeout_ms: int,
) -> ([]u8, bool) {
    if !m.joined {
        return nil, false
    }

    if timeout_ms == 0 {
        net.set_blocking(m.socket, false)
    } else {
        net.set_blocking(m.socket, true)
    }

    received, _, err := net.recv_udp(m.socket, buffer)
    if err != nil || received <= 0 {
        return nil, false
    }

    m.packets_received += 1
    m.bytes_received += u64(received)
    return buffer[:received], true
}

multicast_receiver_print_stats :: proc(m: ^Multicast_Receiver) {
    fmt.println("Multicast Statistics:")
    fmt.printf("  Group:             %s:%d\n", symbol_to_string(m.group[:]), m.port)
    fmt.printf("  Joined:            %s\n", m.joined ? "yes" : "no")
    fmt.printf("  Packets received:  %d\n", m.packets_received)
    fmt.printf("  Bytes received:    %d\n", m.bytes_received)
}
