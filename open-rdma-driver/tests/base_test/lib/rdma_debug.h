#ifndef RDMA_DEBUG_H
#define RDMA_DEBUG_H

#include <stddef.h>
#include <stdint.h>

// ANSI color codes
#define ANSI_COLOR_RED     "\x1b[31m"
#define ANSI_COLOR_GREEN   "\x1b[32m"
#define ANSI_COLOR_YELLOW  "\x1b[33m"
#define ANSI_COLOR_BLUE    "\x1b[34m"
#define ANSI_COLOR_MAGENTA "\x1b[35m"
#define ANSI_COLOR_CYAN    "\x1b[36m"
#define ANSI_COLOR_RESET   "\x1b[0m"

// Compiler barrier
#define COMPILER_BARRIER() asm volatile("" ::: "memory")

// Memory comparison and visualization
size_t rdma_memory_diff(const char *buf1, const char *buf2, size_t length);
void rdma_print_memory_hex(const void *start_addr, size_t length);
void rdma_print_zero_ranges(const char *buffer, size_t length);

// Data pattern types for verification
typedef enum {
    RDMA_PATTERN_SEQUENTIAL,    // Sequential bytes (i & 0xFF)
    RDMA_PATTERN_FIXED_CHAR,    // Fixed character pattern
    RDMA_PATTERN_CUSTOM         // Custom pattern (user-provided data)
} rdma_pattern_type_t;

// Pattern specification
struct rdma_pattern {
    rdma_pattern_type_t type;
    union {
        uint8_t fixed_char;      // For RDMA_PATTERN_FIXED_CHAR
        const void *custom_data; // For RDMA_PATTERN_CUSTOM
    };
};

// Pattern generation and data verification
int rdma_generate_pattern(void *buffer, size_t length,
                          const struct rdma_pattern *pattern);
int rdma_verify_data(const void *received_data, size_t length,
                     const struct rdma_pattern *expected_pattern,
                     size_t *error_count);

// Convenience macros for creating pattern objects
#define RDMA_PATTERN_SEQ()        ((struct rdma_pattern){.type = RDMA_PATTERN_SEQUENTIAL})
#define RDMA_PATTERN_CHAR(c)      ((struct rdma_pattern){.type = RDMA_PATTERN_FIXED_CHAR, .fixed_char = (c)})
#define RDMA_PATTERN_CUSTOM(ptr)  ((struct rdma_pattern){.type = RDMA_PATTERN_CUSTOM, .custom_data = (ptr)})

#endif // RDMA_DEBUG_H
