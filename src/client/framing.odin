package client

import "core:os"

// ============================================================================
// Length-prefixed framing for TCP transport
// Frame format: [u32 big-endian length][payload]
// ============================================================================

FRAME_HEADER_SIZE :: 4
MAX_FRAME_SIZE    :: 4 * 16384  // 65536 bytes, matches Zig server

// ============================================================================
// Big-endian helpers (shared across package)
// ============================================================================

write_u32_be :: proc(buf: []u8, v: u32) {
    buf[0] = u8(v >> 24)
    buf[1] = u8(v >> 16)
    buf[2] = u8(v >> 8)
    buf[3] = u8(v)
}

read_u32_be :: proc(buf: []u8) -> u32 {
    return (u32(buf[0]) << 24) | (u32(buf[1]) << 16) | (u32(buf[2]) << 8) | u32(buf[3])
}

// ============================================================================
// Low-level I/O
// ============================================================================

// Write exactly len(data) bytes to fd
write_all :: proc(fd: os.Handle, data: []u8) -> bool {
    sent := 0
    for sent < len(data) {
        n, err := os.write(fd, data[sent:])
        if err != os.ERROR_NONE || n <= 0 {
            return false
        }
        sent += n
    }
    return true
}

// Read exactly len(buf) bytes from fd
read_exact :: proc(fd: os.Handle, buf: []u8) -> bool {
    got := 0
    for got < len(buf) {
        n, err := os.read(fd, buf[got:])
        if err != os.ERROR_NONE || n <= 0 {
            return false
        }
        got += n
    }
    return true
}

// ============================================================================
// Framed send/recv
// ============================================================================

// Send one framed message: [u32be length][payload]
send_frame :: proc(fd: os.Handle, payload: []u8) -> bool {
    if len(payload) > MAX_FRAME_SIZE {
        return false
    }
    
    hdr: [FRAME_HEADER_SIZE]u8
    write_u32_be(hdr[:], u32(len(payload)))
    
    if !write_all(fd, hdr[:]) {
        return false
    }
    if !write_all(fd, payload) {
        return false
    }
    return true
}

// Receive one framed message into scratch buffer
// Returns (payload_length, success)
recv_frame :: proc(fd: os.Handle, scratch: []u8) -> (int, bool) {
    hdr: [FRAME_HEADER_SIZE]u8
    if !read_exact(fd, hdr[:]) {
        return 0, false
    }
    
    n := read_u32_be(hdr[:])
    if n == 0 || n > MAX_FRAME_SIZE {
        return 0, false
    }
    if int(n) > len(scratch) {
        return 0, false
    }
    if !read_exact(fd, scratch[:int(n)]) {
        return 0, false
    }
    
    return int(n), true
}
