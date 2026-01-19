package client

import "core:time"
import "core:fmt"

// ============================================================================
// Client Configuration
// ============================================================================

CLIENT_DEFAULT_PORT       :: 1234
CLIENT_DEFAULT_TIMEOUT_MS :: 1000
CLIENT_DEFAULT_MCAST_PORT :: 5000

Client_Config :: struct {
    host:               string,
    port:               u16,
    transport_type:     Transport_Type,
    encoding_type:      Encoding_Type,
    connect_timeout_ms: u32,
    recv_timeout_ms:    u32,
    user_id:            u32,
}

default_config :: proc() -> Client_Config {
    return Client_Config{
        host               = "localhost",
        port               = CLIENT_DEFAULT_PORT,
        transport_type     = .Tcp,
        encoding_type      = .Binary,
        connect_timeout_ms = CLIENT_DEFAULT_TIMEOUT_MS,
        recv_timeout_ms    = CLIENT_DEFAULT_TIMEOUT_MS,
        user_id            = 1,
    }
}

// ============================================================================
// Callback Types
// ============================================================================

Response_Callback :: #type proc(msg: ^Output_Msg, user_data: rawptr)

// ============================================================================
// Engine Client
// ============================================================================

Engine_Client :: struct {
    config:             Client_Config,
    transport:          Transport,
    codec:              Codec,
    response_callback:  Response_Callback,
    response_user_data: rawptr,
    connected:          bool,
    next_order_id:      u32,
    recv_buffer:        [1024]u8,
    
    // Stats
    orders_sent:        u64,
    cancels_sent:       u64,
    flushes_sent:       u64,
    responses_received: u64,
    
    // Latency tracking
    last_send_time:     i64,
    last_recv_time:     i64,
    total_latency:      u64,
    latency_samples:    u64,
    min_latency:        u64,
    max_latency:        u64,
}

// ============================================================================
// Lifecycle
// ============================================================================

engine_client_init :: proc(client: ^Engine_Client, config: ^Client_Config) {
    client^ = {}
    client.config = config^
    client.next_order_id = 1
    client.min_latency = max(u64)
    
    transport_init(&client.transport)
    codec_init(&client.codec, config.encoding_type)
}

engine_client_connect :: proc(client: ^Engine_Client) -> bool {
    if client.connected {
        return true
    }
    
    fmt.printf("Connecting to %s:%d...\n", client.config.host, client.config.port)
    
    ok := transport_connect(
        &client.transport,
        client.config.host,
        client.config.port,
        client.config.transport_type,
        client.config.connect_timeout_ms,
    )
    
    if !ok {
        fmt.eprintln("Connection failed!")
        return false
    }
    
    client.connected = true
    transport_type := transport_get_type(&client.transport)
    type_str := transport_type == .Tcp ? "TCP" : "UDP"
    fmt.printf("Connected via %s\n", type_str)
    return true
}

engine_client_disconnect :: proc(client: ^Engine_Client) {
    transport_disconnect(&client.transport)
    client.connected = false
    fmt.println("Disconnected")
}

engine_client_is_connected :: proc(client: ^Engine_Client) -> bool {
    return client.connected && transport_is_connected(&client.transport)
}

// ============================================================================
// Callbacks
// ============================================================================

engine_client_set_response_callback :: proc(
    client: ^Engine_Client,
    callback: Response_Callback,
    user_data: rawptr,
) {
    client.response_callback = callback
    client.response_user_data = user_data
}

// ============================================================================
// Order Entry
// ============================================================================

engine_client_send_order :: proc(
    client: ^Engine_Client,
    symbol: string,
    price: u32,
    quantity: u32,
    side: Side,
    order_id: u32 = 0,
) -> u32 {
    if !client.connected {
        return 0
    }
    
    actual_order_id := order_id
    if actual_order_id == 0 {
        actual_order_id = client.next_order_id
        client.next_order_id += 1
    }
    
    data := codec_encode_new_order(
        &client.codec,
        client.config.user_id,
        symbol,
        price,
        quantity,
        side,
        actual_order_id,
    )
    
    if data == nil {
        return 0
    }
    
    client.last_send_time = time.now()._nsec
    
    if !transport_send(&client.transport, data) {
        return 0
    }
    
    client.orders_sent += 1
    return actual_order_id
}

engine_client_send_cancel :: proc(
    client: ^Engine_Client,
    order_id: u32,
    symbol: string = "",
) -> bool {
    if !client.connected {
        return false
    }
    
    data := codec_encode_cancel(
        &client.codec,
        client.config.user_id,
        order_id,
        symbol,
    )
    
    if data == nil {
        return false
    }
    
    client.last_send_time = time.now()._nsec
    
    if !transport_send(&client.transport, data) {
        return false
    }
    
    client.cancels_sent += 1
    return true
}

engine_client_send_flush :: proc(client: ^Engine_Client) -> bool {
    if !client.connected {
        return false
    }
    
    data := codec_encode_flush(&client.codec)
    
    if data == nil {
        return false
    }
    
    client.last_send_time = time.now()._nsec
    
    if !transport_send(&client.transport, data) {
        return false
    }
    
    client.flushes_sent += 1
    return true
}

// ============================================================================
// Response Handling
// ============================================================================

engine_client_poll :: proc(client: ^Engine_Client) -> int {
    count := 0
    
    for {
        n := transport_recv(&client.transport, client.recv_buffer[:], 0)
        
        if n <= 0 {
            break
        }
        
        msg: Output_Msg
        if codec_decode_response(&client.codec, client.recv_buffer[:n], &msg) {
            now := time.now()._nsec
            client.last_recv_time = now
            
            if client.last_send_time > 0 {
                latency := u64(now - client.last_send_time)
                client.total_latency += latency
                client.latency_samples += 1
                client.min_latency = min(client.min_latency, latency)
                client.max_latency = max(client.max_latency, latency)
            }
            
            client.responses_received += 1
            
            if client.response_callback != nil {
                client.response_callback(&msg, client.response_user_data)
            }
            
            count += 1
        }
    }
    
    return count
}

engine_client_recv :: proc(
    client: ^Engine_Client,
    msg: ^Output_Msg,
    timeout_ms: int,
) -> bool {
    if !client.connected {
        return false
    }
    
    n := transport_recv(&client.transport, client.recv_buffer[:], timeout_ms)
    
    if n <= 0 {
        return false
    }
    
    if !codec_decode_response(&client.codec, client.recv_buffer[:n], msg) {
        return false
    }
    
    client.responses_received += 1
    
    if client.response_callback != nil {
        client.response_callback(msg, client.response_user_data)
    }
    
    return true
}

engine_client_recv_all :: proc(client: ^Engine_Client, timeout_ms: int) -> int {
    count := 0
    msg: Output_Msg
    
    for engine_client_recv(client, &msg, timeout_ms) {
        count += 1
    }
    
    return count
}

// ============================================================================
// Utilities
// ============================================================================

engine_client_get_transport :: proc(client: ^Engine_Client) -> Transport_Type {
    return transport_get_type(&client.transport)
}

engine_client_get_encoding :: proc(client: ^Engine_Client) -> Encoding_Type {
    return codec_get_detected_encoding(&client.codec)
}

engine_client_peek_next_order_id :: proc(client: ^Engine_Client) -> u32 {
    return client.next_order_id
}

engine_client_reset_order_id :: proc(client: ^Engine_Client, start_id: u32) {
    client.next_order_id = start_id
}

// ============================================================================
// Latency
// ============================================================================

engine_client_get_avg_latency_ns :: proc(client: ^Engine_Client) -> u64 {
    if client.latency_samples == 0 {
        return 0
    }
    return client.total_latency / client.latency_samples
}

engine_client_get_min_latency_ns :: proc(client: ^Engine_Client) -> u64 {
    if client.latency_samples == 0 {
        return 0
    }
    return client.min_latency
}

engine_client_get_max_latency_ns :: proc(client: ^Engine_Client) -> u64 {
    return client.max_latency
}

// ============================================================================
// Stats
// ============================================================================

engine_client_print_stats :: proc(client: ^Engine_Client) {
    transport_type := engine_client_get_transport(client)
    encoding_type := engine_client_get_encoding(client)
    
    transport_str := transport_type == .Tcp ? "TCP" : "UDP"
    encoding_str := encoding_type == .Binary ? "Binary" : (encoding_type == .Csv ? "CSV" : "Auto")
    
    avg_latency_us := f64(engine_client_get_avg_latency_ns(client)) / 1000.0
    min_latency_us := f64(engine_client_get_min_latency_ns(client)) / 1000.0
    max_latency_us := f64(engine_client_get_max_latency_ns(client)) / 1000.0
    
    fmt.println("=== Client Statistics ===")
    fmt.printf("Transport: %s | Encoding: %s\n", transport_str, encoding_str)
    fmt.printf("Orders: %d | Cancels: %d | Flushes: %d\n",
        client.orders_sent, client.cancels_sent, client.flushes_sent)
    fmt.printf("Responses: %d\n", client.responses_received)
    fmt.printf("Latency (us): avg=%.1f min=%.1f max=%.1f\n",
        avg_latency_us, min_latency_us, max_latency_us)
}
