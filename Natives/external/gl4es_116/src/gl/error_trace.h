#ifndef _GL4ES_ERROR_TRACE_H_
#define _GL4ES_ERROR_TRACE_H_

#include "gles.h"

// Diagnostics are disabled by default (env AMETHYST_GL4ES_ERROR_TRACE=1 /
// AMETHYST_GL4ES_BACKEND_PROBE=1 enable them). The hooks below are called from hot
// paths (glBindTexture, glBlendFunc, glEnable, errorShim, ...), so the "off" case is an
// inlined check of an exported flag; only the first call (flag == -1) and enabled runs
// reach the *_slow implementations in error_trace.c.
extern int amethyst_trace_state;   // -1 unresolved, 0 off, 1 on
extern int amethyst_probe_state;   // -1 unresolved, 0 off, 1 on

void amethyst_trace_error_shim_slow(GLenum error, const char *file, int line, const char *func);
void amethyst_trace_backend_record_slow(const char *api_name, GLenum target, GLenum param1, GLint param2, const char *file, int line);
void amethyst_probe_backend_call_slow(const char *api_name, const char *file, int line);
void amethyst_validate_backend_enum_slow(const char *api_name, GLenum value, const char *file, int line);

// Tracing for errorShim (called when GL4ES itself raises an error)
static inline void amethyst_trace_error_shim(GLenum error, const char *file, int line, const char *func) {
    if (__builtin_expect(amethyst_trace_state == 0, 1)) return;
    amethyst_trace_error_shim_slow(error, file, line, func);
}

// Ring buffer record of recent backend dispatch operations
static inline void amethyst_trace_backend_record(const char *api_name, GLenum target, GLenum param1, GLint param2, const char *file, int line) {
    if (__builtin_expect(amethyst_trace_state == 0, 1)) return;
    amethyst_trace_backend_record_slow(api_name, target, param1, param2, file, line);
}

// Non-destructive probe of GLES backend error immediately following key calls (if backend probe enabled)
// NOTE: when enabled this calls glGetError on the backend after every probed call (diagnostic only).
static inline void amethyst_probe_backend_call(const char *api_name, const char *file, int line) {
    if (__builtin_expect(amethyst_probe_state == 0, 1)) return;
    amethyst_probe_backend_call_slow(api_name, file, line);
}

// Validate suspect enum about to be sent to GLES backend
static inline void amethyst_validate_backend_enum(const char *api_name, GLenum value, const char *file, int line) {
    if (__builtin_expect(amethyst_trace_state == 0, 1)) return;
    amethyst_validate_backend_enum_slow(api_name, value, file, line);
}

int amethyst_is_error_trace_enabled(void);
int amethyst_is_backend_probe_enabled(void);

// Reporting when gl4es_glGetError() returns an error to the application
void amethyst_trace_report_gl_error(GLenum error, int from_backend);

#endif // _GL4ES_ERROR_TRACE_H_
