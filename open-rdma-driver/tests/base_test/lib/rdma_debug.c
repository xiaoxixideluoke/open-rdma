#include "rdma_debug.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_hex_line(const char *buf, size_t offset, size_t length,
                          const char *diff_mask, const char *color) {
    printf("0x%08lx: ", (unsigned long)offset);

    // Print hex values
    for (size_t i = 0; i < length; i++) {
        if (diff_mask && diff_mask[i]) {
            printf("%s%02x%s ", color, (unsigned char)buf[i], ANSI_COLOR_RESET);
        } else {
            printf("%02x ", (unsigned char)buf[i]);
        }
    }

    // Padding
    for (size_t i = length; i < 16; i++) {
        printf("   ");
    }
}

static void create_diff_mask(const char *buf1, const char *buf2, size_t offset,
                            size_t length, char *diff_mask) {
    for (size_t j = 0; j < length; j++) {
        diff_mask[j] = (buf1[offset + j] != buf2[offset + j]) ? 1 : 0;
    }
}

size_t rdma_memory_diff(const char *buf1, const char *buf2, size_t length) {
    int has_differences = 0;
    size_t bytes_per_line = 16;
    size_t total_diff_bytes = 0;

    for (size_t i = 0; i < length; i += bytes_per_line) {
        char diff_mask[16] = {0};
        int line_has_diff = 0;
        size_t line_length = (i + bytes_per_line <= length) ? bytes_per_line : length - i;

        // Check for differences in this line
        for (size_t j = 0; j < line_length; j++) {
            if (buf1[i + j] != buf2[i + j]) {
                diff_mask[j] = 1;
                line_has_diff = 1;
                has_differences = 1;
                total_diff_bytes++;
            }
        }

        if (line_has_diff) {
            // Print previous line for context
            if (i >= bytes_per_line) {
                char prev_diff_mask[16] = {0};
                size_t prev_line_length = bytes_per_line;
                create_diff_mask(buf1, buf2, i - bytes_per_line, prev_line_length, prev_diff_mask);

                printf("\n");
                print_hex_line(buf1 + i - bytes_per_line, i - bytes_per_line,
                             prev_line_length, prev_diff_mask, ANSI_COLOR_RED);
                printf("    ");
                print_hex_line(buf2 + i - bytes_per_line, i - bytes_per_line,
                             prev_line_length, prev_diff_mask, ANSI_COLOR_GREEN);
                printf("\n");
            }

            // Print current line
            print_hex_line(buf1 + i, i, line_length, diff_mask, ANSI_COLOR_RED);
            printf("    ");
            print_hex_line(buf2 + i, i, line_length, diff_mask, ANSI_COLOR_GREEN);
            printf("\n");

            // Print next line for context
            if (i + bytes_per_line < length) {
                char next_diff_mask[16] = {0};
                size_t next_line_length = (i + 2 * bytes_per_line <= length) ?
                    bytes_per_line : length - (i + bytes_per_line);
                create_diff_mask(buf1, buf2, i + bytes_per_line, next_line_length, next_diff_mask);

                print_hex_line(buf1 + i + bytes_per_line, i + bytes_per_line,
                             next_line_length, next_diff_mask, ANSI_COLOR_RED);
                printf("    ");
                print_hex_line(buf2 + i + bytes_per_line, i + bytes_per_line,
                             next_line_length, next_diff_mask, ANSI_COLOR_GREEN);
                printf("\n");
            }

            printf("\n");
        }
    }

    if (!has_differences) {
        printf("No differences found between the two memory regions.\n");
    }

    return total_diff_bytes;
}

void rdma_print_memory_hex(const void *start_addr, size_t length) {
    if (!start_addr || length == 0) {
        printf("Invalid parameters: start_addr=%p, length=%zu\n", start_addr, length);
        return;
    }

    const unsigned char *addr = (const unsigned char *)start_addr;
    const size_t bytes_per_line = 16;

    printf("Memory dump from %p to %p (%zu bytes)\n", start_addr,
           (const void *)((const char *)start_addr + length), length);

    for (size_t offset = 0; offset < length; offset += bytes_per_line) {
        size_t line_length = (offset + bytes_per_line <= length) ?
            bytes_per_line : length - offset;

        // Print address
        printf("%016lx: ", (unsigned long)(addr + offset));

        // Print hex values
        for (size_t i = 0; i < bytes_per_line; i++) {
            if (i < line_length) {
                printf("%02x ", addr[offset + i]);
            } else {
                printf("   ");
            }
        }

        printf(" ");

        // Print ASCII representation
        for (size_t i = 0; i < line_length; i++) {
            unsigned char c = addr[offset + i];
            if (c >= 32 && c <= 126) {
                printf("%c", c);
            } else {
                printf(".");
            }
        }

        printf("\n");
    }
}

void rdma_print_zero_ranges(const char *buffer, size_t length) {
    if (!buffer) return;

    int start = -1;
    int zero_count = 0;

    for (size_t i = 0; i < length; i++) {
        if (buffer[i] == 0) {
            if (start == -1) {
                start = i;
            }
            zero_count++;
        } else {
            if (start != -1) {
                printf("Zero range: 0x%08x - 0x%08zx (length: %d bytes)\n",
                       start, i - 1, (int)(i - start));
                start = -1;
            }
        }
    }

    if (start != -1) {
        printf("Zero range: 0x%08x - 0x%08zx (length: %d bytes)\n",
               start, length - 1, (int)(length - start));
    }

    if (zero_count == 0) {
        printf("No zero bytes found in buffer\n");
    } else {
        printf("Total zero bytes: %d / %zu\n", zero_count, length);
    }
}

int rdma_generate_pattern(void *buffer, size_t length,
                          const struct rdma_pattern *pattern) {
    if (!buffer || !pattern) {
        fprintf(stderr, "[ERROR] Invalid parameters to rdma_generate_pattern\n");
        return -1;
    }

    uint8_t *buf = (uint8_t *)buffer;

    switch (pattern->type) {
    case RDMA_PATTERN_SEQUENTIAL:
        // Generate sequential bytes: 0x00, 0x01, ..., 0xFF, 0x00, ...
        for (size_t i = 0; i < length; i++) {
            buf[i] = i & 0xFF;
        }
        break;

    case RDMA_PATTERN_FIXED_CHAR:
        // Fill with fixed character
        memset(buf, pattern->fixed_char, length);
        break;

    case RDMA_PATTERN_CUSTOM:
        // Copy user-provided data
        if (!pattern->custom_data) {
            fprintf(stderr, "[ERROR] Custom pattern data is NULL\n");
            return -1;
        }
        memcpy(buf, pattern->custom_data, length);
        break;

    default:
        fprintf(stderr, "[ERROR] Unknown pattern type: %d\n", pattern->type);
        return -1;
    }

    return 0;
}

int rdma_verify_data(const void *received_data, size_t length,
                     const struct rdma_pattern *expected_pattern,
                     size_t *error_count) {
    if (!received_data || !expected_pattern) {
        fprintf(stderr, "[ERROR] Invalid parameters to rdma_verify_data\n");
        if (error_count) *error_count = length;
        return -1;
    }

    // Allocate temporary buffer for expected data
    void *expected_buffer = malloc(length);
    if (!expected_buffer) {
        fprintf(stderr, "[ERROR] Failed to allocate verification buffer (%zu bytes)\n", length);
        if (error_count) *error_count = length;
        return -1;
    }

    // Generate expected pattern
    if (rdma_generate_pattern(expected_buffer, length, expected_pattern) < 0) {
        free(expected_buffer);
        if (error_count) *error_count = length;
        return -1;
    }

    // Use existing rdma_memory_diff for detailed comparison
    // This automatically prints colored diff output
    size_t diff_count = rdma_memory_diff(expected_buffer, received_data, length);

    free(expected_buffer);

    if (error_count) {
        *error_count = diff_count;
    }

    return (diff_count == 0) ? 0 : -1;
}
