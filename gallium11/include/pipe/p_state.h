#ifndef PIPE_STATE_H
#define PIPE_STATE_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define PIPE_BUFFER 0
#define PIPE_TEXTURE_2D 1
#define PIPE_USAGE_DEFAULT 0
#define PIPE_BIND_VERTEX_BUFFER (1 << 0)
#define PIPE_BIND_INDEX_BUFFER  (1 << 1)
#define PIPE_BIND_RENDER_TARGET (1 << 2)

#define PIPE_PRIMITIVE_TRIANGLES 4

struct pipe_screen;
struct pipe_context;

struct pipe_resource {
    int dummy;
    unsigned width0;
    unsigned height0;
    unsigned format;
    void *data;
};

struct pipe_resource_template {
    unsigned target;
    unsigned format;
    unsigned width0;
    unsigned height0;
    unsigned depth0;
    unsigned array_size;
    unsigned last_level;
    unsigned nr_samples;
    unsigned usage;
    unsigned bind;
    unsigned flags;
};

struct pipe_surface {
    struct pipe_screen *screen;
    struct pipe_resource *texture;
    unsigned format;
    unsigned width0;
    unsigned height0;
    unsigned level;
    unsigned layer;
};

struct pipe_framebuffer_state {
    unsigned width;
    unsigned height;
    unsigned nr_cbufs;
    struct pipe_surface *cbufs[8];
    struct pipe_surface *zsbuf;
};

struct pipe_viewport_state {
    float scale[4];
    float translate[4];
};

struct pipe_rasterizer_state {
    unsigned flatshade:1;
    unsigned light_twoside:1;
    unsigned front_ccw:1;
    unsigned cull_face:2;
    unsigned fill_cw:2;
    unsigned fill_ccw:2;
    unsigned scissor:1;
    unsigned multisample:1;
    float line_width;
    float point_size;
};

struct pipe_vertex_buffer {
    unsigned stride;
    unsigned buffer_offset;
    struct pipe_resource *buffer;
    const void *user_buffer;
};

struct pipe_index_buffer {
    unsigned index_size;
    unsigned offset;
    struct pipe_resource *buffer;
    const void *user_buffer;
};

struct pipe_draw_info {
    unsigned char mode;
    unsigned char indexed;
    unsigned char has_user_indices;
    unsigned char has_user_vertices;
    unsigned start;
    unsigned count;
    unsigned start_instance;
    unsigned instance_count;
    int index_bias;
    unsigned min_index;
    unsigned max_index;
    union {
        struct pipe_resource *resource;
        const void *user;
    } indices;
};

#endif // PIPE_STATE_H
