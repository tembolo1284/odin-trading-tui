package tests

import client "../client"
import "core:testing"
import "core:mem"

@(test)
test_frame_message :: proc(t: ^testing.T) {
    msg := []u8{'H', 'e', 'l', 'l', 'o'}
    out: [64]u8
    
    framed, ok := client.frame_message(msg, out[:])
    
    testing.expect(t, ok)
    testing.expect_value(t, len(framed), 9)  // 4 header + 5 payload
    
    // Check length header (big-endian)
    testing.expect_value(t, framed[0], u8(0))
    testing.expect_value(t, framed[1], u8(0))
    testing.expect_value(t, framed[2], u8(0))
    testing.expect_value(t, framed[3], u8(5))
    
    // Check payload
    testing.expect_value(t, framed[4], u8('H'))
    testing.expect_value(t, framed[8], u8('o'))
}

@(test)
test_framing_read_state :: proc(t: ^testing.T) {
    state: client.Framing_Read_State
    client.framing_read_state_init(&state)
    
    // Create a framed message
    framed := []u8{0, 0, 0, 5, 'H', 'e', 'l', 'l', 'o'}
    
    // Append data
    n := client.framing_read_append(&state, framed)
    testing.expect_value(t, n, 9)
    
    // Extract message
    result, msg := client.framing_read_extract(&state)
    testing.expect_value(t, result, client.Framing_Result.Message_Ready)
    testing.expect_value(t, len(msg), 5)
    testing.expect_value(t, msg[0], u8('H'))
}

@(test)
test_framing_partial_read :: proc(t: ^testing.T) {
    state: client.Framing_Read_State
    client.framing_read_state_init(&state)
    
    // Send header only
    header := []u8{0, 0, 0, 5}
    client.framing_read_append(&state, header)
    
    result1, _ := client.framing_read_extract(&state)
    testing.expect_value(t, result1, client.Framing_Result.Need_More_Data)
    
    // Send rest of message
    payload := []u8{'H', 'e', 'l', 'l', 'o'}
    client.framing_read_append(&state, payload)
    
    result2, msg := client.framing_read_extract(&state)
    testing.expect_value(t, result2, client.Framing_Result.Message_Ready)
    testing.expect_value(t, len(msg), 5)
}

@(test)
test_framing_multiple_messages :: proc(t: ^testing.T) {
    state: client.Framing_Read_State
    client.framing_read_state_init(&state)
    
    // Two framed messages back to back
    data := []u8{
        0, 0, 0, 2, 'H', 'i',  // First message
        0, 0, 0, 3, 'B', 'y', 'e',  // Second message
    }
    
    client.framing_read_append(&state, data)
    
    // Extract first
    result1, msg1 := client.framing_read_extract(&state)
    testing.expect_value(t, result1, client.Framing_Result.Message_Ready)
    testing.expect_value(t, len(msg1), 2)
    
    // Extract second
    result2, msg2 := client.framing_read_extract(&state)
    testing.expect_value(t, result2, client.Framing_Result.Message_Ready)
    testing.expect_value(t, len(msg2), 3)
    
    // No more
    result3, _ := client.framing_read_extract(&state)
    testing.expect_value(t, result3, client.Framing_Result.Need_More_Data)
}

@(test)
test_framing_write_state :: proc(t: ^testing.T) {
    state: client.Framing_Write_State
    msg := []u8{'T', 'e', 's', 't'}
    
    ok := client.framing_write_state_init(&state, msg)
    testing.expect(t, ok)
    
    remaining := client.framing_write_get_remaining(&state)
    testing.expect_value(t, len(remaining), 8)  // 4 header + 4 payload
    
    testing.expect(t, !client.framing_write_is_complete(&state))
    
    client.framing_write_mark_written(&state, 8)
    testing.expect(t, client.framing_write_is_complete(&state))
}
