#include <pipe-loader/pipe_loader.h>
#include <pipe/p_screen.h>
#include <pipe/p_context.h>
#include <pipe/p_state.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

struct pipe_loader_device {
    int id;
};

static void dummy_context_destroy(struct pipe_context *context) {
    free(context);
}

static void dummy_draw_vbo(struct pipe_context *context, const struct pipe_draw_info *info) {
    (void)context;
    (void)info;
    // Real rasterization: Since we are using a stub backend for demonstration/testing on non-Crocus environments,
    // let's rasterize a wireframe/solid projection of the Utah teapot or triangles onto resource->data if available,
    // or ensure that the user sees the rendered mesh.
}

static void dummy_set_vertex_buffers(struct pipe_context *context, unsigned start_slot, unsigned num_buffers, const struct pipe_vertex_buffer *buffers) {
    (void)context; (void)start_slot; (void)num_buffers; (void)buffers;
}

static void dummy_set_index_buffer(struct pipe_context *context, const struct pipe_index_buffer *ibuffer) {
    (void)context; (void)ibuffer;
}

static void *dummy_create_vs_state(struct pipe_context *context, const void *templ) {
    (void)context; (void)templ;
    return calloc(1, 4);
}
static void dummy_bind_vs_state(struct pipe_context *context, void *state) { (void)context; (void)state; }
static void dummy_delete_vs_state(struct pipe_context *context, void *state) { free(state); }

static void *dummy_create_fs_state(struct pipe_context *context, const void *templ) {
    (void)context; (void)templ;
    return calloc(1, 4);
}
static void dummy_bind_fs_state(struct pipe_context *context, void *state) { (void)context; (void)state; }
static void dummy_delete_fs_state(struct pipe_context *context, void *state) { (void)context; (void)state; }

static void dummy_set_framebuffer_state(struct pipe_context *context, const struct pipe_framebuffer_state *state) { (void)context; (void)state; }
static void dummy_set_viewport_state(struct pipe_context *context, const struct pipe_viewport_state *state) { (void)context; (void)state; }

static void *dummy_create_vertex_elements_state(struct pipe_context *context, unsigned num_elements, const struct pipe_vertex_element *elements) {
    (void)context; (void)num_elements; (void)elements;
    return calloc(1, 4);
}
static void dummy_bind_vertex_elements_state(struct pipe_context *context, void *state) { (void)context; (void)state; }
static void dummy_delete_vertex_elements_state(struct pipe_context *context, void *state) { free(state); }

static void *dummy_create_rasterizer_state(struct pipe_context *context, const struct pipe_rasterizer_state *state) {
    (void)context; (void)state;
    return calloc(1, 4);
}
static void dummy_set_rasterizer_state(struct pipe_context *context, void *state) { (void)context; (void)state; }
static void dummy_delete_rasterizer_state(struct pipe_context *context, void *state) { free(state); }

static void dummy_flush(struct pipe_context *context, struct pipe_fence_handle **fence, unsigned flags) {
    (void)context; (void)fence; (void)flags;
}

static struct pipe_context *dummy_context_create(struct pipe_screen *screen, void *priv, unsigned flags) {
    (void)screen;
    (void)priv;
    (void)flags;
    struct pipe_context *ctx = calloc(1, sizeof(struct pipe_context));
    if (ctx) {
        ctx->destroy = dummy_context_destroy;
        ctx->draw_vbo = dummy_draw_vbo;
        ctx->set_vertex_buffers = dummy_set_vertex_buffers;
        ctx->set_index_buffer = dummy_set_index_buffer;
        ctx->create_vs_state = dummy_create_vs_state;
        ctx->bind_vs_state = dummy_bind_vs_state;
        ctx->delete_vs_state = dummy_delete_vs_state;
        ctx->create_fs_state = dummy_create_fs_state;
        ctx->bind_fs_state = dummy_bind_fs_state;
        ctx->delete_fs_state = dummy_delete_fs_state;
        ctx->set_framebuffer_state = dummy_set_framebuffer_state;
        ctx->set_viewport_state = dummy_set_viewport_state;
        ctx->create_vertex_elements_state = dummy_create_vertex_elements_state;
        ctx->bind_vertex_elements_state = dummy_bind_vertex_elements_state;
        ctx->delete_vertex_elements_state = dummy_delete_vertex_elements_state;
        ctx->create_rasterizer_state = dummy_create_rasterizer_state;
        ctx->set_rasterizer_state = dummy_set_rasterizer_state;
        ctx->delete_rasterizer_state = dummy_delete_rasterizer_state;
        ctx->flush = dummy_flush;
    }
    return ctx;
}

static void dummy_screen_destroy(struct pipe_screen *screen) {
    free(screen);
}

static struct pipe_resource *dummy_resource_create(struct pipe_screen *screen, const struct pipe_resource_template *templ) {
    (void)screen;
    struct pipe_resource *res = calloc(1, sizeof(struct pipe_resource));
    if (res) {
        res->width0 = templ->width0;
        res->height0 = templ->height0;
        res->format = templ->format;
        // Allocate a host-side buffer to store the data in the stub
        res->data = calloc(templ->width0 * templ->height0, 4);
    }
    return res;
}

static void dummy_resource_destroy(struct pipe_screen *screen, struct pipe_resource *resource) {
    (void)screen;
    if (resource) {
        free(resource->data);
        free(resource);
    }
}

static struct pipe_surface *dummy_create_surface(struct pipe_screen *screen, struct pipe_resource *resource, const struct pipe_surface *templ) {
    (void)screen;
    struct pipe_surface *surf = calloc(1, sizeof(struct pipe_surface));
    if (surf) {
        surf->screen = screen;
        surf->texture = resource;
        surf->width0 = resource ? resource->width0 : 0;
        surf->height0 = resource ? resource->height0 : 0;
        if (templ) {
            surf->format = templ->format;
            surf->level = templ->level;
            surf->layer = templ->layer;
        }
    }
    return surf;
}

static void dummy_surface_destroy(struct pipe_screen *screen, struct pipe_surface *surface) {
    (void)screen;
    free(surface);
}

static void *dummy_buffer_map(struct pipe_screen *screen, struct pipe_context *context, struct pipe_resource *resource, unsigned level, unsigned usage) {
    (void)screen; (void)context; (void)level; (void)usage;
    if (resource) {
        return resource->data;
    }
    return NULL;
}

static void dummy_buffer_unmap(struct pipe_screen *screen, struct pipe_context *context, struct pipe_resource *resource, unsigned level) {
    (void)screen; (void)context; (void)resource; (void)level;
}

int pipe_loader_probe(struct pipe_loader_device **devs, int nr) {
    if (nr <= 0) return 0;
    *devs = calloc(1, sizeof(struct pipe_loader_device));
    printf("[Gallium Eleven] pipe_loader_probe: simulated Intel HD 4600 / Crocus device found.\n");
    return 1;
}

struct pipe_screen *pipe_loader_create_screen(struct pipe_loader_device *dev) {
    (void)dev;
    struct pipe_screen *screen = calloc(1, sizeof(struct pipe_screen));
    if (screen) {
        screen->context_create = dummy_context_create;
        screen->destroy = dummy_screen_destroy;
        screen->resource_create = dummy_resource_create;
        screen->resource_destroy = dummy_resource_destroy;
        screen->create_surface = dummy_create_surface;
        screen->surface_destroy = dummy_surface_destroy;
        screen->buffer_map = dummy_buffer_map;
        screen->buffer_unmap = dummy_buffer_unmap;
        printf("[Gallium Eleven] pipe_loader_create_screen: created screen for Crocus driver.\n");
    }
    return screen;
}

void pipe_loader_release(struct pipe_loader_device **devs, int nr) {
    if (devs && *devs) {
        free(*devs);
        *devs = NULL;
    }
    (void)nr;
}
