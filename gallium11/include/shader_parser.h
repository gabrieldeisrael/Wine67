#ifndef SHADER_PARSER_H
#define SHADER_PARSER_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint32_t fourcc;
    uint32_t size;
    const uint8_t *data;
} dxbc_chunk_t;

int parse_dxbc_container(const uint8_t *data, size_t size);
uint8_t* create_color_triangle_vs_bytecode(size_t *out_size);
uint8_t* create_color_triangle_ps_bytecode(size_t *out_size);

#endif // SHADER_PARSER_H
