#ifndef OBJ_PARSER_H
#define OBJ_PARSER_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    float x, y, z, w; // Position
    float nx, ny, nz; // Normal
    float u, v;       // Texcoord
    float r, g, b, a; // Color
} extended_vertex_t;

typedef struct {
    extended_vertex_t *vertices;
    size_t num_vertices;
    uint32_t *indices;
    size_t num_indices;
} obj_mesh_t;

int parse_obj_string(const char *obj_content, obj_mesh_t *out_mesh);
int parse_obj_file(const char *filename, obj_mesh_t *out_mesh);
void free_obj_mesh(obj_mesh_t *mesh);

const char* get_default_cube_obj(void);
const char* get_default_torus_obj(void);
const char* get_default_sphere_obj(void);

#endif // OBJ_PARSER_H
