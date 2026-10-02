#include "gallium_mgr.h"
#include <pipe/p_screen.h>
#include <pipe/p_context.h>
#include <pipe-loader/pipe_loader.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

int gallium_mgr_init(struct gallium_mgr *mgr) {
    struct pipe_loader_device *devs[1];

    // Probing for real hardware devices
    int num_devs = pipe_loader_probe(devs, 1);

    if (num_devs <= 0) {
        fprintf(stderr, "Failed to probe Gallium devices. Make sure GPU drivers are accessible.\n");
        return -1;
    }

    // Creating screen from discovered device
    mgr->screen = pipe_loader_create_screen(devs[0]);
    if (!mgr->screen) {
        fprintf(stderr, "Failed to create Gallium screen. Driver might be missing or incompatible.\n");
        pipe_loader_release(devs, 1);
        return -1;
    }

    // Creating context
    mgr->context = mgr->screen->context_create(mgr->screen, NULL, 0);
    if (!mgr->context) {
        fprintf(stderr, "Failed to create Gallium context.\n");
        mgr->screen->destroy(mgr->screen);
        pipe_loader_release(devs, 1);
        return -1;
    }

    printf("Gallium manager initialized successfully with real hardware driver!\n");
    return 0;
}

void gallium_mgr_cleanup(struct gallium_mgr *mgr) {
    if (mgr->context) {
        mgr->context->destroy(mgr->context);
    }
    if (mgr->screen) {
        mgr->screen->destroy(mgr->screen);
    }
}
