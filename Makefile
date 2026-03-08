SDKROOT ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
CC ?= $(shell xcrun --sdk iphoneos -f clang)
CFLAGS ?= -isysroot $(SDKROOT) -arch arm64 -fPIC -O2 -Wall -Wextra
LDFLAGS ?= -dynamiclib -framework Foundation -framework UIKit

SRC := filzasbx/main.m
OUT := build/filzasbx.dylib

all: $(OUT)

$(OUT): $(SRC)
	@mkdir -p build
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<
	@echo "built $@"

clean:
	rm -rf build

.PHONY: all clean
