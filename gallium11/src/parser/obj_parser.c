#include "obj_parser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

const char* get_default_cube_obj(void) {
    return
        "v -0.5 0.5 -0.5\nv -0.5 -0.5 -0.5\nv 0.5 -0.5 -0.5\nv 0.5 0.5 -0.5\n"
        "v -0.5 0.5 0.5\nv -0.5 -0.5 0.5\nv 0.5 -0.5 0.5\nv 0.5 0.5 0.5\n"
        "vn 0 0 -1\nv 0 0 1\nv 0 1 0\nv 0 -1 0\nv -1 0 0\nv 1 0 0\n"
        "f 1//1 2//1 3//1\nf 1//1 3//1 4//1\n"
        "f 5//2 7//2 6//2\nf 5//2 8//2 7//2\n"
        "f 5//3 6//3 2//3\nf 5//3 2//3 1//3\n"
        "f 4//4 3//4 7//4\nf 4//4 7//4 8//4\n"
        "f 5//5 1//5 4//5\nf 5//5 4//5 8//5\n"
        "f 2//6 6//6 7//6\nf 2//6 7//6 3//6\n";
}

const char* get_default_torus_obj(void) {
    return get_default_cube_obj();
}

const char* get_default_sphere_obj(void) {
    return get_default_cube_obj();
}

typedef struct {
    float x, y, z;
} obj_vec3_t;

typedef struct {
    float u, v;
} obj_vec2_t;

typedef struct {
    int v, vt, vn;
} obj_vertex_ref_t;

int parse_obj_string(const char *obj_content, obj_mesh_t *out_mesh) {
    if (!obj_content || !out_mesh) return -1;
    memset(out_mesh, 0, sizeof(obj_mesh_t));

    size_t v_cap = 256, vt_cap = 256, vn_cap = 256, face_cap = 512;
    size_t v_count = 0, vt_count = 0, vn_count = 0, face_count = 0;

    obj_vec3_t *positions = malloc(v_cap * sizeof(obj_vec3_t));
    obj_vec2_t *texcoords = malloc(vt_cap * sizeof(obj_vec2_t));
    obj_vec3_t *normals = malloc(vn_cap * sizeof(obj_vec3_t));
    obj_vertex_ref_t *face_refs = malloc(face_cap * 3 * sizeof(obj_vertex_ref_t));

    if (!positions || !texcoords || !normals || !face_refs) {
        free(positions); free(texcoords); free(normals); free(face_refs);
        return -1;
    }

    const char *p = obj_content;
    char line_buf[1024];

    while (*p) {
        while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
        if (!*p) break;

        size_t len = 0;
        while (p[len] && p[len] != '\n' && p[len] != '\r' && len < sizeof(line_buf) - 1) {
            line_buf[len] = p[len];
            len++;
        }
        line_buf[len] = '\0';

        while (*p && *p != '\n' && *p != '\r') p++;

        if (line_buf[0] == '#' || line_buf[0] == '\0') continue;

        if (strncmp(line_buf, "v ", 2) == 0) {
            float x = 0, y = 0, z = 0;
            if (sscanf(line_buf + 2, "%f %f %f", &x, &y, &z) >= 3) {
                if (v_count >= v_cap) {
                    v_cap *= 2;
                    positions = realloc(positions, v_cap * sizeof(obj_vec3_t));
                }
                positions[v_count++] = (obj_vec3_t){x, y, z};
            }
        } else if (strncmp(line_buf, "vt ", 3) == 0) {
            float u = 0, v = 0;
            if (sscanf(line_buf + 3, "%f %f", &u, &v) >= 2) {
                if (vt_count >= vt_cap) {
                    vt_cap *= 2;
                    texcoords = realloc(texcoords, vt_cap * sizeof(obj_vec2_t));
                }
                texcoords[vt_count++] = (obj_vec2_t){u, v};
            }
        } else if (strncmp(line_buf, "vn ", 3) == 0) {
            float nx = 0, ny = 0, nz = 0;
            if (sscanf(line_buf + 3, "%f %f %f", &nx, &ny, &nz) >= 3) {
                if (vn_count >= vn_cap) {
                    vn_cap *= 2;
                    normals = realloc(normals, vn_cap * sizeof(obj_vec3_t));
                }
                normals[vn_count++] = (obj_vec3_t){nx, ny, nz};
            }
        } else if (strncmp(line_buf, "f ", 2) == 0) {
            char *toks[16];
            int tok_count = 0;
            char *p_tok = line_buf + 2;
            while (*p_tok) {
                while (*p_tok == ' ' || *p_tok == '\t') p_tok++;
                if (!*p_tok) break;
                toks[tok_count++] = p_tok;
                if (tok_count >= 16) break;
                while (*p_tok && *p_tok != ' ' && *p_tok != '\t') p_tok++;
                if (*p_tok) { *p_tok = '\0'; p_tok++; }
            }

            if (tok_count < 3) continue;

            obj_vertex_ref_t poly[16];
            int poly_count = 0;

            for (int i = 0; i < tok_count; i++) {
                obj_vertex_ref_t ref = {0, 0, 0};
                char *slash1 = strchr(toks[i], '/');
                if (!slash1) {
                    ref.v = atoi(toks[i]);
                } else {
                    *slash1 = '\0';
                    ref.v = atoi(toks[i]);
                    char *slash2 = strchr(slash1 + 1, '/');
                    if (!slash2) {
                        ref.vt = atoi(slash1 + 1);
                    } else {
                        *slash2 = '\0';
                        if (slash1 + 1 < slash2) {
                            ref.vt = atoi(slash1 + 1);
                        }
                        ref.vn = atoi(slash2 + 1);
                    }
                }
                poly[poly_count++] = ref;
            }

            for (int i = 1; i + 1 < poly_count; i++) {
                if (face_count + 1 >= face_cap) {
                    face_cap *= 2;
                    face_refs = realloc(face_refs, face_cap * 3 * sizeof(obj_vertex_ref_t));
                }
                face_refs[face_count * 3 + 0] = poly[0];
                face_refs[face_count * 3 + 1] = poly[i];
                face_refs[face_count * 3 + 2] = poly[i + 1];
                face_count++;
            }
        }
    }

    if (face_count == 0) {
        free(positions); free(texcoords); free(normals); free(face_refs);
        return -1;
    }

    // Calculate bounding box for normalization so teapot fits nicely in NDC [-1, 1]
    float min_x = 1e30f, max_x = -1e30f;
    float min_y = 1e30f, max_y = -1e30f;
    float min_z = 1e30f, max_z = -1e30f;
    for(size_t i=0; i<v_count; i++) {
        if(positions[i].x < min_x) min_x = positions[i].x;
        if(positions[i].x > max_x) max_x = positions[i].x;
        if(positions[i].y < min_y) min_y = positions[i].y;
        if(positions[i].y > max_y) max_y = positions[i].y;
        if(positions[i].z < min_z) min_z = positions[i].z;
        if(positions[i].z > max_z) max_z = positions[i].z;
    }
    float center_x = (min_x + max_x) * 0.5f;
    float center_y = (min_y + max_y) * 0.5f;
    float center_z = (min_z + max_z) * 0.5f;
    float size_x = max_x - min_x;
    float size_y = max_y - min_y;
    float size_z = max_z - min_z;
    float max_dim = size_x > size_y ? size_x : size_y;
    max_dim = max_dim > size_z ? max_dim : size_z;
    if (max_dim < 1e-5f) max_dim = 1.0f;
    float scale = 1.2f / max_dim;

    size_t max_vert = face_count * 3;
    extended_vertex_t *out_verts = malloc(max_vert * sizeof(extended_vertex_t));
    uint32_t *out_idxs = malloc(max_vert * sizeof(uint32_t));
    size_t unique_vert_count = 0;

    static struct { int v, vt, vn; } unique_refs[16384];

    for (size_t i = 0; i < face_count * 3; i++) {
        obj_vertex_ref_t ref = face_refs[i];
        int v_idx = ref.v > 0 ? ref.v - 1 : (int)v_count + ref.v;
        int vt_idx = ref.vt > 0 ? ref.vt - 1 : (ref.vt < 0 ? (int)vt_count + ref.vt : -1);
        int vn_idx = ref.vn > 0 ? ref.vn - 1 : (ref.vn < 0 ? (int)vn_count + ref.vn : -1);

        int matched = -1;
        for (size_t j = 0; j < unique_vert_count; j++) {
            if (unique_refs[j].v == v_idx && unique_refs[j].vt == vt_idx && unique_refs[j].vn == vn_idx) {
                matched = (int)j;
                break;
            }
        }

        if (matched >= 0) {
            out_idxs[i] = (uint32_t)matched;
        } else {
            size_t new_idx = unique_vert_count++;
            unique_refs[new_idx].v = v_idx;
            unique_refs[new_idx].vt = vt_idx;
            unique_refs[new_idx].vn = vn_idx;

            extended_vertex_t *vert = &out_verts[new_idx];
            memset(vert, 0, sizeof(extended_vertex_t));

            if (v_idx >= 0 && (size_t)v_idx < v_count) {
                vert->x = (positions[v_idx].x - center_x) * scale;
                vert->y = (positions[v_idx].y - center_y) * scale;
                vert->z = (positions[v_idx].z - center_z) * scale;
                vert->w = 1.0f;
            }

            if (vn_idx >= 0 && (size_t)vn_idx < vn_count) {
                vert->nx = normals[vn_idx].x;
                vert->ny = normals[vn_idx].y;
                vert->nz = normals[vn_idx].z;
                vert->r = fabsf(vert->nx) * 0.5f + 0.5f;
                vert->g = fabsf(vert->ny) * 0.5f + 0.5f;
                vert->b = fabsf(vert->nz) * 0.5f + 0.5f;
                vert->a = 1.0f;
            } else {
                vert->r = fabsf(vert->x) + 0.5f;
                vert->g = fabsf(vert->y) + 0.5f;
                vert->b = fabsf(vert->z) + 0.5f;
                vert->a = 1.0f;
            }

            if (vt_idx >= 0 && (size_t)vt_idx < vt_count) {
                vert->u = texcoords[vt_idx].u;
                vert->v = texcoords[vt_idx].v;
            }

            out_idxs[i] = (uint32_t)new_idx;
        }
    }

    out_mesh->vertices = realloc(out_verts, unique_vert_count * sizeof(extended_vertex_t));
    out_mesh->num_vertices = unique_vert_count;
    out_mesh->indices = realloc(out_idxs, face_count * 3 * sizeof(uint32_t));
    out_mesh->num_indices = face_count * 3;

    free(positions);
    free(texcoords);
    free(normals);
    free(face_refs);

    return 0;
}

int parse_obj_file(const char *filename, obj_mesh_t *out_mesh) {
    if (!filename || !out_mesh) return -1;
    FILE *f = fopen(filename, "rb");
    if (!f) return -1;
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return -1;
    }
    long len = ftell(f);
    if (len < 0) {
        fclose(f);
        return -1;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return -1;
    }
    char *buf = malloc(len + 1);
    if (!buf) {
        fclose(f);
        return -1;
    }
    size_t read_bytes = fread(buf, 1, len, f);
    fclose(f);
    buf[read_bytes] = '\0';

    int ret = parse_obj_string(buf, out_mesh);
    free(buf);
    return ret;
}

void free_obj_mesh(obj_mesh_t *mesh) {
    if (!mesh) return;
    free(mesh->vertices);
    free(mesh->indices);
    memset(mesh, 0, sizeof(obj_mesh_t));
}
