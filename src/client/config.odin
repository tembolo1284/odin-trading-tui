package client

// =============================================================================
// Client Configuration
//
// Matches C implementation's client/client_config.h
// =============================================================================

// =============================================================================
// Constants
// =============================================================================

DEFAULT_PORT         :: 1234
DEFAULT_TIMEOUT_MS   :: 1000
PROBE_TIMEOUT_MS     :: 500
MAX_HOST_LEN         :: 256
RECV_BUFFER_SIZE     :: 8192
SEND_BUFFER_SIZE     :: 8192

DEFAULT_MCAST_GROUP  :: "239.255.0.1"
DEFAULT_MCAST_PORT   :: 5000

// =============================================================================
// Enumerations
// =============================================================================

Transport_Type :: enum {
    Auto,  // Try TCP first, fall back to UDP
    TCP,
    UDP,
}

transport_type_str :: proc(t: Transport_Type) -> string {
    switch t {
    case .Auto: return "auto"
    case .TCP:  return "TCP"
    case .UDP:  return "UDP"
    }
    return "unknown"
}

Encoding_Type :: enum {
    Auto,    // Probe server to detect
    Binary,
    CSV,
}

encoding_type_str :: proc(e: Encoding_Type) -> string {
    switch e {
    case .Auto:   return "auto"
    case .Binary: return "binary"
    case .CSV:    return "CSV"
    }
    return "unknown"
}

Client_Mode :: enum {
    Interactive,     // REPL mode
    Scenario,        // Run predefined scenario
    Multicast_Only,  // Only subscribe to multicast
}

client_mode_str :: proc(m: Client_Mode) -> string {
    switch m {
    case .Interactive:    return "interactive"
    case .Scenario:       return "scenario"
    case .Multicast_Only: return "multicast-only"
    }
    return "unknown"
}

Conn_State :: enum {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

// =============================================================================
// Multicast Configuration
// =============================================================================

Multicast_Config :: struct {
    enabled: bool,
    group:   [64]u8,
    port:    u16,
    sock_fd: i32,
}

// =============================================================================
// Client Configuration
// =============================================================================

Client_Config :: struct {
    // Connection target
    host: [MAX_HOST_LEN]u8,
    port: u16,

    // Transport and encoding
    transport:          Transport_Type,
    encoding:           Encoding_Type,
    detected_transport: Transport_Type,
    detected_encoding:  Encoding_Type,

    // Operating mode
    mode:            Client_Mode,
    scenario_id:     int,
    fire_and_forget: bool,
    danger_burst:    bool,

    // Multicast
    multicast: Multicast_Config,

    // Timeouts (milliseconds)
    connect_timeout_ms: u32,
    recv_timeout_ms:    u32,

    // Verbosity
    verbose: bool,
    quiet:   bool,

    // User ID for orders
    user_id: u32,
}

// Initialize config with defaults
config_init :: proc(config: ^Client_Config) {
    config^ = {}

    config.port = DEFAULT_PORT
    config.transport = .Auto
    config.encoding = .Auto
    config.detected_transport = .Auto
    config.detected_encoding = .Auto
    config.mode = .Interactive
    config.multicast.port = DEFAULT_MCAST_PORT
    config.multicast.sock_fd = -1
    config.connect_timeout_ms = DEFAULT_TIMEOUT_MS
    config.recv_timeout_ms = DEFAULT_TIMEOUT_MS
    config.user_id = 1
}

// Set host string
config_set_host :: proc(config: ^Client_Config, host: string) {
    n := min(len(host), MAX_HOST_LEN - 1)
    for i in 0..<n {
        config.host[i] = host[i]
    }
    config.host[n] = 0
}

// Get host as string
config_get_host :: proc(config: ^Client_Config) -> string {
    n := 0
    for i in 0..<MAX_HOST_LEN {
        if config.host[i] == 0 {
            break
        }
        n = i + 1
    }
    return string(config.host[:n])
}

// Validate configuration
config_validate :: proc(config: ^Client_Config) -> bool {
    // Must have host unless multicast-only mode
    if config.mode != .Multicast_Only && config.host[0] == 0 {
        return false
    }

    // Multicast-only requires multicast enabled
    if config.mode == .Multicast_Only && !config.multicast.enabled {
        return false
    }

    // Port must be non-zero
    if config.port == 0 && config.mode != .Multicast_Only {
        return false
    }

    return true
}
