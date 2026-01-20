# Odin Trading TUI Client - Makefile

# Directories
PROJECT_DIR := $(shell pwd)
BUILD_DIR := $(PROJECT_DIR)/build
SRC_CLIENT := $(PROJECT_DIR)/src/client
SRC_DECODER := $(PROJECT_DIR)/src/decoder
TEST_DIR := $(PROJECT_DIR)/tests

# Output binaries
CLIENT_BIN := $(BUILD_DIR)/client
DECODER_BIN := $(BUILD_DIR)/decoder

# Odin compiler flags
ODIN := odin

# Strict flags for development
STRICT_FLAGS := -vet -strict-style -warnings-as-errors

# Release flags
RELEASE_FLAGS := -o:speed -disable-assert

# Debug flags
DEBUG_FLAGS := -debug -o:none

# Colors (optional, for pretty output)
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

.PHONY: all build debug release clean test run decoder help

# Default target
all: build

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Build with strict checks (development)
build: $(BUILD_DIR)
	@echo "$(GREEN)Building client (strict)...$(NC)"
	$(ODIN) build $(SRC_CLIENT) \
		-out:$(CLIENT_BIN) \
		$(STRICT_FLAGS) \
		-o:speed
	@echo "$(GREEN)Built: $(CLIENT_BIN)$(NC)"

# Debug build with strict checks
debug: $(BUILD_DIR)
	@echo "$(YELLOW)Building client (debug + strict)...$(NC)"
	$(ODIN) build $(SRC_CLIENT) \
		-out:$(CLIENT_BIN) \
		$(STRICT_FLAGS) \
		$(DEBUG_FLAGS)
	@echo "$(GREEN)Built: $(CLIENT_BIN)$(NC)"

# Release build (optimized, no asserts)
release: $(BUILD_DIR)
	@echo "$(GREEN)Building client (release)...$(NC)"
	$(ODIN) build $(SRC_CLIENT) \
		-out:$(CLIENT_BIN) \
		$(STRICT_FLAGS) \
		$(RELEASE_FLAGS)
	@echo "$(GREEN)Built: $(CLIENT_BIN)$(NC)"

# Check only (no binary output)
check:
	@echo "$(YELLOW)Checking client...$(NC)"
	$(ODIN) check $(SRC_CLIENT) $(STRICT_FLAGS)
	@echo "$(GREEN)Check passed$(NC)"

# Run the client (build first if needed)
run: build
	@echo "$(GREEN)Running client...$(NC)"
	$(CLIENT_BIN) $(ARGS)

# Run with arguments: make run ARGS="localhost 1234 --tcp"
run-debug: debug
	@echo "$(GREEN)Running client (debug)...$(NC)"
	$(CLIENT_BIN) $(ARGS)

# Build decoder
decoder: $(BUILD_DIR)
	@echo "$(GREEN)Building decoder...$(NC)"
	$(ODIN) build $(SRC_DECODER) \
		-out:$(DECODER_BIN) \
		$(STRICT_FLAGS) \
		-o:speed
	@echo "$(GREEN)Built: $(DECODER_BIN)$(NC)"

# Run tests
test:
	@echo "$(GREEN)Running tests...$(NC)"
	$(ODIN) test $(TEST_DIR) -all-packages $(STRICT_FLAGS)
	@echo "$(GREEN)Tests complete$(NC)"

# Clean build artifacts
clean:
	@echo "$(YELLOW)Cleaning...$(NC)"
	rm -rf $(BUILD_DIR)
	@echo "$(GREEN)Clean complete$(NC)"

# Help
help:
	@echo "Odin Trading TUI Client"
	@echo ""
	@echo "Usage: make [target] [ARGS=\"...\"]"
	@echo ""
	@echo "Targets:"
	@echo "  build     Build client with strict checks (default)"
	@echo "  debug     Build client with debug info + strict checks"
	@echo "  release   Build optimized release binary"
	@echo "  check     Check code without building"
	@echo "  run       Build and run client (use ARGS for arguments)"
	@echo "  run-debug Build debug and run client"
	@echo "  decoder   Build the decoder tool"
	@echo "  test      Run tests"
	@echo "  clean     Remove build artifacts"
	@echo "  help      Show this help"
	@echo ""
	@echo "Examples:"
	@echo "  make build"
	@echo "  make run ARGS=\"localhost 1234\""
	@echo "  make run ARGS=\"localhost 1234 2 --tcp\""
	@echo "  make debug"
	@echo "  make test"
	@echo ""
	@echo "Strict flags enabled: -vet -strict-style -warnings-as-errors"
