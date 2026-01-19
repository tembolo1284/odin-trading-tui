// src/main.odin
package main

import "core:fmt"
import "core:os"
import "core:net"
import "src/client/protocol_binary"
import "src/client/framing"

main :: proc() {
	fmt.println("=== Odin Matching Engine Client ===")

	// Connect
	addr, ok := net.parse_ip4("127.0.0.1")
	if !ok {
		fmt.println("Failed to parse address")
		return
	}

	ep := net.Endpoint{ip = addr, port = 1234}
	c, err := net.tcp_connect(ep)
	if err != os.ERROR_NONE {
		fmt.println("Connect failed:", err)
		return
	}
	defer net.tcp_close(&c)

	fmt.println("Connecting to localhost:1234...")
	fmt.println("Connected via TCP")
	fmt.println("")
	fmt.println("Sending test orders...")
	fmt.println("")

	// Build one NewOrder payload (Zig expects framed payload)
	payload: [protocol_binary.NEW_ORDER_WIRE_SIZE]u8
	n, ok2 := protocol_binary.encode_new_order_binary(
		payload[:],
		1,       // user_id
		"AAPL",  // symbol
		15000,   // price (u32) - keep scaling consistent with server
		100,     // qty
		.Buy,    // side
		1,       // user_order_id
	)
	if !ok2 {
		fmt.println("Failed to encode new order")
		return
	}

	if !framing.send_frame(c.fd, payload[:n]) {
		fmt.println("Failed to send frame")
		return
	}

	fmt.println("Sent BUY order #1: AAPL 100@150.00")
	fmt.println("")
	fmt.println("Waiting for server responses...")
	fmt.println("")

	// Receive loop
	recv_buf: [64 * 1024]u8
	for {
		payload_len, ok3 := framing.recv_frame(c.fd, recv_buf[:])
		if !ok3 {
			fmt.println("Disconnected / read failed")
			return
		}

		out: protocol_binary.Output_Msg
		_, ok4 := protocol_binary.decode_output_binary(recv_buf[:payload_len], &out)
		if !ok4 {
			fmt.println("Received frame, but failed to decode output message (len=", payload_len, ")")
			continue
		}

		sym := protocol_binary.symbol_to_string(out.symbol[:])

		switch out.typ {
		case .Ack:
			fmt.println("ACK: symbol=", sym, " user_id=", out.user_id, " order_id=", out.user_order_id)

		case .Cancel_Ack:
			fmt.println("CANCEL_ACK: symbol=", sym, " user_id=", out.user_id, " order_id=", out.user_order_id)

		case .Trade:
			fmt.println("TRADE: symbol=", sym,
				" buy=", out.buy_user_id, "/", out.buy_order_id,
				" sell=", out.sell_user_id, "/", out.sell_order_id,
				" px=", out.price,
				" qty=", out.quantity)

		case .Top_Of_Book:
			fmt.println("TOB: symbol=", sym,
				" side=", u8(out.side),
				" px=", out.price,
				" qty=", out.quantity)

		case .Reject:
			fmt.println("REJECT: symbol=", sym,
				" user_id=", out.user_id,
				" order_id=", out.user_order_id,
				" reason=", u8(out.reason))

		default:
			fmt.println("Unknown output type:", u8(out.typ))
		}
	}
}

