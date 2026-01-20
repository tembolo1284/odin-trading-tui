package client

// =============================================================================
// Engine Client - High-Level API
//
// Combines transport and codec layers for a unified interface.
// =============================================================================

import "core:fmt"
import "core:time"

// =============================================================================
// Constants
// =============================================================================

MAX_PENDING_RESPONSES :: 64
MAX_RECV_ATTEMPTS     :: 1000
MAX_DRAIN_ITERATIONS  :: 100

// =============================================================================
// Callback Types
// =============================================================================

Response_Callback :: #type proc(msg: ^Output_Msg, user_data: rawptr)
Multicast_Callback :: #type proc(msg: ^Output_Msg, user_data: rawptr)

// =============================================================================
// Engine Client State
// =============================================================================

Engine_Client :: struct {
    // Configuration
    config: Client_Config,

    // Transport
    transport: Transport,

    // Codec
    codec: Codec,

    // Multicast (optional)
    multicast:        Multicast_Receiver,
    multicast_active: bool,

    // Callbacks
    response_callback:   Response_Callback,
    response_user_data:  rawptr,
    multicast_callback:  Multicast_Callback,
    multicast_user_data: rawptr,

    // State
    connected:     bool,
    next_order_id: u32,

    // Statistics
    orders_sent:        u64,
    cancels_sent:       u64,
    flushes_sent:       u64,
    responses_received: u64,
    multicast_received: u64,

    // Timing (nanoseconds)
    last_send_time:  i64,
    last_recv_time:  i64,
    total_latency:   u64,
    latency_samples: u64,
    min_latency:     u64,
    max_latency:     u64,
}

// =============================================================================
// Lifecycle
// =============================================================================

engine_client_init :: proc(client: ^Engine_Client, config: ^Client_Config) {
    client^ = {}
    client.config = config^
    transport_init(&client.transport)
    codec_init(&client.codec, config.encoding)
    multicast_receiver_init(&client.multicast)
    client.next_order_id = 1
    client.min_latency = max(u64)
}

engine_client_connect :: proc(client: ^Engine_Client) -> bool {
    cfg := &client.config

    // Multicast-only mode needs no TCP/UDP connection
    if cfg.mode == .Multicast_Only {
        client.connected = true
        return true
    }

    if !cfg.quiet {
        fmt.printf("Connecting to %s:%d...\n", config_get_host(cfg), cfg.port)
    }

    // Connect transport
    if !transport_connect(&client.transport, config_get_host(cfg), cfg.port,
                          cfg.transport, cfg.connect_timeout_ms) {
        fmt.eprintf("Failed to connect to %s:%d\n", config_get_host(cfg), cfg.port)
        return false
    }

    cfg.detected_transport = transport_get_type(&client.transport)

    if !cfg.quiet {
        fmt.printf("Connected via %s\n", transport_type_str(cfg.detected_transport))
    }

    // Determine encoding
    if cfg.encoding != .Auto {
        cfg.detected_encoding = cfg.encoding
        client.codec.detected_encoding = cfg.encoding
        client.codec.send_encoding = cfg.encoding
        client.codec.encoding_detected = true
    } else if cfg.fire_and_forget {
        cfg.detected_encoding = .Binary
        client.codec.detected_encoding = .Binary
        client.codec.send_encoding = .Binary
        client.codec.encoding_detected = true
    } else if cfg.detected_transport == .UDP {
        cfg.detected_encoding = .CSV
        client.codec.detected_encoding = .CSV
        client.codec.send_encoding = .CSV
        client.codec.encoding_detected = true
        if !cfg.quiet {
            fmt.println("UDP mode: defaulting to CSV")
        }
    } else {
        // TCP mode - probe server
        if !probe_server_encoding(client) {
            fmt.eprintln("Failed to detect server encoding")
            transport_disconnect(&client.transport)
            return false
        }
        if !cfg.quiet {
            fmt.printf("Server encoding: %s\n", encoding_type_str(cfg.detected_encoding))
        }
    }

    client.connected = true

    // Join multicast if configured
    if cfg.multicast.enabled {
        mcast_group := symbol_to_string(cfg.multicast.group[:])
        if !engine_client_join_multicast(client, mcast_group, cfg.multicast.port) {
            fmt.eprintln("Warning: multicast join failed")
        }
    }

    return true
}

engine_client_disconnect :: proc(client: ^Engine_Client) {
    if client.multicast_active {
        engine_client_leave_multicast(client)
    }
    transport_disconnect(&client.transport)
    client.connected = false
}

engine_client_is_connected :: proc(client: ^Engine_Client) -> bool {
    return client.connected && transport_is_connected(&client.transport)
}

// =============================================================================
// Multicast
// =============================================================================

engine_client_join_multicast :: proc(client: ^Engine_Client, group: string, port: u16) -> bool {
    if client.multicast_active {
        return true
    }

    if !client.config.quiet {
        fmt.printf("Joining multicast group %s:%d...\n", group, port)
    }

    if !multicast_receiver_join(&client.multicast, group, port) {
        return false
    }

    client.multicast_active = true
    return true
}

engine_client_leave_multicast :: proc(client: ^Engine_Client) {
    if client.multicast_active {
        multicast_receiver_leave(&client.multicast)
        client.multicast_active = false
    }
}

// =============================================================================
// Callbacks
// =============================================================================

engine_client_set_response_callback :: proc(
    client: ^Engine_Client,
    callback: Response_Callback,
    user_data: rawptr,
) {
    client.response_callback = callback
    client.response_user_data = user_data
}

engine_client_set_multicast_callback :: proc(
    client: ^Engine_Client,
    callback: Multicast_Callback,
    user_data: rawptr,
) {
    client.multicast_callback = callback
    client.multicast_user_data = user_data
}

// =============================================================================
// Order Entry
// =============================================================================

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

    // Auto-assign order ID if not provided
    oid := order_id
    if oid == 0 {
        oid = client.next_order_id
        client.next_order_id += 1
    } else if oid >= client.next_order_id {
        client.next_order_id = oid + 1
    }

    data := codec_encode_new_order(&client.codec, client.config.user_id,
                                   symbol, price, quantity, side, oid)
    if data == nil {
        return 0
    }

    client.last_send_time = time.now()._nsec

    if !transport_send(&client.transport, data) {
        return 0
    }

    client.orders_sent += 1

    if client.config.verbose {
        fmt.printf("[SEND] %s %s %d@%d (order_id=%d)\n",
            side == .Buy ? "BUY" : "SELL", symbol, quantity, price, oid)
    }

    return oid
}

engine_client_send_cancel :: proc(client: ^Engine_Client, order_id: u32) -> bool {
    if !client.connected {
        return false
    }

    data := codec_encode_cancel(&client.codec, client.config.user_id, order_id)
    if data == nil {
        return false
    }

    client.last_send_time = time.now()._nsec

    if !transport_send(&client.transport, data) {
        return false
    }

    client.cancels_sent += 1

    if client.config.verbose {
        fmt.printf("[SEND] CANCEL order_id=%d\n", order_id)
    }

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

    if client.config.verbose {
        fmt.println("[SEND] FLUSH")
    }

    return true
}

// =============================================================================
// Response Handling
// =============================================================================

update_latency_stats :: proc(client: ^Engine_Client) {
    if client.last_send_time == 0 {
        return
    }

    now := time.now()._nsec
    latency := u64(now - client.last_send_time)

    client.total_latency += latency
    client.latency_samples += 1

    if latency < client.min_latency {
        client.min_latency = latency
    }
    if latency > client.max_latency {
        client.max_latency = latency
    }

    client.last_recv_time = now
}

process_response :: proc(client: ^Engine_Client, msg: ^Output_Msg, is_multicast: bool) {
    if !is_multicast {
        update_latency_stats(client)
        client.responses_received += 1
    } else {
        client.multicast_received += 1
    }

    // Invoke callback
    if is_multicast && client.multicast_callback != nil {
        client.multicast_callback(msg, client.multicast_user_data)
    } else if !is_multicast && client.response_callback != nil {
        client.response_callback(msg, client.response_user_data)
    }
}

// Poll for responses (non-blocking)
engine_client_poll :: proc(client: ^Engine_Client) -> int {
    buffer: [RECV_BUFFER_SIZE]u8
    msg: Output_Msg
    count := 0

    // Poll TCP/UDP
    if client.connected && client.config.mode != .Multicast_Only {
        for _ in 0..<MAX_RECV_ATTEMPTS {
            if !transport_has_data(&client.transport) {
                break
            }
            data, ok := transport_recv(&client.transport, buffer[:], 0)
            if !ok {
                break
            }
            if codec_decode_response(&client.codec, data, &msg) {
                process_response(client, &msg, false)
                count += 1
            }
        }
    }

    // Poll multicast
    if client.multicast_active {
        for _ in 0..<MAX_RECV_ATTEMPTS {
            data, ok := multicast_receiver_recv(&client.multicast, buffer[:], 0)
            if !ok {
                break
            }
            if codec_decode_response(&client.codec, data, &msg) {
                process_response(client, &msg, true)
                count += 1
            }
        }
    }

    return count
}

// Receive a single response (blocking with timeout)
engine_client_recv :: proc(client: ^Engine_Client, msg: ^Output_Msg, timeout_ms: int) -> bool {
    if !client.connected && !client.multicast_active {
        return false
    }

    buffer: [RECV_BUFFER_SIZE]u8

    // Check buffered data first
    if client.connected && client.config.mode != .Multicast_Only {
        if transport_has_data(&client.transport) {
            data, ok := transport_recv(&client.transport, buffer[:], 0)
            if ok && codec_decode_response(&client.codec, data, msg) {
                process_response(client, msg, false)
                return true
            }
        }
    }

    // Try receiving with timeout
    if client.connected && client.config.mode != .Multicast_Only {
        data, ok := transport_recv(&client.transport, buffer[:], timeout_ms)
        if ok && codec_decode_response(&client.codec, data, msg) {
            process_response(client, msg, false)
            return true
        }
    }

    return false
}

// Receive all pending responses
engine_client_recv_all :: proc(client: ^Engine_Client, timeout_ms: int) -> int {
    msg: Output_Msg
    count := 0

    // Drain buffered messages first
    for count < MAX_RECV_ATTEMPTS {
        if client.connected && client.config.mode != .Multicast_Only {
            if transport_has_data(&client.transport) {
                if engine_client_recv(client, &msg, 0) {
                    count += 1
                    continue
                }
            }
        }
        break
    }

    // Then poll for new messages
    t := timeout_ms
    for i := count; i < MAX_RECV_ATTEMPTS; i += 1 {
        if !engine_client_recv(client, &msg, t) {
            break
        }
        count += 1
        t = 1  // Short timeout after first
    }

    return count
}

// =============================================================================
// Server Probing
// =============================================================================

probe_server_encoding :: proc(client: ^Engine_Client) -> bool {
    cfg := &client.config
    recv_buf: [4096]u8

    // Save encoding and use binary for probe
    saved_encoding := client.codec.send_encoding
    client.codec.send_encoding = .Binary

    // Send probe order
    data := codec_encode_new_order(&client.codec, cfg.user_id, "ZPROBE", 1, 1, .Buy, 1)
    if data == nil {
        client.codec.send_encoding = saved_encoding
        return false
    }

    if !transport_send(&client.transport, data) {
        client.codec.send_encoding = saved_encoding
        return false
    }

    // Wait for response
    response, ok := transport_recv(&client.transport, recv_buf[:], int(PROBE_TIMEOUT_MS))
    if !ok {
        fmt.eprintln("No response from server (is it running?)")
        client.codec.send_encoding = saved_encoding
        return false
    }

    cfg.detected_encoding = codec_detect_encoding(response)
    client.codec.detected_encoding = cfg.detected_encoding
    client.codec.send_encoding = cfg.detected_encoding
    client.codec.encoding_detected = true

    // Send flush to clear probe
    flush_data := codec_encode_flush(&client.codec)
    if flush_data != nil {
        transport_send(&client.transport, flush_data)
    }

    // Drain responses
    drain_transport(client, 500)

    client.codec.send_encoding = saved_encoding
    return true
}

drain_transport :: proc(client: ^Engine_Client, timeout_ms: int) {
    buf: [4096]u8
    empty_count := 0

    for _ in 0..<MAX_DRAIN_ITERATIONS {
        if transport_has_data(&client.transport) {
            _, ok := transport_recv(&client.transport, buf[:], 0)
            if ok {
                empty_count = 0
                continue
            }
        }

        _, ok := transport_recv(&client.transport, buf[:], 50)
        if ok {
            empty_count = 0
        } else {
            empty_count += 1
            if empty_count >= 3 {
                break
            }
        }
    }
}

// =============================================================================
// Utilities
// =============================================================================

engine_client_get_transport :: proc(client: ^Engine_Client) -> Transport_Type {
    return client.config.detected_transport
}

engine_client_get_encoding :: proc(client: ^Engine_Client) -> Encoding_Type {
    if client.codec.encoding_detected {
        return client.codec.detected_encoding
    }
    return client.config.encoding
}

engine_client_peek_next_order_id :: proc(client: ^Engine_Client) -> u32 {
    return client.next_order_id
}

engine_client_reset_order_id :: proc(client: ^Engine_Client, start_id: u32) {
    client.next_order_id = start_id
}

engine_client_reset_stats :: proc(client: ^Engine_Client) {
    client.orders_sent = 0
    client.cancels_sent = 0
    client.flushes_sent = 0
    client.responses_received = 0
    client.multicast_received = 0
    client.total_latency = 0
    client.latency_samples = 0
    client.min_latency = max(u64)
    client.max_latency = 0
}

engine_client_get_avg_latency_ns :: proc(client: ^Engine_Client) -> u64 {
    if client.latency_samples == 0 {
        return 0
    }
    return client.total_latency / client.latency_samples
}

engine_client_get_min_latency_ns :: proc(client: ^Engine_Client) -> u64 {
    if client.min_latency == max(u64) {
        return 0
    }
    return client.min_latency
}

engine_client_get_max_latency_ns :: proc(client: ^Engine_Client) -> u64 {
    return client.max_latency
}

engine_client_print_stats :: proc(client: ^Engine_Client) {
    fmt.println("\n=== Engine Client Statistics ===\n")

    fmt.println("Connection:")
    fmt.printf("  Host:              %s:%d\n", config_get_host(&client.config), client.config.port)
    fmt.printf("  Transport:         %s\n", transport_type_str(engine_client_get_transport(client)))
    fmt.printf("  Encoding:          %s\n", encoding_type_str(engine_client_get_encoding(client)))
    fmt.printf("  Connected:         %s\n", client.connected ? "yes" : "no")
    fmt.println()

    fmt.println("Messages:")
    fmt.printf("  Orders sent:       %d\n", client.orders_sent)
    fmt.printf("  Cancels sent:      %d\n", client.cancels_sent)
    fmt.printf("  Flushes sent:      %d\n", client.flushes_sent)
    fmt.printf("  Responses recv:    %d\n", client.responses_received)
    if client.multicast_active {
        fmt.printf("  Multicast recv:    %d\n", client.multicast_received)
    }
    fmt.println()

    if client.latency_samples > 0 {
        avg_ns := engine_client_get_avg_latency_ns(client)
        fmt.println("Latency (round-trip):")
        fmt.printf("  Samples:           %d\n", client.latency_samples)
        fmt.printf("  Min:               %d ns (%.3f us)\n",
            client.min_latency, f64(client.min_latency) / 1000.0)
        fmt.printf("  Avg:               %d ns (%.3f us)\n",
            avg_ns, f64(avg_ns) / 1000.0)
        fmt.printf("  Max:               %d ns (%.3f us)\n",
            client.max_latency, f64(client.max_latency) / 1000.0)
        fmt.println()
    }

    transport_print_stats(&client.transport)

    if client.multicast_active {
        fmt.println()
        multicast_receiver_print_stats(&client.multicast)
    }

    fmt.println()
    codec_print_stats(&client.codec)
}
