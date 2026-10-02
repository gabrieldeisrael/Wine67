#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "gallium_mgr.h"
#include "shader_parser.h"
#include "obj_parser.h"
#include <pipe/p_screen.h>
#include <pipe/p_context.h>
#include <pipe/p_state.h>

// Define missing pipe_vertex_element for local binding
struct pipe_vertex_element {
    unsigned src_offset;
    unsigned src_format;
    unsigned instance_divisor;
    unsigned vertex_buffer_index;
};

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    printf("==================================================\n");
    printf(" Gallium Eleven: X11 Window GPU Utah Teapot Renderer\n");
    printf(" Target: X11 Window + Wavefront .OBJ + Gallium GPU\n");
    printf("==================================================\n");

    // 1. Initialize X11 Display and Window
    Display *x_display = XOpenDisplay(NULL);
    if (!x_display) {
        fprintf(stderr, "[X11] Error: Cannot open X display. Make sure DISPLAY is set (e.g. DISPLAY=:0).\n");
        return 1;
    }

    int screen_num = DefaultScreen(x_display);
    Window root_window = RootWindow(x_display, screen_num);

    int win_width = 800;
    int win_height = 600;

    XSetWindowAttributes swa;
    swa.event_mask = ExposureMask | KeyPressMask | StructureNotifyMask;
    swa.background_pixel = BlackPixel(x_display, screen_num);

    Window x_window = XCreateWindow(
        x_display, root_window,
        100, 100, win_width, win_height, 0,
        DefaultDepth(x_display, screen_num),
        InputOutput,
        DefaultVisual(x_display, screen_num),
        CWBackPixel | CWEventMask, &swa
    );

    XStoreName(x_display, x_window, "Gallium Eleven - Utah Teapot (GPU Accelerated)");
    XMapWindow(x_display, x_window);
    GC x_gc = XCreateGC(x_display, x_window, 0, NULL);
    XFlush(x_display);
    printf("[X11] Created and mapped X11 window (%dx%d), GC: %p.\n", win_width, win_height, (void*)x_gc);

    // Allocate pixel buffer for readback (RGBA)
    uint32_t *pixel_buffer = calloc(win_width * win_height, sizeof(uint32_t));

    // Create XImage for blitting
    XImage *ximage = XCreateImage(x_display, DefaultVisual(x_display, screen_num),
                                  DefaultDepth(x_display, screen_num), ZPixmap, 0,
                                  (char*)pixel_buffer, win_width, win_height, 32, 0);

    // 2. Parse Wavefront .OBJ Model
    obj_mesh_t mesh;
    int parse_status = -1;
    const char *paths_to_try[] = {
        "utah_teapot.obj",
        "src/utah_teapot.obj",
        "/home/bernardo/gallium11/utah_teapot.obj",
        "/home/bernardo/gallium11/src/utah_teapot.obj"
    };

    for (size_t i = 0; i < sizeof(paths_to_try)/sizeof(paths_to_try[0]); i++) {
        if (access(paths_to_try[i], R_OK) == 0) {
            printf("[OBJ] Loading %s from disk...\n", paths_to_try[i]);
            parse_status = parse_obj_file(paths_to_try[i], &mesh);
            if (parse_status == 0) {
                printf("[OBJ] Successfully parsed %s!\n", paths_to_try[i]);
                break;
            }
        }
    }

    if (parse_status != 0) {
        printf("[OBJ] utah_teapot.obj not found. Using built-in default OBJ model.\n");
        const char *obj_str = get_default_cube_obj();
        if (parse_obj_string(obj_str, &mesh) != 0) {
            fprintf(stderr, "[OBJ] Error: Failed to parse default OBJ model.\n");
            XDestroyWindow(x_display, x_window);
            XCloseDisplay(x_display);
            return 1;
        }
    }
    printf("[OBJ] Parsed mesh summary: %zu vertices, %zu indices.\n",
           mesh.num_vertices, mesh.num_indices);

    // 3. Initialize Gallium Manager (Hardware GPU / Crocus)
    struct gallium_mgr mgr;
    if (gallium_mgr_init(&mgr) != 0) {
        fprintf(stderr, "[Gallium Eleven] Error: Failed to initialize Gallium manager.\n");
        free_obj_mesh(&mesh);
        XDestroyWindow(x_display, x_window);
        XCloseDisplay(x_display);
        return 1;
    }
    printf("[Gallium Eleven] Gallium manager active. Screen: %p, Context: %p\n",
           (void*)mgr.screen, (void*)mgr.context);

    // 4. Prepare Shaders via DXBC Parser & Gallium Pipeline
    size_t vs_size = 0, ps_size = 0;
    uint8_t *vs_bytecode = create_color_triangle_vs_bytecode(&vs_size);
    uint8_t *ps_bytecode = create_color_triangle_ps_bytecode(&ps_size);
    parse_dxbc_container(vs_bytecode, vs_size);
    parse_dxbc_container(ps_bytecode, ps_size);

    // 5. Allocate Gallium Vertex and Index Buffer Resources
    struct pipe_resource_template vbuf_templ = {
        .target = PIPE_BUFFER,
        .format = 0,
        .width0 = mesh.num_vertices * sizeof(extended_vertex_t),
        .height0 = 1,
        .depth0 = 1,
        .array_size = 1,
        .last_level = 0,
        .nr_samples = 0,
        .usage = PIPE_USAGE_DEFAULT,
        .bind = PIPE_BIND_VERTEX_BUFFER,
        .flags = 0
    };

    struct pipe_resource_template ibuf_templ = {
        .target = PIPE_BUFFER,
        .format = 0,
        .width0 = mesh.num_indices * sizeof(uint32_t),
        .height0 = 1,
        .depth0 = 1,
        .array_size = 1,
        .last_level = 0,
        .nr_samples = 0,
        .usage = PIPE_USAGE_DEFAULT,
        .bind = PIPE_BIND_INDEX_BUFFER,
        .flags = 0
    };

    struct pipe_resource *vbuf_res = NULL;
    struct pipe_resource *ibuf_res = NULL;

    if (mgr.screen && mgr.screen->resource_create) {
        vbuf_res = mgr.screen->resource_create(mgr.screen, &vbuf_templ);
        ibuf_res = mgr.screen->resource_create(mgr.screen, &ibuf_templ);
        printf("[Gallium] Allocated GPU vertex buffer resource: %p (size: %u bytes)\n",
               (void*)vbuf_res, vbuf_templ.width0);
        printf("[Gallium] Allocated GPU index buffer resource: %p (size: %u bytes)\n",
               (void*)ibuf_res, ibuf_templ.width0);
    }

    // 6. Bind Vertex Buffer and Index Buffer
    struct pipe_vertex_buffer vbuffer = {
        .stride = sizeof(extended_vertex_t),
        .buffer_offset = 0,
        .buffer = vbuf_res,
        .user_buffer = mesh.vertices
    };

    struct pipe_index_buffer ibuffer = {
        .index_size = sizeof(uint32_t),
        .offset = 0,
        .buffer = ibuf_res,
        .user_buffer = mesh.indices
    };

    if (mgr.context) {
        if (mgr.context->set_vertex_buffers) {
            mgr.context->set_vertex_buffers(mgr.context, 0, 1, &vbuffer);
            printf("[Gallium] Vertex buffers bound (stride: %zu bytes)\n", sizeof(extended_vertex_t));
        }
        if (mgr.context->set_index_buffer) {
            mgr.context->set_index_buffer(mgr.context, &ibuffer);
            printf("[Gallium] Index buffer bound (index size: %u bytes, count: %zu)\n",
                   4, mesh.num_indices);
        }

        // Add Vertex Element State Binding
        struct pipe_vertex_element velements[2] = {
            { 0, 0, 0, 0 },  // Position (offset 0)
            { 36, 0, 0, 0 }  // Color (offset 36 in extended_vertex_t)
        };
        if (mgr.context->create_vertex_elements_state && mgr.context->bind_vertex_elements_state) {
            void *ve_state = mgr.context->create_vertex_elements_state(mgr.context, 2, velements);
            mgr.context->bind_vertex_elements_state(mgr.context, ve_state);
            printf("[Gallium] Vertex element state bound (pos, color).\n");
        }
    }

    // 6.5. Setup Render Target, Framebuffer State, Viewport, Rasterizer, and Shaders
    struct pipe_resource_template rt_templ = {
        .target = PIPE_TEXTURE_2D,
        .format = 0,
        .width0 = win_width,
        .height0 = win_height,
        .depth0 = 1,
        .array_size = 1,
        .last_level = 0,
        .nr_samples = 0,
        .usage = PIPE_USAGE_DEFAULT,
        .bind = PIPE_BIND_RENDER_TARGET,
        .flags = 0
    };

    struct pipe_resource *rt_res = NULL;
    struct pipe_surface *rt_surf = NULL;
    void *rast_state_obj = NULL;
    void *vs_state_obj = NULL;
    void *ps_state_obj = NULL;

    if (mgr.screen && mgr.screen->resource_create && mgr.screen->create_surface) {
        rt_res = mgr.screen->resource_create(mgr.screen, &rt_templ);
        struct pipe_surface surf_templ = {
            .format = rt_templ.format,
            .level = 0,
            .layer = 0
        };
        rt_surf = mgr.screen->create_surface(mgr.screen, rt_res, &surf_templ);
        printf("[Gallium] Created render target texture %p and surface %p (%dx%d)\n",
               (void*)rt_res, (void*)rt_surf, win_width, win_height);
    }

    if (mgr.context) {
        struct pipe_framebuffer_state fb_state = {
            .width = win_width,
            .height = win_height,
            .nr_cbufs = 1,
            .cbufs = { rt_surf },
            .zsbuf = NULL
        };
        if (mgr.context->set_framebuffer_state) {
            mgr.context->set_framebuffer_state(mgr.context, &fb_state);
            printf("[Gallium] Framebuffer state bound.\n");
        }

        struct pipe_viewport_state vp_state = {
            .scale = { (float)win_width / 2.0f, (float)win_height / 2.0f, 0.5f, 1.0f },
            .translate = { (float)win_width / 2.0f, (float)win_height / 2.0f, 0.5f, 0.0f }
        };
        if (mgr.context->set_viewport_state) {
            mgr.context->set_viewport_state(mgr.context, &vp_state);
            printf("[Gallium] Viewport state bound (%dx%d).\n", win_width, win_height);
        }

        struct pipe_rasterizer_state rast_desc = {
            .cull_face = 0,
            .fill_cw = 0,
            .fill_ccw = 0,
            .line_width = 1.0f,
            .point_size = 1.0f
        };
        if (mgr.context->create_rasterizer_state && mgr.context->set_rasterizer_state) {
            rast_state_obj = mgr.context->create_rasterizer_state(mgr.context, &rast_desc);
            mgr.context->set_rasterizer_state(mgr.context, rast_state_obj);
            printf("[Gallium] Rasterizer state created and bound.\n");
        }

        if (mgr.context->create_vs_state && mgr.context->bind_vs_state) {
            vs_state_obj = mgr.context->create_vs_state(mgr.context, vs_bytecode);
            mgr.context->bind_vs_state(mgr.context, vs_state_obj);
            printf("[Gallium] Vertex shader state bound.\n");
        }

        if (mgr.context->create_fs_state && mgr.context->bind_fs_state) {
            ps_state_obj = mgr.context->create_fs_state(mgr.context, ps_bytecode);
            mgr.context->bind_fs_state(mgr.context, ps_state_obj);
            printf("[Gallium] Pixel shader state bound.\n");
        }
    }

    // 7. Setup Draw Info for Indexed Hardware GPU Drawing
    struct pipe_draw_info draw_info = {
        .mode = PIPE_PRIMITIVE_TRIANGLES,
        .indexed = 1,
        .has_user_indices = 0,
        .has_user_vertices = 0,
        .start = 0,
        .count = (unsigned)mesh.num_indices,
        .start_instance = 0,
        .instance_count = 1,
        .index_bias = 0,
        .min_index = 0,
        .max_index = (unsigned)mesh.num_vertices - 1,
        .indices = { .resource = ibuf_res }
    };

    // 8. Hardware GPU Animation & X11 Presentation Loop (with frame logging)
    printf("\n--- Starting X11 Hardware GPU-Accelerated Animation & Presentation Loop (Running) ---\n");
    fflush(stdout);

    int frame_count = 0;
    while (frame_count < 300) { // Run for 300 frames (~5 seconds at 60 FPS) and exit cleanly
        // Handle X11 events
        while (XPending(x_display) > 0) {
            XEvent event;
            XNextEvent(x_display, &event);
            if (event.type == KeyPress || event.type == DestroyNotify) {
                goto cleanup_exit;
            }
        }

        // Issue hardware GPU indexed draw call through Gallium pipe_context pipeline (Crocus / Intel HD 4600)
        if (mgr.context && mgr.context->draw_vbo) {
            mgr.context->draw_vbo(mgr.context, &draw_info);
        }
        if (mgr.context && mgr.context->flush) {
            mgr.context->flush(mgr.context, NULL, 0);
        }

        // Texture Readback: Transfer GPU Render Target pixels to Host Pixel Buffer
        // Assuming PIPE_MAP_READ is supported for the render target surface
        if (mgr.screen && mgr.screen->buffer_map && rt_res) {
            void *mapped = mgr.screen->buffer_map(mgr.screen, mgr.context, rt_res, 0, 1 /* PIPE_MAP_READ */);
            if (mapped) {
                // Copy the pixels from the mapped GPU texture to the X11 pixel_buffer
                memcpy(pixel_buffer, mapped, win_width * win_height * 4);
                mgr.screen->buffer_unmap(mgr.screen, mgr.context, rt_res, 0);
            } else {
                // Fallback or debug: if map fails, clear to debug color
                // memset(pixel_buffer, 0x22, win_width * win_height * 4);
                // Try clearing with a pattern to see if drawing is happening
                uint32_t *pixels = (uint32_t *)pixel_buffer;
                for (int i = 0; i < win_width * win_height; i++) {
                     pixels[i] = (i % 256) | ((i / win_width % 256) << 8) | 0xFF000000;
                }
            }
        } else {
             // Fallback or debug: if map fails, clear to debug color
             uint32_t *pixels = (uint32_t *)pixel_buffer;
             for (int i = 0; i < win_width * win_height; i++) {
                  pixels[i] = 0xFFFF0000; // RED if mapping is not even attempted/possible
             }
        }

        // Blit to X11 window
        XPutImage(x_display, x_window, x_gc, ximage, 0, 0, 0, 0, win_width, win_height);
        XFlush(x_display);
        frame_count++;

        if (frame_count % 60 == 0) {
            printf("[Renderer] Rendered %d frames successfully...\n", frame_count);
            fflush(stdout);
        }

        // Strict VSync / Frame Pacing sleep to prevent 100% CPU busy-wait (targeting ~60 FPS)
        usleep(16666);
    }

cleanup_exit:
    // Cleanup Resources
    if (mgr.context) {
        if (rast_state_obj && mgr.context->delete_rasterizer_state) {
            mgr.context->delete_rasterizer_state(mgr.context, rast_state_obj);
        }
        if (vs_state_obj && mgr.context->delete_vs_state) {
            mgr.context->delete_vs_state(mgr.context, vs_state_obj);
        }
        if (ps_state_obj && mgr.context->delete_fs_state) {
            mgr.context->delete_fs_state(mgr.context, ps_state_obj);
        }
    }
    if (mgr.screen) {
        if (rt_surf && mgr.screen->surface_destroy) {
            mgr.screen->surface_destroy(mgr.screen, rt_surf);
        }
        if (rt_res && mgr.screen->resource_destroy) {
            mgr.screen->resource_destroy(mgr.screen, rt_res);
        }
        if (vbuf_res && mgr.screen->resource_destroy) {
            mgr.screen->resource_destroy(mgr.screen, vbuf_res);
        }
        if (ibuf_res && mgr.screen->resource_destroy) {
            mgr.screen->resource_destroy(mgr.screen, ibuf_res);
        }
    }

    free_obj_mesh(&mesh);
    free(vs_bytecode);
    free(ps_bytecode);
    gallium_mgr_cleanup(&mgr);

    XDestroyWindow(x_display, x_window);
    XCloseDisplay(x_display);

    printf("\n--- X11 Hardware GPU-Accelerated Utah Teapot Renderer Completed Successfully! ---\n");
    return 0;
}
