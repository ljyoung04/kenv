CC := gcc
CXX := g++

CFLAGS := -Wall -Wextra -g -static

LIBXDK_DIR := ../kctf/kernel-research/libxdk
LIBXDK_INCLUDE := $(LIBXDK_DIR)/include
LIBXDK_LIBDIR := $(LIBXDK_DIR)/build

TEST_CXXFLAGS := -Wall -Wextra -g -static \
	-std=gnu++17 \
	-I$(LIBXDK_INCLUDE)

TEST_LDLIBS := \
	-L$(LIBXDK_LIBDIR) \
	-lkernelXDK \
	-lpthread \
	-ldl \
	-lkeyutils

all: test help module

test: test.c
	$(CXX) -x c++ $(TEST_CXXFLAGS) -o $@ $< $(TEST_LDLIBS)

help: help.c
	$(CC) $(CFLAGS) -o $@ $<

module:
	$(MAKE) -C helper

clean:
	rm -f test help
	$(MAKE) -C helper clean

.PHONY: all module clean