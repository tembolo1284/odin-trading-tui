package client

// =============================================================================
// Codec - Unified Encoding/Decoding Layer
//
// Provides a unified interface for CSV and Binary protocols with:
//   - Auto-detection of server response format
//   - Encoding of outgoing messages
//   - Decoding of incoming messages
// =============================================================================

import "core:fmt"

// =============================================================================
// Constants
// =============================================================================

CODEC_MAX_MESSAGE_SIZE :: 1024
CODEC_MAX_CSV_LINE     :: 512

// =============================================================================
// Codec State
// =============================================================================

Codec :: struct {
    // Configured encoding for sending
    send_encoding: Encoding_Type,

    // Detected encoding from server
    detected_encoding:  Encoding_Type,
    encoding_detected:  bool,

    // Encode buffer
    encode_buffer: [CODEC_MAX_MESSAGE_SIZE]u8,
    encode_len:    int,

    // Statistics
    messages_encoded: u64,
    messages_decoded: u64,
    decode_errors:    u64,
}

// =============================================================================
// Initialization
// =============================================================================

codec_init :: proc(c: ^Codec, send_encoding: Encoding_Type) {
    c^ = {}
    // Default to binary if auto
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

// =============================================================================
// Encoding API
// =============================================================================

// Encode a new order message
// Returns slice of encoded data, or empty slice on error
codec_encode_new_order :: proc(
    c: ^Codec,
    user_id: u32,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
    order_id: u32,
) -> []u8 {
    n: int
    if c.send_encoding == .Binary {
        n = binary_encode_new_order(
            c.encode_buffer[:], user_id, symbol, price, quantity, side, order_id)
    } else {
        n = csv_encode_new_order(
            c.encode_buffer[:], user_id, symbol, price, quantity, side, order_id)
    }

    if n == 0 {
        return nil
    }

    c.encode_len = n
    c.messages_encoded += 1
    return c.encode_buffer[:n]
}

// Encode a cancel message
codec_encode_cancel :: proc(c: ^Codec, user_id: u32, order_id: u32) -> []u8 {
    n: int
    if c.send_encoding == .Binary {
        n = binary_encode_cancel(c.encode_buffer[:], user_id, order_id)
    } else {
        n = csv_encode_cancel(c.encode_buffer[:], user_id, order_id)
    }

    if n == 0 {
        return nil
    }

    c.encode_len = n
    c.messages_encoded += 1
    return c.encode_buffer[:n]
}

// Encode a flush message
codec_encode_flush :: proc(c: ^Codec) -> []u8 {
    n: int
    if c.send_encoding == .Binary {
        n = binary_encode_flush(c.encode_buffer[:])
    } else {
        n = csv_encode_flush(c.encode_buffer[:])
    }

    if n == 0 {
        return nil
    }

    c.encode_len = n
    c.messages_encoded += 1
    return c.encode_buffer[:n]
}

// =============================================================================
// Decoding API
// =============================================================================

// Detect encoding type from received data
codec_detect_encoding :: proc(data: []u8) -> Encoding_Type {
    if len(data) == 0 {
        return .Auto
    }

    if is_binary_message(data) {
        return .Binary
    }

    return .CSV
}

// Decode a server response message
codec_decode_response :: proc(c: ^Codec, data: []u8, msg: ^Output_Msg) -> bool {
    if len(data) == 0 {
        c.decode_errors += 1
        return false
    }

    // Auto-detect encoding
    encoding := codec_detect_encoding(data)

    // Update detected encoding
    if !c.encoding_detected {
        c.detected_encoding = encoding
        c.encoding_detected = true
    }

    success: bool
    if encoding == .Binary {
        success = binary_decode_response(data, msg)
    } else {
        success = csv_decode_response(data, msg)
    }

    if success {
        c.messages_decoded += 1
    } else {
        c.decode_errors += 1
    }

    return success
}

// =============================================================================
// Utilities
// =============================================================================

codec_get_send_encoding :: proc(c: ^Codec) -> Encoding_Type {
    return c.send_encoding
}

codec_get_detected_encoding :: proc(c: ^Codec) -> Encoding_Type {
    return c.detected_encoding
}

codec_is_encoding_detected :: proc(c: ^Codec) -> bool {
    return c.encoding_detected
}

codec_print_stats :: proc(c: ^Codec) {
    fmt.println("Codec Statistics:")
    fmt.printf("  Send encoding:     %s\n", encoding_type_str(c.send_encoding))
    fmt.printf("  Detected encoding: %s\n",
        c.encoding_detected ? encoding_type_str(c.detected_encoding) : "not yet")
    fmt.printf("  Messages encoded:  %d\n", c.messages_encoded)
    fmt.printf("  Messages decoded:  %d\n", c.messages_decoded)
    fmt.printf("  Decode errors:     %d\n", c.decode_errors)
}
