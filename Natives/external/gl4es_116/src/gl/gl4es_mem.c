#include "gl4es_mem.h"

#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#ifndef _WIN32
#include <pthread.h>
#include <strings.h>
#include <unistd.h>
#else
#include <windows.h>
#define strcasecmp _stricmp
#endif

#ifdef __APPLE__
#include <sys/types.h>
#include <sys/sysctl.h>
#endif

#include "../glx/hardext.h"
#include "buffers.h"
#include "envvars.h"
#include "fpe_cache.h"
#include "glstate.h"

#define KB_BYTES(x) ((size_t)(x) * 1024u)
#define MB_BYTES(x) ((size_t)(x) * 1024u * 1024u)

typedef struct {
    int profile;
    size_t budget_bytes;
    size_t texture_scratch_cap;
    size_t color_scratch_cap;
    size_t gl_scratch_cap;
    size_t merger_cap;
    size_t fpe_cache_max_entries;
    size_t psa_max_entries;
    size_t psa_max_bytes;
} gl4es_mem_config_t;

static const gl4es_mem_config_t k_tier_defaults[3] = {
    {
        GL4ES_MEM_PROFILE_LOW,
        MB_BYTES(64),
        MB_BYTES(2),
        KB_BYTES(512),
        MB_BYTES(1),
        MB_BYTES(1),
        192u,
        2048u,
        MB_BYTES(8)
    },
    {
        GL4ES_MEM_PROFILE_MEDIUM,
        MB_BYTES(192),
        MB_BYTES(4),
        MB_BYTES(1),
        MB_BYTES(4),
        MB_BYTES(4),
        512u,
        8192u,
        MB_BYTES(24)
    },
    {
        GL4ES_MEM_PROFILE_HIGH,
        MB_BYTES(384),
        MB_BYTES(8),
        MB_BYTES(2),
        MB_BYTES(8),
        MB_BYTES(8),
        1024u,
        16384u,
        MB_BYTES(48)
    }
};

static gl4es_mem_config_t s_cfg = {
    GL4ES_MEM_PROFILE_MEDIUM,
    MB_BYTES(192),
    MB_BYTES(4),
    MB_BYTES(1),
    MB_BYTES(4),
    MB_BYTES(4),
    512u,
    8192u,
    MB_BYTES(24)
};

static int s_cfg_loaded = 0;
static int s_mem_inited = 0;
static int s_pending_trim_urgency = -1;

#ifndef _WIN32
static pthread_t s_gl_thread;
static int s_gl_thread_set = 0;
#else
static DWORD s_gl_thread_id = 0;
static int s_gl_thread_set = 0;
#endif

static size_t s_current_scratch_bytes = 0;
static size_t s_peak_scratch_bytes = 0;
static size_t s_shadow_cpu_bytes = 0;
static size_t s_displaylist_cpu_bytes = 0;
static size_t s_fpe_cache_entries = 0;
static size_t s_psa_entries = 0;
static size_t s_psa_bytes = 0;
static unsigned long s_trim_count = 0;

static uint64_t detect_system_ram_bytes(void) {
#ifdef __APPLE__
    uint64_t memsize = 0;
    size_t len = sizeof(memsize);
    if (sysctlbyname("hw.memsize", &memsize, &len, NULL, 0) == 0 && memsize > 0)
        return memsize;
    int mib[2] = { CTL_HW, HW_MEMSIZE };
    len = sizeof(memsize);
    if (sysctl(mib, 2, &memsize, &len, NULL, 0) == 0 && memsize > 0)
        return memsize;
    return 0;
#elif defined(_SC_PHYS_PAGES) && defined(_SC_PAGESIZE)
    long pages = sysconf(_SC_PHYS_PAGES);
    long psize = sysconf(_SC_PAGESIZE);
    if (pages > 0 && psize > 0)
        return (uint64_t)pages * (uint64_t)psize;
    return 0;
#else
    return 0;
#endif
}

static size_t scale_cap_u64(size_t base, uint64_t num, uint64_t den, size_t floor_val, size_t ceil_val) {
    if (den == 0) den = 1ULL;
    uint64_t v;
#if defined(__SIZEOF_INT128__)
    __uint128_t prod = ((__uint128_t)(uint64_t)base * (__uint128_t)num) / (__uint128_t)den;
    v = (prod > (__uint128_t)ceil_val) ? (uint64_t)ceil_val : (uint64_t)prod;
#else
    uint64_t q = num / den;
    uint64_t r = num % den;
    if (q > 0 && (uint64_t)base > (uint64_t)ceil_val / q)
        return ceil_val;
    uint64_t p1 = (uint64_t)base * q;
    uint64_t p2 = 0;
    if (r > 0 && base > 0) {
        if ((uint64_t)base <= UINT64_MAX / r) {
            p2 = ((uint64_t)base * r) / den;
        } else {
            long double ld = ((long double)base * (long double)r) / (long double)den;
            p2 = (ld >= (long double)ceil_val) ? (uint64_t)ceil_val : (uint64_t)ld;
        }
    }
    v = (p1 > (uint64_t)ceil_val - p2) ? (uint64_t)ceil_val : (p1 + p2);
#endif
    if (v < (uint64_t)floor_val) v = (uint64_t)floor_val;
    if (v > (uint64_t)ceil_val) v = (uint64_t)ceil_val;
    return (size_t)v;
}

static void parse_mem_config(gl4es_mem_config_t *cfg) {
    int profile = GL4ES_MEM_PROFILE_MEDIUM;
    const char *prof_env = GetEnvVar("LIBGL_MEM_PROFILE");
    int explicit_profile = 0;
    if (prof_env && prof_env[0]) {
        if (strcasecmp(prof_env, "low") == 0) {
            profile = GL4ES_MEM_PROFILE_LOW;
            explicit_profile = 1;
        } else if (strcasecmp(prof_env, "medium") == 0) {
            profile = GL4ES_MEM_PROFILE_MEDIUM;
            explicit_profile = 1;
        } else if (strcasecmp(prof_env, "high") == 0) {
            profile = GL4ES_MEM_PROFILE_HIGH;
            explicit_profile = 1;
        }
    }
    if (!explicit_profile) {
        uint64_t ram = detect_system_ram_bytes();
        const uint64_t thresh_low = 2560ULL * 1024ULL * 1024ULL;
        const uint64_t thresh_med = 5120ULL * 1024ULL * 1024ULL;
        if (ram == 0)
            profile = GL4ES_MEM_PROFILE_MEDIUM;
        else if (ram <= thresh_low)
            profile = GL4ES_MEM_PROFILE_LOW;
        else if (ram <= thresh_med)
            profile = GL4ES_MEM_PROFILE_MEDIUM;
        else
            profile = GL4ES_MEM_PROFILE_HIGH;
    }

    *cfg = k_tier_defaults[profile];

    const char *budget_env = GetEnvVar("AMETHYST_GL4ES_MEM_BUDGET_MB");
    if (budget_env && budget_env[0]) {
        char *end = NULL;
        errno = 0;
        long mb = strtol(budget_env, &end, 10);
        int trailing_ok = 1;
        if (end) {
            const char *p = end;
            while (*p) {
                if (*p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') {
                    trailing_ok = 0;
                    break;
                }
                ++p;
            }
        }
        if (errno == 0 && end && end != budget_env && trailing_ok && mb > 0) {
            uint64_t max_mb = (uint64_t)(SIZE_MAX / (1024u * 1024u));
            uint64_t umb = (uint64_t)mb;
            if (umb > max_mb) umb = max_mb;
            size_t override_bytes = (size_t)(umb * (1024ULL * 1024ULL));
            uint64_t ref_budget = (uint64_t)k_tier_defaults[profile].budget_bytes;
            const gl4es_mem_config_t *hi = &k_tier_defaults[GL4ES_MEM_PROFILE_HIGH];
            cfg->budget_bytes = override_bytes;
            cfg->texture_scratch_cap = scale_cap_u64(cfg->texture_scratch_cap, override_bytes, ref_budget, KB_BYTES(512), hi->texture_scratch_cap);
            cfg->color_scratch_cap = scale_cap_u64(cfg->color_scratch_cap, override_bytes, ref_budget, KB_BYTES(128), hi->color_scratch_cap);
            cfg->gl_scratch_cap = scale_cap_u64(cfg->gl_scratch_cap, override_bytes, ref_budget, KB_BYTES(256), hi->gl_scratch_cap);
            cfg->merger_cap = scale_cap_u64(cfg->merger_cap, override_bytes, ref_budget, KB_BYTES(256), hi->merger_cap);
            cfg->fpe_cache_max_entries = scale_cap_u64(cfg->fpe_cache_max_entries, override_bytes, ref_budget, 64u, hi->fpe_cache_max_entries);
            cfg->psa_max_entries = scale_cap_u64(cfg->psa_max_entries, override_bytes, ref_budget, 256u, hi->psa_max_entries);
            cfg->psa_max_bytes = scale_cap_u64(cfg->psa_max_bytes, override_bytes, ref_budget, MB_BYTES(1), hi->psa_max_bytes);
        }
    }
}

static void get_active_config(gl4es_mem_config_t *out) {
    if (__atomic_load_n(&s_cfg_loaded, __ATOMIC_ACQUIRE)) {
        *out = s_cfg;
    } else {
        parse_mem_config(out);
    }
}

void gl4es_mem_init(void) {
    __atomic_store_n(&s_mem_inited, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&s_pending_trim_urgency, -1, __ATOMIC_RELEASE);
    __atomic_store_n(&s_gl_thread_set, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&s_cfg_loaded, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&s_current_scratch_bytes, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&s_peak_scratch_bytes, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&s_shadow_cpu_bytes, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&s_displaylist_cpu_bytes, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&s_fpe_cache_entries, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&s_psa_entries, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&s_psa_bytes, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&s_trim_count, 0, __ATOMIC_RELAXED);

    gl4es_mem_config_t cfg;
    parse_mem_config(&cfg);
    s_cfg = cfg;
    __atomic_store_n(&s_cfg_loaded, 1, __ATOMIC_RELEASE);

#ifndef _WIN32
    s_gl_thread = pthread_self();
    __atomic_store_n(&s_gl_thread_set, 1, __ATOMIC_RELEASE);
#else
    s_gl_thread_id = GetCurrentThreadId();
    __atomic_store_n(&s_gl_thread_set, 1, __ATOMIC_RELEASE);
#endif
}

void gl4es_mem_mark_initialized(void) {
    __atomic_store_n(&s_mem_inited, 1, __ATOMIC_RELEASE);
}

void gl4es_mem_pre_shutdown(void) {
    __atomic_store_n(&s_mem_inited, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&s_pending_trim_urgency, -1, __ATOMIC_RELEASE);
    __atomic_store_n(&s_gl_thread_set, 0, __ATOMIC_RELEASE);
}

void gl4es_mem_shutdown(void) {
    gl4es_mem_pre_shutdown();
    gl4es_mem_list_shutdown();
    __atomic_store_n(&s_cfg_loaded, 0, __ATOMIC_RELEASE);
}

static int is_on_gl_thread(void) {
    if (!__atomic_load_n(&s_gl_thread_set, __ATOMIC_ACQUIRE))
        return 0;
#ifndef _WIN32
    return pthread_equal(pthread_self(), s_gl_thread) != 0;
#else
    return GetCurrentThreadId() == s_gl_thread_id;
#endif
}

static int is_safe_trim_boundary(void) {
    if (!glstate) return 0;
    if (glstate->list.begin || glstate->list.compiling || glstate->list.active || glstate->merger_used)
        return 0;
    return 1;
}

static void gl4es_mem_trim_now(int urgency) {
    if (urgency < 0) urgency = 0;
    if (urgency > 2) urgency = 2;
    __atomic_fetch_add(&s_trim_count, 1, __ATOMIC_RELAXED);

    gl4es_mem_trim_scratch_pools(urgency);
    gl4es_mem_trim_buffers(urgency);
    gl4es_mem_trim_displaylists(urgency);
    fpe_CacheTrim(urgency);
    fpe_PSATrim(urgency);
}

GL4ES_MEM_EXPORT void gl4es_trim_memory(int urgency) {
    if (urgency < 0) urgency = 0;
    if (urgency > 2) urgency = 2;

    if (!__atomic_load_n(&s_mem_inited, __ATOMIC_ACQUIRE) ||
        !__atomic_load_n(&glstate, __ATOMIC_ACQUIRE))
        return;

    if (is_on_gl_thread() && is_safe_trim_boundary()) {
        int prev = __atomic_exchange_n(&s_pending_trim_urgency, -1, __ATOMIC_ACQ_REL);
        int eff = (prev > urgency) ? prev : urgency;
        gl4es_mem_trim_now(eff);
        return;
    }

    int cur = __atomic_load_n(&s_pending_trim_urgency, __ATOMIC_RELAXED);
    while (cur < urgency) {
        if (__atomic_compare_exchange_n(&s_pending_trim_urgency, &cur, urgency, 1,
                                          __ATOMIC_ACQ_REL, __ATOMIC_RELAXED)) {
            break;
        }
    }
}

void gl4es_mem_drain_pending_trim(void) {
    if (__atomic_load_n(&s_pending_trim_urgency, __ATOMIC_RELAXED) < 0)
        return;
    if (!__atomic_load_n(&s_mem_inited, __ATOMIC_ACQUIRE) || !is_safe_trim_boundary())
        return;
    int urgency = __atomic_exchange_n(&s_pending_trim_urgency, -1, __ATOMIC_ACQ_REL);
    if (urgency >= 0)
        gl4es_mem_trim_now(urgency);
}

GL4ES_MEM_EXPORT void gl4es_get_mem_stats(gl4es_mem_stats_t *out) {
    if (!out) return;
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    out->profile = cfg.profile;
    out->budget_bytes = cfg.budget_bytes;
    out->texture_scratch_cap = cfg.texture_scratch_cap;
    out->color_scratch_cap = cfg.color_scratch_cap;
    out->gl_scratch_cap = cfg.gl_scratch_cap;
    out->merger_cap = cfg.merger_cap;
    out->fpe_cache_max_entries = cfg.fpe_cache_max_entries;
    out->psa_max_entries = cfg.psa_max_entries;
    out->psa_max_bytes = cfg.psa_max_bytes;
    out->fpe_cache_entries = __atomic_load_n(&s_fpe_cache_entries, __ATOMIC_RELAXED);
    out->psa_entries = __atomic_load_n(&s_psa_entries, __ATOMIC_RELAXED);
    out->psa_bytes = __atomic_load_n(&s_psa_bytes, __ATOMIC_RELAXED);
    out->current_scratch_bytes = __atomic_load_n(&s_current_scratch_bytes, __ATOMIC_RELAXED);
    out->peak_scratch_bytes = __atomic_load_n(&s_peak_scratch_bytes, __ATOMIC_RELAXED);
    out->shadow_cpu_bytes = __atomic_load_n(&s_shadow_cpu_bytes, __ATOMIC_RELAXED);
    out->displaylist_cpu_bytes = __atomic_load_n(&s_displaylist_cpu_bytes, __ATOMIC_RELAXED);
    out->trim_count = __atomic_load_n(&s_trim_count, __ATOMIC_RELAXED);
}

int gl4es_mem_profile(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.profile;
}

size_t gl4es_mem_budget_bytes(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.budget_bytes;
}

size_t gl4es_mem_texture_scratch_cap(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.texture_scratch_cap;
}

size_t gl4es_mem_color_scratch_cap(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.color_scratch_cap;
}

size_t gl4es_mem_gl_scratch_cap(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.gl_scratch_cap;
}

size_t gl4es_mem_merger_cap(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.merger_cap;
}

size_t gl4es_mem_fpe_cache_max_entries(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.fpe_cache_max_entries;
}

size_t gl4es_mem_psa_max_entries(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.psa_max_entries;
}

size_t gl4es_mem_psa_max_bytes(void) {
    gl4es_mem_config_t cfg;
    get_active_config(&cfg);
    return cfg.psa_max_bytes;
}

static void atomic_track_delta(size_t *counter, size_t *peak_opt, size_t old_bytes, size_t new_bytes) {
    if (new_bytes == old_bytes) return;
    if (new_bytes > old_bytes) {
        size_t delta = new_bytes - old_bytes;
        size_t cur = __atomic_add_fetch(counter, delta, __ATOMIC_RELAXED);
        if (peak_opt) {
            size_t peak = __atomic_load_n(peak_opt, __ATOMIC_RELAXED);
            while (cur > peak &&
                   !__atomic_compare_exchange_n(peak_opt, &peak, cur, 1,
                                                 __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            }
        }
    } else {
        size_t delta = old_bytes - new_bytes;
        size_t cur = __atomic_load_n(counter, __ATOMIC_RELAXED);
        while (1) {
            size_t next = (cur >= delta) ? (cur - delta) : 0;
            if (__atomic_compare_exchange_n(counter, &cur, next, 1,
                                            __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
                break;
            }
        }
    }
}

void gl4es_mem_track_scratch(size_t old_bytes, size_t new_bytes) {
    atomic_track_delta(&s_current_scratch_bytes, &s_peak_scratch_bytes, old_bytes, new_bytes);
}

void gl4es_mem_track_shadow(size_t old_bytes, size_t new_bytes) {
    atomic_track_delta(&s_shadow_cpu_bytes, NULL, old_bytes, new_bytes);
}

void gl4es_mem_track_displaylist(size_t old_bytes, size_t new_bytes) {
    atomic_track_delta(&s_displaylist_cpu_bytes, NULL, old_bytes, new_bytes);
}

size_t gl4es_mem_shadow_cpu_bytes(void) {
    return __atomic_load_n(&s_shadow_cpu_bytes, __ATOMIC_RELAXED);
}

size_t gl4es_mem_displaylist_cpu_bytes(void) {
    return __atomic_load_n(&s_displaylist_cpu_bytes, __ATOMIC_RELAXED);
}

void gl4es_mem_set_fpe_cache_entries(size_t n) {
    __atomic_store_n(&s_fpe_cache_entries, n, __ATOMIC_RELAXED);
}

void gl4es_mem_set_psa_stats(size_t entries, size_t bytes) {
    __atomic_store_n(&s_psa_entries, entries, __ATOMIC_RELAXED);
    __atomic_store_n(&s_psa_bytes, bytes, __ATOMIC_RELAXED);
}

void *gl4es_mem_acquire_color_scratch(int sidx, size_t needed) {
    if (!glstate || sidx < 0 || sidx >= 4 || needed == 0)
        return NULL;
    size_t cap = gl4es_mem_color_scratch_cap();
    size_t other_used = 0;
    for (int i = 0; i < 4; ++i) {
        if (i != sidx)
            other_used += glstate->color_scratch_cap[i];
    }
    size_t rem = (other_used < cap) ? (cap - other_used) : 0;
    if (needed > rem)
        return NULL;

    if (glstate->color_scratch[sidx] && glstate->color_scratch_cap[sidx] >= needed)
        return glstate->color_scratch[sidx];

    size_t new_cap = (needed + 4095u) & ~(size_t)4095u;
    if (new_cap < needed || new_cap > rem)
        new_cap = rem;

    size_t old_cap = glstate->color_scratch_cap[sidx];
    void *p = realloc(glstate->color_scratch[sidx], new_cap);
    if (!p && new_cap > needed) {
        new_cap = needed;
        p = realloc(glstate->color_scratch[sidx], new_cap);
    }
    if (!p)
        return NULL;
    glstate->color_scratch[sidx] = p;
    glstate->color_scratch_cap[sidx] = new_cap;
    gl4es_mem_track_scratch(old_cap, new_cap);
    return p;
}

float *gl4es_mem_acquire_texgened(int tmu, int len) {
    if (!glstate || tmu < 0 || tmu >= MAX_TEX || len <= 0)
        return NULL;
    const size_t elem_bytes = 4u * sizeof(float);
    if ((size_t)len > SIZE_MAX / elem_bytes)
        return NULL;
    size_t new_bytes = (size_t)len * elem_bytes;
    size_t cap = gl4es_mem_gl_scratch_cap();
    size_t other_bytes = 0;
    for (int i = 0; i < MAX_TEX; ++i) {
        other_bytes += (size_t)glstate->helper_texlen[i] * elem_bytes;
        if (i != tmu)
            other_bytes += (size_t)glstate->texgenedsz[i] * elem_bytes;
    }
    if (other_bytes >= cap || new_bytes > cap - other_bytes)
        return NULL;
    if (glstate->texgened[tmu] && glstate->texgenedsz[tmu] >= len)
        return glstate->texgened[tmu];
    size_t old_bytes = (size_t)glstate->texgenedsz[tmu] * elem_bytes;
    float *p = (float *)realloc(glstate->texgened[tmu], new_bytes);
    if (!p)
        return NULL;
    glstate->texgened[tmu] = p;
    glstate->texgenedsz[tmu] = len;
    gl4es_mem_track_scratch(old_bytes, new_bytes);
    return p;
}

void *gl4es_mem_acquire_helper_tex(int tmu, int len) {
    if (!glstate || tmu < 0 || tmu >= MAX_TEX || len <= 0)
        return NULL;
    const size_t elem_bytes = 4u * sizeof(float);
    if ((size_t)len > SIZE_MAX / elem_bytes)
        return NULL;
    size_t new_bytes = (size_t)len * elem_bytes;
    size_t cap = gl4es_mem_gl_scratch_cap();
    size_t other_bytes = 0;
    for (int i = 0; i < MAX_TEX; ++i) {
        other_bytes += (size_t)glstate->texgenedsz[i] * elem_bytes;
        if (i != tmu)
            other_bytes += (size_t)glstate->helper_texlen[i] * elem_bytes;
    }
    if (other_bytes >= cap || new_bytes > cap - other_bytes)
        return NULL;
    if (glstate->helper_tex[tmu] && glstate->helper_texlen[tmu] >= len)
        return glstate->helper_tex[tmu];
    size_t old_bytes = (size_t)glstate->helper_texlen[tmu] * elem_bytes;
    void *p = realloc(glstate->helper_tex[tmu], new_bytes);
    if (!p)
        return NULL;
    glstate->helper_tex[tmu] = p;
    glstate->helper_texlen[tmu] = len;
    gl4es_mem_track_scratch(old_bytes, new_bytes);
    return p;
}

static void fill_quad_indices(unsigned short *dst, int start_vtx, int count_verts) {
    unsigned short *p = dst;
    unsigned int j = (unsigned int)start_vtx;
    int quads = count_verts / 4;
    for (int q = 0; q < quads; ++q, j += 4u) {
        *(p++) = (unsigned short)(j + 0u);
        *(p++) = (unsigned short)(j + 1u);
        *(p++) = (unsigned short)(j + 2u);
        *(p++) = (unsigned short)(j + 0u);
        *(p++) = (unsigned short)(j + 2u);
        *(p++) = (unsigned short)(j + 3u);
    }
}

int gl4es_mem_prepare_quad_indices(int first, int count,
                                   const unsigned short **out_indices,
                                   unsigned short **out_transient_to_free) {
    if (out_indices) *out_indices = NULL;
    if (out_transient_to_free) *out_transient_to_free = NULL;
    if (!out_indices || !out_transient_to_free || first < 0 || count < 4)
        return 0;

    int aligned_count = count & ~3;
    if (aligned_count < 4)
        return 0;
    if ((size_t)(aligned_count / 4) > (SIZE_MAX / (6u * sizeof(unsigned short))))
        return 0;

    uint64_t realfirst_u64 = ((first % 4) == 0) ? 0ULL : (uint64_t)first;
    uint64_t delta_u64 = (uint64_t)first - realfirst_u64;
    uint64_t realcount_u64 = (uint64_t)aligned_count + delta_u64;
    uint64_t needed_bytes_u64 = (realcount_u64 / 4ULL) * 6ULL * (uint64_t)sizeof(unsigned short);
    size_t cap = gl4es_mem_gl_scratch_cap();

    if (!glstate || realcount_u64 > (uint64_t)INT_MAX || needed_bytes_u64 > (uint64_t)cap ||
        needed_bytes_u64 > (uint64_t)SIZE_MAX) {
        size_t tbytes = (size_t)(aligned_count / 4) * 6u * sizeof(unsigned short);
        unsigned short *buf = (unsigned short *)malloc(tbytes);
        if (!buf)
            return 0;
        fill_quad_indices(buf, first, aligned_count);
        *out_indices = buf;
        *out_transient_to_free = buf;
        return 1;
    }

    int realfirst = (int)realfirst_u64;
    int delta = (int)delta_u64;
    int realcount = (int)realcount_u64;
    size_t needed_bytes = (size_t)needed_bytes_u64;

    if (!glstate->quad_indices_scratch ||
        glstate->quad_indices_verts < realcount ||
        glstate->quad_indices_first != realfirst) {
        if (!glstate->quad_indices_scratch || glstate->quad_indices_verts < realcount) {
            size_t old_bytes = glstate->quad_indices_bytes;
            unsigned short *p = (unsigned short *)realloc(glstate->quad_indices_scratch, needed_bytes);
            if (!p)
                return 0;
            glstate->quad_indices_scratch = p;
            glstate->quad_indices_verts = realcount;
            glstate->quad_indices_bytes = needed_bytes;
            gl4es_mem_track_scratch(old_bytes, needed_bytes);
        }
        glstate->quad_indices_first = realfirst;
        fill_quad_indices(glstate->quad_indices_scratch, realfirst, glstate->quad_indices_verts);
    }

    *out_indices = glstate->quad_indices_scratch + ((size_t)delta * 3u / 2u);
    *out_transient_to_free = NULL;
    return 1;
}

static int is_scratch_vertex_locked(void) {
    if (!glstate) return 1;
    if (glstate->vao) {
        for (int i = 0; i < NB_VA; ++i) {
            if (glstate->vao->locked_mapped[i])
                return 1;
        }
    }
    if (glstate->vaos) {
        glvao_t *vao = NULL;
        kh_foreach_value(glstate->vaos, vao,
            if (vao) {
                for (int i = 0; i < NB_VA; ++i) {
                    if (vao->locked_mapped[i])
                        return 1;
                }
            }
        )
    }
    return 0;
}

void gl4es_mem_trim_scratch_pools(int urgency) {
    if (!glstate) return;

    size_t tex_cap = gl4es_mem_texture_scratch_cap();
    if (glstate->texture_scratch && (urgency >= 1 || glstate->texture_scratch_cap > tex_cap)) {
        gl4es_mem_track_scratch(glstate->texture_scratch_cap, 0);
        free(glstate->texture_scratch);
        glstate->texture_scratch = NULL;
        glstate->texture_scratch_cap = 0;
    }

    size_t color_cap = gl4es_mem_color_scratch_cap();
    size_t total_color = 0;
    for (int i = 0; i < 4; ++i)
        total_color += glstate->color_scratch_cap[i];
    if (urgency >= 1 || total_color > color_cap) {
        for (int i = 0; i < 4; ++i) {
            if (glstate->color_scratch[i]) {
                gl4es_mem_track_scratch(glstate->color_scratch_cap[i], 0);
                free(glstate->color_scratch[i]);
                glstate->color_scratch[i] = NULL;
                glstate->color_scratch_cap[i] = 0;
            }
        }
    }

    size_t gl_cap = gl4es_mem_gl_scratch_cap();
    if (glstate->scratch && (urgency >= 1 || (size_t)glstate->scratch_alloc > gl_cap)) {
        gl4es_mem_track_scratch((size_t)glstate->scratch_alloc, 0);
        free(glstate->scratch);
        glstate->scratch = NULL;
        glstate->scratch_alloc = 0;
    }

    if (glstate->quad_indices_scratch && (urgency >= 1 || glstate->quad_indices_bytes > gl_cap)) {
        gl4es_mem_track_scratch(glstate->quad_indices_bytes, 0);
        free(glstate->quad_indices_scratch);
        glstate->quad_indices_scratch = NULL;
        glstate->quad_indices_verts = 0;
        glstate->quad_indices_first = 0;
        glstate->quad_indices_bytes = 0;
    }

    size_t tex_helper_bytes = 0;
    for (int i = 0; i < MAX_TEX; ++i) {
        tex_helper_bytes += (size_t)glstate->helper_texlen[i] * 4u * sizeof(GLfloat);
        tex_helper_bytes += (size_t)glstate->texgenedsz[i] * 4u * sizeof(GLfloat);
    }
    if (tex_helper_bytes > 0 && (urgency >= 1 || tex_helper_bytes > gl_cap)) {
        for (int i = 0; i < MAX_TEX; ++i) {
            if (glstate->helper_tex[i]) {
                free(glstate->helper_tex[i]);
                glstate->helper_tex[i] = NULL;
            }
            glstate->helper_texlen[i] = 0;
            if (glstate->texgened[i]) {
                free(glstate->texgened[i]);
                glstate->texgened[i] = NULL;
            }
            glstate->texgenedsz[i] = 0;
        }
        gl4es_mem_track_scratch(tex_helper_bytes, 0);
    }

    if (glstate->scratch_indices && (urgency >= 1 || (size_t)glstate->scratch_indices_size > gl_cap)) {
        deleteSingleBuffer(glstate->scratch_indices);
        glstate->scratch_indices = 0;
        glstate->scratch_indices_size = 0;
    }

    if (glstate->scratch_vertex && (urgency >= 1 || (size_t)glstate->scratch_vertex_size > gl_cap)) {
        if (!is_scratch_vertex_locked()) {
            deleteSingleBuffer(glstate->scratch_vertex);
            glstate->scratch_vertex = 0;
            glstate->scratch_vertex_size = 0;
        }
    }

    gl4es_mem_trim_merger(urgency);
}
