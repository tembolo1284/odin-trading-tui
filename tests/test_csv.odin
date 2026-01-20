package tests

import client "../client"
import "core:testing"

@(test)
test_csv_encode_new_order :: proc(t: ^testing.T) {
    buf: [256]u8
    n := client.csv_encode_new_order(buf[:], 1, "IBM", 100, 50, .Buy, 1001)
    
    testing.expect(t, n > 0)
    
    result := string(buf[:n])
    testing.expect(t, result == "N, 1, IBM, 100, 50, B, 1001\n")
}

@(test)
test_csv_encode_cancel :: proc(t: ^testing.T) {
    buf: [256]u8
    n := client.csv_encode_cancel(buf[:], 1, 1001)
    
    testing.expect(t, n > 0)
    
    result := string(buf[:n])
    testing.expect(t, result == "C, 1, 1001\n")
}

@(test)
test_csv_encode_flush :: proc(t: ^testing.T) {
    buf: [256]u8
    n := client.csv_encode_flush(buf[:])
    
    testing.expect_value(t, n, 2)
    testing.expect_value(t, buf[0], u8('F'))
    testing.expect_value(t, buf[1], u8('\n'))
}

@(test)
test_csv_decode_ack :: proc(t: ^testing.T) {
    data := []u8{'A', ',', ' ', 'I', 'B', 'M', ',', ' ', '1', ',', ' ', '1', '0', '0', '1', '\n'}
    
    msg: client.Output_Msg
    ok := client.csv_decode_response(data, &msg)
    
    testing.expect(t, ok)
    testing.expect_value(t, msg.type, client.Output_Msg_Type.Ack)
    
    ack := msg.data.(client.Ack_Msg)
    testing.expect_value(t, ack.user_id, u32(1))
    testing.expect_value(t, ack.user_order_id, u32(1001))
}

@(test)
test_csv_decode_cancel_ack :: proc(t: ^testing.T) {
    data := []u8{'C', ',', ' ', 'I', 'B', 'M', ',', ' ', '1', ',', ' ', '1', '0', '0', '1'}
    
    msg: client.Output_Msg
    ok := client.csv_decode_response(data, &msg)
    
    testing.expect(t, ok)
    testing.expect_value(t, msg.type, client.Output_Msg_Type.Cancel_Ack)
}

@(test)
test_csv_decode_trade :: proc(t: ^testing.T) {
    data := transmute([]u8)string("T, IBM, 1, 1001, 2, 2001, 100, 50\n")
    
    msg: client.Output_Msg
    ok := client.csv_decode_response(data, &msg)
    
    testing.expect(t, ok)
    testing.expect_value(t, msg.type, client.Output_Msg_Type.Trade)
    
    trade := msg.data.(client.Trade_Msg)
    testing.expect_value(t, trade.user_id_buy, u32(1))
    testing.expect_value(t, trade.user_order_id_buy, u32(1001))
    testing.expect_value(t, trade.user_id_sell, u32(2))
    testing.expect_value(t, trade.user_order_id_sell, u32(2001))
    testing.expect_value(t, trade.price, u32(100))
    testing.expect_value(t, trade.quantity, u32(50))
}

@(test)
test_csv_decode_tob :: proc(t: ^testing.T) {
    data := transmute([]u8)string("B, IBM, B, 100, 500")
    
    msg: client.Output_Msg
    ok := client.csv_decode_response(data, &msg)
    
    testing.expect(t, ok)
    testing.expect_value(t, msg.type, client.Output_Msg_Type.Top_Of_Book)
    
    tob := msg.data.(client.Top_Of_Book_Msg)
    testing.expect_value(t, tob.side, client.Side.Buy)
    testing.expect_value(t, tob.price, u32(100))
    testing.expect_value(t, tob.total_quantity, u32(500))
}

@(test)
test_csv_decode_tob_empty :: proc(t: ^testing.T) {
    data := transmute([]u8)string("B, IBM, S, -, -")
    
    msg: client.Output_Msg
    ok := client.csv_decode_response(data, &msg)
    
    testing.expect(t, ok)
    testing.expect_value(t, msg.type, client.Output_Msg_Type.Top_Of_Book)
    
    tob := msg.data.(client.Top_Of_Book_Msg)
    testing.expect_value(t, tob.side, client.Side.Sell)
    testing.expect_value(t, tob.price, u32(0))
    testing.expect_value(t, tob.total_quantity, u32(0))
}
