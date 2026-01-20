# Matching Engine Client - Odin

An Odin port of the C matching engine client.

## Structure

```
matching-engine-odin/
├── build.sh
├── README.md
├── src/
│   ├── client/
│   │   ├── main.odin           # Entry point, arg parsing
│   │   ├── types.odin          # Core types (Side, Messages)
│   │   ├── config.odin         # Client configuration
│   │   ├── binary.odin         # Binary protocol encode/decode
│   │   ├── csv.odin            # CSV protocol encode/decode
│   │   ├── codec.odin          # Unified codec layer
│   │   ├── framing.odin        # TCP length-prefix framing
│   │   ├── transport.odin      # TCP/UDP transport
│   │   ├── multicast.odin      # Multicast receiver
│   │   ├── engine_client.odin  # High-level client API
│   │   ├── interactive.odin    # REPL interface
│   │   └── scenarios.odin      # Test scenarios
│   └── decoder/
│       └── main.odin           # Binary message decoder tool
├── tests/
│   ├── test_binary.odin
│   ├── test_csv.odin
│   └── test_framing.odin
└── build/                      # Build output (generated)
```

## Building

```bash
# Build release
./build.sh build

# Build debug
./build.sh debug

# Clean
./build.sh clean
```

## Running

```bash
# Interactive mode
./build.sh run localhost 1234

# With scenario
./build.sh run localhost 1234 2 --tcp

# Options
./build.sh run localhost 1234 --tcp --binary
./build.sh run localhost 1234 --udp --csv
```

## Testing

```bash
./build.sh test
```

## Interactive Commands

| Command | Alias | Description |
|---------|-------|-------------|
| buy SYMBOL QTY@PRICE | b | Send buy order |
| sell SYMBOL QTY@PRICE | s | Send sell order |
| cancel ORDER_ID | c | Cancel order |
| flush | f | Flush all orders |
| recv [timeout_ms] | r | Receive responses |
| poll | p | Poll messages |
| scenario ID | sc | Run scenario |
| scenarios | list | List scenarios |
| stats | | Print statistics |
| status | | Connection status |
| help | h | Show help |
| quit | q | Exit |

## Scenarios

| ID | Description |
|----|-------------|
| 1 | Simple orders (no match) |
| 2 | Matching trade |
| 3 | Cancel order |
| 10 | Stress: 1K orders |
| 11 | Stress: 10K orders |
| 20 | Matching: 1K pairs |
| 21 | Matching: 10K pairs |
| 22 | Matching: 100K pairs |
| 23 | Matching: 1M pairs |
| 24 | Matching: 10M pairs |

## Wire Protocol

### Binary Format

All multi-byte integers are network byte order (big-endian).

| Message | Size | Format |
|---------|------|--------|
| New Order | 27 | magic(1) + type(1) + user_id(4) + symbol(8) + price(4) + qty(4) + side(1) + order_id(4) |
| Cancel | 10 | magic(1) + type(1) + user_id(4) + order_id(4) |
| Flush | 2 | magic(1) + type(1) |

### TCP Framing

```
[4-byte length (big-endian)][payload]
```

## Requirements

- Odin compiler (latest)
- Linux or macOS
