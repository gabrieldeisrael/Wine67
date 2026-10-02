#ifndef P_SCREEN_H
#define P_SCREEN_H

struct pipe_context;
struct pipe_resource;
struct pipe_resource_template;
struct pipe_surface;

struct pipe_screen {
    struct pipe_context *(*context_create)(struct pipe_screen *screen, void *priv, unsigned flags);
    void (*destroy)(struct pipe_screen *screen);
    struct pipe_resource *(*resource_create)(struct pipe_screen *screen, const struct pipe_resource_template *templ);
    void (*resource_destroy)(struct pipe_screen *screen, struct pipe_resource *resource);
    struct pipe_surface *(*create_surface)(struct pipe_screen *screen, struct pipe_resource *resource, const struct pipe_surface *templ);
    void (*surface_destroy)(struct pipe_screen *screen, struct pipe_surface *surface);
    void *(*buffer_map)(struct pipe_screen *screen, struct pipe_context *context, struct pipe_resource *resource, unsigned level, unsigned usage);
    void (*buffer_unmap)(struct pipe_screen *screen, struct pipe_context *context, struct pipe_resource *resource, unsigned level);
};

#endif // P_SCREEN_H
