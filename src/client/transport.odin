package client
// =============================================================================
// Transport Layer
//
// Provides TCP and UDP transport with:
//   - Auto-detection (try TCP first, fall back to UDP)
//   - TCP length-prefix framing
//   - UDP datagram mode
// =============================================================================
import "core:fmt"
import "core:mem"
import "core:net"
import "core:time"

// =============================================================================
// Constants
// =============================================================================
TRANSPORT_MAX_MESSAGE_SIZE :: MAX_FRAMED_MESSAGE_SIZE
TRANSPORT_RECV_BUFFER_SIZE :: 8192

// =============================================================================
// Transport State
// =============================================================================
Transport :: struct {
    // Configuration
    type:     Transport_Type,
    host:     [MAX_HOST_LEN]u8,
    port:     u16,
    // Socket state
    socket:      net.TCP_Socket,
    udp_socket:  net.UDP_Socket,
    server_addr: net.Endpoint,
    state:       Conn_State,
    // TCP framing state
    read_state: Framing_Read_State,
    // Receive buffer
    recv_buffer:     [TRANSPORT_RECV_BUFFER_SIZE]u8,
    recv_buffer_len: int,
    // Timeouts
    connect_timeout_ms: u32,
    recv_timeout_ms:    u32,
    // Statistics
    bytes_sent:        u64,
    bytes_received:    u64,
    messages_sent:     u64,
    messages_received: u64,
}

// =============================================================================
// Initialization
// =============================================================================
transport_init :: proc(t: ^Transport) {
    t^ = {}
    t.state = .Disconnected
    t.connect_timeout_ms = DEFAULT_TIMEOUT_MS
    t.recv_timeout_ms = DEFAULT_TIMEOUT_MS
    framing_read_state_init(&t.read_state)
}

// =============================================================================
// Connection
// =============================================================================
// Connect to server
// Returns true on success
transport_connect :: proc(
    t: ^Transport,
    host: string,
    port: u16,
    transport_type: Transport_Type,
    timeout_ms: u32,
) -> bool {
    // Store config
    copy_symbol(t.host[:], host)
    t.port = port
    t.connect_timeout_ms = timeout_ms

    // Resolve host
    endpoint, ok := resolve_endpoint(host, port)
    if !ok {
        fmt.eprintf("Failed to resolve host: %s\n", host)
        return false
    }
    t.server_addr = endpoint
    t.state = .Connecting

    if transport_type == .TCP {
        return try_tcp_connect(t, timeout_ms)
    } else if transport_type == .UDP {
        return setup_udp(t)
    } else {
        // Auto: try TCP first, fall back to UDP
        if try_tcp_connect(t, timeout_ms) {
            return true
        }
        return setup_udp(t)
    }
}

// Try TCP connection
try_tcp_connect :: proc(t: ^Transport, timeout_ms: u32) -> bool {
    // Use dial_tcp_from_endpoint which handles connect internally
    sock, err := net.dial_tcp_from_endpoint(t.server_addr)
    if err != nil {
        return false
    }

    // Set TCP_NODELAY for low latency
    net.set_option(sock, .TCP_Nodelay, true)

    t.socket = sock
    t.type = .TCP
    t.state = .Connected
    framing_read_state_init(&t.read_state)
    return true
}

// Setup UDP socket
setup_udp :: proc(t: ^Transport) -> bool {
    sock, err := net.make_unbound_udp_socket(.IP4)
    if err != nil {
        return false
    }
    t.udp_socket = sock
    t.type = .UDP
    t.state = .Connected
    return true
}

// Disconnect
transport_disconnect :: proc(t: ^Transport) {
    if t.state != .Disconnected {
        if t.type == .TCP {
            net.close(t.socket)
        } else {
            net.close(t.udp_socket)
        }
    }
    t.state = .Disconnected
}

// =============================================================================
// Send/Receive
// =============================================================================
// Send data
// For TCP: adds length-prefix framing
// For UDP: sends as datagram
transport_send :: proc(t: ^Transport, data: []u8) -> bool {
    if t.state != .Connected {
        return false
    }

    if t.type == .TCP {
        // Frame the message
        framed: [FRAMING_BUFFER_SIZE]u8
        framed_data, ok := frame_message(data, framed[:])
        if !ok {
            return false
        }

        // Send framed data
        total_sent := 0
        for total_sent < len(framed_data) {
            sent, err := net.send_tcp(t.socket, framed_data[total_sent:])
            if err != nil {
                return false
            }
            total_sent += sent
        }
        t.bytes_sent += u64(len(framed_data))
    } else {
        // UDP: send as datagram
        sent, err := net.send_udp(t.udp_socket, data, t.server_addr)
        if err != nil || sent != len(data) {
            return false
        }
        t.bytes_sent += u64(len(data))
    }
    t.messages_sent += 1
    return true
}

// Receive a complete message
// For TCP: handles framing
// For UDP: returns single datagram
// timeout_ms: 0 = non-blocking, -1 = block forever
transport_recv :: proc(t: ^Transport, buffer: []u8, timeout_ms: int = 0) -> ([]u8, bool) {
    if t.state != .Connected {
        return nil, false
    }

    if t.type == .TCP {
        return tcp_recv(t, buffer, timeout_ms)
    } else {
        return udp_recv(t, buffer, timeout_ms)
    }
}

// TCP receive with framing
tcp_recv :: proc(t: ^Transport, buffer: []u8, timeout_ms: int) -> ([]u8, bool) {
    // First check if we already have a complete message
    result, msg := framing_read_extract(&t.read_state)
    if result == .Message_Ready {
        if len(msg) > len(buffer) {
            return nil, false
        }
        mem.copy(raw_data(buffer), raw_data(msg), len(msg))
        t.messages_received += 1
        return buffer[:len(msg)], true
    }

    // Need to read more data
    // Set timeout (simplified - would use poll in production)
    if timeout_ms == 0 {
        net.set_blocking(t.socket, false)
    } else {
        net.set_blocking(t.socket, true)
    }

    recv_buf: [TRANSPORT_RECV_BUFFER_SIZE]u8
    received, err := net.recv_tcp(t.socket, recv_buf[:])
    if err != nil || received <= 0 {
        if received == 0 {
            t.state = .Disconnected
        }
        return nil, false
    }
    t.bytes_received += u64(received)

    // Append to framing buffer
    framing_read_append(&t.read_state, recv_buf[:received])

    // Try to extract message again
    result, msg = framing_read_extract(&t.read_state)
    if result == .Message_Ready {
        if len(msg) > len(buffer) {
            return nil, false
        }
        mem.copy(raw_data(buffer), raw_data(msg), len(msg))
        t.messages_received += 1
        return buffer[:len(msg)], true
    }
    return nil, false
}

// UDP receive
udp_recv :: proc(t: ^Transport, buffer: []u8, timeout_ms: int) -> ([]u8, bool) {
    if timeout_ms == 0 {
        net.set_blocking(t.udp_socket, false)
    } else {
        net.set_blocking(t.udp_socket, true)
    }

    received, _, err := net.recv_udp(t.udp_socket, buffer)
    if err != nil || received <= 0 {
        return nil, false
    }

    t.bytes_received += u64(received)
    t.messages_received += 1
    return buffer[:received], true
}

// Check if data is available
transport_has_data :: proc(t: ^Transport) -> bool {
    if t.state != .Connected {
        return false
    }

    // Check framing buffer first (TCP)
    if t.type == .TCP && framing_read_has_data(&t.read_state) {
        return true
    }

    // Would need poll() to check socket without blocking
    // For simplicity, return false here
    return false
}

// =============================================================================
// Utilities
// =============================================================================
transport_get_type :: proc(t: ^Transport) -> Transport_Type {
    return t.type
}

transport_is_connected :: proc(t: ^Transport) -> bool {
    return t.state == .Connected
}

transport_print_stats :: proc(t: ^Transport) {
    fmt.println("Transport Statistics:")
    fmt.printf("  Type:              %s\n", transport_type_str(t.type))
    fmt.printf("  State:             %s\n",
        t.state == .Connected ? "connected" : "disconnected")
    fmt.printf("  Messages sent:     %d\n", t.messages_sent)
    fmt.printf("  Messages received: %d\n", t.messages_received)
    fmt.printf("  Bytes sent:        %d\n", t.bytes_sent)
    fmt.printf("  Bytes received:    %d\n", t.bytes_received)
}

// =============================================================================
// Host Resolution
// =============================================================================
resolve_endpoint :: proc(host: string, port: u16) -> (net.Endpoint, bool) {
    // Try parsing as IP first
    addr := net.parse_address(host)
    if addr != nil {
        return net.Endpoint{addr, int(port)}, true
    }

    // Try DNS resolution - resolve returns (Endpoint, Endpoint, error)
    ip4_endpoint, _, err := net.resolve(host)
    if err != nil {
        return {}, false
    }
    
    // Use the resolved address but override the port
    return net.Endpoint{ip4_endpoint.address, int(port)}, true
}
