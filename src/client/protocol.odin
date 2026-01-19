package client

import "core:mem"
import "core:fmt"
import "core:strings"
import "core:strconv"

// ============================================================================
// Constants
// ============================================================================

CODEC_MAX_MESSAGE_SIZE :: 1024
CODEC_MAX_CSV_LINE     :: 512

// Binary protocol magic bytes (first byte detection)
BINARY_MSG_TYPE_MAX :: 3  // Max valid message type for binary

// ============================================================================
// Codec State
// ============================================================================

Codec :: struct {
    // Configured encoding for sending
    send_encoding:     Encoding_Type,
    
    // Detected encoding from server responses
    detected_encoding: Encoding_Type,
    encoding_detected: bool,
    
    // Output buffer for encoded messages
    encode_buffer:     [CODEC_MAX_MESSAGE_SIZE]u8,
    encode_len:        uint,
    
    // Format buffer for human-readable output
    format_buffer:     [512]u8,
    
    // Statistics
    messages_encoded:  u64,
    messages_decoded:  u64,
    decode_errors:     u64,
}

// ============================================================================
// Codec Lifecycle
// ============================================================================

codec_init :: proc(c: ^Codec, send_encoding: Encoding_Type) {
    c^ = {}
    c.send_encoding = send_encoding == .Auto ? .Binary : send_encoding
    c.detected_encoding = .Auto
    c.encoding_detected = false
}

codec_reset :: proc(c: ^Codec) {
    c.detected_encoding = .Auto
    c.encoding_detected = false
    c.messages_encoded = 0
    c.messages_decoded = 0
    c.decode_errors = 0
}

// ============================================================================
// Encoding (Client -> Server)
// ============================================================================

// Encode new order to binary format
// Returns slice of encoded bytes, or nil on failure
codec_encode_new_order :: proc(
    c: ^Codec,
    user_id: u32,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
    order_id: u32,
) -> []u8 {
    if c.send_encoding == .Csv {
        return encode_new_order_csv(c, user_id, symbol, price, quantity, side, order_id)
    }
    return encode_new_order_binary(c, user_id, symbol, price, quantity, side, order_id)
}

// Encode cancel to wire format
codec_encode_cancel :: proc(
    c: ^Codec,
    user_id: u32,
    order_id: u32,
    symbol: string,
) -> []u8 {
    if c.send_encoding == .Csv {
        return encode_cancel_csv(c, user_id, order_id, symbol)
    }
    return encode_cancel_binary(c, user_id, order_id, symbol)
}

// Encode flush to wire format
codec_encode_flush :: proc(c: ^Codec) -> []u8 {
    if c.send_encoding == .Csv {
        return encode_flush_csv(c)
    }
    return encode_flush_binary(c)
}

// ============================================================================
// Binary Encoding
// ============================================================================

encode_new_order_binary :: proc(
    c: ^Codec,
    user_id: u32,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
    order_id: u32,
) -> []u8 {
    msg := make_new_order(user_id, order_id, symbol, price, quantity, side)
    
    // Copy raw bytes to encode buffer
    src := mem.ptr_to_bytes(&msg)
    mem.copy(&c.encode_buffer[0], raw_data(src), size_of(Input_Msg))
    c.encode_len = size_of(Input_Msg)
    c.messages_encoded += 1
    
    return c.encode_buffer[:c.encode_len]
}

encode_cancel_binary :: proc(
    c: ^Codec,
    user_id: u32,
    order_id: u32,
    symbol: string,
) -> []u8 {
    msg := make_cancel(user_id, order_id, symbol)
    
    src := mem.ptr_to_bytes(&msg)
    mem.copy(&c.encode_buffer[0], raw_data(src), size_of(Input_Msg))
    c.encode_len = size_of(Input_Msg)
    c.messages_encoded += 1
    
    return c.encode_buffer[:c.encode_len]
}

encode_flush_binary :: proc(c: ^Codec) -> []u8 {
    msg := make_flush()
    
    src := mem.ptr_to_bytes(&msg)
    mem.copy(&c.encode_buffer[0], raw_data(src), size_of(Input_Msg))
    c.encode_len = size_of(Input_Msg)
    c.messages_encoded += 1
    
    return c.encode_buffer[:c.encode_len]
}

// ============================================================================
// CSV Encoding
// ============================================================================

encode_new_order_csv :: proc(
    c: ^Codec,
    user_id: u32,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
    order_id: u32,
) -> []u8 {
    side_char := side == .Buy ? 'B' : 'S'
    
    // Format: N,user_id,symbol,price,quantity,side,order_id\n
    s := fmt.bprintf(
        c.encode_buffer[:],
        "N,%d,%s,%d,%d,%c,%d\n",
        user_id, symbol, price, quantity, side_char, order_id,
    )
    c.encode_len = uint(len(s))
    c.messages_encoded += 1
    
    return c.encode_buffer[:c.encode_len]
}

encode_cancel_csv :: proc(
    c: ^Codec,
    user_id: u32,
    order_id: u32,
    symbol: string,
) -> []u8 {
    // Format: C,user_id,order_id\n (symbol not needed for CSV cancel)
    s := fmt.bprintf(
        c.encode_buffer[:],
        "C,%d,%d,%s\n",
        user_id, order_id, symbol,
    )
    c.encode_len = uint(len(s))
    c.messages_encoded += 1
    
    return c.encode_buffer[:c.encode_len]
}

encode_flush_csv :: proc(c: ^Codec) -> []u8 {
    s := fmt.bprintf(c.encode_buffer[:], "F\n")
    c.encode_len = uint(len(s))
    c.messages_encoded += 1
    
    return c.encode_buffer[:c.encode_len]
}

// ============================================================================
// Decoding (Server -> Client)
// ============================================================================

// Detect encoding from first byte of response
codec_detect_encoding :: proc(data: []u8) -> Encoding_Type {
    if len(data) == 0 {
        return .Auto
    }
    
    first := data[0]
    
    // Binary messages start with type byte 0-3
    if first <= BINARY_MSG_TYPE_MAX {
        return .Binary
    }
    
    // CSV responses start with 'A', 'C', 'T', 'B' (Ack, Cancel, Trade, Book)
    // or printable ASCII
    if first >= 0x20 && first <= 0x7E {
        return .Csv
    }
    
    return .Binary  // Default to binary
}

// Decode server response
// Returns true on success, fills msg
codec_decode_response :: proc(c: ^Codec, data: []u8, msg: ^Output_Msg) -> bool {
    if len(data) == 0 {
        c.decode_errors += 1
        return false
    }
    
    // Auto-detect encoding on first message
    if !c.encoding_detected {
        c.detected_encoding = codec_detect_encoding(data)
        c.encoding_detected = true
    }
    
    ok: bool
    if c.detected_encoding == .Csv {
        ok = decode_response_csv(data, msg)
    } else {
        ok = decode_response_binary(data, msg)
    }
    
    if ok {
        c.messages_decoded += 1
    } else {
        c.decode_errors += 1
    }
    
    return ok
}

// ============================================================================
// Binary Decoding
// ============================================================================

decode_response_binary :: proc(data: []u8, msg: ^Output_Msg) -> bool {
    if len(data) < size_of(Output_Msg) {
        return false
    }
    
    // Direct memory copy (wire-compatible structs)
    mem.copy(msg, raw_data(data), size_of(Output_Msg))
    
    // Validate message type
    return output_msg_type_is_valid(msg.type)
}

// Decode from envelope (64-byte cache-aligned)
decode_response_envelope :: proc(data: []u8, env: ^Output_Msg_Envelope) -> bool {
    if len(data) < size_of(Output_Msg_Envelope) {
        return false
    }
    
    mem.copy(env, raw_data(data), size_of(Output_Msg_Envelope))
    return output_msg_type_is_valid(env.msg.type)
}

// ============================================================================
// CSV Decoding
// ============================================================================

decode_response_csv :: proc(data: []u8, msg: ^Output_Msg) -> bool {
    line := string(data)
    line = strings.trim_space(line)
    
    if len(line) == 0 {
        return false
    }
    
    parts := strings.split(line, ",")
    defer delete(parts)
    
    if len(parts) == 0 {
        return false
    }
    
    msg^ = {}
    
    switch parts[0] {
    case "A":  // Ack
        if len(parts) < 3 { return false }
        msg.type = .Ack
        msg.data.ack.user_id = parse_u32(parts[1])
        msg.data.ack.user_order_id = parse_u32(parts[2])
        if len(parts) > 3 {
            copy_symbol(msg.data.ack.symbol[:], parts[3])
        }
        return true
        
    case "C":  // Cancel Ack
        if len(parts) < 3 { return false }
        msg.type = .Cancel_Ack
        msg.data.cancel_ack.user_id = parse_u32(parts[1])
        msg.data.cancel_ack.user_order_id = parse_u32(parts[2])
        if len(parts) > 3 {
            copy_symbol(msg.data.cancel_ack.symbol[:], parts[3])
        }
        return true
        
    case "T":  // Trade
        if len(parts) < 7 { return false }
        msg.type = .Trade
        msg.data.trade.user_id_buy = parse_u32(parts[1])
        msg.data.trade.user_order_id_buy = parse_u32(parts[2])
        msg.data.trade.user_id_sell = parse_u32(parts[3])
        msg.data.trade.user_order_id_sell = parse_u32(parts[4])
        msg.data.trade.price = parse_u32(parts[5])
        msg.data.trade.quantity = parse_u32(parts[6])
        if len(parts) > 7 {
            copy_symbol(msg.data.trade.symbol[:], parts[7])
        }
        return true
        
    case "B":  // Top of Book
        if len(parts) < 5 { return false }
        msg.type = .Top_Of_Book
        copy_symbol(msg.data.top_of_book.symbol[:], parts[1])
        msg.data.top_of_book.side = parts[2] == "B" ? .Buy : .Sell
        msg.data.top_of_book.price = parse_u32(parts[3])
        msg.data.top_of_book.total_quantity = parse_u32(parts[4])
        return true
    }
    
    return false
}

// ============================================================================
// Utility
// ============================================================================

parse_u32 :: proc(s: string) -> u32 {
    val, ok := strconv.parse_uint(s, 10)
    return ok ? u32(val) : 0
}

// ============================================================================
// Getters
// ============================================================================

codec_get_send_encoding :: proc(c: ^Codec) -> Encoding_Type {
    return c.send_encoding
}

codec_get_detected_encoding :: proc(c: ^Codec) -> Encoding_Type {
    return c.detected_encoding
}

codec_is_encoding_detected :: proc(c: ^Codec) -> bool {
    return c.encoding_detected
}

// ============================================================================
// Formatting (for display)
// ============================================================================

codec_format_output :: proc(c: ^Codec, msg: ^Output_Msg) -> string {
    switch msg.type {
    case .Ack:
        return fmt.bprintf(
            c.format_buffer[:],
            "[ACK] %s user=%d order=%d",
            get_symbol(msg.data.ack.symbol[:]),
            msg.data.ack.user_id,
            msg.data.ack.user_order_id,
        )
        
    case .Cancel_Ack:
        return fmt.bprintf(
            c.format_buffer[:],
            "[CANCEL_ACK] %s user=%d order=%d",
            get_symbol(msg.data.cancel_ack.symbol[:]),
            msg.data.cancel_ack.user_id,
            msg.data.cancel_ack.user_order_id,
        )
        
    case .Trade:
        return fmt.bprintf(
            c.format_buffer[:],
            "[TRADE] %s %d@%d buy=%d/%d sell=%d/%d",
            get_symbol(msg.data.trade.symbol[:]),
            msg.data.trade.quantity,
            msg.data.trade.price,
            msg.data.trade.user_id_buy,
            msg.data.trade.user_order_id_buy,
            msg.data.trade.user_id_sell,
            msg.data.trade.user_order_id_sell,
        )
        
    case .Top_Of_Book:
        tob := &msg.data.top_of_book
        if top_of_book_is_eliminated(tob) {
            return fmt.bprintf(
                c.format_buffer[:],
                "[TOB] %s %c: EMPTY",
                get_symbol(tob.symbol[:]),
                side_char(tob.side),
            )
        }
        return fmt.bprintf(
            c.format_buffer[:],
            "[TOB] %s %c: %d @ %d",
            get_symbol(tob.symbol[:]),
            side_char(tob.side),
            tob.total_quantity,
            tob.price,
        )
    }
    
    return "[UNKNOWN]"
}
