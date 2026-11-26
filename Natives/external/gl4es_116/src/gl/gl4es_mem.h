#ifndef _GL4ES_MEM_H_
#define _GL4ES_MEM_H_

#include <stddef.h>
#include <stdint.h>

#if defined(__EMSCRIPTEN__) || defined(STATICLIB)
#define GL4ES_MEM_EXPORT
#elif defined(_WIN32) || defined(__CYGWIN__)
#define GL4ES_MEM_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
#define GL4ES_MEM_EXPORT __attribute__((visibility("default")))
#else
#define GL4ES_MEM_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    GL4ES_MEM_PROFILE_LOW = 0,
    GL4ES_MEM_PROFILE_MEDIUM = 1,
    GL4ES_MEM_PROFILE_HIGH = 2
} gl4es_mem_profile_t;

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
    size_t fpe_cache_entries;
    size_t psa_entries;
    size_t psa_bytes;
    size_t current_scratch_bytes;
    size_t peak_scratch_bytes;
    size_t shadow_cpu_bytes;
    size_t displaylist_cpu_bytes;
    unsigned long trim_count;
} gl4es_mem_stats_t;

GL4ES_MEM_EXPORT void gl4es_trim_memory(int urgency);
GL4ES_MEM_EXPORT void gl4es_get_mem_stats(gl4es_mem_stats_t *out);

/* Internal lifecycle & budget helpers (M1/M2) */
void gl4es_mem_init(void);
void gl4es_mem_mark_initialized(void);
void gl4es_mem_pre_shutdown(void);
void gl4es_mem_shutdown(void);
void gl4es_mem_drain_pending_trim(void);

int gl4es_mem_profile(void);
size_t gl4es_mem_budget_bytes(void);
size_t gl4es_mem_texture_scratch_cap(void);
size_t gl4es_mem_color_scratch_cap(void);
size_t gl4es_mem_gl_scratch_cap(void);
size_t gl4es_mem_merger_cap(void);
size_t gl4es_mem_fpe_cache_max_entries(void);
size_t gl4es_mem_psa_max_entries(void);
size_t gl4es_mem_psa_max_bytes(void);

void gl4es_mem_track_scratch(size_t old_bytes, size_t new_bytes);
void gl4es_mem_track_shadow(size_t old_bytes, size_t new_bytes);
void gl4es_mem_track_displaylist(size_t old_bytes, size_t new_bytes);
size_t gl4es_mem_shadow_cpu_bytes(void);
size_t gl4es_mem_displaylist_cpu_bytes(void);
void gl4es_mem_set_fpe_cache_entries(size_t n);
void gl4es_mem_set_psa_stats(size_t entries, size_t bytes);

void *gl4es_mem_acquire_color_scratch(int sidx, size_t needed);
float *gl4es_mem_acquire_texgened(int tmu, int len);
void *gl4es_mem_acquire_helper_tex(int tmu, int len);
int gl4es_mem_prepare_quad_indices(int first, int count,
                                   const unsigned short **out_indices,
                                   unsigned short **out_transient_to_free);

/* Subsystem trim & metadata hooks */
void gl4es_mem_trim_scratch_pools(int urgency);
void gl4es_mem_trim_buffers(int urgency);
void gl4es_mem_trim_displaylists(int urgency);
struct glstate_s;
void gl4es_mem_trim_merger(int urgency);
int gl4es_mem_merger_at_cap(void);
void gl4es_mem_list_shutdown(void);
void gl4es_mem_sync_merger_bytes(void);
void gl4es_mem_reset_merger_bytes(void);
void gl4es_mem_reset_merger_bytes_for(struct glstate_s *state);

struct _renderlist_t;
int gl4es_merger_alloc_opt_buffer(struct _renderlist_t *list, float **slot);
void gl4es_list_set_vbo_mask(struct _renderlist_t *list, uint32_t mask);
uint32_t gl4es_list_get_vbo_mask(const struct _renderlist_t *list);
int gl4es_list_is_arrays_trimmed(const struct _renderlist_t *list);
int gl4es_list_is_indices_trimmed(const struct _renderlist_t *list);
void gl4es_list_sync_cpu_bytes(struct _renderlist_t *list);
void gl4es_list_sync_chain_cpu_bytes(struct _renderlist_t *list);

#ifdef __cplusplus
}
#endif

#endif /* _GL4ES_MEM_H_ */
