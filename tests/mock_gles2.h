#ifndef AMETHYST_MOCK_GLES2_H
#define AMETHYST_MOCK_GLES2_H

#include <stddef.h>
#include <stdint.h>

#include "gles.h"
#include "gl4esinit.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mock_gles2_state_s {
    GLuint bound_array_buffer;
    GLuint bound_element_array_buffer;
    GLuint bound_framebuffer;
    GLuint bound_renderbuffer;
    GLuint active_texture_unit;
    GLuint bound_textures[32];
    GLuint current_program;

    size_t live_buffers;
    size_t live_textures;
    size_t live_shaders;
    size_t live_programs;
    size_t live_fbos;
    size_t live_rbos;

    size_t buffer_bytes_live;
    size_t buffer_bytes_peak;
    size_t texture_bytes_live;
    size_t texture_bytes_peak;

    unsigned long gen_buffers_calls;
    unsigned long delete_buffers_calls;
    unsigned long buffer_data_calls;
    unsigned long buffer_sub_data_calls;
    unsigned long tex_bind_calls;
    unsigned long tex_image_calls;
    unsigned long tex_sub_image_calls;
    unsigned long shader_compile_calls;
    unsigned long program_link_calls;
    unsigned long program_binary_loads;
    unsigned long program_binary_saves;
    unsigned long use_program_calls;
    unsigned long draw_arrays_calls;
    unsigned long draw_elements_calls;
    unsigned long clear_calls;
    unsigned long bind_buffer_calls;
    unsigned long enable_vertex_attrib_calls;
    unsigned long disable_vertex_attrib_calls;
    unsigned long vertex_attrib_pointer_calls;
    unsigned long uniform_fv_calls;
    unsigned long uniform_matrix_calls;

    GLenum last_draw_mode;
    GLsizei last_draw_count;
    GLenum last_draw_type;
    GLuint last_draw_ibo;
    GLuint last_draw_vbo;
    GLuint last_draw_program;
    uint8_t last_draw_color_bytes[16];
    int last_draw_color_captured;

    int fail_program_binary;
    const char *vendor_override;
    const char *extensions_override;
} mock_gles2_state_t;

void mock_gles2_reset(void);
const mock_gles2_state_t *mock_gles2_get_state(void);
mock_gles2_state_t *mock_gles2_mutable_state(void);
int mock_gles2_get_buffer_bytes(GLuint buffer, size_t offset, void *out, size_t len, size_t *out_size, GLenum *out_usage);
void * APIENTRY_GL4ES mock_gles2_get_proc_address(const char *name);

#ifdef __cplusplus
}
#endif

#endif
