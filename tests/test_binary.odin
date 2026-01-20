package tests

import client "../client"
import "core:testing"
import "core:fmt"

@(test)
test_binary_new_order_size :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(client.Binary_New_Order), 27)
}

@(test)
test_binary_cancel_size :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(client.Binary_Cancel), 10)
}

@(test)
test_binary_flush_size :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(client.Binary_Flush), 2)
}

@(test)
test_binary_ack_size :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(client.Binary_Ack), 18)
}

@(test)
test_binary_cancel_ack_size :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(client.Binary_Cancel_Ack), 18)
}

@(test)
test_binary_trade_size :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(client.Binary_Trade), 34)
}

@(test)
test_binary_top_of_book_size :: proc(t: ^testing.T) {
    testing.expect_value(t, size_of(client.Binary_Top_Of_Book), 19)
}

@(test)
test_binary_encode_new_order :: proc(t: ^testing.T) {
    buf: [64]u8
    n := client.binary_encode_new_order(buf[:], 1, "IBM", 100, 50, .Buy, 1001)
    
    testing.expect_value(t, n, 27)
    testing.expect_value(t, buf[0], client.BINARY_MAGIC)
    testing.expect_value(t, buf[1], u8('N'))
}

@(test)
test_binary_encode_cancel :: proc(t: ^testing.T) {
    buf: [64]u8
    n := client.binary_encode_cancel(buf[:], 1, 1001)
    
    testing.expect_value(t, n, 10)
    testing.expect_value(t, buf[0], client.BINARY_MAGIC)
    testing.expect_value(t, buf[1], u8('C'))
}

@(test)
test_binary_encode_flush :: proc(t: ^testing.T) {
    buf: [64]u8
    n := client.binary_encode_flush(buf[:])
    
    testing.expect_value(t, n, 2)
    testing.expect_value(t, buf[0], client.BINARY_MAGIC)
    testing.expect_value(t, buf[1], u8('F'))
}

@(test)
test_is_binary_message :: proc(t: ^testing.T) {
    binary_data := []u8{0x4D, 'N', 0, 0, 0, 1}
    csv_data := []u8{'N', ',', ' ', '1'}
    
    testing.expect(t, client.is_binary_message(binary_data))
    testing.expect(t, !client.is_binary_message(csv_data))
}

@(test)
test_binary_decode_ack :: proc(t: ^testing.T) {
    // Build a binary ACK message
    ack := client.Binary_Ack{
        magic = client.BINARY_MAGIC,
        msg_type = 'A',
        symbol = {'I', 'B', 'M', 0, 0, 0, 0, 0},
        user_id = u32be(1),
        user_order_id = u32be(1001),
    }
    
    data := transmute([size_of(client.Binary_Ack)]u8)ack
    
    msg: client.Output_Msg
    ok := client.binary_decode_response(data[:], &msg)
    
    testing.expect(t, ok)
    testing.expect_value(t, msg.type, client.Output_Msg_Type.Ack)
    
    ack_data := msg.data.(client.Ack_Msg)
    testing.expect_value(t, ack_data.user_id, u32(1))
    testing.expect_value(t, ack_data.user_order_id, u32(1001))
}
