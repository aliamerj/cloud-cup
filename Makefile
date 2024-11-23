
# Paths
LIBS_DIR := libs
BORINGSSL_DIR := $(LIBS_DIR)/boringssl


install:
	@echo "Setting up libs directory..."
	mkdir -p $(LIBS_DIR)

	@echo "Downloading BoringSSL tarball..."
	curl -L https://github.com/google/boringssl/archive/refs/heads/master.zip -o $(LIBS_DIR)/boringssl.zip

	@echo "Extracting BoringSSL..."
	unzip -q $(LIBS_DIR)/boringssl.zip -d $(LIBS_DIR)
	mv $(LIBS_DIR)/boringssl-master $(BORINGSSL_DIR)
	rm $(LIBS_DIR)/boringssl.zip

	@echo "Building BoringSSL..."
	cd $(BORINGSSL_DIR) && cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release && ninja -C build

	@echo "Cleaning up unnecessary files..."
	cd $(BORINGSSL_DIR) && rm -rf build/CMakeFiles && rm -f build/CMakeCache.txt build/Makefile build/*.ninja

	@echo "BoringSSL installation completed."

clean:
	@echo "Cleaning up BoringSSL..."
	rm -rf $(BORINGSSL_DIR)
	@echo "Cleanup completed."


# Run the tests (this assumes you already have a test target defined in your build setup)
test:
	@echo "Running tests..."
	zig build test --summary all
