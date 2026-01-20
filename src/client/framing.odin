package client

// =============================================================================
// Message Framing for TCP Streams
//
// Handles length-prefixed message framing.
// Format: [4-byte big-endian length][payload]
// =============================================================================

import "core:mem"

// =============================================================================
// Constants
// =============================================================================

FRAME_HEADER_SIZE        :: 4
MAX_FRAMED_MESSAGE_SIZE  :: 4096
FRAMING_BUFFER_SIZE      :: MAX_FRAMED_MESSAGE_SIZE + FRAME_HEADER_SIZE + 256

// =============================================================================
// Result Codes
// =============================================================================

Framing_Result :: enum {
    Ok,
    Need_More_Data,
    Message_Ready,
    Error,
}

// =============================================================================
// Read-side State
// =============================================================================

Framing_Read_State :: struct {
    buffer:          [FRAMING_BUFFER_SIZE]u8,
    extract_buffer:  [MAX_FRAMED_MESSAGE_SIZE]u8,
    buffer_pos:      int,
    expected_length: u32,
    reading_header:  bool,
}

// =============================================================================
// Write-side State
// =============================================================================

Framing_Write_State :: struct {
    buffer:        [FRAMING_BUFFER_SIZE]u8,
    total_len:     int,
    bytes_written: int,
}

// =============================================================================
// Read-side API
// =============================================================================

framing_read_state_init :: proc(state: ^Framing_Read_State) {
    state^ = {}
    state.reading_header = true
}

// Append received data to the framing buffer
// Returns number of bytes consumed
framing_read_append :: proc(state: ^Framing_Read_State, data: []u8) -> int {
    available := FRAMING_BUFFER_SIZE - state.buffer_pos
    to_copy := min(available, len(data))

    if to_copy > 0 {
        mem.copy(&state.buffer[state.buffer_pos], raw_data(data), to_copy)
        state.buffer_pos += to_copy
    }

    return to_copy
}

// Try to extract a complete message
// Returns Message_Ready if message available, Need_More_Data otherwise
framing_read_extract :: proc(state: ^Framing_Read_State) -> (Framing_Result, []u8) {
    // Need at least header
    if state.buffer_pos < FRAME_HEADER_SIZE {
        return .Need_More_Data, nil
    }

    // Read length from header (big-endian)
    length := u32(state.buffer[0]) << 24 |
              u32(state.buffer[1]) << 16 |
              u32(state.buffer[2]) << 8  |
              u32(state.buffer[3])

    // Validate length
    if length > MAX_FRAMED_MESSAGE_SIZE {
        return .Error, nil
    }

    // Check if we have complete message
    total_needed := FRAME_HEADER_SIZE + int(length)
    if state.buffer_pos < total_needed {
        state.expected_length = length
        return .Need_More_Data, nil
    }

    // Copy message to extract buffer
    msg_len := int(length)
    mem.copy(&state.extract_buffer[0], &state.buffer[FRAME_HEADER_SIZE], msg_len)

    // Shift remaining data
    remaining := state.buffer_pos - total_needed
    if remaining > 0 {
        mem.copy(&state.buffer[0], &state.buffer[total_needed], remaining)
    }
    state.buffer_pos = remaining
    state.expected_length = 0

    return .Message_Ready, state.extract_buffer[:msg_len]
}

// Check if there's potentially more data to extract
framing_read_has_data :: proc(state: ^Framing_Read_State) -> bool {
    return state.buffer_pos >= FRAME_HEADER_SIZE
}

framing_read_buffered :: proc(state: ^Framing_Read_State) -> int {
    return state.buffer_pos
}

// =============================================================================
// Write-side API
// =============================================================================

// Initialize write state with a message to send
// Returns true on success
framing_write_state_init :: proc(state: ^Framing_Write_State, msg: []u8) -> bool {
    if len(msg) > MAX_FRAMED_MESSAGE_SIZE {
        return false
    }

    msg_len := u32(len(msg))

    // Write length header (big-endian)
    state.buffer[0] = u8(msg_len >> 24)
    state.buffer[1] = u8(msg_len >> 16)
    state.buffer[2] = u8(msg_len >> 8)
    state.buffer[3] = u8(msg_len)

    // Copy message
    mem.copy(&state.buffer[FRAME_HEADER_SIZE], raw_data(msg), len(msg))

    state.total_len = FRAME_HEADER_SIZE + len(msg)
    state.bytes_written = 0

    return true
}

// Get pointer to remaining data to write
framing_write_get_remaining :: proc(state: ^Framing_Write_State) -> []u8 {
    if state.bytes_written >= state.total_len {
        return nil
    }
    return state.buffer[state.bytes_written:state.total_len]
}

// Mark bytes as successfully written
framing_write_mark_written :: proc(state: ^Framing_Write_State, n: int) {
    state.bytes_written += n
}

// Check if all data has been written
framing_write_is_complete :: proc(state: ^Framing_Write_State) -> bool {
    return state.bytes_written >= state.total_len
}

framing_write_remaining :: proc(state: ^Framing_Write_State) -> int {
    return state.total_len - state.bytes_written
}

// =============================================================================
// Simple Write API
// =============================================================================

// Frame a message with length prefix (simple version)
// Returns framed data slice, or nil on error
frame_message :: proc(msg: []u8, out: []u8) -> ([]u8, bool) {
    if len(msg) > MAX_FRAMED_MESSAGE_SIZE {
        return nil, false
    }
    if len(out) < FRAME_HEADER_SIZE + len(msg) {
        return nil, false
    }

    msg_len := u32(len(msg))

    // Write length header (big-endian)
    out[0] = u8(msg_len >> 24)
    out[1] = u8(msg_len >> 16)
    out[2] = u8(msg_len >> 8)
    out[3] = u8(msg_len)

    // Copy message
    mem.copy(&out[FRAME_HEADER_SIZE], raw_data(msg), len(msg))

    return out[:FRAME_HEADER_SIZE + len(msg)], true
}
