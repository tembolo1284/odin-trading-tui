package main

import "core:fmt"
import "core:time"
import "core:os"

import "client"

// Response callback - print received messages
on_response :: proc(msg: ^client.Output_Msg, user_data: rawptr) {
    c := cast(^client.Codec)user_data
    fmt.println(client.codec_format_output(c, msg))
}

main :: proc() {
    fmt.println("=== Odin Matching Engine Client ===")
    fmt.println()
    
    // Configuration
    config := client.default_config()
    config.host = "localhost"
    config.port = 1234           // Your TCP port
    config.transport_type = .Tcp
    config.encoding_type = .Binary
    config.user_id = 1
    
    // Initialize client
    c: client.Engine_Client
    client.engine_client_init(&c, &config)
    
    // Set response callback
    client.engine_client_set_response_callback(&c, on_response, &c.codec)
    
    // Connect
    if !client.engine_client_connect(&c) {
        fmt.eprintln("Failed to connect to matching engine")
        os.exit(1)
    }
    defer client.engine_client_disconnect(&c)
    
    fmt.println()
    fmt.println("Sending test orders...")
    fmt.println()
    
    // Send a BUY order
    order1 := client.engine_client_send_order(&c, "AAPL", 15000, 100, .Buy)
    if order1 > 0 {
        fmt.printf("Sent BUY order #%d: AAPL 100@150.00\n", order1)
    }
    
    // Wait for response
    time.sleep(100 * time.Millisecond)
    client.engine_client_poll(&c)
    
    // Send a SELL order (should match)
    order2 := client.engine_client_send_order(&c, "AAPL", 15000, 50, .Sell)
    if order2 > 0 {
        fmt.printf("Sent SELL order #%d: AAPL 50@150.00\n", order2)
    }
    
    // Wait for responses
    time.sleep(100 * time.Millisecond)
    client.engine_client_poll(&c)
    
    // Send another BUY
    order3 := client.engine_client_send_order(&c, "MSFT", 40000, 200, .Buy)
    if order3 > 0 {
        fmt.printf("Sent BUY order #%d: MSFT 200@400.00\n", order3)
    }
    
    time.sleep(100 * time.Millisecond)
    client.engine_client_poll(&c)
    
    // Cancel order 3
    if client.engine_client_send_cancel(&c, order3, "MSFT") {
        fmt.printf("Sent CANCEL for order #%d\n", order3)
    }
    
    time.sleep(100 * time.Millisecond)
    client.engine_client_poll(&c)
    
    fmt.println()
    client.engine_client_print_stats(&c)
}
