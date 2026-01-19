package client

import "core:mem"

// ============================================================================
// TCP Length-Prefix Framing
//
// Format: [4-byte BIG-ENDIAN length][payload]
// This matches your message_framing.h (network byte order)
// ============================================================================

FRAME_HEADER_SIZE     :: 4
MAX_FRAMED_MESSAGE    :: 4096
FRAMING_BUFFER_SIZE   :: 8192

// ============================================================================
// Read State
// ============================================================================

Framing_Read_State :: struct {
    buffer:          [FRAMING_BUFFER_SIZE]u8,
    buffer_len:      uint,
    msg_len:         u32,
    header_complete: bool,
}

// ============================================================================
// Write State
// ============================================================================

Framing_Write_State :: struct {
    buffer:     [MAX_FRAMED_MESSAGE + FRAME_HEADER_SIZE]u8,
    buffer_len: uint,
}

// ============================================================================
// Lifecycle
// ============================================================================

framing_read_init :: proc(state: ^Framing_Read_State) {
    state^ = {}
}

framing_write_init :: proc(state: ^Framing_Write_State) {
    state^ = {}
}

framing_read_reset :: proc(state: ^Framing_Read_State) {
    state.buffer_len = 0
    state.msg_len = 0
    state.header_complete = false
}

// ============================================================================
// Writing (add length prefix - BIG ENDIAN)
// ============================================================================

framing_encode :: proc(state: ^Framing_Write_State, payload: []u8) -> []u8 {
    if len(payload) > MAX_FRAMED_MESSAGE {
        return nil
    }
    
    // Write length prefix (BIG-ENDIAN / network byte order)
    length := u32(len(payload))
    state.buffer[0] = u8(length >> 24)
    state.buffer[1] = u8(length >> 16)
    state.buffer[2] = u8(length >> 8)
    state.buffer[3] = u8(length)
    
    // Copy payload
    mem.copy(&state.buffer[FRAME_HEADER_SIZE], raw_data(payload), len(payload))
    
    state.buffer_len = uint(FRAME_HEADER_SIZE + len(payload))
    return state.buffer[:state.buffer_len]
}

// ============================================================================
// Reading
// ============================================================================

Framing_Result :: enum {
    Complete,
    Incomplete,
    Error,
}

framing_feed :: proc(state: ^Framing_Read_State, data: []u8) -> bool {
    if state.buffer_len + uint(len(data)) > FRAMING_BUFFER_SIZE {
        return false
    }
    
    mem.copy(&state.buffer[state.buffer_len], raw_data(data), len(data))
    state.buffer_len += uint(len(data))
    return true
}

framing_try_extract :: proc(
    state: ^Framing_Read_State,
    out_msg: []u8,
) -> (Framing_Result, uint) {
    if state.buffer_len < FRAME_HEADER_SIZE {
        return .Incomplete, 0
    }
    
    // Parse length (BIG-ENDIAN / network byte order)
    if !state.header_complete {
        state.msg_len = (u32(state.buffer[0]) << 24) |
                        (u32(state.buffer[1]) << 16) |
                        (u32(state.buffer[2]) << 8) |
                        (u32(state.buffer[3]))
        
        if state.msg_len > MAX_FRAMED_MESSAGE {
            return .Error, 0
        }
        
        state.header_complete = true
    }
    
    total_needed := uint(FRAME_HEADER_SIZE) + uint(state.msg_len)
    
    if state.buffer_len < total_needed {
        return .Incomplete, 0
    }
    
    if uint(len(out_msg)) < uint(state.msg_len) {
        return .Error, 0
    }
    
    msg_len := uint(state.msg_len)
    mem.copy(raw_data(out_msg), &state.buffer[FRAME_HEADER_SIZE], int(msg_len))
    
    // Shift remaining data
    remaining := state.buffer_len - total_needed
    if remaining > 0 {
        mem.copy(&state.buffer[0], &state.buffer[total_needed], int(remaining))
    }
    state.buffer_len = remaining
    state.header_complete = false
    state.msg_len = 0
    
    return .Complete, msg_len
}

framing_has_pending :: proc(state: ^Framing_Read_State) -> bool {
    return state.buffer_len >= FRAME_HEADER_SIZE
}

framing_buffer_used :: proc(state: ^Framing_Read_State) -> uint {
    return state.buffer_len
}
