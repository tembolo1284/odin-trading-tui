package client

import "core:net"
import "core:mem"
import "core:fmt"

// ============================================================================
// Transport Layer
// ============================================================================

TRANSPORT_MAX_MESSAGE_SIZE :: MAX_FRAMED_MESSAGE
TRANSPORT_RECV_BUFFER_SIZE :: 8192

// ============================================================================
// Transport Handle
// ============================================================================

Transport :: struct {
    type:               Transport_Type,
    host:               [256]u8,
    port:               u16,
    socket:             net.TCP_Socket,
    udp_socket:         net.UDP_Socket,
    endpoint:           net.Endpoint,
    state:              Conn_State,
    read_state:         Framing_Read_State,
    write_state:        Framing_Write_State,
    recv_buffer:        [TRANSPORT_RECV_BUFFER_SIZE]u8,
    recv_buffer_len:    uint,
    connect_timeout_ms: u32,
    recv_timeout_ms:    u32,
    bytes_sent:         u64,
    bytes_received:     u64,
    messages_sent:      u64,
    messages_received:  u64,
}

// ============================================================================
// Lifecycle
// ============================================================================

transport_init :: proc(t: ^Transport) {
    t^ = {}
    t.state = .Disconnected
    t.connect_timeout_ms = 5000
    t.recv_timeout_ms = 1000
    framing_read_init(&t.read_state)
    framing_write_init(&t.write_state)
}

transport_connect :: proc(
    t: ^Transport,
    host: string,
    port: u16,
    type: Transport_Type,
    timeout_ms: u32,
) -> bool {
    t.port = port
    t.connect_timeout_ms = timeout_ms
    copy_host(t.host[:], host)
    
    ep, ok := resolve_endpoint(host, port)
    if !ok {
        t.state = .Error
        return false
    }
    t.endpoint = ep
    
    actual_type := type
    
    // Auto-detect: try TCP first
    if type == .Auto {
        t.state = .Connecting
        if try_tcp_connect(t, timeout_ms) {
            actual_type = .Tcp
        } else {
            actual_type = .Udp
        }
    }
    
    if actual_type == .Tcp {
        if t.state != .Connected {
            if !try_tcp_connect(t, timeout_ms) {
                t.state = .Error
                return false
            }
        }
        t.type = .Tcp
    } else {
        if !try_udp_connect(t) {
            t.state = .Error
            return false
        }
        t.type = .Udp
    }
    
    t.state = .Connected
    return true
}

transport_disconnect :: proc(t: ^Transport) {
    if t.type == .Tcp && t.state == .Connected {
        net.close(t.socket)
    } else if t.type == .Udp && t.state == .Connected {
        net.close(t.udp_socket)
    }
    t.state = .Disconnected
    framing_read_reset(&t.read_state)
}

// ============================================================================
// TCP Connection
// ============================================================================

try_tcp_connect :: proc(t: ^Transport, timeout_ms: u32) -> bool {
    sock, err := net.create_socket(.IP4, .TCP)
    if err != nil {
        fmt.eprintln("Failed to create TCP socket:", err)
        return false
    }
    
    // TCP_NODELAY
    net.set_option(sock, .TCP_Nodelay, true)
    
    // Connect
    connect_err := net.connect(sock, t.endpoint)
    if connect_err != nil {
        fmt.eprintln("Failed to connect:", connect_err)
        net.close(sock)
        return false
    }
    
    t.socket = sock
    t.state = .Connected
    return true
}

// ============================================================================
// UDP Connection
// ============================================================================

try_udp_connect :: proc(t: ^Transport) -> bool {
    sock, err := net.create_socket(.IP4, .UDP)
    if err != nil {
        fmt.eprintln("Failed to create UDP socket:", err)
        return false
    }
    
    t.udp_socket = sock
    return true
}

// ============================================================================
// Send
// ============================================================================

transport_send :: proc(t: ^Transport, data: []u8) -> bool {
    if t.state != .Connected {
        return false
    }
    
    if t.type == .Tcp {
        return tcp_send_framed(t, data)
    } else {
        return udp_send(t, data)
    }
}

tcp_send_framed :: proc(t: ^Transport, data: []u8) -> bool {
    framed := framing_encode(&t.write_state, data)
    if framed == nil {
        return false
    }
    
    sent := 0
    for sent < len(framed) {
        n, err := net.send(t.socket, framed[sent:])
        if err != nil {
            fmt.eprintln("Send error:", err)
            t.state = .Error
            return false
        }
        sent += n
    }
    
    t.bytes_sent += u64(len(framed))
    t.messages_sent += 1
    return true
}

udp_send :: proc(t: ^Transport, data: []u8) -> bool {
    n, err := net.send_to(t.udp_socket, data, t.endpoint)
    if err != nil {
        fmt.eprintln("UDP send error:", err)
        return false
    }
    
    t.bytes_sent += u64(n)
    t.messages_sent += 1
    return true
}

// ============================================================================
// Receive
// ============================================================================

transport_recv :: proc(
    t: ^Transport,
    buffer: []u8,
    timeout_ms: int,
) -> int {
    if t.state != .Connected {
        return -1
    }
    
    if t.type == .Tcp {
        return tcp_recv_framed(t, buffer, timeout_ms)
    } else {
        return udp_recv(t, buffer, timeout_ms)
    }
}

tcp_recv_framed :: proc(t: ^Transport, buffer: []u8, timeout_ms: int) -> int {
    // First try to extract from existing buffer
    result, msg_len := framing_try_extract(&t.read_state, buffer)
    if result == .Complete {
        t.bytes_received += u64(msg_len)
        t.messages_received += 1
        return int(msg_len)
    }
    if result == .Error {
        t.state = .Error
        return -1
    }
    
    // Need more data
    recv_buf: [4096]u8
    n, err := net.recv(t.socket, recv_buf[:])
    if err != nil {
        // Check for timeout/would block
        if err == net.TCP_Recv_Error.Timeout {
            return 0
        }
        fmt.eprintln("Recv error:", err)
        t.state = .Error
        return -1
    }
    
    if n == 0 {
        t.state = .Disconnected
        return -1
    }
    
    // Feed to framing
    if !framing_feed(&t.read_state, recv_buf[:n]) {
        t.state = .Error
        return -1
    }
    
    // Try extract again
    result, msg_len = framing_try_extract(&t.read_state, buffer)
    if result == .Complete {
        t.bytes_received += u64(msg_len)
        t.messages_received += 1
        return int(msg_len)
    }
    if result == .Error {
        t.state = .Error
        return -1
    }
    
    return 0  // Incomplete
}

udp_recv :: proc(t: ^Transport, buffer: []u8, timeout_ms: int) -> int {
    n, _, err := net.recv_from(t.udp_socket, buffer)
    if err != nil {
        return 0
    }
    
    t.bytes_received += u64(n)
    t.messages_received += 1
    return n
}

// ============================================================================
// Utilities
// ============================================================================

transport_is_connected :: proc(t: ^Transport) -> bool {
    return t.state == .Connected
}

transport_get_type :: proc(t: ^Transport) -> Transport_Type {
    return t.type
}

transport_has_data :: proc(t: ^Transport) -> bool {
    if t.type == .Tcp {
        return framing_has_pending(&t.read_state)
    }
    return false
}

copy_host :: proc(dest: []u8, src: string) {
    n := min(len(dest) - 1, len(src))
    for i in 0..<n {
        dest[i] = src[i]
    }
    dest[n] = 0
}

resolve_endpoint :: proc(host: string, port: u16) -> (net.Endpoint, bool) {
    // Try parsing as IP first
    addr, ok := net.parse_address(host)
    if ok {
        return net.Endpoint{addr, int(port)}, true
    }
    
    // Try localhost specially
    if host == "localhost" {
        addr4 := net.IP4_Address{127, 0, 0, 1}
        return net.Endpoint{addr4, int(port)}, true
    }
    
    // Try DNS resolution
    addrs, err := net.resolve(host)
    if err != nil || len(addrs) == 0 {
        return {}, false
    }
    defer delete(addrs)
    
    return net.Endpoint{addrs[0], int(port)}, true
}
