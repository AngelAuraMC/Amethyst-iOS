#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L
#endif

#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "gl4esinit.h"
#include "gles.h"
#include "const.h"
#include "gl4es.h"
#include "buffers.h"
#include "glstate.h"
#include "fpe.h"
#include "fpe_cache.h"
#include "program.h"
#include "shader.h"
#include "texture.h"
#include "matrix.h"
#include "fog.h"
#include "depth.h"
#include "framebuffers.h"
#include "wrap/gl4es.h"
#include "mock_gles2.h"
#include "win_alloc_shim.h"

#ifndef GL4ES_PRE_M1_SMOKE
#include "gl4es_mem.h"
#endif

/* Exported from glstate.c */
void *NewGLState(void *shared_glstate, int es2only);
void DeleteGLState(void *oldstate);
void ActivateGLState(void *new_glstate);

#ifndef GL_BGRA
#define GL_BGRA 0x80E1
#endif
#ifndef GL_STREAM_DRAW
#define GL_STREAM_DRAW 0x88E0
#endif
#ifndef GL_VERTEX_SHADER
#define GL_VERTEX_SHADER 0x8B31
#endif
#ifndef GL_FRAGMENT_SHADER
#define GL_FRAGMENT_SHADER 0x8B30
#endif
#ifndef GL_FOG_COORDINATE_SOURCE
#define GL_FOG_COORDINATE_SOURCE 0x8450
#endif
#ifndef GL_FOG_COORD
#define GL_FOG_COORD 0x8451
#endif
#ifndef GL_FOG_DISTANCE_MODE_NV
#define GL_FOG_DISTANCE_MODE_NV 0x855A
#endif
#ifndef GL_EYE_RADIAL_NV
#define GL_EYE_RADIAL_NV 0x855B
#endif
#ifndef GL_EYE_PLANE_ABSOLUTE_NV
#define GL_EYE_PLANE_ABSOLUTE_NV 0x855C
#endif

static int g_passed = 0;
static int g_failed = 0;

static void check(int cond, const char *name, const char *detail) {
    if (cond) {
        g_passed++;
        printf("  [PASS] %s%s%s\n", name, detail ? " - " : "", detail ? detail : "");
    } else {
        g_failed++;
        printf("  [FAIL] %s%s%s\n", name, detail ? " - " : "", detail ? detail : "");
    }
    fflush(stdout);
}

static void set_env_var(const char *k, const char *v) {
#ifdef _WIN32
    _putenv_s(k, v ? v : "");
#else
    if (v) setenv(k, v, 1);
    else unsetenv(k);
#endif
}

static double now_ms(void) {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
}

static void init_with_mock(void) {
    mock_gles2_reset();
    set_env_var("LIBGL_NOBANNER", "1");
    set_env_var("AMETHYST_GL4ES_ERROR_TRACE", "0");
    set_getprocaddress(mock_gles2_get_proc_address);
    initialize_gl4es();
}

static void setup_simple_quad_arrays(const float *verts, const uint8_t *bgra_colors) {
    gl4es_glEnableClientState(GL_VERTEX_ARRAY);
    gl4es_glVertexPointer(3, GL_FLOAT, 0, verts);
    if (bgra_colors) {
        gl4es_glEnableClientState(GL_COLOR_ARRAY);
        gl4es_glColorPointer(GL_BGRA, GL_UNSIGNED_BYTE, 0, bgra_colors);
    } else {
        gl4es_glDisableClientState(GL_COLOR_ARRAY);
    }
}

#ifndef GL4ES_PRE_M1_SMOKE
static void *trim_worker_fn(void *arg) {
    int urgency = *(int *)arg;
    gl4es_trim_memory(urgency);
    return NULL;
}

static void suite_tier1_mem_low(void) {
    set_env_var("LIBGL_MEM_PROFILE", "low");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);
    init_with_mock();

    gl4es_mem_stats_t st;
    memset(&st, 0, sizeof(st));
    gl4es_get_mem_stats(&st);

    check(st.profile == GL4ES_MEM_PROFILE_LOW, "low: profile == LOW", NULL);
    check(st.budget_bytes > 0 && st.budget_bytes <= 256u * 1024u * 1024u, "low: budget_bytes <= 256MB", NULL);
    check(st.texture_scratch_cap > 0 && st.texture_scratch_cap <= 2u * 1024u * 1024u, "low: texture_scratch_cap <= 2MB", NULL);
    check(st.color_scratch_cap > 0 && st.color_scratch_cap <= 512u * 1024u, "low: color_scratch_cap <= 512KB", NULL);
    check(st.fpe_cache_max_entries > 0 && st.fpe_cache_max_entries <= 192u, "low: fpe_cache_max_entries <= 192", NULL);
    check(st.psa_max_entries > 0 && st.psa_max_entries <= 2048u && st.psa_max_bytes <= 8u * 1024u * 1024u,
          "low: psa_max_entries <= 2048 & psa_max_bytes <= 8MB", NULL);

    close_gl4es();
}

static void suite_tier1_mem_medium(void) {
    set_env_var("LIBGL_MEM_PROFILE", "medium");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);
    init_with_mock();

    gl4es_mem_stats_t st;
    memset(&st, 0, sizeof(st));
    gl4es_get_mem_stats(&st);

    check(st.profile == GL4ES_MEM_PROFILE_MEDIUM, "medium: profile == MEDIUM", NULL);
    check(st.texture_scratch_cap > 2u * 1024u * 1024u && st.texture_scratch_cap <= 4u * 1024u * 1024u,
          "medium: 2MB < texture_scratch_cap <= 4MB", NULL);
    check(st.color_scratch_cap > 512u * 1024u && st.color_scratch_cap <= 1024u * 1024u,
          "medium: 512KB < color_scratch_cap <= 1MB", NULL);
    check(st.fpe_cache_max_entries > 192u && st.fpe_cache_max_entries <= 512u,
          "medium: 192 < fpe_cache_max_entries <= 512", NULL);
    check(st.psa_max_entries > 2048u && st.psa_max_entries <= 8192u,
          "medium: 2048 < psa_max_entries <= 8192", NULL);
    check(st.psa_max_bytes > 8u * 1024u * 1024u && st.psa_max_bytes <= 24u * 1024u * 1024u,
          "medium: 8MB < psa_max_bytes <= 24MB", NULL);

    close_gl4es();
}

static void suite_tier1_mem_high(void) {
    set_env_var("LIBGL_MEM_PROFILE", "high");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);
    init_with_mock();

    gl4es_mem_stats_t st;
    memset(&st, 0, sizeof(st));
    gl4es_get_mem_stats(&st);

    check(st.profile == GL4ES_MEM_PROFILE_HIGH, "high: profile == HIGH", NULL);
    check(st.texture_scratch_cap >= 8u * 1024u * 1024u, "high: texture_scratch_cap >= 8MB", NULL);
    check(st.color_scratch_cap >= 2u * 1024u * 1024u, "high: color_scratch_cap >= 2MB", NULL);
    check(st.fpe_cache_max_entries >= 1024u, "high: fpe_cache_max_entries >= 1024", NULL);
    check(st.psa_max_entries >= 16384u, "high: psa_max_entries >= 16384", NULL);
    check(st.psa_max_bytes >= 48u * 1024u * 1024u, "high: psa_max_bytes >= 48MB", NULL);

    close_gl4es();
}

static void suite_tier1_mem_auto(void) {
    set_env_var("LIBGL_MEM_PROFILE", "auto");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);
    init_with_mock();

    gl4es_mem_stats_t st;
    memset(&st, 0, sizeof(st));
    gl4es_get_mem_stats(&st);

    check(st.profile >= GL4ES_MEM_PROFILE_LOW && st.profile <= GL4ES_MEM_PROFILE_HIGH,
          "auto: valid profile tier selected", NULL);
    check(st.budget_bytes > 0 && st.texture_scratch_cap > 0 && st.color_scratch_cap > 0,
          "auto: positive scratch & budget caps", NULL);
    check(st.gl_scratch_cap > 0 && st.merger_cap > 0 && st.fpe_cache_max_entries > 0,
          "auto: positive gl_scratch/merger/fpe caps", NULL);
    check(st.psa_max_entries > 0 && st.psa_max_bytes > 0,
          "auto: positive psa caps", NULL);
    check(st.current_scratch_bytes <= st.peak_scratch_bytes,
          "auto: current_scratch <= peak_scratch", NULL);

    close_gl4es();
}

static void suite_tier1_mem_budget(void) {
    set_env_var("LIBGL_MEM_PROFILE", "high");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", "128");
    init_with_mock();

    gl4es_mem_stats_t st;
    memset(&st, 0, sizeof(st));
    gl4es_get_mem_stats(&st);

    check(st.budget_bytes == 128u * 1024u * 1024u, "budget: AMETHYST_GL4ES_MEM_BUDGET_MB=128 sets exact budget_bytes", NULL);
    check(st.texture_scratch_cap <= 4u * 1024u * 1024u, "budget: 128MB clamps scratch caps below high tier", NULL);
    check(st.fpe_cache_max_entries <= 512u, "budget: 128MB constrains fpe_cache_max_entries", NULL);
    check(st.psa_max_bytes <= 24u * 1024u * 1024u, "budget: 128MB constrains psa_max_bytes", NULL);
    check(st.color_scratch_cap <= 1024u * 1024u, "budget: 128MB constrains color_scratch_cap", NULL);

    close_gl4es();
}

static void suite_tier1_trim(void) {
    /* Pre-init safety */
    gl4es_trim_memory(0);
    gl4es_trim_memory(1);
    gl4es_trim_memory(2);
    gl4es_mem_stats_t pre_trim;
    memset(&pre_trim, 0, sizeof(pre_trim));
    gl4es_get_mem_stats(&pre_trim);
    check(pre_trim.trim_count == 0, "trim: pre-init gl4es_trim_memory(0/1/2) safe no-op", NULL);

    set_env_var("LIBGL_MEM_PROFILE", "low");
    init_with_mock();

    /* Allocate texture scratch + color scratch */
    size_t tex_len = 1024u * 1024u;
    uint8_t *rgba = (uint8_t *)calloc(1, tex_len);
    GLuint tex = 0;
    gl4es_glGenTextures(1, &tex);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 512, 512, 0, GL_BGRA, GL_UNSIGNED_BYTE, rgba);
    free(rgba);

    float verts[12] = {0,0,0, 1,0,0, 1,1,0, 0,1,0};
    uint8_t bgra[16] = {10,20,30,255, 10,20,30,255, 10,20,30,255, 10,20,30,255};
    setup_simple_quad_arrays(verts, bgra);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);

    gl4es_mem_stats_t before, after1, after2;
    gl4es_get_mem_stats(&before);
    check(before.current_scratch_bytes > 0 || before.peak_scratch_bytes > 0,
          "trim: scratch usage tracked before trim", NULL);

    /* Render-thread warning trim */
    gl4es_trim_memory(1);
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_get_mem_stats(&after1);
    check(after1.trim_count >= before.trim_count + 1, "trim: render-thread urgency=1 increments trim_count", NULL);
    check(after1.current_scratch_bytes <= before.current_scratch_bytes,
          "trim: urgency=1 reduces or preserves current_scratch_bytes", NULL);

    /* Off-thread critical trim queued atomically & drained on glClear */
    int urg = 2;
    pthread_t th;
    int rc = pthread_create(&th, NULL, trim_worker_fn, &urg);
    check(rc == 0, "trim: spawn worker pthread for off-thread gl4es_trim_memory(2)", NULL);
    if (rc == 0) pthread_join(th, NULL);

    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_get_mem_stats(&after2);
    check(after2.trim_count >= after1.trim_count + 1,
          "trim: off-thread urgency=2 drained on glClear and incremented trim_count", NULL);
    check(after2.current_scratch_bytes == 0,
          "trim: critical urgency=2 drains persistent scratch pools to 0", NULL);

    gl4es_glDeleteTextures(1, &tex);
    close_gl4es();
}

static void suite_tier1_caps(void) {
    set_env_var("LIBGL_MEM_PROFILE", "low");
    init_with_mock();

    gl4es_mem_stats_t caps;
    gl4es_get_mem_stats(&caps);

    /* Texture scratch <= cap for within-cap upload, transient for > cap */
    size_t within_sz = 1024u * 1024u;
    uint8_t *px1 = (uint8_t *)calloc(1, within_sz);
    GLuint tex = 0;
    gl4es_glGenTextures(1, &tex);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 512, 512, 0, GL_BGRA, GL_UNSIGNED_BYTE, px1);
    free(px1);

    gl4es_mem_stats_t s1;
    gl4es_get_mem_stats(&s1);
    check(s1.current_scratch_bytes <= caps.texture_scratch_cap + caps.color_scratch_cap + caps.gl_scratch_cap,
          "caps: within-cap texture upload stays under scratch caps", NULL);

    /* > cap upload (4096x1024 = 16MB BGRA->RGBA) must NOT stay retained in persistent texture_scratch */
    size_t huge_sz = 16u * 1024u * 1024u;
    uint8_t *px_huge = (uint8_t *)malloc(huge_sz);
    memset(px_huge, 0x55, huge_sz);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4096, 1024, 0, GL_BGRA, GL_UNSIGNED_BYTE, px_huge);
    free(px_huge);

    gl4es_mem_stats_t s2;
    gl4es_get_mem_stats(&s2);
    check(s2.texture_scratch_cap <= caps.texture_scratch_cap
          && s2.current_scratch_bytes <= caps.texture_scratch_cap + caps.color_scratch_cap + caps.gl_scratch_cap,
          "caps: >cap texture upload does NOT bloat persistent texture_scratch_cap or current_scratch_bytes", NULL);

    /* BGRA color_scratch capped */
    const int nverts = 16384;
    float *verts = (float *)calloc((size_t)nverts * 3u, sizeof(float));
    uint8_t *cols = (uint8_t *)calloc((size_t)nverts * 4u, 1);
    setup_simple_quad_arrays(verts, cols);
    gl4es_glDrawArrays(GL_QUADS, 0, nverts);
    free(verts);
    free(cols);

    gl4es_mem_stats_t s3;
    gl4es_get_mem_stats(&s3);
    check(s3.current_scratch_bytes <= caps.texture_scratch_cap + caps.color_scratch_cap + caps.gl_scratch_cap + caps.merger_cap,
          "caps: color_scratch stays within tiered caps", NULL);

    /* No 1.5x exponential blowup on VBO shadow buffer */
    GLuint vbo = 0;
    gl4es_glGenBuffers(1, &vbo);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo);
    size_t req = 1024u * 1024u;
    uint8_t *vdata = (uint8_t *)calloc(1, req);
    gl4es_glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)req, vdata, GL_DYNAMIC_DRAW);
    GLint vbo_sz = 0;
    gl4es_glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &vbo_sz);
    gl4es_mem_stats_t s_vbo;
    gl4es_get_mem_stats(&s_vbo);
    check((size_t)vbo_sz == req && s_vbo.shadow_cpu_bytes == req,
          "caps: VBO shadow bytes equal exact requested 1MB (no 1.5x inflation)", NULL);
    free(vdata);

    /* Merger cap check */
    gl4es_glBegin(GL_QUADS);
    for (int i = 0; i < 64; ++i) {
        gl4es_glColor4f(1.0f, 0.5f, 0.25f, 1.0f);
        gl4es_glVertex3f((float)i, 0.0f, 0.0f);
    }
    gl4es_glEnd();
    gl4es_mem_stats_t s4;
    gl4es_get_mem_stats(&s4);
    check(s4.peak_scratch_bytes <= caps.budget_bytes, "caps: peak_scratch_bytes <= budget_bytes", NULL);

    gl4es_glDeleteBuffers(1, &vbo);
    gl4es_glDeleteTextures(1, &tex);
    close_gl4es();
}

static void suite_tier1_fpe_cache(void) {
    set_env_var("LIBGL_MEM_PROFILE", "low");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);
    init_with_mock();

    const mock_gles2_state_t *ms = mock_gles2_get_state();
    gl4es_mem_stats_t caps;
    gl4es_get_mem_stats(&caps);

    float verts[12] = {0,0,0, 1,0,0, 1,1,0, 0,1,0};
    setup_simple_quad_arrays(verts, NULL);

    /* Drive 256 truly distinct FPE states (8-bit GL_LIGHT0..GL_LIGHT7 mask) to exceed low cap (192) */
    gl4es_glEnable(GL_LIGHTING);
    for (int mask = 0; mask < 256; ++mask) {
        for (int b = 0; b < 8; ++b) {
            if (mask & (1 << b)) gl4es_glEnable(GL_LIGHT0 + b);
            else gl4es_glDisable(GL_LIGHT0 + b);
        }
        gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    }

    gl4es_mem_stats_t st;
    gl4es_get_mem_stats(&st);
    check(caps.fpe_cache_max_entries == 192u,
          "fpe_cache: low profile cap == 192 enforced", NULL);
    check(st.fpe_cache_entries == st.fpe_cache_max_entries,
          "fpe_cache: 256 distinct states trigger LRU eviction and cap at 192/192", NULL);
    check(ms->live_programs <= st.fpe_cache_max_entries,
          "fpe_cache: evicted FPE programs deleted in GLES2 (live_programs <= 192)", NULL);
    check(st.psa_entries > 0 && st.psa_entries <= st.psa_max_entries,
          "fpe_cache: psa_entries populated & bounded by psa_max_entries", NULL);
    check(st.psa_bytes > 0 && st.psa_bytes <= st.psa_max_bytes,
          "fpe_cache: psa_bytes populated & bounded by psa_max_bytes", NULL);

    close_gl4es();

    /* Phase 2: Verify PSA cap eviction when budget scales psa_max_entries down to floor (256) */
    set_env_var("LIBGL_MEM_PROFILE", "low");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", "1");
    init_with_mock();
    setup_simple_quad_arrays(verts, NULL);
    gl4es_glEnable(GL_LIGHTING);
    gl4es_glEnable(GL_FOG);
    for (int mask = 0; mask < 256; ++mask) {
        for (int b = 0; b < 8; ++b) {
            if (mask & (1 << b)) gl4es_glEnable(GL_LIGHT0 + b);
            else gl4es_glDisable(GL_LIGHT0 + b);
        }
        gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    }
    gl4es_glDisable(GL_FOG);
    gl4es_glEnable(GL_ALPHA_TEST);
    gl4es_glAlphaFunc(GL_GREATER, 0.5f);
    for (int mask = 0; mask < 44; ++mask) {
        for (int b = 0; b < 8; ++b) {
            if (mask & (1 << b)) gl4es_glEnable(GL_LIGHT0 + b);
            else gl4es_glDisable(GL_LIGHT0 + b);
        }
        gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    }
    gl4es_mem_stats_t st2;
    gl4es_get_mem_stats(&st2);
    char psa2_msg[128];
    snprintf(psa2_msg, sizeof(psa2_msg), "psa=%zu/%zu bytes=%zu/%zu fpe=%zu/%zu",
             st2.psa_entries, st2.psa_max_entries, st2.psa_bytes, st2.psa_max_bytes,
             st2.fpe_cache_entries, st2.fpe_cache_max_entries);
    check(st2.psa_max_entries == 256u && st2.psa_entries == st2.psa_max_entries
          && st2.psa_bytes <= st2.psa_max_bytes,
          "fpe_cache: PSA cap eviction enforces psa_entries == psa_max_entries (256) & psa_bytes <= psa_max_bytes", psa2_msg);
    close_gl4es();
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);
}
#endif /* GL4ES_PRE_M1_SMOKE */

static void suite_tier1_leaks(void) {
    set_env_var("LIBGL_MEM_PROFILE", "low");
    init_with_mock();

    /* 1. 500 VAO create/bind/delete cycles */
    GLuint vaos[500];
    gl4es_glGenVertexArrays(500, vaos);
    for (int i = 0; i < 500; ++i) {
        gl4es_glBindVertexArray(vaos[i]);
    }
    gl4es_glBindVertexArray(0);
    gl4es_glDeleteVertexArrays(500, vaos);
    int any_alive = 0;
    for (int i = 0; i < 500; ++i) {
        if (gl4es_glIsVertexArray(vaos[i])) any_alive = 1;
    }
    check(!any_alive, "leaks: 500 VAOs deleted cleanly (glIsVertexArray == FALSE)", NULL);

    /* 2. deleteSingleBuffer when index == buffer && want_index == buffer */
    GLuint ibo = 0;
    uint16_t idx[6] = {0, 1, 2, 0, 2, 3};
    gl4es_glGenBuffers(1, &ibo);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    gl4es_glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(idx), idx, GL_STATIC_DRAW);
    float verts[12] = {0,0,0, 1,0,0, 1,1,0, 0,1,0};
    setup_simple_quad_arrays(verts, NULL);
    gl4es_glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
    gl4es_glDeleteBuffers(1, &ibo);
    GLint ibo_binding = -1;
    gl4es_glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &ibo_binding);
    check(!gl4es_glIsBuffer(ibo) && ibo_binding == 0, "leaks: deleted IBO no longer live or bound", NULL);
    check(glstate->bind_buffer.want_index == 0 && glstate->bind_buffer.index == 0,
          "leaks: deleteSingleBuffer cleared BOTH index and want_index", NULL);

    /* 3. Secondary GLState lifecycle (scoped heap leak tracking on Windows) */
    const mock_gles2_state_t *ms = mock_gles2_get_state();
    unsigned long de_sec_before = ms->draw_elements_calls;
    size_t sec_leaked_bytes = 0, sec_leaked_allocs = 0;
    win_alloc_shim_begin();
    void *orig_state = glstate;
    void *sec_state = NewGLState(NULL, 0);
    check(sec_state != NULL, "leaks: NewGLState(NULL, 0) succeeded", NULL);
    ActivateGLState(sec_state);
    GLuint svbo = 0;
    gl4es_glGenBuffers(1, &svbo);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, svbo);
    gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STATIC_DRAW);
    gl4es_glEnableClientState(GL_VERTEX_ARRAY);
    gl4es_glDisableClientState(GL_COLOR_ARRAY);
    gl4es_glVertexPointer(3, GL_FLOAT, 0, 0);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);
    ActivateGLState(orig_state);
    DeleteGLState(sec_state);
    win_alloc_shim_end(&sec_leaked_bytes, &sec_leaked_allocs);
    check(ms->draw_elements_calls > de_sec_before && gl4es_glGetError() == GL_NO_ERROR
          && (!win_alloc_shim_is_active() || (sec_leaked_bytes == 0 && sec_leaked_allocs == 0)),
          "leaks: secondary GLState draw + DeleteGLState completed with 0 leaked bytes", NULL);

    /* 4. Unaligned / large quad draw (no leaked static indices) */
    unsigned long de_quad_before = ms->draw_elements_calls;
    float big_verts[20 * 3] = {0};
    setup_simple_quad_arrays(big_verts, NULL);
    gl4es_glDrawArrays(GL_QUADS, 1, 8);
    check(ms->draw_elements_calls > de_quad_before && gl4es_glGetError() == GL_NO_ERROR,
          "leaks: unaligned GL_QUADS fallback path drew cleanly", NULL);

    close_gl4es();
#ifndef GL4ES_PRE_M1_SMOKE
    check(ms->live_buffers == 0, "leaks: 0 live GLES2 buffers after close_gl4es() (quad_ibo + VBOs freed)", NULL);
#else
    check(ms->live_buffers <= 1, "leaks: pre-M1 smoke live_buffers <= 1 (quad_ibo)", NULL);
#endif
    check(ms->live_textures == 0 && ms->live_fbos == 0 && ms->live_rbos == 0
          && ms->live_shaders == 0 && ms->live_programs == 0,
          "leaks: 0 live GLES2 textures/FBOs/RBOs/shaders/programs after close_gl4es()", NULL);
}

static void suite_tier1_fpe_invariants(void) {
    set_env_var("LIBGL_MEM_PROFILE", "medium");
    init_with_mock();

    float verts[12] = {0,0,0, 1,0,0, 1,1,0, 0,1,0};
    setup_simple_quad_arrays(verts, NULL);

    /* 1. texmat FPE invalidation */
    GLuint tex1 = 0, tex2 = 0, tex3 = 0;
    uint8_t px[64 * 64 * 4];
    memset(px, 0xFF, sizeof(px));
    gl4es_glGenTextures(1, &tex1);
    gl4es_glGenTextures(1, &tex2);
    gl4es_glGenTextures(1, &tex3);

    gl4es_glEnable(GL_TEXTURE_2D);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex1);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    uint64_t g0 = glstate->fpe_generation;

    gl4es_glMatrixMode(GL_TEXTURE);
    gl4es_glScalef(2.0f, 2.0f, 1.0f);
    gl4es_glMatrixMode(GL_MODELVIEW);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    check(glstate->fpe_generation > g0 && glstate->fpe_state->texture[0].texmat == 1,
          "fpe_invariants: non-identity texmat bumps fpe_generation", NULL);

    /* 2. textype == 0 zeroes texmat in relevant state */
    gl4es_glDisable(GL_TEXTURE_2D);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    check(glstate->fpe != NULL && glstate->fpe->state.texture[0].texmat == 0,
          "fpe_invariants: textype == 0 zeroes texmat in fpe->state", NULL);

    /* Reset texmat and re-enable texturing for bind check */
    gl4es_glMatrixMode(GL_TEXTURE);
    gl4es_glLoadIdentity();
    gl4es_glMatrixMode(GL_MODELVIEW);
    gl4es_glEnable(GL_TEXTURE_2D);

    /* 3. glBindTexture same (textype, texformat, texadjust) vs format change */
    gl4es_glBindTexture(GL_TEXTURE_2D, tex2);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 64, 64, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    uint64_t g_same_before = glstate->fpe_generation;

    gl4es_glBindTexture(GL_TEXTURE_2D, tex1);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    uint64_t g_same_after = glstate->fpe_generation;
#ifndef GL4ES_PRE_M1_SMOKE
    check(g_same_after == g_same_before,
          "fpe_invariants: no-op glBindTexture (same textype/texformat/texadjust) does NOT bump fpe_generation", NULL);
#else
    check(gl4es_glGetError() == GL_NO_ERROR,
          "fpe_invariants: pre-M1 smoke bind tex1->tex2->tex1 draw completed without GL error", NULL);
#endif

    gl4es_glBindTexture(GL_TEXTURE_2D, tex3);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 64, 64, 0, GL_RGB, GL_UNSIGNED_BYTE, px);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    check(glstate->fpe_generation > g_same_after,
          "fpe_invariants: glBindTexture format change (RGBA -> RGB) bumps fpe_generation", NULL);

    /* 4. fog mutations */
    gl4es_glEnable(GL_FOG);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    uint64_t g_fog = glstate->fpe_generation;
    GLfloat fmode = (GLfloat)GL_LINEAR;
    gl4es_glFogfv(GL_FOG_MODE, &fmode);
    GLfloat fog_src = (GLfloat)GL_FOG_COORD;
    gl4es_glFogfv(GL_FOG_COORDINATE_SOURCE, &fog_src);
    GLfloat fdist = (GLfloat)GL_EYE_RADIAL_NV;
    gl4es_glFogfv(GL_FOG_DISTANCE_MODE_NV, &fdist);
    check(glstate->fpe_generation >= g_fog + 2,
          "fpe_invariants: fog mode/coord_src/dist mutations bump fpe_generation", NULL);

    /* 5. material mutations */
    gl4es_glEnable(GL_LIGHTING);
    gl4es_glEnable(GL_COLOR_MATERIAL);
    gl4es_glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 0.0f);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    uint64_t g_mat = glstate->fpe_generation;
    gl4es_glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 32.0f);
    check(glstate->fpe_generation > g_mat,
          "fpe_invariants: glMaterialf shininess 0->32 flips nullexp & bumps fpe_generation", NULL);
    gl4es_glDisable(GL_LIGHTING);
    gl4es_glDisable(GL_FOG);
    gl4es_glDisable(GL_TEXTURE_2D);

    /* 6. clear_program resets applied_matrix_seq */
    const char *vsrc =
        "attribute vec4 gl_Vertex;\n"
        "uniform mat4 gl_ModelViewProjectionMatrix;\n"
        "void main() { gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex; }\n";
    const char *fsrc = "void main() { gl_FragColor = vec4(1.0); }\n";
    GLuint vs = gl4es_glCreateShader(GL_VERTEX_SHADER);
    GLuint fs = gl4es_glCreateShader(GL_FRAGMENT_SHADER);
    gl4es_glShaderSource(vs, 1, &vsrc, NULL);
    gl4es_glShaderSource(fs, 1, &fsrc, NULL);
    gl4es_glCompileShader(vs);
    gl4es_glCompileShader(fs);
    GLuint prog = gl4es_glCreateProgram();
    gl4es_glAttachShader(prog, vs);
    gl4es_glAttachShader(prog, fs);
    gl4es_glLinkProgram(prog);
    gl4es_glUseProgram(prog);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    /* Re-link must reset applied_matrix_seq = 0 */
    gl4es_glLinkProgram(prog);
    khint_t kp = kh_get(programlist, glstate->glsl->programs, prog);
    program_t *gp = (kp != kh_end(glstate->glsl->programs)) ? kh_value(glstate->glsl->programs, kp) : NULL;
    check(gp != NULL && gp->applied_matrix_seq == 0,
          "fpe_invariants: clear_program on relink resets applied_matrix_seq = 0", NULL);

    gl4es_glUseProgram(0);
    gl4es_glDeleteProgram(prog);
    gl4es_glDeleteShader(vs);
    gl4es_glDeleteShader(fs);
    gl4es_glDeleteTextures(1, &tex1);
    gl4es_glDeleteTextures(1, &tex2);
    gl4es_glDeleteTextures(1, &tex3);
    close_gl4es();
}

static void suite_tier1_ibo_stream(void) {
    set_env_var("LIBGL_MEM_PROFILE", "medium");
    init_with_mock();

    float verts[48] = {
        0,0,0, 1,0,0, 1,1,0, 0,1,0,
        2,0,0, 3,0,0, 3,1,0, 2,1,0,
        4,0,0, 5,0,0, 5,1,0, 4,1,0,
        6,0,0, 7,0,0, 7,1,0, 6,1,0
    };
    uint16_t tri_idx[6] = {0, 1, 2, 0, 2, 3};
    uint16_t quad_seq[4] = {0, 1, 2, 3};
    uint16_t quad_nonseq[4] = {3, 1, 0, 2};

    GLuint ibo = 0;
    gl4es_glGenBuffers(1, &ibo);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    gl4es_glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(tri_idx), tri_idx, GL_STATIC_DRAW);
    const mock_gles2_state_t *ms = mock_gles2_get_state();
    GLuint real_ibo = ms->bound_element_array_buffer;

    setup_simple_quad_arrays(verts, NULL);

    /* 1. draw_quad_arrays fast path unbinds & restores real_ibo */
    gl4es_glDrawArrays(GL_QUADS, 0, 8);
    check(ms->last_draw_ibo != real_ibo, "ibo_stream: draw_quad_arrays fast path did NOT draw with user IBO bound", NULL);
    check(glstate->bind_buffer.want_index == real_ibo && ms->bound_element_array_buffer == real_ibo,
          "ibo_stream: draw_quad_arrays fast path restored GL_ELEMENT_ARRAY_BUFFER", NULL);

    /* 2. draw_quad_arrays fallback path (unaligned first=1) */
    gl4es_glDrawArrays(GL_QUADS, 1, 8);
    check(ms->last_draw_ibo != real_ibo, "ibo_stream: draw_quad_arrays fallback unbinds user IBO during draw", NULL);
    check(glstate->bind_buffer.want_index == real_ibo,
          "ibo_stream: draw_quad_arrays fallback restores want_index", NULL);
#ifndef GL4ES_PRE_M1_SMOKE
    check(ms->bound_element_array_buffer == real_ibo,
          "ibo_stream: draw_quad_arrays fallback unconditionally restores bound_element_array_buffer", NULL);
#endif

    /* 3. glDrawElements(GL_QUADS) sequential & non-sequential */
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    gl4es_glDrawElements(GL_QUADS, 4, GL_UNSIGNED_SHORT, quad_seq);
    check(ms->draw_elements_calls > 0 && ms->last_draw_count == 6,
          "ibo_stream: glDrawElements(GL_QUADS, 4) sequential draws 6 tri indices", NULL);
    gl4es_glDrawElements(GL_QUADS, 4, GL_UNSIGNED_SHORT, quad_nonseq);
    check(ms->last_draw_count == 6,
          "ibo_stream: glDrawElements(GL_QUADS, 4) non-sequential draws 6 tri indices", NULL);

    /* 4. glDrawArraysInstanced(GL_QUADS) IBO restore */
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    gl4es_glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
    check(ms->last_draw_ibo == real_ibo,
          "ibo_stream: baseline glDrawElements binds user IBO", NULL);
    gl4es_glDrawArraysInstanced(GL_QUADS, 0, 4, 2);
    check(ms->last_draw_ibo != real_ibo,
          "ibo_stream: glDrawArraysInstanced(GL_QUADS) unbinds user IBO during draw", NULL);
    gl4es_glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
    check(ms->last_draw_ibo == real_ibo,
          "ibo_stream: subsequent glDrawElements still draws with user IBO", NULL);

    /* 5. GL_STREAM_DRAW + glBufferSubData + GL_BGRA color coherency */
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    GLuint vbo_pos = 0, vbo_col = 0;
    gl4es_glGenBuffers(1, &vbo_pos);
    gl4es_glGenBuffers(1, &vbo_col);

    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo_pos);
    gl4es_glBufferData(GL_ARRAY_BUFFER, 12 * sizeof(float), verts, GL_STREAM_DRAW);
    gl4es_glVertexPointer(3, GL_FLOAT, 0, 0);

    uint8_t bgra1[16] = {
        10, 20, 30, 255,
        10, 20, 30, 255,
        10, 20, 30, 255,
        10, 20, 30, 255
    };
    uint8_t bgra2[16] = {
        200, 100, 50, 254,
        200, 100, 50, 254,
        200, 100, 50, 254,
        200, 100, 50, 254
    };
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo_col);
    gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(bgra1), bgra1, GL_STREAM_DRAW);
    gl4es_glEnableClientState(GL_COLOR_ARRAY);
    gl4es_glColorPointer(GL_BGRA, GL_UNSIGNED_BYTE, 0, 0);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    check(ms->last_draw_color_captured &&
          ms->last_draw_color_bytes[0] == 30 &&
          ms->last_draw_color_bytes[1] == 20 &&
          ms->last_draw_color_bytes[2] == 10 &&
          ms->last_draw_color_bytes[3] == 255,
          "ibo_stream: STREAM_DRAW + BGRA draw 1 converted {B=10,G=20,R=30} -> {30,20,10,255}", NULL);

    gl4es_glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(bgra2), bgra2);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    check(ms->last_draw_color_captured &&
          ms->last_draw_color_bytes[0] == 50 &&
          ms->last_draw_color_bytes[1] == 100 &&
          ms->last_draw_color_bytes[2] == 200 &&
          ms->last_draw_color_bytes[3] == 254,
          "ibo_stream: STREAM_DRAW + glBufferSubData + BGRA draw 2 reads fresh {50,100,200,254} (not stale)", NULL);

    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    gl4es_glDeleteBuffers(1, &vbo_pos);
    gl4es_glDeleteBuffers(1, &vbo_col);
    gl4es_glDeleteBuffers(1, &ibo);
    close_gl4es();
}

#ifndef GL4ES_PRE_M1_SMOKE
static void suite_tier1_draw_upload(void) {
    set_env_var("LIBGL_MEM_PROFILE", "low");
    init_with_mock();

    const mock_gles2_state_t *ms = mock_gles2_get_state();
    gl4es_mem_stats_t caps;
    gl4es_get_mem_stats(&caps);

    /* 1 & 2. Sequential vs non-sequential GL_QUADS index fast path in glDrawElements */
    float qverts[8 * 3] = {
        0,0,0, 1,0,0, 1,1,0, 0,1,0,
        2,0,0, 3,0,0, 3,1,0, 2,1,0
    };
    uint8_t qcols[8 * 4] = {
        11, 22, 33, 255,  44, 55, 66, 255,  77, 88, 99, 255,  111, 122, 133, 255,
        10, 20, 30, 255,  40, 50, 60, 255,  70, 80, 90, 255,  100, 110, 120, 255
    };
    uint16_t seq_idx[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    uint16_t nonseq_idx[8] = {3, 1, 0, 2, 7, 5, 4, 6};

    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    setup_simple_quad_arrays(qverts, qcols);
    /* Warm up initial FPE state & quad_ibo & color_scratch */
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    gl4es_trim_memory(2);
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);

    gl4es_mem_stats_t s_before_seq;
    gl4es_get_mem_stats(&s_before_seq);
    gl4es_glDrawElements(GL_QUADS, 8, GL_UNSIGNED_SHORT, seq_idx);
    gl4es_mem_stats_t s_after_seq;
    gl4es_get_mem_stats(&s_after_seq);
    check(ms->last_draw_mode == GL_TRIANGLES && ms->last_draw_count == 12
          && ms->last_draw_color_captured && ms->last_draw_color_bytes[0] == 33
          && s_after_seq.current_scratch_bytes == s_before_seq.current_scratch_bytes
          && gl4es_glGetError() == GL_NO_ERROR,
          "draw_upload: sequential GL_QUADS glDrawElements uses fast path without scratch expansion", NULL);

    gl4es_glDrawElements(GL_QUADS, 8, GL_UNSIGNED_SHORT, nonseq_idx);
    check(ms->last_draw_mode == GL_TRIANGLES && ms->last_draw_count == 12
          && ms->last_draw_color_captured && ms->last_draw_color_bytes[0] == 133
          && gl4es_glGetError() == GL_NO_ERROR,
          "draw_upload: non-sequential GL_QUADS glDrawElements expands vertex order [3,1,0,2] accurately", NULL);

    /* 3. texture.c BGRA upload/swizzle keeps retained scratch bounded (no persistent blowup) */
    size_t bgra_sz = 256u * 256u * 4u;
    uint8_t *tex_bgra = (uint8_t *)calloc(1, bgra_sz);
    GLuint ttex[4] = {0};
    gl4es_glGenTextures(4, ttex);
    gl4es_glEnable(GL_TEXTURE_2D);
    for (int i = 0; i < 4; ++i) {
        gl4es_glBindTexture(GL_TEXTURE_2D, ttex[i]);
        gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 256, 0, GL_BGRA, GL_UNSIGNED_BYTE, tex_bgra);
    }
    gl4es_mem_stats_t st_tex1;
    gl4es_get_mem_stats(&st_tex1);
    for (int r = 0; r < 8; ++r) {
        gl4es_glBindTexture(GL_TEXTURE_2D, ttex[r & 3]);
        gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 256, 0, GL_BGRA, GL_UNSIGNED_BYTE, tex_bgra);
        gl4es_glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 128, 128, GL_BGRA, GL_UNSIGNED_BYTE, tex_bgra);
    }
    gl4es_mem_stats_t st_tex2;
    gl4es_get_mem_stats(&st_tex2);
    free(tex_bgra);
    check(st_tex2.current_scratch_bytes <= caps.texture_scratch_cap + caps.color_scratch_cap + caps.gl_scratch_cap
          && st_tex2.peak_scratch_bytes == st_tex1.peak_scratch_bytes
          && gl4es_glGetError() == GL_NO_ERROR,
          "draw_upload: repeated BGRA TexImage/TexSubImage reuses bounded scratch without growth", NULL);
    gl4es_glDisable(GL_TEXTURE_2D);
    gl4es_glDeleteTextures(4, ttex);

    /* 4. Redundant glBindBuffer & vertex-attrib avoidance across repeated identical VBO draws */
    GLuint steady_vbo = 0;
    uint8_t vbo_bytes[256];
    memset(vbo_bytes, 0, sizeof(vbo_bytes));
    memcpy(vbo_bytes + 16, qverts, 9 * sizeof(float));
    gl4es_glGenBuffers(1, &steady_vbo);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, steady_vbo);
    gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(vbo_bytes), vbo_bytes, GL_STATIC_DRAW);
    gl4es_glDisableClientState(GL_COLOR_ARRAY);
    gl4es_glEnableClientState(GL_VERTEX_ARRAY);
    gl4es_glVertexPointer(3, GL_FLOAT, 0, (const void *)(uintptr_t)16);

    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3); /* warm VA/VBO state */
    unsigned long da0 = ms->draw_arrays_calls;
    unsigned long bb0 = ms->bind_buffer_calls;
    unsigned long eva0 = ms->enable_vertex_attrib_calls;
    unsigned long dva0 = ms->disable_vertex_attrib_calls;
    unsigned long vap0 = ms->vertex_attrib_pointer_calls;
    unsigned long up0 = ms->use_program_calls;

    for (int i = 0; i < 20; ++i) {
        gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    }
    check(ms->draw_arrays_calls == da0 + 20
          && ms->bind_buffer_calls == bb0
          && ms->enable_vertex_attrib_calls == eva0
          && ms->disable_vertex_attrib_calls == dva0
          && ms->vertex_attrib_pointer_calls == vap0,
          "draw_upload: 20 identical VBO draws emit 0 redundant glBindBuffer/EnableVA/VAPointer calls", NULL);

    /* 5. Small-draw / glDrawArrays sequence avoids redundant glUseProgram flushes */
    check(ms->use_program_calls == up0 && gl4es_glGetError() == GL_NO_ERROR,
          "draw_upload: repeated small draws emit 0 redundant glUseProgram flushes", NULL);

    /* 6. FPE/PSA shader cache compile hitch mitigation across repeated alternating states */
    gl4es_glEnable(GL_BLEND);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    gl4es_glDisable(GL_BLEND);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    unsigned long sc0 = ms->shader_compile_calls;
    unsigned long pl0 = ms->program_link_calls;
    for (int i = 0; i < 10; ++i) {
        if (i & 1) gl4es_glEnable(GL_BLEND);
        else gl4es_glDisable(GL_BLEND);
        gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    }
    check(ms->shader_compile_calls == sc0 && ms->program_link_calls == pl0
          && gl4es_glGetError() == GL_NO_ERROR,
          "draw_upload: alternating cached FPE states incur 0 extra shader compiles/links", NULL);

    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    gl4es_glDeleteBuffers(1, &steady_vbo);
    close_gl4es();
}
#endif /* GL4ES_PRE_M1_SMOKE */

static void suite_tier2_bounds(void) {
    set_env_var("LIBGL_MEM_PROFILE", "invalid_tier_name");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", "0");
    init_with_mock();

    float verts[16 * 3] = {0};
    uint8_t bgra[16 * 4];
    memset(bgra, 0x44, sizeof(bgra));
    uint8_t px4[4 * 4 * 4];
    memset(px4, 0x80, sizeof(px4));

#ifndef GL4ES_PRE_M1_SMOKE
    /* F1 boundaries (6) */
    gl4es_get_mem_stats(NULL);
    gl4es_mem_stats_t st;
    memset(&st, 0, sizeof(st));
    gl4es_get_mem_stats(&st);
    check(gl4es_glGetError() == GL_NO_ERROR && st.budget_bytes > 0,
          "tier2_f1: gl4es_get_mem_stats(NULL) safe no-op without corrupting state", NULL);
    check(st.profile >= GL4ES_MEM_PROFILE_LOW && st.profile <= GL4ES_MEM_PROFILE_HIGH,
          "tier2_f1: invalid LIBGL_MEM_PROFILE falls back to valid profile", NULL);
    check(st.budget_bytes > 0, "tier2_f1: AMETHYST_GL4ES_MEM_BUDGET_MB=0 ignored/bounded > 0", NULL);
    check(st.texture_scratch_cap > 0 && st.color_scratch_cap > 0,
          "tier2_f1: fallback scratch caps positive", NULL);
    check(st.fpe_cache_max_entries > 0 && st.psa_max_entries > 0,
          "tier2_f1: fallback cache caps positive", NULL);
    check(st.current_scratch_bytes <= st.peak_scratch_bytes,
          "tier2_f1: initial current_scratch_bytes <= peak_scratch_bytes", NULL);

    /* F2 boundaries (6) */
    gl4es_mem_stats_t st_tc0;
    gl4es_get_mem_stats(&st_tc0);
    gl4es_trim_memory(-1);
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_mem_stats_t st_tc_neg;
    gl4es_get_mem_stats(&st_tc_neg);
    check(st_tc_neg.trim_count >= st_tc0.trim_count + 1,
          "tier2_f2: gl4es_trim_memory(-1) clamps safely to urgency=0 and drains", NULL);

    gl4es_trim_memory(99);
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_mem_stats_t st_tc_99;
    gl4es_get_mem_stats(&st_tc_99);
    check(st_tc_99.trim_count >= st_tc_neg.trim_count + 1,
          "tier2_f2: gl4es_trim_memory(99) clamps safely to urgency=2 and drains", NULL);

    gl4es_trim_memory(0);
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_mem_stats_t st_trim0;
    gl4es_get_mem_stats(&st_trim0);
    check(st_trim0.trim_count >= st_tc_99.trim_count + 1,
          "tier2_f2: urgency=0 + glClear increments trim_count", NULL);

    /* Deferral while glNewList compilation is active */
    gl4es_glNewList(1, GL_COMPILE);
    gl4es_trim_memory(2);
    gl4es_mem_stats_t st_during_list;
    gl4es_get_mem_stats(&st_during_list);
    gl4es_glEndList();
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_mem_stats_t st_after_list;
    gl4es_get_mem_stats(&st_after_list);
    gl4es_glDeleteLists(1, 1);
    check(st_during_list.trim_count == st_trim0.trim_count
          && st_after_list.trim_count >= st_trim0.trim_count + 1,
          "tier2_f2: gl4es_trim_memory(2) defers during glNewList and drains at glClear", NULL);
#endif

    /* F3 boundaries (5) */
    const mock_gles2_state_t *ms2 = mock_gles2_get_state();
    gl4es_glDeleteVertexArrays(0, NULL);
    check(gl4es_glGetError() == GL_NO_ERROR && gl4es_glIsVertexArray(0) == GL_TRUE,
          "tier2_f3: glDeleteVertexArrays(0, NULL) safe no-op & preserves VAO 0", NULL);
    GLuint zero_id = 0;
    gl4es_glDeleteVertexArrays(1, &zero_id);
    check(gl4es_glIsVertexArray(0) == GL_TRUE && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f3: glDeleteVertexArrays(1, {0}) preserves defaultvao", NULL);
    unsigned long db_before = ms2->delete_buffers_calls;
    gl4es_glDeleteBuffers(0, NULL);
    check(gl4es_glGetError() == GL_NO_ERROR && ms2->delete_buffers_calls == db_before,
          "tier2_f3: glDeleteBuffers(0, NULL) safe no-op", NULL);
    gl4es_glDeleteBuffers(1, &zero_id);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    GLint zero_arr_bind = -1;
    gl4es_glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &zero_arr_bind);
    check(zero_arr_bind == 0 && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f3: glDeleteBuffers(1, {0}) preserves defaultvbo", NULL);

    GLuint ibo_del = 0;
    uint16_t idx4[4] = {0, 1, 2, 3};
    gl4es_glGenBuffers(1, &ibo_del);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo_del);
    gl4es_glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(idx4), idx4, GL_STATIC_DRAW);
    gl4es_glDeleteBuffers(1, &ibo_del);
    setup_simple_quad_arrays(verts, NULL);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);
    check(ms2->bound_element_array_buffer == 0,
          "tier2_f3: deleting active IBO before GL_QUADS leaves bound IBO == 0", NULL);

    /* F4 boundaries (6) */
    GLuint vbo0 = 0;
    gl4es_glGenBuffers(1, &vbo0);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo0);
    gl4es_glBufferData(GL_ARRAY_BUFFER, 0, NULL, GL_DYNAMIC_DRAW);
    GLint bsz = -1;
    gl4es_glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &bsz);
    check(bsz == 0, "tier2_f4: 0-byte VBO has GL_BUFFER_SIZE == 0", NULL);

    uint8_t one_byte = 0x5A;
    gl4es_glBufferData(GL_ARRAY_BUFFER, 1, &one_byte, GL_DYNAMIC_DRAW);
    gl4es_glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &bsz);
    check(bsz == 1, "tier2_f4: 1-byte VBO has GL_BUFFER_SIZE == 1", NULL);
    gl4es_glDeleteBuffers(1, &vbo0);

    GLuint vbo_osc = 0;
    gl4es_glGenBuffers(1, &vbo_osc);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo_osc);
    uint8_t *buf64 = (uint8_t *)calloc(1, 65536);
    for (int i = 0; i < 60; ++i) {
        size_t sz = (i % 3 == 0) ? 1024u : ((i % 3 == 1) ? 65536u : 4096u);
        gl4es_glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)sz, buf64, GL_DYNAMIC_DRAW);
        gl4es_glBufferSubData(GL_ARRAY_BUFFER, 0, (GLsizeiptr)(sz / 2), buf64);
    }
    free(buf64);
    GLint osc_sz = 0;
    gl4es_glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &osc_sz);
#ifndef GL4ES_PRE_M1_SMOKE
    {
        gl4es_mem_stats_t st_osc;
        gl4es_get_mem_stats(&st_osc);
        check(osc_sz == 4096 && st_osc.shadow_cpu_bytes <= 65536,
              "tier2_f4: rapid shrink/grow oscillation does not inflate shadow cap", NULL);
    }
#else
    check(osc_sz == 4096 && glstate->vao->vertex != NULL && glstate->vao->vertex->cap <= 65536,
          "tier2_f4: rapid shrink/grow oscillation does not inflate shadow cap", NULL);
#endif

#ifndef GL4ES_PRE_M1_SMOKE
    gl4es_trim_memory(2);
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    check(gl4es_glIsBuffer(vbo_osc) == GL_TRUE,
          "tier2_f2: critical trim under active VBO preserves buffer validity", NULL);
#endif
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    gl4es_glDeleteBuffers(1, &vbo_osc);

    GLuint tex_min = 0;
    uint8_t px1[4] = {1, 2, 3, 4};
    gl4es_glGenTextures(1, &tex_min);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex_min);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_BGRA, GL_UNSIGNED_BYTE, px1);
    check(ms2->tex_image_calls > 0, "tier2_f4: 1x1 minimum BGRA texture upload succeeds", NULL);
    gl4es_glDeleteTextures(1, &tex_min);

    unsigned long da_zero_v = ms2->draw_arrays_calls;
    unsigned long de_zero_v = ms2->draw_elements_calls;
    gl4es_glDrawArrays(GL_QUADS, 0, 0);
    check(ms2->draw_arrays_calls == da_zero_v && ms2->draw_elements_calls == de_zero_v
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f4: 0-vertex glDrawArrays(GL_QUADS, 0, 0) emits 0 GLES2 draws", NULL);

#ifndef GL4ES_PRE_M1_SMOKE
    gl4es_glBegin(GL_QUADS);
    for (int i = 0; i < 512; ++i) {
        gl4es_glVertex3f((float)i, 0.0f, 0.0f);
    }
    gl4es_glEnd();
    gl4es_glFlush();
    gl4es_mem_stats_t st_merger;
    gl4es_get_mem_stats(&st_merger);
    check(st_merger.current_scratch_bytes <= st_merger.budget_bytes
          && st_merger.peak_scratch_bytes <= st_merger.budget_bytes
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f4: merger/gl_scratch 512-vertex burst stays within budget_bytes", NULL);
#endif

    /* F5 boundaries (5) */
    setup_simple_quad_arrays(verts, NULL);
    for (int r = 0; r < 10; ++r) {
        gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    }
#ifndef GL4ES_PRE_M1_SMOKE
    gl4es_mem_stats_t st_fpe1, st_fpe2;
    gl4es_get_mem_stats(&st_fpe1);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    gl4es_get_mem_stats(&st_fpe2);
    check(st_fpe2.fpe_cache_entries == st_fpe1.fpe_cache_entries,
          "tier2_f5: repeated identical state draw reuses FPE cache without growth", NULL);
    check(st_fpe2.fpe_cache_entries <= st_fpe2.fpe_cache_max_entries,
          "tier2_f5: fpe_cache_entries <= fpe_cache_max_entries", NULL);
    check(st_fpe2.psa_entries <= st_fpe2.psa_max_entries && st_fpe2.psa_bytes <= st_fpe2.psa_max_bytes,
          "tier2_f5: psa_entries & psa_bytes within bounds", NULL);
#endif
    gl4es_glUseProgram(0);
    gl4es_glDisable(GL_TEXTURE_2D);
    gl4es_glDisable(GL_FOG);
    gl4es_glDisable(GL_LIGHTING);
    gl4es_glDisable(GL_ALPHA_TEST);
    gl4es_glDisable(GL_BLEND);
    unsigned long da_min = ms2->draw_arrays_calls;
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    check(ms2->draw_arrays_calls > da_min && ms2->last_draw_program != 0 && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f5: default minimal FPE draw succeeds cleanly", NULL);

    /* fail_program_binary = 1 fallback check (verifies GL_LINK_STATUS == GL_FALSE + link fallback) */
    {
        GLuint pbin = gl4es_glCreateProgram();
        uint8_t dummy_bin[32];
        memset(dummy_bin, 0xAB, sizeof(dummy_bin));
        mock_gles2_mutable_state()->fail_program_binary = 1;
        gl4es_glProgramBinary(pbin, 0x87FF, dummy_bin, (GLsizei)sizeof(dummy_bin));
        GLenum bin_err = gl4es_glGetError();
        GLint link_ok = GL_TRUE;
        gl4es_glGetProgramiv(pbin, GL_LINK_STATUS, &link_ok);
        mock_gles2_mutable_state()->fail_program_binary = 0;

        const char *vs_s = "attribute vec4 gl_Vertex;\nvoid main(){gl_Position=gl_Vertex;}\n";
        const char *fs_s = "void main(){gl_FragColor=vec4(1.0);}\n";
        GLuint vs = gl4es_glCreateShader(GL_VERTEX_SHADER);
        GLuint fs = gl4es_glCreateShader(GL_FRAGMENT_SHADER);
        gl4es_glShaderSource(vs, 1, &vs_s, NULL);
        gl4es_glShaderSource(fs, 1, &fs_s, NULL);
        gl4es_glCompileShader(vs);
        gl4es_glCompileShader(fs);
        gl4es_glAttachShader(pbin, vs);
        gl4es_glAttachShader(pbin, fs);
        gl4es_glLinkProgram(pbin);
        GLint relink_ok = GL_FALSE;
        gl4es_glGetProgramiv(pbin, GL_LINK_STATUS, &relink_ok);
        gl4es_glDeleteProgram(pbin);
        gl4es_glDeleteShader(vs);
        gl4es_glDeleteShader(fs);
        check(bin_err == GL_INVALID_OPERATION && link_ok == GL_FALSE && relink_ok == GL_TRUE,
              "tier2_f5: fail_program_binary=1 reports GL_LINK_STATUS=FALSE & falls back to shader link", NULL);
    }

    /* F6 boundaries (5) */
    GLuint tex7 = 0;
    gl4es_glActiveTexture(GL_TEXTURE7);
    gl4es_glGenTextures(1, &tex7);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex7);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, px4);
    check(ms2->bound_textures[7] != 0, "tier2_f6: GL_TEXTURE7 boundary bind works", NULL);
    gl4es_glBindTexture(GL_TEXTURE_2D, 0);
    GLint bound_2d = -1;
    gl4es_glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound_2d);
    /* Flush deferred 2D texture bind via draw so realize_textures updates GLES2 TMU 7 */
    gl4es_glEnable(GL_TEXTURE_2D);
    setup_simple_quad_arrays(verts, NULL);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    gl4es_glDisable(GL_TEXTURE_2D);
    check(bound_2d == 0 && ms2->bound_textures[7] == 0,
          "tier2_f6: unbind GL_TEXTURE7 to 0 clears GL binding & flushes unit 7 on draw", NULL);
    gl4es_glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    GLint min_filt = 0;
    gl4es_glGetTexParameteriv(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, &min_filt);
    check(gl4es_glGetError() == GL_NO_ERROR && min_filt == GL_NEAREST,
          "tier2_f6: glTexParameteri on default texture 0 updates filter cleanly", NULL);
    gl4es_glActiveTexture(GL_TEXTURE0);
    gl4es_glDeleteTextures(1, &tex7);

    gl4es_glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, -1.0f);
    gl4es_glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 0.0f);
    gl4es_glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 0.001f);
    check(glstate->fpe_state->cm_front_nullexp == 1, "tier2_f6: shininess boundary -1/0/0.001 updates nullexp", NULL);

    (void)gl4es_glGetError(); /* drain prior error */
    GLfloat bad_fog = 99999.0f;
    gl4es_glFogfv(GL_FOG_MODE, &bad_fog);
    check(gl4es_glGetError() == GL_INVALID_ENUM,
          "tier2_f6: invalid GL_FOG_MODE enum sets GL_INVALID_ENUM", NULL);

    /* F7 boundaries (6) */
    unsigned long de_before = ms2->draw_elements_calls;
    gl4es_glDrawArrays(GL_QUADS, 0, 3); /* adjust_vertices(GL_QUADS, 3) == 0 */
    check(ms2->draw_elements_calls == de_before,
          "tier2_f7: GL_QUADS count=3 (<4) adjusts to 0 without draw", NULL);
    gl4es_glDrawArrays(GL_QUADS, 2, 4);
    check(ms2->draw_elements_calls > de_before,
          "tier2_f7: GL_QUADS first=2, count=4 unaligned quad draws", NULL);
    unsigned long de_q0 = ms2->draw_elements_calls;
    unsigned long da_q0 = ms2->draw_arrays_calls;
    gl4es_glDrawElements(GL_QUADS, 0, GL_UNSIGNED_SHORT, idx4);
    check(ms2->draw_elements_calls == de_q0 && ms2->draw_arrays_calls == da_q0
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f7: glDrawElements(GL_QUADS, 0) emits 0 GLES2 draws", NULL);

    /* Partial 4-byte GL_STREAM_DRAW offset update */
    GLuint vcol = 0;
    uint8_t two_cols[8] = {1,2,3,255, 4,5,6,255};
    uint8_t sub_col[4] = {200,150,100,253};
    gl4es_glGenBuffers(1, &vcol);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vcol);
    gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(two_cols), two_cols, GL_STREAM_DRAW);
    gl4es_glBufferSubData(GL_ARRAY_BUFFER, 4, 4, sub_col);
    uint8_t readback[4] = {0};
    gl4es_glGetBufferSubData(GL_ARRAY_BUFFER, 4, 4, readback);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    check(memcmp(readback, sub_col, 4) == 0,
          "tier2_f7: partial offset=4 glBufferSubData syncs STREAM_DRAW shadow", NULL);
    gl4es_glDeleteBuffers(1, &vcol);

    /* Overflow > QUAD_IDX_VERTS fallback */
    const int big_verts = QUAD_IDX_VERTS + 4;
    float *huge_v = (float *)calloc((size_t)big_verts * 3u, sizeof(float));
    setup_simple_quad_arrays(huge_v, NULL);
    unsigned long de_big = ms2->draw_elements_calls;
    gl4es_glDrawArrays(GL_QUADS, 0, big_verts);
    free(huge_v);
    check(ms2->draw_elements_calls > de_big && ms2->last_draw_mode == GL_TRIANGLES
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f7: count > QUAD_IDX_VERTS quad draw fallback converts to triangles", NULL);

    /* GL_UNSIGNED_INT GL_QUADS boundary */
    uint32_t ui_quads[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    setup_simple_quad_arrays(verts, NULL);
    unsigned long de_uiq = ms2->draw_elements_calls;
    gl4es_glDrawElements(GL_QUADS, 8, GL_UNSIGNED_INT, ui_quads);
    check(ms2->draw_elements_calls > de_uiq && ms2->last_draw_mode == GL_TRIANGLES
          && ms2->last_draw_count == 12 && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f7: glDrawElements(GL_QUADS, 8, GL_UNSIGNED_INT) draws 12 triangle indices", NULL);

    /* F8 boundaries (5) */
    unsigned long da_p0 = ms2->draw_arrays_calls;
    unsigned long de_p0 = ms2->draw_elements_calls;
    gl4es_glDrawArraysInstanced(GL_QUADS, 0, 4, 0);
    check(ms2->draw_arrays_calls == da_p0 && ms2->draw_elements_calls == de_p0
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f8: glDrawArraysInstanced primcount=0 emits 0 GLES2 draws", NULL);

    uint32_t ui_idx[3] = {0, 1, 2};
    setup_simple_quad_arrays(verts, NULL);
    unsigned long de_ui = ms2->draw_elements_calls;
    gl4es_glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_INT, ui_idx);
    check(ms2->draw_elements_calls > de_ui && ms2->last_draw_type == GL_UNSIGNED_INT
          && ms2->last_draw_count == 3 && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f8: glDrawElements GL_UNSIGNED_INT draws 3 uint indices", NULL);

    GLuint tex_sub = 0;
    gl4es_glGenTextures(1, &tex_sub);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex_sub);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 4, 4, 0, GL_RGBA, GL_UNSIGNED_BYTE, px4);
    gl4es_glTexSubImage2D(GL_TEXTURE_2D, 0, 1, 1, 1, 1, GL_BGRA, GL_UNSIGNED_BYTE, px1);
    check(ms2->tex_sub_image_calls > 0, "tier2_f8: 1x1 BGRA glTexSubImage2D succeeds", NULL);
    gl4es_glDeleteTextures(1, &tex_sub);

    unsigned long da_emp = ms2->draw_arrays_calls;
    unsigned long de_emp = ms2->draw_elements_calls;
    gl4es_glBegin(GL_QUADS);
    gl4es_glEnd();
    check(ms2->draw_arrays_calls == da_emp && ms2->draw_elements_calls == de_emp
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f8: empty glBegin(GL_QUADS)/glEnd() emits 0 GLES2 draws", NULL);

    unsigned long tot_pt = ms2->draw_arrays_calls + ms2->draw_elements_calls;
    gl4es_glBegin(GL_POINTS);
    gl4es_glVertex3f(1.0f, 2.0f, 3.0f);
    gl4es_glEnd();
    gl4es_glFlush();
    check((ms2->draw_arrays_calls + ms2->draw_elements_calls) > tot_pt
          && ms2->last_draw_mode == GL_POINTS && gl4es_glGetError() == GL_NO_ERROR,
          "tier2_f8: single-vertex glBegin(GL_POINTS)/glEnd() draws GL_POINTS", NULL);

    close_gl4es();
}

static void suite_tier3_pairwise(void) {
    set_env_var("LIBGL_MEM_PROFILE", "low");
    init_with_mock();

    float verts[16 * 3] = {0};
    uint8_t bgra[16 * 4];
    for (int i = 0; i < 16; ++i) {
        bgra[i * 4 + 0] = (uint8_t)(10 + i);
        bgra[i * 4 + 1] = (uint8_t)(20 + i);
        bgra[i * 4 + 2] = (uint8_t)(30 + i);
        bgra[i * 4 + 3] = 255;
    }

    GLuint vbo = 0, ibo = 0, tex1 = 0, tex2 = 0, tex3 = 0;
    uint16_t qidx[8] = {0, 1, 2, 3, 4, 5, 6, 7};
    uint8_t px[32 * 32 * 4];
    memset(px, 0xCC, sizeof(px));

    gl4es_glGenBuffers(1, &vbo);
    gl4es_glGenBuffers(1, &ibo);
    gl4es_glGenTextures(1, &tex1);
    gl4es_glGenTextures(1, &tex2);
    gl4es_glGenTextures(1, &tex3);

    gl4es_glEnable(GL_TEXTURE_2D);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex1);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 32, 32, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex2);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 32, 32, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex3);
    gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 32, 32, 0, GL_RGB, GL_UNSIGNED_BYTE, px);

    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo);
    gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(verts), verts, GL_STREAM_DRAW);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    gl4es_glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(qidx), qidx, GL_STATIC_DRAW);
    const mock_gles2_state_t *ms3 = mock_gles2_get_state();
    GLuint real_ibo3 = ms3->bound_element_array_buffer;

    /* Pair 1: LOW profile + GL_STREAM_DRAW + GL_BGRA */
    gl4es_glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(verts), verts);
    gl4es_glEnableClientState(GL_VERTEX_ARRAY);
    gl4es_glVertexPointer(3, GL_FLOAT, 0, 0);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    gl4es_glEnableClientState(GL_COLOR_ARRAY);
    gl4es_glColorPointer(GL_BGRA, GL_UNSIGNED_BYTE, 0, bgra);
    gl4es_glDrawArrays(GL_QUADS, 0, 8);
    check(ms3->last_draw_color_bytes[0] == 30,
          "tier3_p1: LOW + STREAM_DRAW + BGRA converts color cleanly", NULL);

    /* Pair 2: texmat + fog + material simultaneous FPE mutation */
    gl4es_glMatrixMode(GL_TEXTURE);
    gl4es_glScalef(1.5f, 1.5f, 1.0f);
    gl4es_glMatrixMode(GL_MODELVIEW);
    gl4es_glEnable(GL_FOG);
    gl4es_glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 16.0f);
    unsigned long da_p2 = ms3->draw_arrays_calls;
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    check(ms3->draw_arrays_calls > da_p2 && ms3->last_draw_program != 0 && gl4es_glGetError() == GL_NO_ERROR,
          "tier3_p2: texmat + fog + material active FPE compiled", NULL);

    /* Pair 3: glBindTexture same-format vs diff-format + GL_QUADS fast path */
    unsigned long de_p3 = ms3->draw_elements_calls;
    gl4es_glBindTexture(GL_TEXTURE_2D, tex1);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex2);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex3);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);
    check(ms3->draw_elements_calls == de_p3 + 3 && ms3->last_draw_ibo != real_ibo3
          && ms3->bound_element_array_buffer == real_ibo3 && gl4es_glGetError() == GL_NO_ERROR,
          "tier3_p3: bind same-format & diff-format interleaved with GL_QUADS preserves user IBO", NULL);

    /* Pair 4: Unaligned GL_QUADS fallback + active user IBO + glDrawElements */
    gl4es_glDrawArrays(GL_QUADS, 1, 8);
    gl4es_glDrawElements(GL_QUADS, 8, GL_UNSIGNED_SHORT, 0);
    check(ms3->draw_elements_calls > 0,
          "tier3_p4: unaligned GL_QUADS fallback + glDrawElements(GL_QUADS)", NULL);

    /* Pair 5: glDrawArraysInstanced(GL_QUADS) + BGRA + active IBO */
    unsigned long de_p5 = ms3->draw_elements_calls;
    gl4es_glDrawArraysInstanced(GL_QUADS, 0, 4, 2);
    check(ms3->draw_elements_calls > de_p5 && ms3->last_draw_ibo != real_ibo3
          && ms3->bound_element_array_buffer == real_ibo3
          && ms3->last_draw_color_captured && ms3->last_draw_color_bytes[0] == 30,
          "tier3_p5: glDrawArraysInstanced(GL_QUADS) + BGRA + active IBO converts color & restores IBO", NULL);

    /* Pair 6: glBegin/glEnd merger + gl4es_trim_memory(1) + glClear */
    unsigned long clr_p6 = ms3->clear_calls;
    unsigned long draw_p6 = ms3->draw_arrays_calls + ms3->draw_elements_calls;
#ifndef GL4ES_PRE_M1_SMOKE
    gl4es_mem_stats_t st_p6_a;
    gl4es_get_mem_stats(&st_p6_a);
#endif
    gl4es_glBegin(GL_QUADS);
    gl4es_glColor4f(1, 1, 1, 1);
    gl4es_glVertex3f(0, 0, 0);
    gl4es_glVertex3f(1, 0, 0);
    gl4es_glVertex3f(1, 1, 0);
    gl4es_glVertex3f(0, 1, 0);
    gl4es_glEnd();
#ifndef GL4ES_PRE_M1_SMOKE
    gl4es_trim_memory(1);
#endif
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
#ifndef GL4ES_PRE_M1_SMOKE
    gl4es_mem_stats_t st_p6_b;
    gl4es_get_mem_stats(&st_p6_b);
    check(ms3->clear_calls > clr_p6
          && (ms3->draw_arrays_calls + ms3->draw_elements_calls) > draw_p6
          && st_p6_b.trim_count >= st_p6_a.trim_count + 1
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier3_p6: glBegin/glEnd + trim(1) + glClear flushes draw & drains trim", NULL);
#else
    check(ms3->clear_calls > clr_p6
          && (ms3->draw_arrays_calls + ms3->draw_elements_calls) > draw_p6
          && gl4es_glGetError() == GL_NO_ERROR,
          "tier3_p6: glBegin/glEnd + glClear flushes draw", NULL);
#endif

    /* Pair 7: >cap transient texture + glTexSubImage2D + GL_TEXTURE7 */
    (void)gl4es_glGetError();
    unsigned long tsi_p7 = ms3->tex_sub_image_calls;
    gl4es_glActiveTexture(GL_TEXTURE7);
    gl4es_glBindTexture(GL_TEXTURE_2D, tex1);
    gl4es_glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 16, 16, GL_BGRA, GL_UNSIGNED_BYTE, px);
    gl4es_glActiveTexture(GL_TEXTURE0);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    GLint bound_tmu0 = -1;
    gl4es_glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound_tmu0);
    GLenum p7_err = gl4es_glGetError();
    char p7_msg[128];
    snprintf(p7_msg, sizeof(p7_msg), "tsi=%lu->%lu bound_tmu0=%d (tex3=%u tex1=%u) err=0x%x",
             tsi_p7, ms3->tex_sub_image_calls, bound_tmu0, tex3, tex1, (unsigned)p7_err);
    check(ms3->tex_sub_image_calls > tsi_p7 && bound_tmu0 == (GLint)tex3
          && p7_err == GL_NO_ERROR,
          "tier3_p7: GL_TEXTURE7 + BGRA glTexSubImage2D + TMU0 restore", p7_msg);

    /* Pair 8: VAO switch + VBO delete + draw */
    GLuint vao = 0;
    gl4es_glGenVertexArrays(1, &vao);
    gl4es_glBindVertexArray(vao);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    setup_simple_quad_arrays(verts, bgra);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);
    gl4es_glBindVertexArray(0);
    gl4es_glDeleteVertexArrays(1, &vao);
    check(!gl4es_glIsVertexArray(vao), "tier3_p8: VAO bind + BGRA draw + VAO delete", NULL);

    /* Pair 9: Off-thread trim(2) + FPE cache pressure + glClear */
#ifndef GL4ES_PRE_M1_SMOKE
    int urg = 2;
    pthread_t th;
    if (pthread_create(&th, NULL, trim_worker_fn, &urg) == 0) pthread_join(th, NULL);
    gl4es_glClear(GL_COLOR_BUFFER_BIT);
    gl4es_mem_stats_t st;
    gl4es_get_mem_stats(&st);
    check(st.fpe_cache_entries <= st.fpe_cache_max_entries && st.peak_scratch_bytes <= st.budget_bytes,
          "tier3_p9: off-thread trim(2) + FPE pressure within caps", NULL);
#endif

    /* Pair 10: Custom GLSL shader relink + FPE fixed restore */
    (void)gl4es_glGetError();
    gl4es_glDisable(GL_FOG);
    gl4es_glDisable(GL_TEXTURE_2D);
    const char *vsrc = "attribute vec4 gl_Vertex;\nvoid main(){gl_Position=gl_Vertex;}\n";
    const char *fsrc = "void main(){gl_FragColor=vec4(1.0);}\n";
    GLuint vs = gl4es_glCreateShader(GL_VERTEX_SHADER);
    GLuint fs = gl4es_glCreateShader(GL_FRAGMENT_SHADER);
    gl4es_glShaderSource(vs, 1, &vsrc, NULL);
    gl4es_glShaderSource(fs, 1, &fsrc, NULL);
    gl4es_glCompileShader(vs);
    gl4es_glCompileShader(fs);
    GLuint prog = gl4es_glCreateProgram();
    gl4es_glAttachShader(prog, vs);
    gl4es_glAttachShader(prog, fs);
    gl4es_glLinkProgram(prog);
    gl4es_glUseProgram(prog);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    GLuint cust_prog_used = ms3->last_draw_program;
    gl4es_glUseProgram(0);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
    GLuint fpe_prog_restored = ms3->last_draw_program;
    gl4es_glDeleteProgram(prog);
    gl4es_glDeleteShader(vs);
    gl4es_glDeleteShader(fs);
    GLenum p10_err = gl4es_glGetError();
    char p10_msg[128];
    snprintf(p10_msg, sizeof(p10_msg), "prog=%u cust=%u fpe=%u err=0x%x",
             prog, cust_prog_used, fpe_prog_restored, (unsigned)p10_err);
    check(cust_prog_used >= prog && fpe_prog_restored != cust_prog_used
          && fpe_prog_restored != prog && fpe_prog_restored != 0
          && p10_err == GL_NO_ERROR,
          "tier3_p10: custom GLSL draw + FPE fixed-function program restore", p10_msg);

    /* Pair 11: Secondary GLState + STREAM_DRAW + DeleteGLState */
    unsigned long de_p11 = ms3->draw_elements_calls;
    void *orig = glstate;
    void *sec = NewGLState(NULL, 0);
    ActivateGLState(sec);
    setup_simple_quad_arrays(verts, bgra);
    gl4es_glDrawArrays(GL_QUADS, 0, 4);
    ActivateGLState(orig);
    DeleteGLState(sec);
    check(ms3->draw_elements_calls > de_p11 && ms3->last_draw_color_captured
          && ms3->last_draw_color_bytes[0] == 30 && gl4es_glGetError() == GL_NO_ERROR,
          "tier3_p11: secondary GLState + BGRA draw + DeleteGLState", NULL);

    /* Pair 12: glBufferData shrink/grow + glBufferSubData + glGetBufferParameteriv */
    uint8_t p12_buf[256];
    memset(p12_buf, 0x42, sizeof(p12_buf));
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo);
    gl4es_glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)sizeof(p12_buf), p12_buf, GL_STREAM_DRAW);
    gl4es_glBufferSubData(GL_ARRAY_BUFFER, 0, 64, verts);
    GLint gsz = 0;
    gl4es_glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &gsz);
    gl4es_glBufferData(GL_ARRAY_BUFFER, 128, p12_buf, GL_STREAM_DRAW);
    gl4es_glBufferSubData(GL_ARRAY_BUFFER, 0, 64, verts);
    GLint gsz_shrink = 0;
    gl4es_glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &gsz_shrink);
    check(gsz == 256 && gsz_shrink == 128,
          "tier3_p12: grow/shrink glBufferData + glBufferSubData + glGetBufferParameteriv", NULL);

    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    gl4es_glDeleteBuffers(1, &vbo);
    gl4es_glDeleteBuffers(1, &ibo);
    gl4es_glDeleteTextures(1, &tex1);
    gl4es_glDeleteTextures(1, &tex2);
    gl4es_glDeleteTextures(1, &tex3);
    close_gl4es();
}

#ifndef GL4ES_PRE_M1_SMOKE
static void run_village_stress(const char *profile_name) {
    set_env_var("LIBGL_MEM_PROFILE", profile_name);
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);
    init_with_mock();

    const int num_chunks = 1200;
    const int num_draws = 5000;
    const size_t chunk_bytes = 32u * 1024u;
    uint8_t *chunk_data = (uint8_t *)malloc(chunk_bytes);
    memset(chunk_data, 0x33, chunk_bytes);

    GLuint pool_vbos[64] = {0};
    gl4es_glGenBuffers(64, pool_vbos);

    GLuint textures[8] = {0};
    uint8_t tex_px[64 * 64 * 4];
    memset(tex_px, 0x7F, sizeof(tex_px));
    gl4es_glGenTextures(8, textures);
    gl4es_glEnable(GL_TEXTURE_2D);
    for (int t = 0; t < 8; ++t) {
        gl4es_glBindTexture(GL_TEXTURE_2D, textures[t]);
        gl4es_glTexImage2D(GL_TEXTURE_2D, 0, (t < 6) ? GL_RGBA : GL_RGB, 64, 64, 0,
                           (t < 6) ? GL_BGRA : GL_RGB, GL_UNSIGNED_BYTE, tex_px);
    }

    float quad_verts[12] = {0,0,0, 1,0,0, 1,1,0, 0,1,0};
    uint8_t quad_bgra[16] = {10,20,30,255, 20,30,40,255, 30,40,50,255, 40,50,60,255};

    double t_start = now_ms();
    double max_batch_ms = 0.0;

    /* 1. Chunk rebuild storm (1,200 cycles) */
    for (int c = 0; c < num_chunks; ++c) {
        double b0 = now_ms();
        GLuint vbo = pool_vbos[c & 63];
        if (c >= 64 && (c % 64) == 0) {
            gl4es_glDeleteBuffers(64, pool_vbos);
            gl4es_glGenBuffers(64, pool_vbos);
            vbo = pool_vbos[0];
        }
        size_t sz = (c & 1) ? 16384u : chunk_bytes;
        gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbo);
        gl4es_glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)sz, chunk_data, GL_STATIC_DRAW);
        gl4es_glBufferSubData(GL_ARRAY_BUFFER, 0, 4096, chunk_data);
        gl4es_glEnableClientState(GL_VERTEX_ARRAY);
        gl4es_glVertexPointer(3, GL_FLOAT, 16, 0);
        gl4es_glDisableClientState(GL_COLOR_ARRAY);
        gl4es_glDrawArrays(GL_QUADS, 0, 16);

        if (c == 600) {
            int urg = 1;
            pthread_t th;
            if (pthread_create(&th, NULL, trim_worker_fn, &urg) == 0) {
                pthread_join(th, NULL);
            }
            gl4es_glClear(GL_COLOR_BUFFER_BIT);
        }
        double b1 = now_ms();
        if (b1 - b0 > max_batch_ms) max_batch_ms = b1 - b0;
    }

    /* 2. Heavy modded FPE thrash + BindTexture + particle/UI GL_QUADS + STREAM_DRAW + BGRA burst + active IBO storm (5,000 draws) */
    GLuint stream_vbo = 0, vert_vbo = 0, user_ibo = 0;
    uint16_t user_idx[4] = {0, 1, 2, 3};
    gl4es_glGenBuffers(1, &stream_vbo);
    gl4es_glGenBuffers(1, &vert_vbo);
    gl4es_glGenBuffers(1, &user_ibo);
    gl4es_glBindBuffer(GL_ARRAY_BUFFER, vert_vbo);
    gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(quad_verts), quad_verts, GL_STATIC_DRAW);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, user_ibo);
    gl4es_glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(user_idx), user_idx, GL_STATIC_DRAW);
    const mock_gles2_state_t *ms = mock_gles2_get_state();
    GLuint real_user_ibo = ms->bound_element_array_buffer;
    int ibo_preserved_ok = 1;

    /* 2a. Heavy BGRA vertex color burst (> 512KB low cap, <= 2MB high cap) */
    {
        const int burst_verts_count = 250002;
        float *burst_verts = (float *)calloc((size_t)burst_verts_count * 3u, sizeof(float));
        uint8_t *burst_bgra = (uint8_t *)malloc((size_t)burst_verts_count * 4u);
        memset(burst_bgra, 0x66, (size_t)burst_verts_count * 4u);
        double b0 = now_ms();
        gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
        setup_simple_quad_arrays(burst_verts, burst_bgra);
        gl4es_glDrawArrays(GL_TRIANGLES, 0, burst_verts_count);
        double b1 = now_ms();
        if (b1 - b0 > max_batch_ms) max_batch_ms = b1 - b0;
        free(burst_verts);
        free(burst_bgra);
    }

    gl4es_glEnable(GL_LIGHTING);
    gl4es_glEnable(GL_COLOR_MATERIAL);
    for (int d = 0; d < num_draws; ++d) {
        double b0 = now_ms();
        gl4es_glBindTexture(GL_TEXTURE_2D, textures[d & 7]);
        {
            int lmask = d & 255;
            for (int b = 0; b < 8; ++b) {
                if (lmask & (1 << b)) gl4es_glEnable(GL_LIGHT0 + b);
                else gl4es_glDisable(GL_LIGHT0 + b);
            }
        }
        if ((d & 31) == 0) {
            gl4es_glMatrixMode(GL_TEXTURE);
            if (d & 32) gl4es_glLoadIdentity();
            else gl4es_glScalef(2.0f, 2.0f, 1.0f);
            gl4es_glMatrixMode(GL_MODELVIEW);
        }
        if ((d & 63) == 0) {
            if (d & 64) gl4es_glEnable(GL_FOG);
            else gl4es_glDisable(GL_FOG);
            gl4es_glAlphaFunc((d & 128) ? GL_GREATER : GL_ALWAYS, 0.1f);
        }
        if ((d & 15) == 0) {
            gl4es_glBindBuffer(GL_ARRAY_BUFFER, vert_vbo);
            gl4es_glEnableClientState(GL_VERTEX_ARRAY);
            gl4es_glVertexPointer(3, GL_FLOAT, 0, 0);
            gl4es_glBindBuffer(GL_ARRAY_BUFFER, stream_vbo);
            gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(quad_bgra), quad_bgra, GL_STREAM_DRAW);
            gl4es_glEnableClientState(GL_COLOR_ARRAY);
            gl4es_glColorPointer(GL_BGRA, GL_UNSIGNED_BYTE, 0, 0);
            gl4es_glDrawArrays(GL_QUADS, 0, 4);
            if (ms->bound_element_array_buffer != real_user_ibo || ms->last_draw_ibo == real_user_ibo) {
                ibo_preserved_ok = 0;
            }
        } else {
            gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
            setup_simple_quad_arrays(quad_verts, NULL);
            gl4es_glDrawArrays(GL_QUADS, 0, 4);
        }
        if (d == 2500) {
            int urg = 2;
            pthread_t th;
            if (pthread_create(&th, NULL, trim_worker_fn, &urg) == 0) {
                pthread_join(th, NULL);
            }
            gl4es_glClear(GL_COLOR_BUFFER_BIT);
        }
        double b1 = now_ms();
        if (b1 - b0 > max_batch_ms) max_batch_ms = b1 - b0;
    }
    double total_ms = now_ms() - t_start;

    gl4es_mem_stats_t st;
    gl4es_get_mem_stats(&st);

    printf("  [METRIC] village(%s): total=%.2fms max_batch=%.2fms peak_scratch=%zu/%zu (color_cap=%zu) fpe=%zu/%zu psa=%zu/%zu trims=%lu\n",
           profile_name, total_ms, max_batch_ms,
           st.peak_scratch_bytes, st.budget_bytes, st.color_scratch_cap,
           st.fpe_cache_entries, st.fpe_cache_max_entries,
           st.psa_entries, st.psa_max_entries, st.trim_count);
    printf("METRIC profile=%s peak_scratch_bytes=%zu budget_bytes=%zu color_scratch_cap=%zu fpe_cache_entries=%zu fpe_cache_max_entries=%zu psa_entries=%zu psa_max_entries=%zu psa_max_bytes=%zu elapsed_ms=%.2f max_batch_ms=%.2f\n",
           profile_name, st.peak_scratch_bytes, st.budget_bytes, st.color_scratch_cap,
           st.fpe_cache_entries, st.fpe_cache_max_entries,
           st.psa_entries, st.psa_max_entries, st.psa_max_bytes,
           total_ms, max_batch_ms);

    check(max_batch_ms < 2000.0, "village: no multi-second stall spike (max_batch < 2000ms)", NULL);
    check(st.peak_scratch_bytes <= st.budget_bytes, "village: peak_scratch_bytes <= budget_bytes", NULL);
    check(st.fpe_cache_entries <= st.fpe_cache_max_entries, "village: fpe_cache_entries <= fpe_cache_max_entries", NULL);
    if (strcmp(profile_name, "low") == 0) {
        check(st.fpe_cache_entries == st.fpe_cache_max_entries && st.fpe_cache_entries <= 192u,
              "village(low): heavy FPE storm triggers LRU eviction & caps at 192", NULL);
        check(st.peak_scratch_bytes <= st.color_scratch_cap,
              "village(low): peak_scratch_bytes rejects >512KB burst retention & stays <= low color_scratch_cap", NULL);
    } else {
        check(st.fpe_cache_entries > 192u && st.fpe_cache_entries <= st.fpe_cache_max_entries,
              "village(high): heavy FPE storm retains >192 states without low-tier eviction", NULL);
        check(st.peak_scratch_bytes > 512u * 1024u && st.peak_scratch_bytes <= st.budget_bytes,
              "village(high): peak_scratch_bytes retains >512KB burst inside high-tier scratch budget", NULL);
    }
    check(st.psa_entries <= st.psa_max_entries && st.psa_bytes <= st.psa_max_bytes,
          "village: psa_entries & psa_bytes within caps", NULL);
    check(st.trim_count >= 2, "village: mid-storm off-thread trims drained", NULL);
    check(ibo_preserved_ok && real_user_ibo != 0,
          "village: active user IBO preserved cleanly across GL_QUADS + STREAM_DRAW burst", NULL);

    gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
    gl4es_glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    gl4es_glDeleteBuffers(64, pool_vbos);
    gl4es_glDeleteBuffers(1, &stream_vbo);
    gl4es_glDeleteBuffers(1, &vert_vbo);
    gl4es_glDeleteBuffers(1, &user_ibo);
    gl4es_glDeleteTextures(8, textures);
    free(chunk_data);
    close_gl4es();

    check(ms->live_buffers == 0 && ms->live_textures == 0 && ms->live_fbos == 0 && ms->live_rbos == 0
          && ms->live_shaders == 0 && ms->live_programs == 0,
          "village: 0 live GL object leaks after teardown", NULL);
}

static void suite_tier4_multicontext(void) {
    set_env_var("LIBGL_MEM_PROFILE", "low");
    set_env_var("AMETHYST_GL4ES_MEM_BUDGET_MB", NULL);

    init_with_mock();

    float verts[12] = {0,0,0, 1,0,0, 1,1,0, 0,1,0};
    /* Warm up one-time process-wide reachable FPE shader generator scratch before arming leak-shim */
    setup_simple_quad_arrays(verts, NULL);
    gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);

    size_t leaked_bytes = 0, leaked_allocs = 0;
    win_alloc_shim_begin();

    uint8_t vbo_blob[128];
    memset(vbo_blob, 0, sizeof(vbo_blob));
    memcpy(vbo_blob + 16, verts, sizeof(verts));
    uint8_t px[32 * 32 * 4];
    memset(px, 0x5A, sizeof(px));

    void *orig_ctx = glstate;
    int all_ctx_ok = 1;
    for (int c = 0; c < 4; ++c) {
        void *ctx = NewGLState(NULL, 0);
        if (!ctx) {
            all_ctx_ok = 0;
            continue;
        }
        ActivateGLState(ctx);

        GLuint vaos[4] = {0};
        GLuint vbos[4] = {0};
        GLuint tex = 0;
        gl4es_glGenVertexArrays(4, vaos);
        gl4es_glGenBuffers(4, vbos);
        gl4es_glGenTextures(1, &tex);

        gl4es_glEnable(GL_TEXTURE_2D);
        gl4es_glBindTexture(GL_TEXTURE_2D, tex);
        gl4es_glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 32, 32, 0, GL_BGRA, GL_UNSIGNED_BYTE, px);

        for (int k = 0; k < 4; ++k) {
            gl4es_glBindVertexArray(vaos[k]);
            gl4es_glBindBuffer(GL_ARRAY_BUFFER, vbos[k]);
            gl4es_glBufferData(GL_ARRAY_BUFFER, sizeof(vbo_blob), vbo_blob, GL_DYNAMIC_DRAW);
            gl4es_glEnableClientState(GL_VERTEX_ARRAY);
            gl4es_glDisableClientState(GL_COLOR_ARRAY);
            gl4es_glVertexPointer(3, GL_FLOAT, 0, (const void *)(uintptr_t)16);
            if (k & 1) gl4es_glEnable(GL_BLEND);
            else gl4es_glDisable(GL_BLEND);
            if (k & 2) gl4es_glEnable(GL_FOG);
            else gl4es_glDisable(GL_FOG);
            gl4es_glDrawArrays(GL_QUADS, 0, 4);
        }

        gl4es_glBindVertexArray(0);
        gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
        gl4es_glDeleteTextures(1, &tex);
        gl4es_glDeleteBuffers(4, vbos);
        gl4es_glDeleteVertexArrays(4, vaos);

        ActivateGLState(orig_ctx);
        DeleteGLState(ctx);
    }

    /* Shared context cycle */
    for (int s = 0; s < 2; ++s) {
        void *sctx = NewGLState(orig_ctx, 0);
        if (!sctx) {
            all_ctx_ok = 0;
            continue;
        }
        ActivateGLState(sctx);
        GLuint svao = 0;
        gl4es_glGenVertexArrays(1, &svao);
        gl4es_glBindVertexArray(svao);
        gl4es_glBindBuffer(GL_ARRAY_BUFFER, 0);
        setup_simple_quad_arrays(verts, NULL);
        gl4es_glDrawArrays(GL_TRIANGLES, 0, 3);
        gl4es_glBindVertexArray(0);
        gl4es_glDeleteVertexArrays(1, &svao);
        ActivateGLState(orig_ctx);
        DeleteGLState(sctx);
    }

    GLenum err_before_close = gl4es_glGetError();
    close_gl4es();
    const mock_gles2_state_t *ms = mock_gles2_get_state();
    int gl_objects_clean = (ms->live_buffers == 0 && ms->live_textures == 0
                            && ms->live_fbos == 0 && ms->live_rbos == 0
                            && ms->live_shaders == 0 && ms->live_programs == 0);
    mock_gles2_reset();
    win_alloc_shim_end(&leaked_bytes, &leaked_allocs);

    char leak_msg[128];
    snprintf(leak_msg, sizeof(leak_msg), "leaked_bytes=%zu leaked_allocs=%zu", leaked_bytes, leaked_allocs);
    check(all_ctx_ok && err_before_close == GL_NO_ERROR,
          "multicontext: 4 standalone + 2 shared GLState thrash cycles completed cleanly", NULL);
    check(!win_alloc_shim_is_active() || (leaked_bytes == 0 && leaked_allocs == 0),
          "multicontext: Windows allocator leak-shim delta == 0 bytes across full lifecycle", leak_msg);
    check(gl_objects_clean,
          "multicontext: 0 live GLES2 buffers/textures/FBOs/RBOs/shaders/programs after close_gl4es()", NULL);
}
#endif /* GL4ES_PRE_M1_SMOKE */

int main(int argc, char **argv) {
    const char *suite = NULL;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--suite") == 0 && i + 1 < argc) {
            suite = argv[++i];
        }
    }
    if (!suite) {
        fprintf(stderr, "Usage: %s --suite <name>\n", argv[0]);
        return 2;
    }

    printf("=== Running C Suite: %s ===\n", suite);
    if (strcmp(suite, "tier1_leaks") == 0) suite_tier1_leaks();
    else if (strcmp(suite, "tier1_fpe_invariants") == 0) suite_tier1_fpe_invariants();
    else if (strcmp(suite, "tier1_ibo_stream") == 0) suite_tier1_ibo_stream();
    else if (strcmp(suite, "tier2_bounds") == 0) suite_tier2_bounds();
    else if (strcmp(suite, "tier3_pairwise") == 0) suite_tier3_pairwise();
#ifndef GL4ES_PRE_M1_SMOKE
    else if (strcmp(suite, "tier1_mem_low") == 0) suite_tier1_mem_low();
    else if (strcmp(suite, "tier1_mem_medium") == 0) suite_tier1_mem_medium();
    else if (strcmp(suite, "tier1_mem_high") == 0) suite_tier1_mem_high();
    else if (strcmp(suite, "tier1_mem_auto") == 0) suite_tier1_mem_auto();
    else if (strcmp(suite, "tier1_mem_budget") == 0) suite_tier1_mem_budget();
    else if (strcmp(suite, "tier1_trim") == 0) suite_tier1_trim();
    else if (strcmp(suite, "tier1_caps") == 0) suite_tier1_caps();
    else if (strcmp(suite, "tier1_fpe_cache") == 0) suite_tier1_fpe_cache();
    else if (strcmp(suite, "tier1_draw_upload") == 0) suite_tier1_draw_upload();
    else if (strcmp(suite, "tier4_village_low") == 0) run_village_stress("low");
    else if (strcmp(suite, "tier4_village_high") == 0) run_village_stress("high");
    else if (strcmp(suite, "tier4_multicontext") == 0) suite_tier4_multicontext();
#endif
    else {
        fprintf(stderr, "Unknown or disabled suite: %s\n", suite);
        return 2;
    }

    printf("=== Suite %s Result: %d PASSED, %d FAILED ===\n", suite, g_passed, g_failed);
    return (g_failed == 0) ? 0 : 1;
}
