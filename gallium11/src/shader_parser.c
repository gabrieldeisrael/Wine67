#include "shader_parser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int parse_dxbc_container(const uint8_t *data, size_t size) {
    if (size < 32) {
        fprintf(stderr, "Error: DXBC container size %zu is too small (min 32 bytes)\n", size);
        return -1;
    }

    printf("Parsing DXBC container of size %zu bytes...\n", size);

    // Verify magic 'DXBC'
    if (memcmp(data, "DXBC", 4) != 0) {
        fprintf(stderr, "Error: Invalid DXBC magic bytes\n");
        return -1;
    }

    uint32_t chunk_count = *(const uint32_t *)(data + 28);
    uint32_t total_size = *(const uint32_t *)(data + 24);
    printf("DXBC Header verified: version=0x%x, total_size=%u, chunk_count=%u\n",
           *(const uint32_t *)(data + 20), total_size, chunk_count);

    const uint32_t *offsets = (const uint32_t *)(data + 32);
    for (uint32_t i = 0; i < chunk_count; i++) {
        uint32_t offset = offsets[i];
        if (offset + 8 > size) {
            fprintf(stderr, "Error: Chunk %u offset %u out of bounds\n", i, offset);
            return -1;
        }
        uint32_t chunk_size = *(const uint32_t *)(data + offset);
        uint32_t fourcc = *(const uint32_t *)(data + offset + 4);

        char fourcc_str[5] = {
            (char)(fourcc & 0xff),
            (char)((fourcc >> 8) & 0xff),
            (char)((fourcc >> 16) & 0xff),
            (char)((fourcc >> 24) & 0xff),
            '\0'
        };

        printf("  Chunk %u: FourCC = '%s' (0x%08x), Size = %u bytes at offset %u\n",
               i, fourcc_str, fourcc, chunk_size, offset);
    }

    return 0;
}

// Helper to create a sample DXBC binary blob for Color Triangle Vertex Shader
uint8_t* create_color_triangle_vs_bytecode(size_t *out_size) {
    size_t total_size = 76;
    uint8_t *blob = (uint8_t *)calloc(1, total_size);
    if (!blob) return NULL;

    memcpy(blob, "DXBC", 4);
    *(uint32_t *)(blob + 20) = 0x00000001;
    *(uint32_t *)(blob + 24) = (uint32_t)total_size;
    *(uint32_t *)(blob + 28) = 1;
    *(uint32_t *)(blob + 32) = 36;

    uint32_t chunk_offset = 36;
    uint32_t chunk_payload_size = 32;
    uint32_t chunk_total_size = 8 + chunk_payload_size;
    *(uint32_t *)(blob + chunk_offset) = chunk_total_size;
    memcpy(blob + chunk_offset + 4, "SHDR", 4);

    uint32_t *bytecode = (uint32_t *)(blob + chunk_offset + 8);
    bytecode[0] = 0x01000050; // VS 4.0 / 5.0 token header
    bytecode[1] = 0x00000008; // Length
    bytecode[2] = 0x10000001; // dcl_output position
    bytecode[3] = 0x10000002; // dcl_output color
    bytecode[4] = 0x20000060; // mov o0.xyzw, v0.xyzw
    bytecode[5] = 0x00000000;
    bytecode[6] = 0x20000061; // mov o1.xyzw, v1.xyzw
    bytecode[7] = 0x00000000;

    if (out_size) *out_size = total_size;
    return blob;
}

// Helper to create a sample DXBC binary blob for Color Triangle Pixel Shader
uint8_t* create_color_triangle_ps_bytecode(size_t *out_size) {
    size_t total_size = 76;
    uint8_t *blob = (uint8_t *)calloc(1, total_size);
    if (!blob) return NULL;

    memcpy(blob, "DXBC", 4);
    *(uint32_t *)(blob + 20) = 0x00000001;
    *(uint32_t *)(blob + 24) = (uint32_t)total_size;
    *(uint32_t *)(blob + 28) = 1;
    *(uint32_t *)(blob + 32) = 36;

    uint32_t chunk_offset = 36;
    uint32_t chunk_payload_size = 32;
    uint32_t chunk_total_size = 8 + chunk_payload_size;
    *(uint32_t *)(blob + chunk_offset) = chunk_total_size;
    memcpy(blob + chunk_offset + 4, "SHDR", 4);

    uint32_t *bytecode = (uint32_t *)(blob + chunk_offset + 8);
    bytecode[0] = 0x01000060; // PS 4.0 / 5.0 token header
    bytecode[1] = 0x00000008; // Length
    bytecode[2] = 0x10000002; // dcl_input color
    bytecode[3] = 0x10000003; // dcl_output color
    bytecode[4] = 0x20000063; // mov o0.xyzw, v0.xyzw
    bytecode[5] = 0x00000000;
    bytecode[6] = 0x00000001; // ret
    bytecode[7] = 0x00000000;

    if (out_size) *out_size = total_size;
    return blob;
}
