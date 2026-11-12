#include "error_trace.h"
#include "debug.h"
#include "envvars.h"
#include "gl4es.h"
#include "glstate.h"
#include "init.h"
#include "loader.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define AMETHYST_MAX_ERROR_SITES 128
#define AMETHYST_MAX_LOGS_PER_SITE 5
#define AMETHYST_BACKEND_RING_SIZE 16

typedef struct {
    GLenum error;
    const char *file;
    int line;
    const char *func;
    uint32_t count;
    uint32_t logged;
} amethyst_error_site_t;

typedef struct {
    const char *api_name;
    GLenum target;
    GLenum param1;
    GLint param2;
    const char *file;
    int line;
} amethyst_backend_op_t;

// State is exported (see error_trace.h) so that disabled diagnostics cost a single
// inlined, well-predicted branch on hot paths instead of a cross-TU call.
// -1 = not resolved yet, 0 = off (default), 1 = on.
int amethyst_trace_state = -1;
int amethyst_probe_state = -1;

static uint32_t s_total_shim_errors = 0;
static uint32_t s_count_invalid_enum = 0;
static uint32_t s_count_invalid_value = 0;
static uint32_t s_count_invalid_op = 0;
static uint32_t s_count_out_of_memory = 0;
static uint32_t s_count_other = 0;

static uint32_t s_site_count = 0;
static amethyst_error_site_t s_sites[AMETHYST_MAX_ERROR_SITES];

static uint32_t s_backend_op_head = 0;
static amethyst_backend_op_t s_backend_ring[AMETHYST_BACKEND_RING_SIZE];

int amethyst_is_error_trace_enabled(void) {
    if (__builtin_expect(amethyst_trace_state == -1, 0)) {
        const char *env = GetEnvVar("AMETHYST_GL4ES_ERROR_TRACE");
        amethyst_trace_state = (!env || strcmp(env, "0") != 0) ? 1 : 0;
        if (amethyst_trace_state) {
            printf("[Amethyst ErrorTrace] Diagnostics activated\n");
        }
    }
    return amethyst_trace_state;
}

int amethyst_is_backend_probe_enabled(void) {
    if (__builtin_expect(amethyst_probe_state == -1, 0)) {
        const char *env = GetEnvVar("AMETHYST_GL4ES_BACKEND_PROBE");
        amethyst_probe_state = (env && strcmp(env, "1") == 0) ? 1 : 0;
        if (amethyst_probe_state) {
            printf("[Amethyst BackendProbe] Active backend probe activated (AMETHYST_GL4ES_BACKEND_PROBE=1)\n");
        }
    }
    return amethyst_probe_state;
}

void amethyst_trace_error_shim_slow(GLenum error, const char *file, int line, const char *func) {
    if (!amethyst_is_error_trace_enabled()) return;
    if (error == GL_NO_ERROR) return;

    s_total_shim_errors++;
    switch (error) {
        case GL_INVALID_ENUM: s_count_invalid_enum++; break;
        case GL_INVALID_VALUE: s_count_invalid_value++; break;
        case GL_INVALID_OPERATION: s_count_invalid_op++; break;
        case GL_OUT_OF_MEMORY: s_count_out_of_memory++; break;
        default: s_count_other++; break;
    }

    // Lookup call site in bounded table
    int found_idx = -1;
    for (uint32_t i = 0; i < s_site_count; ++i) {
        if (s_sites[i].line == line && s_sites[i].error == error && strcmp(s_sites[i].file, file) == 0) {
            found_idx = (int)i;
            break;
        }
    }

    if (found_idx >= 0) {
        s_sites[found_idx].count++;
        if (s_sites[found_idx].logged < AMETHYST_MAX_LOGS_PER_SITE) {
            s_sites[found_idx].logged++;
            printf("[Amethyst ErrorTrace] Shim error %s (0x%04X) at %s:%d in %s() [site hits: %u, total: %u]\n",
                   PrintEnum(error), error, file, line, func, s_sites[found_idx].count, s_total_shim_errors);
            if (s_sites[found_idx].logged == AMETHYST_MAX_LOGS_PER_SITE) {
                printf("[Amethyst ErrorTrace] Site %s:%d reached log limit (%d), suppressing future individual logs\n",
                       file, line, AMETHYST_MAX_LOGS_PER_SITE);
            }
        }
    } else if (s_site_count < AMETHYST_MAX_ERROR_SITES) {
        uint32_t idx = s_site_count++;
        s_sites[idx].error = error;
        s_sites[idx].file = file;
        s_sites[idx].line = line;
        s_sites[idx].func = func;
        s_sites[idx].count = 1;
        s_sites[idx].logged = 1;
        printf("[Amethyst ErrorTrace] [NEW SITE #%u] Shim error %s (0x%04X) at %s:%d in %s() [total: %u]\n",
               idx + 1, PrintEnum(error), error, file, line, func, s_total_shim_errors);
    }

    // Periodic summary every 500 shim errors
    if (s_total_shim_errors > 0 && (s_total_shim_errors % 500 == 0)) {
        printf("[Amethyst ErrorTrace] --- SHIM ERROR SUMMARY (Total: %u | INVALID_ENUM: %u, INVALID_VALUE: %u, INVALID_OP: %u, OOM: %u) ---\n",
               s_total_shim_errors, s_count_invalid_enum, s_count_invalid_value, s_count_invalid_op, s_count_out_of_memory);
        for (uint32_t i = 0; i < s_site_count && i < 10; ++i) {
            printf("  site #%u: %s:%d %s() -> %s (0x%04X) [%u hits]\n",
                   i + 1, s_sites[i].file, s_sites[i].line, s_sites[i].func, PrintEnum(s_sites[i].error), s_sites[i].error, s_sites[i].count);
        }
    }
}

void amethyst_trace_backend_record_slow(const char *api_name, GLenum target, GLenum param1, GLint param2, const char *file, int line) {
    if (!amethyst_is_error_trace_enabled()) return;
    uint32_t idx = s_backend_op_head % AMETHYST_BACKEND_RING_SIZE;
    s_backend_ring[idx].api_name = api_name;
    s_backend_ring[idx].target = target;
    s_backend_ring[idx].param1 = param1;
    s_backend_ring[idx].param2 = param2;
    s_backend_ring[idx].file = file;
    s_backend_ring[idx].line = line;
    s_backend_op_head++;
}

void amethyst_trace_report_gl_error(GLenum error, int from_backend) {
    static uint32_t s_reported_count = 0;
    if (s_reported_count >= 100) return; // bounded report to prevent log flood
    s_reported_count++;

    printf("[Amethyst ErrorTrace #%u] glGetError() -> 0x%04X (%s) [Source: %s]\n",
           s_reported_count, error, PrintEnum(error), from_backend ? "GLES Backend" : "GL4ES Shim");

    if (from_backend) {
        printf("  Recent GLES backend dispatches leading to error:\n");
        uint32_t count = s_backend_op_head < AMETHYST_BACKEND_RING_SIZE ? s_backend_op_head : AMETHYST_BACKEND_RING_SIZE;
        for (uint32_t i = 0; i < count; ++i) {
            uint32_t ring_idx = (s_backend_op_head - count + i) % AMETHYST_BACKEND_RING_SIZE;
            amethyst_backend_op_t *op = &s_backend_ring[ring_idx];
            printf("    [%u] %s (target=0x%04X, param1=0x%04X, param2=%d) at %s:%d\n",
                   i + 1, op->api_name, op->target, op->param1, op->param2, op->file, op->line);
        }
    } else {
        printf("  Shim error counts: Total=%u (INVALID_ENUM=%u, INVALID_VAL=%u, INVALID_OP=%u, OOM=%u)\n",
               s_total_shim_errors, s_count_invalid_enum, s_count_invalid_value, s_count_invalid_op, s_count_out_of_memory);
    }
}

void amethyst_probe_backend_call_slow(const char *api_name, const char *file, int line) {
    if (!amethyst_is_backend_probe_enabled()) return;
    LOAD_GLES(glGetError);
    if (!gles_glGetError) return;
    GLenum err = gles_glGetError();
    if (err != GL_NO_ERROR) {
        static uint32_t s_backend_probe_errors = 0;
        if (s_backend_probe_errors < 50) {
            s_backend_probe_errors++;
            printf("[Amethyst BackendProbe #%u] DETECTED GLES ERROR 0x%04X (%s) immediately following %s at %s:%d\n",
                   s_backend_probe_errors, err, PrintEnum(err), api_name, file, line);
        }
        // Preserve error in shim so Minecraft application still receives it
        if (glstate && glstate->shim_error == GL_NO_ERROR) {
            glstate->shim_error = err;
            glstate->type_error = 1;
        }
    }
}

void amethyst_validate_backend_enum_slow(const char *api_name, GLenum value, const char *file, int line) {
    if (!amethyst_is_error_trace_enabled()) return;
    // Highlight desktop GL enums that are invalid in OpenGL ES
    switch (value) {
        case 0x8515: // GL_TEXTURE_CUBE_MAP_POSITIVE_X as glBindTexture target
        case 0x8516: // GL_TEXTURE_CUBE_MAP_NEGATIVE_X
        case 0x8517: // GL_TEXTURE_CUBE_MAP_POSITIVE_Y
        case 0x8518: // GL_TEXTURE_CUBE_MAP_NEGATIVE_Y
        case 0x8519: // GL_TEXTURE_CUBE_MAP_POSITIVE_Z
        case 0x851A: // GL_TEXTURE_CUBE_MAP_NEGATIVE_Z
        case 0x2900: // GL_CLAMP (invalid in ES, requires GL_CLAMP_TO_EDGE)
            printf("[Amethyst BackendProbe] SUSPICIOUS ENUM 0x%04X passed to %s at %s:%d (known to trigger GL_INVALID_ENUM on GLES)\n",
                   value, api_name, file, line);
            break;
        default:
            break;
    }
}
