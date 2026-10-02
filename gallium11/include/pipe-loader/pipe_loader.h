#ifndef PIPE_LOADER_H
#define PIPE_LOADER_H

struct pipe_loader_device;
struct pipe_screen;

int pipe_loader_probe(struct pipe_loader_device **devs, int nr);
struct pipe_screen *pipe_loader_create_screen(struct pipe_loader_device *dev);
void pipe_loader_release(struct pipe_loader_device **devs, int nr);

#endif
