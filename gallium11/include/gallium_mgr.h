#ifndef GALLIUM_MGR_H
#define GALLIUM_MGR_H

#include <pipe/p_screen.h>
#include <pipe/p_context.h>
#include <pipe/p_state.h>
#include <X11/Xlib.h>

struct gallium_mgr {
    struct pipe_screen *screen;
    struct pipe_context *context;
    struct pipe_resource *color_res;
    struct pipe_surface *color_surf;
    struct pipe_framebuffer_state fb_state;
    struct pipe_viewport_state vp_state;
    void *vs_state;
    void *fs_state;
    void *rast_state;
    uint32_t *pixel_buffer;
    unsigned width;
    unsigned height;
};

int gallium_mgr_init(struct gallium_mgr *mgr);
void gallium_mgr_cleanup(struct gallium_mgr *mgr);
void gallium_mgr_present(struct gallium_mgr *mgr, Display *display, Window window, GC gc, XImage *ximage);

#endif
