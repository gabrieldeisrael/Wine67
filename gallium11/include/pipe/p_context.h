#ifndef P_CONTEXT_H
#define P_CONTEXT_H

struct pipe_context;
struct pipe_vertex_buffer;
struct pipe_index_buffer;
struct pipe_draw_info;
struct pipe_framebuffer_state;
struct pipe_viewport_state;
struct pipe_rasterizer_state;
struct pipe_fence_handle;
struct pipe_vertex_element;

struct pipe_context {
    void (*destroy)(struct pipe_context *context);
    void (*draw_vbo)(struct pipe_context *context, const struct pipe_draw_info *info);
    void (*set_vertex_buffers)(struct pipe_context *context, unsigned start_slot, unsigned num_buffers, const struct pipe_vertex_buffer *buffers);
    void (*set_index_buffer)(struct pipe_context *context, const struct pipe_index_buffer *ibuffer);

    void *(*create_vs_state)(struct pipe_context *context, const void *state);
    void (*bind_vs_state)(struct pipe_context *context, void *state);
    void (*delete_vs_state)(struct pipe_context *context, void *state);

    void *(*create_fs_state)(struct pipe_context *context, const void *state);
    void (*bind_fs_state)(struct pipe_context *context, void *state);
    void (*delete_fs_state)(struct pipe_context *context, void *state);

    void (*set_framebuffer_state)(struct pipe_context *context, const struct pipe_framebuffer_state *state);
    void (*set_viewport_state)(struct pipe_context *context, const struct pipe_viewport_state *state);

    void *(*create_vertex_elements_state)(struct pipe_context *context, unsigned num_elements, const struct pipe_vertex_element *elements);
    void (*bind_vertex_elements_state)(struct pipe_context *context, void *state);
    void (*delete_vertex_elements_state)(struct pipe_context *context, void *state);

    void *(*create_rasterizer_state)(struct pipe_context *context, const struct pipe_rasterizer_state *state);
    void (*set_rasterizer_state)(struct pipe_context *context, void *state);
    void (*delete_rasterizer_state)(struct pipe_context *context, void *state);

    void (*flush)(struct pipe_context *context, struct pipe_fence_handle **fence, unsigned flags);
};

#endif // P_CONTEXT_H
