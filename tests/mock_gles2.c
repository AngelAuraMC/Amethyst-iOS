#include "mock_gles2.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "const.h"
#include "gl4es.h"

#ifndef GL_SHADING_LANGUAGE_VERSION
#define GL_SHADING_LANGUAGE_VERSION 0x8B8C
#endif
#ifndef GL_CURRENT_PROGRAM
#define GL_CURRENT_PROGRAM 0x8B8D
#endif
#ifndef GL_MAX_VERTEX_ATTRIBS
#define GL_MAX_VERTEX_ATTRIBS 0x8869
#endif
#ifndef GL_MAX_TEXTURE_IMAGE_UNITS
#define GL_MAX_TEXTURE_IMAGE_UNITS 0x8872
#endif
#ifndef GL_MAX_VARYING_VECTORS
#define GL_MAX_VARYING_VECTORS 0x8DFC
#endif
#ifndef GL_NUM_PROGRAM_BINARY_FORMATS_OES
#define GL_NUM_PROGRAM_BINARY_FORMATS_OES 0x87FE
#endif
#ifndef GL_PROGRAM_BINARY_FORMATS_OES
#define GL_PROGRAM_BINARY_FORMATS_OES 0x87FF
#endif
#ifndef GL_PROGRAM_BINARY_LENGTH_OES
#define GL_PROGRAM_BINARY_LENGTH_OES 0x8741
#endif
#ifndef GL_MAX_COLOR_ATTACHMENTS_EXT
#define GL_MAX_COLOR_ATTACHMENTS_EXT 0x8CDF
#endif
#ifndef GL_MAX_DRAW_BUFFERS_ARB
#define GL_MAX_DRAW_BUFFERS_ARB 0x8824
#endif
#ifndef GL_MAX_TEXTURE_MAX_ANISOTROPY
#define GL_MAX_TEXTURE_MAX_ANISOTROPY 0x84FF
#endif
#ifndef GL_VERTEX_SHADER
#define GL_VERTEX_SHADER 0x8B31
#endif
#ifndef GL_FRAGMENT_SHADER
#define GL_FRAGMENT_SHADER 0x8B30
#endif
#ifndef GL_COMPILE_STATUS
#define GL_COMPILE_STATUS 0x8B81
#endif
#ifndef GL_LINK_STATUS
#define GL_LINK_STATUS 0x8B82
#endif
#ifndef GL_VALIDATE_STATUS
#define GL_VALIDATE_STATUS 0x8B83
#endif
#ifndef GL_DELETE_STATUS
#define GL_DELETE_STATUS 0x8B80
#endif
#ifndef GL_INFO_LOG_LENGTH
#define GL_INFO_LOG_LENGTH 0x8B84
#endif
#ifndef GL_ATTACHED_SHADERS
#define GL_ATTACHED_SHADERS 0x8B85
#endif
#ifndef GL_ACTIVE_UNIFORMS
#define GL_ACTIVE_UNIFORMS 0x8B86
#endif
#ifndef GL_ACTIVE_UNIFORM_MAX_LENGTH
#define GL_ACTIVE_UNIFORM_MAX_LENGTH 0x8B87
#endif
#ifndef GL_ACTIVE_ATTRIBUTES
#define GL_ACTIVE_ATTRIBUTES 0x8B89
#endif
#ifndef GL_ACTIVE_ATTRIBUTE_MAX_LENGTH
#define GL_ACTIVE_ATTRIBUTE_MAX_LENGTH 0x8B8A
#endif
#ifndef GL_SHADER_SOURCE_LENGTH
#define GL_SHADER_SOURCE_LENGTH 0x8B88
#endif
#ifndef GL_SHADER_TYPE
#define GL_SHADER_TYPE 0x8B4F
#endif
#ifndef GL_HIGH_FLOAT
#define GL_HIGH_FLOAT 0x8DF2
#endif
#ifndef GL_FLOAT_VEC4
#define GL_FLOAT_VEC4 0x8B52
#endif
#ifndef GL_FLOAT_MAT4
#define GL_FLOAT_MAT4 0x8B5C
#endif

typedef struct mock_obj_slot_s {
    GLuint id;
    int alive;
} mock_obj_slot_t;

typedef struct mock_buffer_s {
    GLuint id;
    int alive;
    uint8_t *data;
    size_t size;
    GLenum usage;
} mock_buffer_t;

typedef struct mock_texture_s {
    GLuint id;
    int alive;
    size_t bytes;
    GLsizei width;
    GLsizei height;
    GLenum format;
} mock_texture_t;

typedef struct mock_shader_s {
    GLuint id;
    int alive;
    GLenum type;
    char *source;
} mock_shader_t;

typedef struct mock_program_s {
    GLuint id;
    int alive;
    int linked;
    GLuint shaders[8];
    int shader_count;
    uint32_t attr_mask; /* bit 0: _gl4es_Vertex, bit 1: _gl4es_Color, bit 2: _gl4es_Normal, bit 3: _gl4es_MultiTexCoord0 */
    uint32_t uniform_mask; /* bit 0: MVP, bit 1: LightSource_0.diffuse, bit 2: Fog.color, bit 3: AlphaRef, bit 4: TextureEnvColor_0 */
} mock_program_t;

typedef struct mock_attrib_state_s {
    int enabled;
    GLint size;
    GLenum type;
    GLboolean normalized;
    GLsizei stride;
    const void *pointer;
    GLuint vbo;
} mock_attrib_state_t;

static mock_gles2_state_t g_state;
static GLenum g_last_error = GL_NO_ERROR;

static mock_buffer_t *g_buffers = NULL;
static size_t g_buffers_cap = 0;
static GLuint g_next_buffer = 1;

static mock_texture_t *g_textures = NULL;
static size_t g_textures_cap = 0;
static GLuint g_next_texture = 1;

static mock_shader_t *g_shaders = NULL;
static size_t g_shaders_cap = 0;
static GLuint g_next_shader = 1;

static mock_program_t *g_programs = NULL;
static size_t g_programs_cap = 0;
static GLuint g_next_program = 1;

static mock_obj_slot_t *g_fbos = NULL;
static size_t g_fbos_cap = 0;
static GLuint g_next_fbo = 1;

static mock_obj_slot_t *g_rbos = NULL;
static size_t g_rbos_cap = 0;
static GLuint g_next_rbo = 1;

static mock_attrib_state_t g_attribs[16];

static const char *DEFAULT_EXTENSIONS =
    "GL_OES_element_index_uint "
    "GL_OES_mapbuffer "
    "GL_OES_rgb8_rgba8 "
    "GL_OES_depth24 "
    "GL_OES_packed_depth_stencil "
    "GL_EXT_texture_format_BGRA8888 "
    "GL_OES_fragment_precision_high "
    "GL_OES_standard_derivatives "
    "GL_OES_get_program_binary "
    "GL_EXT_shader_texture_lod "
    "GL_EXT_draw_buffers "
    "GL_EXT_texture_filter_anisotropic ";

static void ensure_cap(void **arr, size_t *cap, size_t elem_size, size_t needed) {
    if (*cap >= needed) return;
    size_t new_cap = (*cap == 0) ? 64 : (*cap * 2);
    while (new_cap < needed) new_cap *= 2;
    void *p = realloc(*arr, new_cap * elem_size);
    if (!p) abort();
    memset((uint8_t *)p + (*cap * elem_size), 0, (new_cap - *cap) * elem_size);
    *arr = p;
    *cap = new_cap;
}

static mock_buffer_t *find_buffer(GLuint id) {
    if (id == 0) return NULL;
    for (size_t i = 0; i < g_buffers_cap; ++i) {
        if (g_buffers[i].alive && g_buffers[i].id == id) return &g_buffers[i];
    }
    return NULL;
}

static mock_buffer_t *find_or_create_buffer(GLuint id) {
    mock_buffer_t *b = find_buffer(id);
    if (b) return b;
    for (size_t i = 0; i < g_buffers_cap; ++i) {
        if (!g_buffers[i].alive) {
            memset(&g_buffers[i], 0, sizeof(mock_buffer_t));
            g_buffers[i].id = id;
            g_buffers[i].alive = 1;
            g_state.live_buffers++;
            return &g_buffers[i];
        }
    }
    size_t idx = g_buffers_cap;
    ensure_cap((void **)&g_buffers, &g_buffers_cap, sizeof(mock_buffer_t), idx + 1);
    g_buffers[idx].id = id;
    g_buffers[idx].alive = 1;
    g_state.live_buffers++;
    return &g_buffers[idx];
}

static mock_texture_t *find_or_create_texture(GLuint id) {
    if (id == 0) return NULL;
    for (size_t i = 0; i < g_textures_cap; ++i) {
        if (g_textures[i].alive && g_textures[i].id == id) return &g_textures[i];
    }
    for (size_t i = 0; i < g_textures_cap; ++i) {
        if (!g_textures[i].alive) {
            memset(&g_textures[i], 0, sizeof(mock_texture_t));
            g_textures[i].id = id;
            g_textures[i].alive = 1;
            g_state.live_textures++;
            return &g_textures[i];
        }
    }
    size_t idx = g_textures_cap;
    ensure_cap((void **)&g_textures, &g_textures_cap, sizeof(mock_texture_t), idx + 1);
    g_textures[idx].id = id;
    g_textures[idx].alive = 1;
    g_state.live_textures++;
    return &g_textures[idx];
}

static mock_shader_t *find_shader(GLuint id) {
    if (id == 0) return NULL;
    for (size_t i = 0; i < g_shaders_cap; ++i) {
        if (g_shaders[i].alive && g_shaders[i].id == id) return &g_shaders[i];
    }
    return NULL;
}

static mock_program_t *find_program(GLuint id) {
    if (id == 0) return NULL;
    for (size_t i = 0; i < g_programs_cap; ++i) {
        if (g_programs[i].alive && g_programs[i].id == id) return &g_programs[i];
    }
    return NULL;
}

static void capture_color_bytes_at_draw(GLint first_vertex, GLenum idx_type, const void *indices) {
    g_state.last_draw_color_captured = 0;
    memset(g_state.last_draw_color_bytes, 0, sizeof(g_state.last_draw_color_bytes));
    const mock_attrib_state_t *ca = &g_attribs[3]; /* ARB_COLOR */
    if (!ca->enabled) return;

    GLint vtx = first_vertex;
    if (idx_type != 0) {
        const uint8_t *idx_ptr = NULL;
        size_t avail = 0;
        if (g_state.bound_element_array_buffer != 0) {
            mock_buffer_t *ibo = find_buffer(g_state.bound_element_array_buffer);
            size_t off = (size_t)(uintptr_t)indices;
            if (ibo && ibo->data && off < ibo->size) {
                idx_ptr = ibo->data + off;
                avail = ibo->size - off;
            }
        } else if (indices != NULL) {
            idx_ptr = (const uint8_t *)indices;
            avail = 4;
        }
        if (idx_ptr) {
            if (idx_type == GL_UNSIGNED_SHORT && avail >= 2) {
                uint16_t u16 = 0;
                memcpy(&u16, idx_ptr, 2);
                vtx = (GLint)u16;
            } else if (idx_type == GL_UNSIGNED_INT && avail >= 4) {
                uint32_t u32 = 0;
                memcpy(&u32, idx_ptr, 4);
                vtx = (GLint)u32;
            } else if (idx_type == GL_UNSIGNED_BYTE && avail >= 1) {
                vtx = (GLint)idx_ptr[0];
            }
        }
    }

    size_t elem_sz = (ca->type == GL_FLOAT) ? 4 : 1;
    size_t stride = ca->stride ? (size_t)ca->stride : (size_t)(ca->size * (GLint)elem_sz);
    size_t byte_off = (size_t)((vtx >= 0) ? vtx : 0) * stride;
    if (ca->vbo == 0) {
        if (!ca->pointer) return;
        const uint8_t *src = (const uint8_t *)ca->pointer + byte_off;
        memcpy(g_state.last_draw_color_bytes, src, 4);
        g_state.last_draw_color_captured = 1;
    } else {
        mock_buffer_t *vbo = find_buffer(ca->vbo);
        size_t total_off = (size_t)(uintptr_t)ca->pointer + byte_off;
        if (vbo && vbo->data && total_off + 4 <= vbo->size) {
            memcpy(g_state.last_draw_color_bytes, vbo->data + total_off, 4);
            g_state.last_draw_color_captured = 1;
        }
    }
}

void mock_gles2_reset(void) {
    for (size_t i = 0; i < g_buffers_cap; ++i) {
        free(g_buffers[i].data);
    }
    free(g_buffers); g_buffers = NULL; g_buffers_cap = 0; g_next_buffer = 1;

    free(g_textures); g_textures = NULL; g_textures_cap = 0; g_next_texture = 1;

    for (size_t i = 0; i < g_shaders_cap; ++i) {
        free(g_shaders[i].source);
    }
    free(g_shaders); g_shaders = NULL; g_shaders_cap = 0; g_next_shader = 1;

    free(g_programs); g_programs = NULL; g_programs_cap = 0; g_next_program = 1;
    free(g_fbos); g_fbos = NULL; g_fbos_cap = 0; g_next_fbo = 1;
    free(g_rbos); g_rbos = NULL; g_rbos_cap = 0; g_next_rbo = 1;

    memset(&g_state, 0, sizeof(g_state));
    memset(g_attribs, 0, sizeof(g_attribs));
    g_last_error = GL_NO_ERROR;
}

const mock_gles2_state_t *mock_gles2_get_state(void) {
    return &g_state;
}

mock_gles2_state_t *mock_gles2_mutable_state(void) {
    return &g_state;
}

int mock_gles2_get_buffer_bytes(GLuint buffer, size_t offset, void *out, size_t len, size_t *out_size, GLenum *out_usage) {
    mock_buffer_t *b = find_buffer(buffer);
    if (!b) return 0;
    if (out_size) *out_size = b->size;
    if (out_usage) *out_usage = b->usage;
    if (out && len > 0) {
        if (!b->data || offset + len > b->size) return 0;
        memcpy(out, b->data + offset, len);
    }
    return 1;
}

/* Mock GLES2 API functions */
static const GLubyte * APIENTRY_GLES m_glGetString(GLenum name) {
    switch (name) {
        case GL_VENDOR:
            return (const GLubyte *)(g_state.vendor_override ? g_state.vendor_override : "Amethyst Mock GLES2");
        case GL_RENDERER:
            return (const GLubyte *)"MockGLES2 Renderer";
        case GL_VERSION:
            return (const GLubyte *)"OpenGL ES 2.0 MockGLES2";
        case GL_SHADING_LANGUAGE_VERSION:
            return (const GLubyte *)"OpenGL ES GLSL ES 1.00";
        case GL_EXTENSIONS:
            return (const GLubyte *)(g_state.extensions_override ? g_state.extensions_override : DEFAULT_EXTENSIONS);
        default:
            return (const GLubyte *)"";
    }
}

static GLenum APIENTRY_GLES m_glGetError(void) {
    GLenum err = g_last_error;
    g_last_error = GL_NO_ERROR;
    return err;
}

static void APIENTRY_GLES m_glGetIntegerv(GLenum pname, GLint *params) {
    if (!params) return;
    switch (pname) {
        case GL_MAX_VERTEX_ATTRIBS: params[0] = 16; break;
        case GL_MAX_TEXTURE_SIZE: params[0] = 4096; break;
        case GL_MAX_TEXTURE_IMAGE_UNITS: params[0] = 8; break;
        case GL_MAX_TEXTURE_UNITS: params[0] = 8; break;
        case GL_MAX_VARYING_VECTORS: params[0] = 16; break;
        case GL_NUM_PROGRAM_BINARY_FORMATS_OES: params[0] = 1; break;
        case GL_PROGRAM_BINARY_FORMATS_OES: params[0] = 0x87FF; break;
        case GL_MAX_COLOR_ATTACHMENTS_EXT: params[0] = 4; break;
        case GL_MAX_DRAW_BUFFERS_ARB: params[0] = 4; break;
        case GL_MAX_TEXTURE_MAX_ANISOTROPY: params[0] = 16; break;
        case GL_MAX_RENDERBUFFER_SIZE_OES: params[0] = 4096; break;
        case GL_MAX_CUBE_MAP_TEXTURE_SIZE_OES: params[0] = 4096; break;
        case GL_VIEWPORT:
            params[0] = 0; params[1] = 0; params[2] = 1280; params[3] = 720; break;
        case GL_SCISSOR_BOX:
            params[0] = 0; params[1] = 0; params[2] = 1280; params[3] = 720; break;
        case GL_IMPLEMENTATION_COLOR_READ_FORMAT_OES: params[0] = GL_RGBA; break;
        case GL_IMPLEMENTATION_COLOR_READ_TYPE_OES: params[0] = GL_UNSIGNED_BYTE; break;
        case GL_ARRAY_BUFFER_BINDING: params[0] = (GLint)g_state.bound_array_buffer; break;
        case GL_ELEMENT_ARRAY_BUFFER_BINDING: params[0] = (GLint)g_state.bound_element_array_buffer; break;
        case GL_FRAMEBUFFER_BINDING_OES: params[0] = (GLint)g_state.bound_framebuffer; break;
        case GL_RENDERBUFFER_BINDING_OES: params[0] = (GLint)g_state.bound_renderbuffer; break;
        case GL_CURRENT_PROGRAM: params[0] = (GLint)g_state.current_program; break;
        case GL_TEXTURE_BINDING_2D:
            params[0] = (GLint)g_state.bound_textures[g_state.active_texture_unit & 31u];
            break;
        case GL_ACTIVE_TEXTURE:
            params[0] = (GLint)(GL_TEXTURE0 + (g_state.active_texture_unit & 31u));
            break;
        default: params[0] = 0; break;
    }
}

static void APIENTRY_GLES m_glGetBooleanv(GLenum pname, GLboolean *params) {
    if (!params) return;
    (void)pname;
    params[0] = GL_FALSE;
}

static void APIENTRY_GLES m_glGetFloatv(GLenum pname, GLfloat *params) {
    if (!params) return;
    (void)pname;
    params[0] = 0.0f;
}

static void APIENTRY_GLES m_glGetShaderPrecisionFormat(GLenum shadertype, GLenum precisiontype, GLint *range, GLint *precision) {
    (void)shadertype;
    (void)precisiontype;
    if (range) {
        range[0] = 127;
        range[1] = 127;
    }
    if (precision) *precision = 23;
}

static GLuint APIENTRY_GLES m_glCreateShader(GLenum type) {
    GLuint id = g_next_shader++;
    for (size_t i = 0; i < g_shaders_cap; ++i) {
        if (!g_shaders[i].alive) {
            memset(&g_shaders[i], 0, sizeof(mock_shader_t));
            g_shaders[i].id = id;
            g_shaders[i].alive = 1;
            g_shaders[i].type = type;
            g_state.live_shaders++;
            return id;
        }
    }
    size_t idx = g_shaders_cap;
    ensure_cap((void **)&g_shaders, &g_shaders_cap, sizeof(mock_shader_t), idx + 1);
    g_shaders[idx].id = id;
    g_shaders[idx].alive = 1;
    g_shaders[idx].type = type;
    g_state.live_shaders++;
    return id;
}

static void APIENTRY_GLES m_glShaderSource(GLuint shader, GLsizei count, const GLchar * const *string, const GLint *length) {
    mock_shader_t *s = find_shader(shader);
    if (!s || !string || count <= 0) return;
    size_t total = 0;
    for (GLsizei i = 0; i < count; ++i) {
        if (!string[i]) continue;
        size_t l = (length && length[i] >= 0) ? (size_t)length[i] : strlen(string[i]);
        total += l;
    }
    free(s->source);
    s->source = (char *)malloc(total + 1);
    if (!s->source) return;
    size_t pos = 0;
    for (GLsizei i = 0; i < count; ++i) {
        if (!string[i]) continue;
        size_t l = (length && length[i] >= 0) ? (size_t)length[i] : strlen(string[i]);
        memcpy(s->source + pos, string[i], l);
        pos += l;
    }
    s->source[pos] = '\0';
}

static void APIENTRY_GLES m_glCompileShader(GLuint shader) {
    (void)shader;
    g_state.shader_compile_calls++;
}

static void APIENTRY_GLES m_glGetShaderiv(GLuint shader, GLenum pname, GLint *params) {
    if (!params) return;
    mock_shader_t *s = find_shader(shader);
    switch (pname) {
        case GL_COMPILE_STATUS: params[0] = GL_TRUE; break;
        case GL_DELETE_STATUS: params[0] = GL_FALSE; break;
        case GL_INFO_LOG_LENGTH: params[0] = 1; break;
        case GL_SHADER_TYPE: params[0] = s ? (GLint)s->type : 0; break;
        case GL_SHADER_SOURCE_LENGTH: params[0] = (s && s->source) ? (GLint)(strlen(s->source) + 1) : 1; break;
        default: params[0] = 0; break;
    }
}

static void APIENTRY_GLES m_glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *infoLog) {
    (void)shader;
    if (length) *length = 0;
    if (infoLog && bufSize > 0) infoLog[0] = '\0';
}

static void APIENTRY_GLES m_glGetShaderSource(GLuint shader, GLsizei bufSize, GLsizei *length, GLchar *source) {
    mock_shader_t *s = find_shader(shader);
    const char *src = (s && s->source) ? s->source : "";
    size_t l = strlen(src);
    if (bufSize > 0 && source) {
        size_t cp = (l < (size_t)bufSize - 1) ? l : (size_t)(bufSize - 1);
        memcpy(source, src, cp);
        source[cp] = '\0';
        if (length) *length = (GLsizei)cp;
    } else if (length) {
        *length = 0;
    }
}

static void APIENTRY_GLES m_glDeleteShader(GLuint shader) {
    mock_shader_t *s = find_shader(shader);
    if (!s) return;
    free(s->source);
    s->source = NULL;
    s->alive = 0;
    if (g_state.live_shaders > 0) g_state.live_shaders--;
}

static GLboolean APIENTRY_GLES m_glIsShader(GLuint shader) {
    return find_shader(shader) ? GL_TRUE : GL_FALSE;
}

static GLuint APIENTRY_GLES m_glCreateProgram(void) {
    GLuint id = g_next_program++;
    for (size_t i = 0; i < g_programs_cap; ++i) {
        if (!g_programs[i].alive) {
            memset(&g_programs[i], 0, sizeof(mock_program_t));
            g_programs[i].id = id;
            g_programs[i].alive = 1;
            g_state.live_programs++;
            return id;
        }
    }
    size_t idx = g_programs_cap;
    ensure_cap((void **)&g_programs, &g_programs_cap, sizeof(mock_program_t), idx + 1);
    g_programs[idx].id = id;
    g_programs[idx].alive = 1;
    g_state.live_programs++;
    return id;
}

static void APIENTRY_GLES m_glAttachShader(GLuint program, GLuint shader) {
    mock_program_t *p = find_program(program);
    if (!p || p->shader_count >= 8) return;
    p->shaders[p->shader_count++] = shader;
}

static void APIENTRY_GLES m_glDetachShader(GLuint program, GLuint shader) {
    mock_program_t *p = find_program(program);
    if (!p) return;
    for (int i = 0; i < p->shader_count; ++i) {
        if (p->shaders[i] == shader) {
            p->shaders[i] = p->shaders[--p->shader_count];
            break;
        }
    }
}

static void APIENTRY_GLES m_glBindAttribLocation(GLuint program, GLuint index, const GLchar *name) {
    (void)program; (void)index; (void)name;
}

static void APIENTRY_GLES m_glLinkProgram(GLuint program) {
    mock_program_t *p = find_program(program);
    g_state.program_link_calls++;
    if (!p) return;
    p->linked = 1;
    p->attr_mask = 0;
    p->uniform_mask = 0;
    for (int i = 0; i < p->shader_count; ++i) {
        mock_shader_t *s = find_shader(p->shaders[i]);
        if (s && s->source) {
            if (strstr(s->source, "_gl4es_Vertex")) p->attr_mask |= 1u;
            if (strstr(s->source, "_gl4es_Color")) p->attr_mask |= 2u;
            if (strstr(s->source, "_gl4es_Normal")) p->attr_mask |= 4u;
            if (strstr(s->source, "_gl4es_MultiTexCoord0")) p->attr_mask |= 8u;
            if (strstr(s->source, "_gl4es_ModelViewProjectionMatrix")) p->uniform_mask |= 1u;
            if (strstr(s->source, "_gl4es_LightSource_0")) p->uniform_mask |= 2u;
            if (strstr(s->source, "_gl4es_Fog")) p->uniform_mask |= 4u;
            if (strstr(s->source, "_gl4es_AlphaRef")) p->uniform_mask |= 8u;
            if (strstr(s->source, "_gl4es_TextureEnvColor_0")) p->uniform_mask |= 16u;
        }
    }
}

static void APIENTRY_GLES m_glValidateProgram(GLuint program) { (void)program; }

static void APIENTRY_GLES m_glUseProgram(GLuint program) {
    g_state.current_program = program;
    g_state.use_program_calls++;
}

static void APIENTRY_GLES m_glDeleteProgram(GLuint program) {
    mock_program_t *p = find_program(program);
    if (!p) return;
    p->alive = 0;
    if (g_state.current_program == program) g_state.current_program = 0;
    if (g_state.live_programs > 0) g_state.live_programs--;
}

static GLboolean APIENTRY_GLES m_glIsProgram(GLuint program) {
    return find_program(program) ? GL_TRUE : GL_FALSE;
}

static int count_bits(uint32_t m) {
    int c = 0;
    while (m) { c += (int)(m & 1u); m >>= 1; }
    return c;
}

static void APIENTRY_GLES m_glGetProgramiv(GLuint program, GLenum pname, GLint *params) {
    if (!params) return;
    mock_program_t *p = find_program(program);
    switch (pname) {
        case GL_LINK_STATUS: params[0] = (p && p->linked) ? GL_TRUE : GL_FALSE; break;
        case GL_VALIDATE_STATUS: params[0] = GL_TRUE; break;
        case GL_DELETE_STATUS: params[0] = GL_FALSE; break;
        case GL_INFO_LOG_LENGTH: params[0] = 1; break;
        case GL_ATTACHED_SHADERS: params[0] = p ? p->shader_count : 0; break;
        case GL_ACTIVE_UNIFORMS: params[0] = p ? count_bits(p->uniform_mask) : 0; break;
        case GL_ACTIVE_UNIFORM_MAX_LENGTH: params[0] = (p && p->uniform_mask) ? 40 : 1; break;
        case GL_ACTIVE_ATTRIBUTES: params[0] = p ? count_bits(p->attr_mask) : 0; break;
        case GL_ACTIVE_ATTRIBUTE_MAX_LENGTH: params[0] = 32; break;
        case GL_PROGRAM_BINARY_LENGTH_OES: params[0] = 32; break;
        default: params[0] = 0; break;
    }
}

static void APIENTRY_GLES m_glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, GLchar *infoLog) {
    (void)program;
    if (length) *length = 0;
    if (infoLog && bufSize > 0) infoLog[0] = '\0';
}

static void APIENTRY_GLES m_glGetAttachedShaders(GLuint program, GLsizei maxCount, GLsizei *count, GLuint *obj) {
    mock_program_t *p = find_program(program);
    if (!p) { if (count) *count = 0; return; }
    GLsizei n = (p->shader_count < maxCount) ? p->shader_count : maxCount;
    for (GLsizei i = 0; i < n; ++i) {
        if (obj) obj[i] = p->shaders[i];
    }
    if (count) *count = n;
}

static void APIENTRY_GLES m_glGetActiveUniform(GLuint program, GLuint index, GLsizei bufSize, GLsizei *length, GLint *size, GLenum *type, GLchar *name) {
    mock_program_t *p = find_program(program);
    static const struct { uint32_t bit; const char *name; GLenum type; } umap[] = {
        {1u,  "_gl4es_ModelViewProjectionMatrix", GL_FLOAT_MAT4},
        {2u,  "_gl4es_LightSource_0.diffuse",     GL_FLOAT_VEC4},
        {4u,  "_gl4es_Fog.color",                 GL_FLOAT_VEC4},
        {8u,  "_gl4es_AlphaRef",                  GL_FLOAT},
        {16u, "_gl4es_TextureEnvColor_0",         GL_FLOAT_VEC4},
    };
    const char *uname = "u_mock";
    GLenum utype = GL_FLOAT_VEC4;
    if (p) {
        GLuint seen = 0;
        for (size_t i = 0; i < sizeof(umap)/sizeof(umap[0]); ++i) {
            if (p->uniform_mask & umap[i].bit) {
                if (seen == index) {
                    uname = umap[i].name;
                    utype = umap[i].type;
                    break;
                }
                seen++;
            }
        }
    }
    if (size) *size = 1;
    if (type) *type = utype;
    if (name && bufSize > 0) {
        size_t l = strlen(uname);
        size_t cp = (l < (size_t)bufSize - 1) ? l : (size_t)(bufSize - 1);
        memcpy(name, uname, cp);
        name[cp] = '\0';
        if (length) *length = (GLsizei)cp;
    } else if (length) {
        *length = 0;
    }
}

static GLint APIENTRY_GLES m_glGetUniformLocation(GLuint program, const GLchar *name) {
    (void)program;
    if (!name) return -1;
    if (strcmp(name, "_gl4es_ModelViewProjectionMatrix") == 0) return 0;
    if (strcmp(name, "_gl4es_LightSource_0.diffuse") == 0) return 1;
    if (strcmp(name, "_gl4es_Fog.color") == 0) return 2;
    if (strcmp(name, "_gl4es_AlphaRef") == 0) return 3;
    if (strcmp(name, "_gl4es_TextureEnvColor_0") == 0) return 4;
    return -1;
}

static void APIENTRY_GLES m_glGetActiveAttrib(GLuint program, GLuint index, GLsizei bufSize, GLsizei *length, GLint *size, GLenum *type, GLchar *name) {
    mock_program_t *p = find_program(program);
    static const struct { uint32_t bit; const char *name; } map[] = {
        {1u, "_gl4es_Vertex"},
        {2u, "_gl4es_Color"},
        {4u, "_gl4es_Normal"},
        {8u, "_gl4es_MultiTexCoord0"},
    };
    const char *aname = "_gl4es_Vertex";
    if (p) {
        GLuint seen = 0;
        for (size_t i = 0; i < sizeof(map)/sizeof(map[0]); ++i) {
            if (p->attr_mask & map[i].bit) {
                if (seen == index) { aname = map[i].name; break; }
                seen++;
            }
        }
    }
    if (size) *size = 1;
    if (type) *type = GL_FLOAT_VEC4;
    if (name && bufSize > 0) {
        size_t l = strlen(aname);
        size_t cp = (l < (size_t)bufSize - 1) ? l : (size_t)(bufSize - 1);
        memcpy(name, aname, cp);
        name[cp] = '\0';
        if (length) *length = (GLsizei)cp;
    } else if (length) {
        *length = 0;
    }
}

static GLint APIENTRY_GLES m_glGetAttribLocation(GLuint program, const GLchar *name) {
    (void)program;
    if (!name) return -1;
    if (strcmp(name, "_gl4es_Vertex") == 0) return 0;
    if (strcmp(name, "_gl4es_Normal") == 0) return 2;
    if (strcmp(name, "_gl4es_Color") == 0) return 3;
    if (strcmp(name, "_gl4es_MultiTexCoord0") == 0) return 8;
    return -1;
}

static void APIENTRY_GLES m_glGetProgramBinaryOES(GLuint program, GLsizei bufSize, GLsizei *length, GLenum *binaryFormat, GLvoid *binary) {
    mock_program_t *p = find_program(program);
    g_state.program_binary_saves++;
    if (binaryFormat) *binaryFormat = 0x87FF;
    GLsizei out_len = (bufSize >= 32) ? 32 : bufSize;
    if (length) *length = out_len;
    if (binary && out_len > 0) {
        uint8_t *dst = (uint8_t *)binary;
        memset(dst, 0xA5, (size_t)out_len);
        uint32_t mask = p ? p->attr_mask : 3u;
        uint32_t umask = p ? p->uniform_mask : 1u;
        if (out_len >= 4) memcpy(dst, &mask, 4);
        if (out_len >= 8) memcpy(dst + 4, &umask, 4);
    }
}

static void APIENTRY_GLES m_glProgramBinaryOES(GLuint program, GLenum binaryFormat, const GLvoid *binary, GLint length) {
    (void)binaryFormat;
    mock_program_t *p = find_program(program);
    if (g_state.fail_program_binary || !p || !binary || length <= 0) {
        if (p) p->linked = 0;
        return;
    }
    p->linked = 1;
    p->attr_mask = 3u; /* _gl4es_Vertex + _gl4es_Color */
    p->uniform_mask = 1u;
    if (length >= 4) memcpy(&p->attr_mask, binary, 4);
    if (length >= 8) memcpy(&p->uniform_mask, (const uint8_t *)binary + 4, 4);
    g_state.program_binary_loads++;
}

static void APIENTRY_GLES m_glGenBuffers(GLsizei n, GLuint *buffers) {
    if (!buffers || n <= 0) return;
    g_state.gen_buffers_calls++;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = g_next_buffer++;
        find_or_create_buffer(id);
        buffers[i] = id;
    }
}

static void APIENTRY_GLES m_glDeleteBuffers(GLsizei n, const GLuint *buffers) {
    if (!buffers || n <= 0) return;
    g_state.delete_buffers_calls++;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = buffers[i];
        if (id == 0) continue;
        if (g_state.bound_array_buffer == id) g_state.bound_array_buffer = 0;
        if (g_state.bound_element_array_buffer == id) g_state.bound_element_array_buffer = 0;
        mock_buffer_t *b = find_buffer(id);
        if (b) {
            if (g_state.buffer_bytes_live >= b->size) g_state.buffer_bytes_live -= b->size;
            else g_state.buffer_bytes_live = 0;
            free(b->data);
            b->data = NULL;
            b->size = 0;
            b->alive = 0;
            if (g_state.live_buffers > 0) g_state.live_buffers--;
        }
    }
}

static void APIENTRY_GLES m_glBindBuffer(GLenum target, GLuint buffer) {
    g_state.bind_buffer_calls++;
    if (target == GL_ARRAY_BUFFER) g_state.bound_array_buffer = buffer;
    else if (target == GL_ELEMENT_ARRAY_BUFFER) g_state.bound_element_array_buffer = buffer;
}

static GLboolean APIENTRY_GLES m_glIsBuffer(GLuint buffer) {
    return find_buffer(buffer) ? GL_TRUE : GL_FALSE;
}

static void APIENTRY_GLES m_glBufferData(GLenum target, GLsizeiptr size, const GLvoid *data, GLenum usage) {
    g_state.buffer_data_calls++;
    GLuint id = (target == GL_ELEMENT_ARRAY_BUFFER) ? g_state.bound_element_array_buffer : g_state.bound_array_buffer;
    if (id == 0 || size < 0) return;
    mock_buffer_t *b = find_or_create_buffer(id);
    if (g_state.buffer_bytes_live >= b->size) g_state.buffer_bytes_live -= b->size;
    free(b->data);
    b->data = NULL;
    b->size = (size_t)size;
    b->usage = usage;
    if (b->size > 0) {
        b->data = (uint8_t *)malloc(b->size);
        if (b->data) {
            if (data) memcpy(b->data, data, b->size);
            else memset(b->data, 0, b->size);
        }
    }
    g_state.buffer_bytes_live += b->size;
    if (g_state.buffer_bytes_live > g_state.buffer_bytes_peak) {
        g_state.buffer_bytes_peak = g_state.buffer_bytes_live;
    }
}

static void APIENTRY_GLES m_glBufferSubData(GLenum target, GLintptr offset, GLsizeiptr size, const GLvoid *data) {
    g_state.buffer_sub_data_calls++;
    GLuint id = (target == GL_ELEMENT_ARRAY_BUFFER) ? g_state.bound_element_array_buffer : g_state.bound_array_buffer;
    mock_buffer_t *b = find_buffer(id);
    if (!b || !b->data || !data || offset < 0 || size < 0) return;
    if ((size_t)offset + (size_t)size <= b->size) {
        memcpy(b->data + offset, data, (size_t)size);
    }
}

static void APIENTRY_GLES m_glGetBufferParameteriv(GLenum target, GLenum pname, GLint *params) {
    if (!params) return;
    GLuint id = (target == GL_ELEMENT_ARRAY_BUFFER) ? g_state.bound_element_array_buffer : g_state.bound_array_buffer;
    mock_buffer_t *b = find_buffer(id);
    if (pname == GL_BUFFER_SIZE) params[0] = b ? (GLint)b->size : 0;
    else if (pname == GL_BUFFER_USAGE) params[0] = b ? (GLint)b->usage : GL_STATIC_DRAW;
    else params[0] = 0;
}

static void APIENTRY_GLES m_glActiveTexture(GLenum texture) {
    if (texture >= GL_TEXTURE0) {
        g_state.active_texture_unit = (GLuint)(texture - GL_TEXTURE0);
    }
}

static void APIENTRY_GLES m_glGenTextures(GLsizei n, GLuint *textures) {
    if (!textures || n <= 0) return;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = g_next_texture++;
        find_or_create_texture(id);
        textures[i] = id;
    }
}

static void APIENTRY_GLES m_glDeleteTextures(GLsizei n, const GLuint *textures) {
    if (!textures || n <= 0) return;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = textures[i];
        if (id == 0) continue;
        for (int u = 0; u < 32; ++u) {
            if (g_state.bound_textures[u] == id) g_state.bound_textures[u] = 0;
        }
        for (size_t k = 0; k < g_textures_cap; ++k) {
            if (g_textures[k].alive && g_textures[k].id == id) {
                if (g_state.texture_bytes_live >= g_textures[k].bytes) {
                    g_state.texture_bytes_live -= g_textures[k].bytes;
                } else {
                    g_state.texture_bytes_live = 0;
                }
                g_textures[k].alive = 0;
                g_textures[k].bytes = 0;
                if (g_state.live_textures > 0) g_state.live_textures--;
                break;
            }
        }
    }
}

static void APIENTRY_GLES m_glBindTexture(GLenum target, GLuint texture) {
    (void)target;
    g_state.tex_bind_calls++;
    g_state.bound_textures[g_state.active_texture_unit & 31u] = texture;
    if (texture != 0) find_or_create_texture(texture);
}

static GLboolean APIENTRY_GLES m_glIsTexture(GLuint texture) {
    if (texture == 0) return GL_FALSE;
    for (size_t k = 0; k < g_textures_cap; ++k) {
        if (g_textures[k].alive && g_textures[k].id == texture) return GL_TRUE;
    }
    return GL_FALSE;
}

static void APIENTRY_GLES m_glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid *data) {
    (void)target; (void)internalformat; (void)border; (void)type; (void)data;
    g_state.tex_image_calls++;
    GLuint id = g_state.bound_textures[g_state.active_texture_unit & 31u];
    mock_texture_t *t = find_or_create_texture(id);
    if (t && level == 0 && width > 0 && height > 0) {
        if (g_state.texture_bytes_live >= t->bytes) g_state.texture_bytes_live -= t->bytes;
        t->width = width;
        t->height = height;
        t->format = format;
        t->bytes = (size_t)width * (size_t)height * 4u;
        g_state.texture_bytes_live += t->bytes;
        if (g_state.texture_bytes_live > g_state.texture_bytes_peak) {
            g_state.texture_bytes_peak = g_state.texture_bytes_live;
        }
    }
}

static void APIENTRY_GLES m_glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid *data) {
    (void)target; (void)level; (void)xoffset; (void)yoffset; (void)width; (void)height; (void)format; (void)type; (void)data;
    g_state.tex_sub_image_calls++;
}

static void APIENTRY_GLES m_glCompressedTexImage2D(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLint border, GLsizei imageSize, const GLvoid *data) {
    (void)target; (void)level; (void)internalformat; (void)width; (void)height; (void)border; (void)imageSize; (void)data;
    g_state.tex_image_calls++;
}

static void APIENTRY_GLES m_glCompressedTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLsizei imageSize, const GLvoid *data) {
    (void)target; (void)level; (void)xoffset; (void)yoffset; (void)width; (void)height; (void)format; (void)imageSize; (void)data;
    g_state.tex_sub_image_calls++;
}

static void APIENTRY_GLES m_glCopyTexImage2D(GLenum target, GLint level, GLenum internalformat, GLint x, GLint y, GLsizei width, GLsizei height, GLint border) {
    (void)target; (void)level; (void)internalformat; (void)x; (void)y; (void)width; (void)height; (void)border;
}

static void APIENTRY_GLES m_glCopyTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height) {
    (void)target; (void)level; (void)xoffset; (void)yoffset; (void)x; (void)y; (void)width; (void)height;
}

static void APIENTRY_GLES m_glTexParameterf(GLenum target, GLenum pname, GLfloat param) { (void)target; (void)pname; (void)param; }
static void APIENTRY_GLES m_glTexParameterfv(GLenum target, GLenum pname, const GLfloat *params) { (void)target; (void)pname; (void)params; }
static void APIENTRY_GLES m_glTexParameteri(GLenum target, GLenum pname, GLint param) { (void)target; (void)pname; (void)param; }
static void APIENTRY_GLES m_glTexParameteriv(GLenum target, GLenum pname, const GLint *params) { (void)target; (void)pname; (void)params; }
static void APIENTRY_GLES m_glTexParameterx(GLenum target, GLenum pname, GLfixed param) { (void)target; (void)pname; (void)param; }
static void APIENTRY_GLES m_glTexParameterxv(GLenum target, GLenum pname, const GLfixed *params) { (void)target; (void)pname; (void)params; }
static void APIENTRY_GLES m_glGetTexParameterfv(GLenum target, GLenum pname, GLfloat *params) { (void)target; (void)pname; if (params) params[0] = 0.0f; }
static void APIENTRY_GLES m_glGetTexParameteriv(GLenum target, GLenum pname, GLint *params) { (void)target; (void)pname; if (params) params[0] = 0; }
static void APIENTRY_GLES m_glGenerateMipmap(GLenum target) { (void)target; }

static void APIENTRY_GLES m_glGenFramebuffers(GLsizei n, GLuint *ids) {
    if (!ids || n <= 0) return;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = g_next_fbo++;
        size_t idx = g_fbos_cap;
        int placed = 0;
        for (size_t k = 0; k < g_fbos_cap; ++k) {
            if (!g_fbos[k].alive) { g_fbos[k].id = id; g_fbos[k].alive = 1; placed = 1; break; }
        }
        if (!placed) {
            ensure_cap((void **)&g_fbos, &g_fbos_cap, sizeof(mock_obj_slot_t), idx + 1);
            g_fbos[idx].id = id; g_fbos[idx].alive = 1;
        }
        g_state.live_fbos++;
        ids[i] = id;
    }
}

static void APIENTRY_GLES m_glDeleteFramebuffers(GLsizei n, GLuint *framebuffers) {
    if (!framebuffers || n <= 0) return;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = framebuffers[i];
        if (!id) continue;
        if (g_state.bound_framebuffer == id) g_state.bound_framebuffer = 0;
        for (size_t k = 0; k < g_fbos_cap; ++k) {
            if (g_fbos[k].alive && g_fbos[k].id == id) {
                g_fbos[k].alive = 0;
                if (g_state.live_fbos > 0) g_state.live_fbos--;
                break;
            }
        }
    }
}

static void APIENTRY_GLES m_glBindFramebuffer(GLenum target, GLuint framebuffer) {
    (void)target;
    g_state.bound_framebuffer = framebuffer;
}

static GLenum APIENTRY_GLES m_glCheckFramebufferStatus(GLenum target) {
    (void)target;
    return GL_FRAMEBUFFER_COMPLETE_OES;
}

static GLboolean APIENTRY_GLES m_glIsFramebuffer(GLuint framebuffer) {
    for (size_t k = 0; k < g_fbos_cap; ++k) {
        if (g_fbos[k].alive && g_fbos[k].id == framebuffer) return GL_TRUE;
    }
    return GL_FALSE;
}

static void APIENTRY_GLES m_glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
    (void)target; (void)attachment; (void)textarget; (void)texture; (void)level;
}

static void APIENTRY_GLES m_glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) {
    (void)target; (void)attachment; (void)renderbuffertarget; (void)renderbuffer;
}

static void APIENTRY_GLES m_glGetFramebufferAttachmentParameteriv(GLenum target, GLenum attachment, GLenum pname, GLint *params) {
    (void)target; (void)attachment; (void)pname;
    if (params) params[0] = 0;
}

static void APIENTRY_GLES m_glGenRenderbuffers(GLsizei n, GLuint *renderbuffers) {
    if (!renderbuffers || n <= 0) return;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = g_next_rbo++;
        size_t idx = g_rbos_cap;
        int placed = 0;
        for (size_t k = 0; k < g_rbos_cap; ++k) {
            if (!g_rbos[k].alive) { g_rbos[k].id = id; g_rbos[k].alive = 1; placed = 1; break; }
        }
        if (!placed) {
            ensure_cap((void **)&g_rbos, &g_rbos_cap, sizeof(mock_obj_slot_t), idx + 1);
            g_rbos[idx].id = id; g_rbos[idx].alive = 1;
        }
        g_state.live_rbos++;
        renderbuffers[i] = id;
    }
}

static void APIENTRY_GLES m_glDeleteRenderbuffers(GLsizei n, GLuint *renderbuffers) {
    if (!renderbuffers || n <= 0) return;
    for (GLsizei i = 0; i < n; ++i) {
        GLuint id = renderbuffers[i];
        if (!id) continue;
        if (g_state.bound_renderbuffer == id) g_state.bound_renderbuffer = 0;
        for (size_t k = 0; k < g_rbos_cap; ++k) {
            if (g_rbos[k].alive && g_rbos[k].id == id) {
                g_rbos[k].alive = 0;
                if (g_state.live_rbos > 0) g_state.live_rbos--;
                break;
            }
        }
    }
}

static void APIENTRY_GLES m_glBindRenderbuffer(GLenum target, GLuint renderbuffer) {
    (void)target;
    g_state.bound_renderbuffer = renderbuffer;
}

static void APIENTRY_GLES m_glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height) {
    (void)target; (void)internalformat; (void)width; (void)height;
}

static GLboolean APIENTRY_GLES m_glIsRenderbuffer(GLuint renderbuffer) {
    for (size_t k = 0; k < g_rbos_cap; ++k) {
        if (g_rbos[k].alive && g_rbos[k].id == renderbuffer) return GL_TRUE;
    }
    return GL_FALSE;
}

static void APIENTRY_GLES m_glGetRenderbufferParameteriv(GLenum target, GLenum pname, GLint *params) {
    (void)target; (void)pname;
    if (params) params[0] = 0;
}

static void APIENTRY_GLES m_glDrawBuffers(GLsizei n, const GLenum *bufs) { (void)n; (void)bufs; }

static void APIENTRY_GLES m_glEnableVertexAttribArray(GLuint index) {
    g_state.enable_vertex_attrib_calls++;
    if (index < 16) g_attribs[index].enabled = 1;
}

static void APIENTRY_GLES m_glDisableVertexAttribArray(GLuint index) {
    g_state.disable_vertex_attrib_calls++;
    if (index < 16) g_attribs[index].enabled = 0;
}

static void APIENTRY_GLES m_glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid *pointer) {
    g_state.vertex_attrib_pointer_calls++;
    if (index < 16) {
        g_attribs[index].size = size;
        g_attribs[index].type = type;
        g_attribs[index].normalized = normalized;
        g_attribs[index].stride = stride;
        g_attribs[index].pointer = pointer;
        g_attribs[index].vbo = g_state.bound_array_buffer;
    }
}

static void APIENTRY_GLES m_glVertexAttribIPointer(GLuint index, GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
    m_glVertexAttribPointer(index, size, type, GL_FALSE, stride, pointer);
}

static void APIENTRY_GLES m_glDrawArrays(GLenum mode, GLint first, GLsizei count) {
    g_state.draw_arrays_calls++;
    g_state.last_draw_mode = mode;
    g_state.last_draw_count = count;
    g_state.last_draw_type = 0;
    g_state.last_draw_ibo = g_state.bound_element_array_buffer;
    g_state.last_draw_vbo = g_state.bound_array_buffer;
    g_state.last_draw_program = g_state.current_program;
    capture_color_bytes_at_draw(first, 0, NULL);
}

static void APIENTRY_GLES m_glDrawElements(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices) {
    g_state.draw_elements_calls++;
    g_state.last_draw_mode = mode;
    g_state.last_draw_count = count;
    g_state.last_draw_type = type;
    g_state.last_draw_ibo = g_state.bound_element_array_buffer;
    g_state.last_draw_vbo = g_state.bound_array_buffer;
    g_state.last_draw_program = g_state.current_program;
    capture_color_bytes_at_draw(0, type, indices);
}

static void APIENTRY_GLES m_glMultiDrawArrays(GLenum mode, const GLint *first, const GLsizei *count, GLsizei primcount) {
    if (!first || !count) return;
    for (GLsizei i = 0; i < primcount; ++i) m_glDrawArrays(mode, first[i], count[i]);
}

static void APIENTRY_GLES m_glMultiDrawElements(GLenum mode, GLsizei *count, GLenum type, const void * const *indices, GLsizei primcount) {
    if (!count || !indices) return;
    for (GLsizei i = 0; i < primcount; ++i) m_glDrawElements(mode, count[i], type, indices[i]);
}

static void APIENTRY_GLES m_glClear(GLbitfield mask) { (void)mask; g_state.clear_calls++; }
static void APIENTRY_GLES m_glClearColor(GLclampf r, GLclampf g, GLclampf b, GLclampf a) { (void)r; (void)g; (void)b; (void)a; }
static void APIENTRY_GLES m_glClearDepthf(GLclampf d) { (void)d; }
static void APIENTRY_GLES m_glClearStencil(GLint s) { (void)s; }
static void APIENTRY_GLES m_glViewport(GLint x, GLint y, GLsizei w, GLsizei h) { (void)x; (void)y; (void)w; (void)h; }
static void APIENTRY_GLES m_glScissor(GLint x, GLint y, GLsizei w, GLsizei h) { (void)x; (void)y; (void)w; (void)h; }
static void APIENTRY_GLES m_glEnable(GLenum cap) { (void)cap; }
static void APIENTRY_GLES m_glDisable(GLenum cap) { (void)cap; }
static GLboolean APIENTRY_GLES m_glIsEnabled(GLenum cap) { (void)cap; return GL_FALSE; }
static void APIENTRY_GLES m_glBlendColor(GLclampf r, GLclampf g, GLclampf b, GLclampf a) { (void)r; (void)g; (void)b; (void)a; }
static void APIENTRY_GLES m_glBlendEquation(GLenum m) { (void)m; }
static void APIENTRY_GLES m_glBlendEquationSeparate(GLenum r, GLenum a) { (void)r; (void)a; }
static void APIENTRY_GLES m_glBlendFunc(GLenum s, GLenum d) { (void)s; (void)d; }
static void APIENTRY_GLES m_glBlendFuncSeparate(GLenum sr, GLenum dr, GLenum sa, GLenum da) { (void)sr; (void)dr; (void)sa; (void)da; }
static void APIENTRY_GLES m_glColorMask(GLboolean r, GLboolean g, GLboolean b, GLboolean a) { (void)r; (void)g; (void)b; (void)a; }
static void APIENTRY_GLES m_glCullFace(GLenum m) { (void)m; }
static void APIENTRY_GLES m_glFrontFace(GLenum m) { (void)m; }
static void APIENTRY_GLES m_glDepthFunc(GLenum f) { (void)f; }
static void APIENTRY_GLES m_glDepthMask(GLboolean f) { (void)f; }
static void APIENTRY_GLES m_glDepthRangef(GLclampf n, GLclampf f) { (void)n; (void)f; }
static void APIENTRY_GLES m_glLineWidth(GLfloat w) { (void)w; }
static void APIENTRY_GLES m_glPolygonOffset(GLfloat f, GLfloat u) { (void)f; (void)u; }
static void APIENTRY_GLES m_glSampleCoverage(GLclampf v, GLboolean i) { (void)v; (void)i; }
static void APIENTRY_GLES m_glStencilFunc(GLenum f, GLint r, GLuint m) { (void)f; (void)r; (void)m; }
static void APIENTRY_GLES m_glStencilFuncSeparate(GLenum fa, GLenum f, GLint r, GLuint m) { (void)fa; (void)f; (void)r; (void)m; }
static void APIENTRY_GLES m_glStencilMask(GLuint m) { (void)m; }
static void APIENTRY_GLES m_glStencilMaskSeparate(GLenum fa, GLuint m) { (void)fa; (void)m; }
static void APIENTRY_GLES m_glStencilOp(GLenum s, GLenum z, GLenum p) { (void)s; (void)z; (void)p; }
static void APIENTRY_GLES m_glStencilOpSeparate(GLenum fa, GLenum s, GLenum z, GLenum p) { (void)fa; (void)s; (void)z; (void)p; }
static void APIENTRY_GLES m_glHint(GLenum t, GLenum m) { (void)t; (void)m; }
static void APIENTRY_GLES m_glPixelStorei(GLenum p, GLint v) { (void)p; (void)v; }
static void APIENTRY_GLES m_glReadPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum f, GLenum t, GLvoid *p) { (void)x; (void)y; (void)w; (void)h; (void)f; (void)t; (void)p; }
static void APIENTRY_GLES m_glFinish(void) {}
static void APIENTRY_GLES m_glFlush(void) {}
static void APIENTRY_GLES m_glReleaseShaderCompiler(void) {}
static void APIENTRY_GLES m_glShaderBinary(GLsizei n, const GLuint *s, GLenum bf, const GLvoid *b, GLsizei l) { (void)n; (void)s; (void)bf; (void)b; (void)l; }

static void APIENTRY_GLES m_glUniform1f(GLint l, GLfloat v0) { (void)l; (void)v0; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform1fv(GLint l, GLsizei c, const GLfloat *v) { (void)l; (void)c; (void)v; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform1i(GLint l, GLint v0) { (void)l; (void)v0; }
static void APIENTRY_GLES m_glUniform1iv(GLint l, GLsizei c, const GLint *v) { (void)l; (void)c; (void)v; }
static void APIENTRY_GLES m_glUniform2f(GLint l, GLfloat v0, GLfloat v1) { (void)l; (void)v0; (void)v1; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform2fv(GLint l, GLsizei c, const GLfloat *v) { (void)l; (void)c; (void)v; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform2i(GLint l, GLint v0, GLint v1) { (void)l; (void)v0; (void)v1; }
static void APIENTRY_GLES m_glUniform2iv(GLint l, GLsizei c, const GLint *v) { (void)l; (void)c; (void)v; }
static void APIENTRY_GLES m_glUniform3f(GLint l, GLfloat v0, GLfloat v1, GLfloat v2) { (void)l; (void)v0; (void)v1; (void)v2; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform3fv(GLint l, GLsizei c, const GLfloat *v) { (void)l; (void)c; (void)v; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform3i(GLint l, GLint v0, GLint v1, GLint v2) { (void)l; (void)v0; (void)v1; (void)v2; }
static void APIENTRY_GLES m_glUniform3iv(GLint l, GLsizei c, const GLint *v) { (void)l; (void)c; (void)v; }
static void APIENTRY_GLES m_glUniform4f(GLint l, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) { (void)l; (void)v0; (void)v1; (void)v2; (void)v3; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform4fv(GLint l, GLsizei c, const GLfloat *v) { (void)l; (void)c; (void)v; g_state.uniform_fv_calls++; }
static void APIENTRY_GLES m_glUniform4i(GLint l, GLint v0, GLint v1, GLint v2, GLint v3) { (void)l; (void)v0; (void)v1; (void)v2; (void)v3; }
static void APIENTRY_GLES m_glUniform4iv(GLint l, GLsizei c, const GLint *v) { (void)l; (void)c; (void)v; }
static void APIENTRY_GLES m_glUniformMatrix2fv(GLint l, GLsizei c, GLboolean t, const GLfloat *v) { (void)l; (void)c; (void)t; (void)v; g_state.uniform_matrix_calls++; }
static void APIENTRY_GLES m_glUniformMatrix3fv(GLint l, GLsizei c, GLboolean t, const GLfloat *v) { (void)l; (void)c; (void)t; (void)v; g_state.uniform_matrix_calls++; }
static void APIENTRY_GLES m_glUniformMatrix4fv(GLint l, GLsizei c, GLboolean t, const GLfloat *v) { (void)l; (void)c; (void)t; (void)v; g_state.uniform_matrix_calls++; }
static void APIENTRY_GLES m_glGetUniformfv(GLuint p, GLint l, GLfloat *params) { (void)p; (void)l; if (params) params[0] = 0.0f; }
static void APIENTRY_GLES m_glGetUniformiv(GLuint p, GLint l, GLint *params) { (void)p; (void)l; if (params) params[0] = 0; }

static void APIENTRY_GLES m_glVertexAttrib1f(GLuint i, GLfloat x) { (void)i; (void)x; }
static void APIENTRY_GLES m_glVertexAttrib1fv(GLuint i, const GLfloat *v) { (void)i; (void)v; }
static void APIENTRY_GLES m_glVertexAttrib2f(GLuint i, GLfloat x, GLfloat y) { (void)i; (void)x; (void)y; }
static void APIENTRY_GLES m_glVertexAttrib2fv(GLuint i, const GLfloat *v) { (void)i; (void)v; }
static void APIENTRY_GLES m_glVertexAttrib3f(GLuint i, GLfloat x, GLfloat y, GLfloat z) { (void)i; (void)x; (void)y; (void)z; }
static void APIENTRY_GLES m_glVertexAttrib3fv(GLuint i, const GLfloat *v) { (void)i; (void)v; }
static void APIENTRY_GLES m_glVertexAttrib4f(GLuint i, GLfloat x, GLfloat y, GLfloat z, GLfloat w) { (void)i; (void)x; (void)y; (void)z; (void)w; }
static void APIENTRY_GLES m_glVertexAttrib4fv(GLuint i, const GLfloat *v) { (void)i; (void)v; }
static void APIENTRY_GLES m_glGetVertexAttribfv(GLuint i, GLenum p, GLfloat *params) { (void)i; (void)p; if (params) params[0] = 0.0f; }
static void APIENTRY_GLES m_glGetVertexAttribiv(GLuint i, GLenum p, GLint *params) { (void)i; (void)p; if (params) params[0] = 0; }
static void APIENTRY_GLES m_glGetVertexAttribPointerv(GLuint i, GLenum p, GLvoid **ptr) { (void)i; (void)p; if (ptr) *ptr = NULL; }

/* ES1 / OES fallback stubs */
static void APIENTRY_GLES m_glDrawTexfOES(GLfloat x, GLfloat y, GLfloat z, GLfloat w, GLfloat h) { (void)x; (void)y; (void)z; (void)w; (void)h; }
static void APIENTRY_GLES m_glDrawTexiOES(GLint x, GLint y, GLint z, GLint w, GLint h) { (void)x; (void)y; (void)z; (void)w; (void)h; }
static void APIENTRY_GLES m_glTexGenfvOES(GLenum coord, GLenum pname, const GLfloat *params) { (void)coord; (void)pname; (void)params; }
static void APIENTRY_GLES m_glTexGeniOES(GLenum coord, GLenum pname, GLint param) { (void)coord; (void)pname; (void)param; }
static void APIENTRY_GLES m_glPointSizePointerOES(GLenum t, GLsizei s, const GLvoid *p) { (void)t; (void)s; (void)p; }
static void APIENTRY_GLES m_glGenericVoidStub(void) {}

typedef struct proc_entry_s {
    const char *name;
    void *fn;
} proc_entry_t;

static const proc_entry_t g_proc_table[] = {
    {"glGetString", (void *)m_glGetString},
    {"glGetError", (void *)m_glGetError},
    {"glGetIntegerv", (void *)m_glGetIntegerv},
    {"glGetBooleanv", (void *)m_glGetBooleanv},
    {"glGetFloatv", (void *)m_glGetFloatv},
    {"glGetShaderPrecisionFormat", (void *)m_glGetShaderPrecisionFormat},
    {"glCreateShader", (void *)m_glCreateShader},
    {"glShaderSource", (void *)m_glShaderSource},
    {"glCompileShader", (void *)m_glCompileShader},
    {"glGetShaderiv", (void *)m_glGetShaderiv},
    {"glGetShaderInfoLog", (void *)m_glGetShaderInfoLog},
    {"glGetShaderSource", (void *)m_glGetShaderSource},
    {"glDeleteShader", (void *)m_glDeleteShader},
    {"glIsShader", (void *)m_glIsShader},
    {"glCreateProgram", (void *)m_glCreateProgram},
    {"glAttachShader", (void *)m_glAttachShader},
    {"glDetachShader", (void *)m_glDetachShader},
    {"glBindAttribLocation", (void *)m_glBindAttribLocation},
    {"glLinkProgram", (void *)m_glLinkProgram},
    {"glValidateProgram", (void *)m_glValidateProgram},
    {"glUseProgram", (void *)m_glUseProgram},
    {"glDeleteProgram", (void *)m_glDeleteProgram},
    {"glIsProgram", (void *)m_glIsProgram},
    {"glGetProgramiv", (void *)m_glGetProgramiv},
    {"glGetProgramInfoLog", (void *)m_glGetProgramInfoLog},
    {"glGetAttachedShaders", (void *)m_glGetAttachedShaders},
    {"glGetActiveUniform", (void *)m_glGetActiveUniform},
    {"glGetUniformLocation", (void *)m_glGetUniformLocation},
    {"glGetActiveAttrib", (void *)m_glGetActiveAttrib},
    {"glGetAttribLocation", (void *)m_glGetAttribLocation},
    {"glGetProgramBinary", (void *)m_glGetProgramBinaryOES},
    {"glGetProgramBinaryOES", (void *)m_glGetProgramBinaryOES},
    {"glProgramBinary", (void *)m_glProgramBinaryOES},
    {"glProgramBinaryOES", (void *)m_glProgramBinaryOES},
    {"glGenBuffers", (void *)m_glGenBuffers},
    {"glDeleteBuffers", (void *)m_glDeleteBuffers},
    {"glBindBuffer", (void *)m_glBindBuffer},
    {"glIsBuffer", (void *)m_glIsBuffer},
    {"glBufferData", (void *)m_glBufferData},
    {"glBufferSubData", (void *)m_glBufferSubData},
    {"glGetBufferParameteriv", (void *)m_glGetBufferParameteriv},
    {"glActiveTexture", (void *)m_glActiveTexture},
    {"glGenTextures", (void *)m_glGenTextures},
    {"glDeleteTextures", (void *)m_glDeleteTextures},
    {"glBindTexture", (void *)m_glBindTexture},
    {"glIsTexture", (void *)m_glIsTexture},
    {"glTexImage2D", (void *)m_glTexImage2D},
    {"glTexSubImage2D", (void *)m_glTexSubImage2D},
    {"glCompressedTexImage2D", (void *)m_glCompressedTexImage2D},
    {"glCompressedTexSubImage2D", (void *)m_glCompressedTexSubImage2D},
    {"glCopyTexImage2D", (void *)m_glCopyTexImage2D},
    {"glCopyTexSubImage2D", (void *)m_glCopyTexSubImage2D},
    {"glTexParameterf", (void *)m_glTexParameterf},
    {"glTexParameterfv", (void *)m_glTexParameterfv},
    {"glTexParameteri", (void *)m_glTexParameteri},
    {"glTexParameteriv", (void *)m_glTexParameteriv},
    {"glTexParameterx", (void *)m_glTexParameterx},
    {"glTexParameterxv", (void *)m_glTexParameterxv},
    {"glGetTexParameterfv", (void *)m_glGetTexParameterfv},
    {"glGetTexParameteriv", (void *)m_glGetTexParameteriv},
    {"glGenerateMipmap", (void *)m_glGenerateMipmap},
    {"glGenerateMipmapOES", (void *)m_glGenerateMipmap},
    {"glGenFramebuffers", (void *)m_glGenFramebuffers},
    {"glGenFramebuffersOES", (void *)m_glGenFramebuffers},
    {"glDeleteFramebuffers", (void *)m_glDeleteFramebuffers},
    {"glDeleteFramebuffersOES", (void *)m_glDeleteFramebuffers},
    {"glBindFramebuffer", (void *)m_glBindFramebuffer},
    {"glBindFramebufferOES", (void *)m_glBindFramebuffer},
    {"glCheckFramebufferStatus", (void *)m_glCheckFramebufferStatus},
    {"glCheckFramebufferStatusOES", (void *)m_glCheckFramebufferStatus},
    {"glIsFramebuffer", (void *)m_glIsFramebuffer},
    {"glIsFramebufferOES", (void *)m_glIsFramebuffer},
    {"glFramebufferTexture2D", (void *)m_glFramebufferTexture2D},
    {"glFramebufferTexture2DOES", (void *)m_glFramebufferTexture2D},
    {"glFramebufferRenderbuffer", (void *)m_glFramebufferRenderbuffer},
    {"glFramebufferRenderbufferOES", (void *)m_glFramebufferRenderbuffer},
    {"glGetFramebufferAttachmentParameteriv", (void *)m_glGetFramebufferAttachmentParameteriv},
    {"glGetFramebufferAttachmentParameterivOES", (void *)m_glGetFramebufferAttachmentParameteriv},
    {"glGenRenderbuffers", (void *)m_glGenRenderbuffers},
    {"glGenRenderbuffersOES", (void *)m_glGenRenderbuffers},
    {"glDeleteRenderbuffers", (void *)m_glDeleteRenderbuffers},
    {"glDeleteRenderbuffersOES", (void *)m_glDeleteRenderbuffers},
    {"glBindRenderbuffer", (void *)m_glBindRenderbuffer},
    {"glBindRenderbufferOES", (void *)m_glBindRenderbuffer},
    {"glRenderbufferStorage", (void *)m_glRenderbufferStorage},
    {"glRenderbufferStorageOES", (void *)m_glRenderbufferStorage},
    {"glIsRenderbuffer", (void *)m_glIsRenderbuffer},
    {"glIsRenderbufferOES", (void *)m_glIsRenderbuffer},
    {"glGetRenderbufferParameteriv", (void *)m_glGetRenderbufferParameteriv},
    {"glGetRenderbufferParameterivOES", (void *)m_glGetRenderbufferParameteriv},
    {"glDrawBuffers", (void *)m_glDrawBuffers},
    {"glDrawBuffersEXT", (void *)m_glDrawBuffers},
    {"glEnableVertexAttribArray", (void *)m_glEnableVertexAttribArray},
    {"glDisableVertexAttribArray", (void *)m_glDisableVertexAttribArray},
    {"glVertexAttribPointer", (void *)m_glVertexAttribPointer},
    {"glVertexAttribIPointer", (void *)m_glVertexAttribIPointer},
    {"glDrawArrays", (void *)m_glDrawArrays},
    {"glDrawElements", (void *)m_glDrawElements},
    {"glMultiDrawArrays", (void *)m_glMultiDrawArrays},
    {"glMultiDrawArraysOES", (void *)m_glMultiDrawArrays},
    {"glMultiDrawElements", (void *)m_glMultiDrawElements},
    {"glMultiDrawElementsOES", (void *)m_glMultiDrawElements},
    {"glClear", (void *)m_glClear},
    {"glClearColor", (void *)m_glClearColor},
    {"glClearDepthf", (void *)m_glClearDepthf},
    {"glClearStencil", (void *)m_glClearStencil},
    {"glViewport", (void *)m_glViewport},
    {"glScissor", (void *)m_glScissor},
    {"glEnable", (void *)m_glEnable},
    {"glDisable", (void *)m_glDisable},
    {"glIsEnabled", (void *)m_glIsEnabled},
    {"glBlendColor", (void *)m_glBlendColor},
    {"glBlendColorOES", (void *)m_glBlendColor},
    {"glBlendEquation", (void *)m_glBlendEquation},
    {"glBlendEquationOES", (void *)m_glBlendEquation},
    {"glBlendEquationSeparate", (void *)m_glBlendEquationSeparate},
    {"glBlendEquationSeparateOES", (void *)m_glBlendEquationSeparate},
    {"glBlendFunc", (void *)m_glBlendFunc},
    {"glBlendFuncSeparate", (void *)m_glBlendFuncSeparate},
    {"glBlendFuncSeparateOES", (void *)m_glBlendFuncSeparate},
    {"glColorMask", (void *)m_glColorMask},
    {"glCullFace", (void *)m_glCullFace},
    {"glFrontFace", (void *)m_glFrontFace},
    {"glDepthFunc", (void *)m_glDepthFunc},
    {"glDepthMask", (void *)m_glDepthMask},
    {"glDepthRangef", (void *)m_glDepthRangef},
    {"glLineWidth", (void *)m_glLineWidth},
    {"glPolygonOffset", (void *)m_glPolygonOffset},
    {"glSampleCoverage", (void *)m_glSampleCoverage},
    {"glStencilFunc", (void *)m_glStencilFunc},
    {"glStencilFuncSeparate", (void *)m_glStencilFuncSeparate},
    {"glStencilFuncSeparateOES", (void *)m_glStencilFuncSeparate},
    {"glStencilMask", (void *)m_glStencilMask},
    {"glStencilMaskSeparate", (void *)m_glStencilMaskSeparate},
    {"glStencilMaskSeparateOES", (void *)m_glStencilMaskSeparate},
    {"glStencilOp", (void *)m_glStencilOp},
    {"glStencilOpSeparate", (void *)m_glStencilOpSeparate},
    {"glStencilOpSeparateOES", (void *)m_glStencilOpSeparate},
    {"glHint", (void *)m_glHint},
    {"glPixelStorei", (void *)m_glPixelStorei},
    {"glReadPixels", (void *)m_glReadPixels},
    {"glFinish", (void *)m_glFinish},
    {"glFlush", (void *)m_glFlush},
    {"glReleaseShaderCompiler", (void *)m_glReleaseShaderCompiler},
    {"glShaderBinary", (void *)m_glShaderBinary},
    {"glUniform1f", (void *)m_glUniform1f},
    {"glUniform1fv", (void *)m_glUniform1fv},
    {"glUniform1i", (void *)m_glUniform1i},
    {"glUniform1iv", (void *)m_glUniform1iv},
    {"glUniform2f", (void *)m_glUniform2f},
    {"glUniform2fv", (void *)m_glUniform2fv},
    {"glUniform2i", (void *)m_glUniform2i},
    {"glUniform2iv", (void *)m_glUniform2iv},
    {"glUniform3f", (void *)m_glUniform3f},
    {"glUniform3fv", (void *)m_glUniform3fv},
    {"glUniform3i", (void *)m_glUniform3i},
    {"glUniform3iv", (void *)m_glUniform3iv},
    {"glUniform4f", (void *)m_glUniform4f},
    {"glUniform4fv", (void *)m_glUniform4fv},
    {"glUniform4i", (void *)m_glUniform4i},
    {"glUniform4iv", (void *)m_glUniform4iv},
    {"glUniformMatrix2fv", (void *)m_glUniformMatrix2fv},
    {"glUniformMatrix3fv", (void *)m_glUniformMatrix3fv},
    {"glUniformMatrix4fv", (void *)m_glUniformMatrix4fv},
    {"glGetUniformfv", (void *)m_glGetUniformfv},
    {"glGetUniformiv", (void *)m_glGetUniformiv},
    {"glVertexAttrib1f", (void *)m_glVertexAttrib1f},
    {"glVertexAttrib1fv", (void *)m_glVertexAttrib1fv},
    {"glVertexAttrib2f", (void *)m_glVertexAttrib2f},
    {"glVertexAttrib2fv", (void *)m_glVertexAttrib2fv},
    {"glVertexAttrib3f", (void *)m_glVertexAttrib3f},
    {"glVertexAttrib3fv", (void *)m_glVertexAttrib3fv},
    {"glVertexAttrib4f", (void *)m_glVertexAttrib4f},
    {"glVertexAttrib4fv", (void *)m_glVertexAttrib4fv},
    {"glGetVertexAttribfv", (void *)m_glGetVertexAttribfv},
    {"glGetVertexAttribiv", (void *)m_glGetVertexAttribiv},
    {"glGetVertexAttribPointerv", (void *)m_glGetVertexAttribPointerv},
    {"glDrawTexfOES", (void *)m_glDrawTexfOES},
    {"glDrawTexiOES", (void *)m_glDrawTexiOES},
    {"glTexGenfvOES", (void *)m_glTexGenfvOES},
    {"glTexGeniOES", (void *)m_glTexGeniOES},
    {"glPointSizePointerOES", (void *)m_glPointSizePointerOES},
};

void * APIENTRY_GL4ES mock_gles2_get_proc_address(const char *name) {
    if (!name) return NULL;
    for (size_t i = 0; i < sizeof(g_proc_table) / sizeof(g_proc_table[0]); ++i) {
        if (strcmp(g_proc_table[i].name, name) == 0) {
            return g_proc_table[i].fn;
        }
    }
    /* Return safe no-op stub for ES1-only fallback symbols if ever probed */
    return (void *)m_glGenericVoidStub;
}
