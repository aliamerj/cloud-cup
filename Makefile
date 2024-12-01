
# Paths
LIBS_DIR := libs
BORINGSSL_DIR := $(LIBS_DIR)/boringssl

# Run the tests (this assumes you already have a test target defined in your build setup)
test:
	@echo "Running tests..."
	zig build test --summary all
