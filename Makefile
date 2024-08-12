# Define the Zig compiler
ZIG = zig

# Find all .zig files in the src directory and subdirectories
ZIG_SOURCES := $(shell find ./src -name "*.zig")

# Define a target to test each .zig file
test: $(ZIG_SOURCES)
	@for file in $(ZIG_SOURCES); do \
		echo "Running tests for $$file"; \
		$(ZIG) test $$file || exit 1; \
	done
