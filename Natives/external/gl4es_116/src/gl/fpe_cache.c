#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../glx/hardext.h"
#include "init.h"
#include "logs.h"
#include "debug.h"
#include "program.h"
#include "fpe_cache.h"
#include "fpe.h"
#include "gl4es.h"
#include "glstate.h"
#include "fpe_shader.h"
#include "shaderconv.h"
#include "loader.h"
#if defined(__APPLE__)
#include <pthread.h>
#include <time.h>
#define PSA_BG_SAVE 1
#define PSA_LD(x)    __atomic_load_n(&(x), __ATOMIC_ACQUIRE)
#define PSA_ST(x,v)  __atomic_store_n(&(x), (v), __ATOMIC_RELEASE)
#ifndef PSA_SAVE_INTERVAL
#define PSA_SAVE_INTERVAL 15.0
#endif
#endif

//#define DEBUG
#ifdef DEBUG
#pragma GCC optimize 0
#define DBG(a) a
#else
#define DBG(a)
#endif

static const char PSA_SIGN[] = "GL4ES PrecompiledShaderArchive";
#define CACHE_VERSION 115

static kh_inline uint64_t _hash_fpe(fpe_state_t *p)
{
    const unsigned char* s = (const unsigned char*)p;
    uint64_t h = 1469598103934665603ULL;
    size_t i = 0;
    for (; i+8<=sizeof(fpe_state_t); i+=8) {
        uint64_t w;
        memcpy(&w, s+i, 8);
        h = (h ^ w) * 1099511628211ULL;
        h ^= h >> 29;
    }
    for (; i<sizeof(fpe_state_t); ++i)
        h = (h ^ s[i]) * 1099511628211ULL;
    return h;
}

static kh_inline khint_t _hash_fpe_kh(fpe_state_t *p)
{
    uint64_t h = _hash_fpe(p);
    return (khint_t)(h ^ (h >> 32));
}

#define kh_fpe_hash_func(key) _hash_fpe_kh(key)

#define kh_fpe_hash_equal(a, b) (memcmp(a, b, sizeof(fpe_state_t)) == 0)

#define KHASH_MAP_INIT_FPE(name, khval_t)								\
	KHASH_INIT(name, kh_fpe_t, khval_t, 1, kh_fpe_hash_func, kh_fpe_hash_equal)

KHASH_MAP_INIT_FPE(fpecachelist, fpe_fpe_t *);

static kh_inline khint_t kh_get_fpecachelist_hash(const kh_fpecachelist_t *h, kh_fpe_t key, khint_t hash_val)
{
    if (h && h->n_buckets) {
        khint_t i, last, mask, step = 0;
        mask = h->n_buckets - 1;
        i = hash_val & mask;
        last = i;
        while (!__ac_isempty(h->flags, i) && (__ac_isdel(h->flags, i) || !kh_fpe_hash_equal(h->keys[i], key))) {
            i = (i + (++step)) & mask;
            if (i == last) return h->n_buckets;
        }
        return __ac_iseither(h->flags, i) ? h->n_buckets : i;
    } else return 0;
}

// ********* Cache handling *********

typedef struct fpe_lru_node_s {
    fpe_fpe_t               entry;
    struct fpe_lru_node_s  *lru_prev;
    struct fpe_lru_node_s  *lru_next;
} fpe_lru_node_t;

static fpe_cache_t *g_fpe_caches_head = NULL;
static size_t g_fpe_total_entries = 0;

static void fpe_lru_push_front(fpe_cache_t *cur, fpe_lru_node_t *node) {
    node->lru_prev = NULL;
    node->lru_next = cur->lru_head;
    if (cur->lru_head)
        cur->lru_head->lru_prev = node;
    else
        cur->lru_tail = node;
    cur->lru_head = node;
}

static void fpe_lru_unlink(fpe_cache_t *cur, fpe_lru_node_t *node) {
    if (node->lru_prev)
        node->lru_prev->lru_next = node->lru_next;
    else if (cur->lru_head == node)
        cur->lru_head = node->lru_next;
    if (node->lru_next)
        node->lru_next->lru_prev = node->lru_prev;
    else if (cur->lru_tail == node)
        cur->lru_tail = node->lru_prev;
    node->lru_prev = NULL;
    node->lru_next = NULL;
}

static void fpe_lru_touch(fpe_cache_t *cur, fpe_lru_node_t *node) {
    if (!cur || !node || cur->lru_head == node)
        return;
    fpe_lru_unlink(cur, node);
    fpe_lru_push_front(cur, node);
}

static void fpe_mru_remove(fpe_cache_t *cur, const fpe_fpe_t *entry) {
    if (!cur || !entry) return;
    int dst = 0;
    for (int i = 0; i < cur->mru_count; ++i) {
        if (cur->mru[i] != entry)
            cur->mru[dst++] = cur->mru[i];
    }
    for (int i = dst; i < FPE_MRU_SIZE; ++i)
        cur->mru[i] = NULL;
    cur->mru_count = dst;
}

static void fpe_mru_promote(fpe_cache_t *cur, fpe_fpe_t *entry) {
    int limit = (cur->mru_count < FPE_MRU_SIZE) ? cur->mru_count : (FPE_MRU_SIZE - 1);
    for (int j = limit; j > 0; --j) {
        cur->mru[j] = cur->mru[j - 1];
    }
    cur->mru[0] = entry;
    if (cur->mru_count < FPE_MRU_SIZE)
        cur->mru_count++;
}

static int fpe_is_protected(const fpe_fpe_t *e) {
    if (!glstate || !e)
        return 0;
    if (e == glstate->fpe)
        return 1;
    if (glstate->gleshard) {
        if (e->glprogram && e->glprogram == glstate->gleshard->glprogram)
            return 1;
        if (e->prog && e->prog == glstate->gleshard->program)
            return 1;
    }
    return 0;
}

static size_t fpe_owner_total_entries(const struct glsl_s *owner_glsl) {
    size_t total = 0;
    for (fpe_cache_t *cache = g_fpe_caches_head; cache; cache = cache->cache_next) {
        if (cache->owner_glsl == owner_glsl)
            total += cache->count;
    }
    return total;
}

static void fpe_evict_node(fpe_cache_t *cur, fpe_lru_node_t *node, int freeprog) {
    if (!cur || !node) return;
    fpe_fpe_t *victim = &node->entry;

    fpe_lru_unlink(cur, node);
    if (cur->count > 0) cur->count--;
    if (g_fpe_total_entries > 0) g_fpe_total_entries--;
    gl4es_mem_set_fpe_cache_entries(g_fpe_total_entries);

    fpe_mru_remove(cur, victim);

    if (cur->map) {
        khint_t hv = victim->hash ? (khint_t)(victim->hash ^ (victim->hash >> 32))
                                  : _hash_fpe_kh(&victim->state);
        khint_t vk = kh_get_fpecachelist_hash(cur->map, &victim->state, hv);
        if (vk != kh_end(cur->map))
            kh_del(fpecachelist, cur->map, vk);
    }

    if (freeprog && glstate && glstate->glsl &&
        (!cur->owner_glsl || cur->owner_glsl == glstate->glsl)) {
        if (glstate->fpe == victim)
            glstate->fpe = NULL;
        if (glstate->gleshard) {
            if ((victim->glprogram && glstate->gleshard->glprogram == victim->glprogram) ||
                (victim->prog && glstate->gleshard->program == victim->prog)) {
                glstate->gleshard->program = 0;
                glstate->gleshard->glprogram = NULL;
            }
        }
        if (victim->prog && glstate->glsl->programs) {
            khint_t pk = kh_get(programlist, glstate->glsl->programs, victim->prog);
            if (pk != kh_end(glstate->glsl->programs))
                gl4es_glDeleteProgram(victim->prog);
        }
        if (victim->vert && glstate->glsl->shaders) {
            khint_t sk = kh_get(shaderlist, glstate->glsl->shaders, victim->vert);
            if (sk != kh_end(glstate->glsl->shaders))
                gl4es_glDeleteShader(victim->vert);
        }
        if (victim->frag && glstate->glsl->shaders) {
            khint_t sk = kh_get(shaderlist, glstate->glsl->shaders, victim->frag);
            if (sk != kh_end(glstate->glsl->shaders))
                gl4es_glDeleteShader(victim->frag);
        }
    }

    free(node);
}

fpe_cache_t* fpe_NewCache(void) {
    fpe_cache_t *cache = (fpe_cache_t*)calloc(1, sizeof(fpe_cache_t));
    if (cache) {
        cache->map = kh_init(fpecachelist);
        if (!cache->map) {
            free(cache);
            return NULL;
        }
        cache->owner_glsl = glstate ? glstate->glsl : NULL;
        cache->cache_prev = NULL;
        cache->cache_next = g_fpe_caches_head;
        if (g_fpe_caches_head)
            g_fpe_caches_head->cache_prev = cache;
        g_fpe_caches_head = cache;
    }
    return cache;
}

void fpe_disposeCache(fpe_cache_t* cache, int freeprog) {
    if(!cache) return;
    if (cache->cache_prev)
        cache->cache_prev->cache_next = cache->cache_next;
    else if (g_fpe_caches_head == cache)
        g_fpe_caches_head = cache->cache_next;
    if (cache->cache_next)
        cache->cache_next->cache_prev = cache->cache_prev;
    cache->cache_prev = NULL;
    cache->cache_next = NULL;

    if (freeprog && glstate && glstate->list.pending && !glstate->list.begin && !glstate->list.compiling)
        gl4es_flush();

    while (cache->lru_head) {
        fpe_evict_node(cache, cache->lru_head, freeprog);
    }
    if(cache->map) {
        kh_destroy(fpecachelist, cache->map);
        cache->map = NULL;
    }
    free(cache);
}

fpe_fpe_t *fpe_GetCache(fpe_cache_t *cur, fpe_state_t *state, int fixed) {
    (void)fixed;
    if(!cur || !state || !cur->map) return NULL;
    if (!cur->owner_glsl && glstate)
        cur->owner_glsl = glstate->glsl;

    uint64_t key_hash = _hash_fpe(state);

    for(int i = 0; i < cur->mru_count; ++i) {
        fpe_fpe_t *entry = cur->mru[i];
        if(entry && entry->hash == key_hash && memcmp(&entry->state, state, sizeof(fpe_state_t)) == 0) {
            if(i > 0) {
                for(int j = i; j > 0; --j) {
                    cur->mru[j] = cur->mru[j-1];
                }
                cur->mru[0] = entry;
            }
            fpe_lru_touch(cur, (fpe_lru_node_t*)entry);
            return entry;
        }
    }

    khint_t hash_val = (khint_t)(key_hash ^ (key_hash >> 32));
    khint_t k = kh_get_fpecachelist_hash(cur->map, state, hash_val);
    fpe_fpe_t *result = NULL;
    if(k != kh_end(cur->map)) {
        result = kh_value(cur->map, k);
        if(!result->hash)
            result->hash = key_hash;
        fpe_lru_touch(cur, (fpe_lru_node_t*)result);
    } else {
        size_t max_entries = gl4es_mem_fpe_cache_max_entries();
        if (max_entries == 0) max_entries = 1;
        if (!glstate || !glstate->list.pending) {
            size_t owner_total = fpe_owner_total_entries(cur->owner_glsl);
            fpe_lru_node_t *cand = cur->lru_tail;
            while (owner_total >= max_entries && cand) {
                fpe_lru_node_t *prev = cand->lru_prev;
                if (!fpe_is_protected(&cand->entry)) {
                    fpe_evict_node(cur, cand, 1);
                    if (owner_total > 0) owner_total--;
                }
                cand = prev;
            }
            if (owner_total >= max_entries) {
                for (fpe_cache_t *sib = g_fpe_caches_head; sib && owner_total >= max_entries; sib = sib->cache_next) {
                    if (sib == cur || sib->owner_glsl != cur->owner_glsl)
                        continue;
                    cand = sib->lru_tail;
                    while (owner_total >= max_entries && cand) {
                        fpe_lru_node_t *prev = cand->lru_prev;
                        if (!fpe_is_protected(&cand->entry)) {
                            fpe_evict_node(sib, cand, 1);
                            if (owner_total > 0) owner_total--;
                        }
                        cand = prev;
                    }
                }
            }
        }
        fpe_lru_node_t *node = (fpe_lru_node_t*)calloc(1, sizeof(fpe_lru_node_t));
        if(!node) return NULL;
        result = &node->entry;
        result->hash = key_hash;
        memcpy(&result->state, state, sizeof(fpe_state_t));
        int r = 0;
        k = kh_put(fpecachelist, cur->map, &result->state, &r);
        if (r < 0 || k == kh_end(cur->map)) {
            free(node);
            return NULL;
        }
        kh_value(cur->map, k) = result;
        fpe_lru_push_front(cur, node);
        cur->count++;
        g_fpe_total_entries++;
        gl4es_mem_set_fpe_cache_entries(g_fpe_total_entries);
    }

    fpe_mru_promote(cur, result);
    return result;
}

void fpe_CacheTrim(int urgency) {
    if (!glstate || !glstate->glsl || glstate->list.pending)
        return;
    size_t max_e = gl4es_mem_fpe_cache_max_entries();
    size_t target = (urgency <= 0) ? max_e : ((urgency == 1) ? (max_e / 2) : 0);
    size_t total = fpe_owner_total_entries(glstate->glsl);

    for (fpe_cache_t *cache = g_fpe_caches_head; cache && total > target; cache = cache->cache_next) {
        if (cache->owner_glsl != glstate->glsl)
            continue;
        fpe_lru_node_t *cand = cache->lru_tail;
        while (total > target && cand) {
            fpe_lru_node_t *prev = cand->lru_prev;
            if (!fpe_is_protected(&cand->entry)) {
                fpe_evict_node(cache, cand, 1);
                if (total > 0) total--;
            }
            cand = prev;
        }
    }
}

typedef struct psa_s {
    fpe_state_t state;
    GLenum      format;
    int         size;
    void*       prog;
    struct psa_s *dead_next;
    struct psa_s *lru_prev;
    struct psa_s *lru_next;
} psa_t;

KHASH_MAP_INIT_FPE(psalist, psa_t *);

// Precompiled Shader Archive
typedef struct gl4es_psa_s {
    int             size;
    int             dirty;
    kh_psalist_t*   cache;
    psa_t*          lru_head;
    psa_t*          lru_tail;
    size_t          total_bytes;
#ifdef PSA_BG_SAVE
    volatile int    busy;
    int             thread_valid;
    pthread_t       thread;
    double          last_save;
    psa_t*          dead;
#endif
} gl4es_psa_t;

static gl4es_psa_t *psa = NULL;
static char *psa_name = NULL;

#define PSA_MAX_ENTRIES     65536
#define PSA_MAX_PROG_SIZE   (8*1024*1024)

static void psa_lru_push_front(psa_t *p) {
    if (!psa || !p) return;
    p->lru_prev = NULL;
    p->lru_next = psa->lru_head;
    if (psa->lru_head)
        psa->lru_head->lru_prev = p;
    else
        psa->lru_tail = p;
    psa->lru_head = p;
}

static void psa_lru_unlink(psa_t *p) {
    if (!psa || !p) return;
    if (p->lru_prev)
        p->lru_prev->lru_next = p->lru_next;
    else if (psa->lru_head == p)
        psa->lru_head = p->lru_next;
    if (p->lru_next)
        p->lru_next->lru_prev = p->lru_prev;
    else if (psa->lru_tail == p)
        psa->lru_tail = p->lru_prev;
    p->lru_prev = NULL;
    p->lru_next = NULL;
}

static void psa_lru_touch(psa_t *p) {
    if (!psa || !p || psa->lru_head == p)
        return;
    psa_lru_unlink(p);
    psa_lru_push_front(p);
}

static void psa_retire_locked(psa_t *victim) {
    if (!psa || !victim) return;
    psa_lru_unlink(victim);
    size_t entry_bytes = sizeof(psa_t) + (size_t)(victim->size > 0 ? victim->size : 0);
    psa->total_bytes = (psa->total_bytes >= entry_bytes) ? (psa->total_bytes - entry_bytes) : 0;

    if (psa->cache) {
        khint_t vk = kh_get(psalist, psa->cache, &victim->state);
        if (vk != kh_end(psa->cache))
            kh_del(psalist, psa->cache, vk);
    }

#ifdef PSA_BG_SAVE
    if (PSA_LD(psa->busy)) {
        victim->dead_next = psa->dead;
        psa->dead = victim;
        return;
    }
#endif
    free(victim->prog);
    free(victim);
}

static uint64_t psa_fnv(uint64_t h, const char* s)
{
    if(!s) s = "";
    while(*s)
        h = (h ^ (unsigned char)*s++) * 1099511628211ULL;
    return (h ^ 0xFF) * 1099511628211ULL;
}

static uint64_t psa_identity(void)
{
    LOAD_GLES(glGetString);
    if(!gles_glGetString)
        return 0;
    const char *vendor = (const char*)gles_glGetString(GL_VENDOR);
    const char *renderer = (const char*)gles_glGetString(GL_RENDERER);
    const char *version = (const char*)gles_glGetString(GL_VERSION);
    if(!vendor && !renderer && !version)
        return 0;
    char tmp[64];
    snprintf(tmp, sizeof(tmp), "es%d/bin%d/%zu", hardext.esversion, hardext.prgbin_n, sizeof(fpe_state_t));
    uint64_t h = 1469598103934665603ULL;
    h = psa_fnv(h, vendor);
    h = psa_fnv(h, renderer);
    h = psa_fnv(h, version);
    h = psa_fnv(h, tmp);
    h = psa_fnv(h, fpe_shader_build_stamp());
    h = psa_fnv(h, shaderconv_build_stamp());
    h = psa_fnv(h, __DATE__ " " __TIME__);
    return h?h:1;
}

static uint64_t psa_id = 0;

void fpe_readPSA(void)
{
    if(!psa || !psa_name || !psa->cache)
        return;
    FILE *f = fopen(psa_name, "rb");
    if(!f)
        return;
    char tmp[sizeof(PSA_SIGN)];
    if(fread(tmp, sizeof(PSA_SIGN), 1, f)!=1) {
        fclose(f);
        return; //to short
    }
    if(memcmp(tmp, PSA_SIGN, sizeof(PSA_SIGN))!=0) {
        fclose(f);
        return; // bad signature
    }
    int version = 0;
    if(fread(&version, sizeof(version), 1, f)!=1) {
        fclose(f);
        return;
    }
    if(version!=CACHE_VERSION) {
        fclose(f);
        return; // unsupported version
    }
    int sz_fpe = 0;
    if(fread(&sz_fpe, sizeof(sz_fpe), 1, f)!=1) {
        fclose(f);
        return;
    }
    if(sz_fpe!=sizeof(fpe_state_t)) {
        fclose(f);
        return; // maybe try to adapt instead?
    }
    uint64_t id = 0;
    if(fread(&id, sizeof(id), 1, f)!=1 || id!=psa_id) {
        fclose(f);
        SHUT_LOGD("Ignoring PSA: written by a different GLES backend / GL4ES build\n");
        return;
    }
    int n = 0;
    if(fread(&n, sizeof(n), 1, f)!=1 || n<0 || n>PSA_MAX_ENTRIES) {
        fclose(f);
        return;
    }
    size_t max_entries = gl4es_mem_psa_max_entries();
    size_t max_bytes = gl4es_mem_psa_max_bytes();
    for (int i=0; i<n; ++i) {
        if ((size_t)kh_size(psa->cache) >= max_entries)
            break;
        psa_t *p = (psa_t*)calloc(1, sizeof(psa_t));
        if(!p)
            break;
        if(fread(&p->state, sizeof(p->state), 1, f)!=1
        || fread(&p->format, sizeof(p->format), 1, f)!=1
        || fread(&p->size, sizeof(p->size), 1, f)!=1
        || p->size<=0 || p->size>PSA_MAX_PROG_SIZE) {
            free(p);
            break;
        }
        size_t entry_bytes = sizeof(psa_t) + (size_t)p->size;
        if (psa->total_bytes + entry_bytes > max_bytes) {
            free(p);
            break;
        }
        p->prog = malloc(p->size);
        if(!p->prog || fread(p->prog, p->size, 1, f)!=1) {
            free(p->prog);
            free(p);
            break;
        }
        int ret;
        khint_t k = kh_put(psalist, psa->cache, &p->state, &ret);
        if(ret <= 0 || k == kh_end(psa->cache)) {
            free(p->prog);
            free(p);
            continue;
        }
        kh_value(psa->cache, k) = p;
        psa_lru_push_front(p);
        psa->total_bytes += entry_bytes;
    }
    fclose(f);
    psa->size = (int)kh_size(psa->cache);
    gl4es_mem_set_psa_stats((size_t)psa->size, psa->total_bytes);
    SHUT_LOGD("Loaded a PSA with %d Precompiled Programs\n", psa->size);
}

static int psa_write_file(psa_t* const* list, int count)
{
    size_t nlen = strlen(psa_name);
    char *tmpname = (char*)malloc(nlen + 5);
    if(!tmpname)
        return 0;
    memcpy(tmpname, psa_name, nlen);
    memcpy(tmpname+nlen, ".tmp", 5);
    FILE *f = fopen(tmpname, "wb");
    if(!f) {
        free(tmpname);
        return 0;
    }
    int version = CACHE_VERSION;
    int sz_fpe = sizeof(fpe_state_t);
    int ok = fwrite(PSA_SIGN, sizeof(PSA_SIGN), 1, f)==1
          && fwrite(&version, sizeof(version), 1, f)==1
          && fwrite(&sz_fpe, sizeof(sz_fpe), 1, f)==1
          && fwrite(&psa_id, sizeof(psa_id), 1, f)==1
          && fwrite(&count, sizeof(count), 1, f)==1;
    for(int i=0; ok && i<count; ++i) {
        const psa_t *p = list[i];
        ok = fwrite(&p->state, sizeof(p->state), 1, f)==1
          && fwrite(&p->format, sizeof(p->format), 1, f)==1
          && fwrite(&p->size, sizeof(p->size), 1, f)==1
          && fwrite(p->prog, p->size, 1, f)==1;
    }
    ok = (fclose(f)==0) && ok;
    ok = ok && rename(tmpname, psa_name)==0;
    if(ok) {
        SHUT_LOGD("Saved a PSA with %d Precompiled Programs\n", count);
    } else {
        remove(tmpname);
    }
    free(tmpname);
    return ok;
}

static psa_t** psa_snapshot(int *count)
{
    if(!psa || !psa->cache || !count)
        return NULL;
    int n = (int)kh_size(psa->cache);
    psa_t **list = (psa_t**)malloc((n?n:1)*sizeof(psa_t*));
    if(!list)
        return NULL;
    int i = 0;
    psa_t *p;
    kh_foreach_value(psa->cache, p, if(i<n) list[i++] = p;);
    *count = i;
    return list;
}

#ifdef PSA_BG_SAVE
static pthread_mutex_t psa_lock = PTHREAD_MUTEX_INITIALIZER;

typedef struct psa_job_s {
    psa_t **list;
    int     count;
} psa_job_t;

static double psa_now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec*1e-9;
}

static void* psa_writer(void *arg)
{
    psa_job_t *job = (psa_job_t*)arg;
    int ok = psa_write_file(job->list, job->count);
    free(job->list);
    free(job);
    pthread_mutex_lock(&psa_lock);
    if(!ok)
        PSA_ST(psa->dirty, 1);
    psa_t *d = psa->dead;
    psa->dead = NULL;
    PSA_ST(psa->busy, 0);
    pthread_mutex_unlock(&psa_lock);
    while(d) {
        psa_t *n = d->dead_next;
        free(d->prog);
        free(d);
        d = n;
    }
    return NULL;
}

static void psa_join(void)
{
    if(psa && psa->thread_valid) {
        pthread_join(psa->thread, NULL);
        psa->thread_valid = 0;
    }
}
#endif

void fpe_PSATick(void)
{
#ifdef PSA_BG_SAVE
    if(!psa || !PSA_LD(psa->dirty) || PSA_LD(psa->busy))
        return;
    double now = psa_now();
    if(now - psa->last_save < PSA_SAVE_INTERVAL)
        return;
    psa->last_save = now;
    psa_join();
    psa_job_t *job = (psa_job_t*)malloc(sizeof(psa_job_t));
    if(!job)
        return;
    pthread_mutex_lock(&psa_lock);
    job->list = psa_snapshot(&job->count);
    if(!job->list) {
        pthread_mutex_unlock(&psa_lock);
        free(job);
        return;
    }
    PSA_ST(psa->dirty, 0);
    PSA_ST(psa->busy, 1);
    pthread_mutex_unlock(&psa_lock);
    if(pthread_create(&psa->thread, NULL, psa_writer, job)==0) {
        psa->thread_valid = 1;
    } else {
        free(job->list);
        free(job);
        pthread_mutex_lock(&psa_lock);
        PSA_ST(psa->busy, 0);
        PSA_ST(psa->dirty, 1);
        pthread_mutex_unlock(&psa_lock);
    }
#endif
}

void fpe_writePSA(void)
{
    if(!psa || !psa_name)
        return;
#ifdef PSA_BG_SAVE
    psa_join();
#endif
    if(!psa->dirty)
        return; // no need
    int count = 0;
    psa_t **list = psa_snapshot(&count);
    if(!list)
        return;
    if(psa_write_file(list, count))
        psa->dirty = 0;
    free(list);
}

void fpe_InitPSA(const char* name)
{
    if(psa)
        return; // already inited
    psa_id = psa_identity();
    if(!psa_id) {
        SHUT_LOGD("Not using PSA: cannot identify GLES backend\n");
        return;
    }
    psa = (gl4es_psa_t*)calloc(1, sizeof(gl4es_psa_t));
    if(!psa)
        return;
    psa->cache = kh_init(psalist);
    if(!psa->cache) {
        free(psa);
        psa = NULL;
        return;
    }
    psa_name = name?strdup(name):NULL;
    if(!psa_name) {
        kh_destroy(psalist, psa->cache);
        free(psa);
        psa = NULL;
        return;
    }
#ifdef PSA_BG_SAVE
    psa->last_save = psa_now();
#endif
}

void fpe_FreePSA(void)
{
#ifdef PSA_BG_SAVE
    psa_join();
#endif
    if(!psa)
        return; // nothing to init
    
    psa_t *m;
    if(psa->cache) {
        kh_foreach_value(psa->cache, m, 
            free(m->prog);
            free(m);
        )
        kh_destroy(psalist, psa->cache);
    }
#ifdef PSA_BG_SAVE
    {
        psa_t *d = psa->dead;
        while(d) {
            psa_t *n = d->dead_next;
            free(d->prog);
            free(d);
            d = n;
        }
    }
#endif

    free(psa);
    psa = NULL;
    free(psa_name);
    psa_name = NULL;
    gl4es_mem_set_psa_stats(0, 0);
}

int fpe_GetProgramPSA(GLuint program, fpe_state_t* state)
{
    if(!psa || !psa->cache)
        return 0;
    // if state contains custom vertex of fragment shader, then ignore
    if(state->vertex_prg_enable || state->fragment_prg_enable)
        return 0;
    khint_t k = kh_get(psalist, psa->cache, state);
    if(k==kh_end(psa->cache))
        return 0; // not here
    psa_t *p = kh_value(psa->cache, k);
    psa_lru_touch(p);
    // try to load...
    return gl4es_useProgramBinary(program, p->size, p->format, p->prog);
}

void fpe_AddProgramPSA(GLuint program, fpe_state_t* state)
{
    if(!psa || !psa->cache)
        return;
    // if state contains custom vertex of fragment shader, then ignore
    if(state->vertex_prg_enable || state->fragment_prg_enable)
        return;
    size_t max_entries = gl4es_mem_psa_max_entries();
    size_t max_bytes = gl4es_mem_psa_max_bytes();
    if (max_entries == 0 || max_bytes <= sizeof(psa_t))
        return;
    psa_t *p = (psa_t*)calloc(1, sizeof(psa_t));
    if(!p)
        return;
    memcpy(&p->state, state, sizeof(p->state));

    int l = gl4es_getProgramBinary(program, &p->size, &p->format, &p->prog);
    if(l==0 || p->size<=0 || p->size>PSA_MAX_PROG_SIZE) { // there was an error...
        free(p->prog);
        free(p);
        return;
    }
    size_t entry_bytes = sizeof(psa_t) + (size_t)p->size;
    if (entry_bytes > max_bytes) {
        free(p->prog);
        free(p);
        return;
    }
    // add program
#ifdef PSA_BG_SAVE
    pthread_mutex_lock(&psa_lock);
#endif
    khint_t existing = kh_get(psalist, psa->cache, &p->state);
    if (existing != kh_end(psa->cache)) {
        psa_retire_locked(kh_value(psa->cache, existing));
    }
    int ret = 0;
    khint_t k = kh_put(psalist, psa->cache, &p->state, &ret);
    if (ret <= 0 || k == kh_end(psa->cache)) {
#ifdef PSA_BG_SAVE
        pthread_mutex_unlock(&psa_lock);
#endif
        free(p->prog);
        free(p);
        return;
    }
    kh_key(psa->cache, k) = &p->state;
    kh_value(psa->cache, k) = p;
    psa_lru_push_front(p);
    psa->total_bytes += entry_bytes;

    while ((size_t)kh_size(psa->cache) > max_entries || psa->total_bytes > max_bytes) {
        psa_t *victim = psa->lru_tail;
        if (!victim || victim == p)
            break;
        psa_retire_locked(victim);
    }

    psa->size = (int)kh_size(psa->cache);
    gl4es_mem_set_psa_stats((size_t)psa->size, psa->total_bytes);
#ifdef PSA_BG_SAVE
    PSA_ST(psa->dirty, 1);
    pthread_mutex_unlock(&psa_lock);
#else
    psa->dirty = 1;
#endif
}

void fpe_PSATrim(int urgency)
{
    if(!psa || !psa->cache)
        return;
    size_t max_e = gl4es_mem_psa_max_entries();
    size_t max_b = gl4es_mem_psa_max_bytes();
    if (urgency == 1) {
        max_e /= 2;
        max_b /= 2;
    } else if (urgency >= 2) {
        max_e = 0;
        max_b = 0;
    }
#ifdef PSA_BG_SAVE
    pthread_mutex_lock(&psa_lock);
#endif
    while (psa->lru_tail && ((size_t)kh_size(psa->cache) > max_e || psa->total_bytes > max_b)) {
        psa_retire_locked(psa->lru_tail);
    }
    psa->size = (int)kh_size(psa->cache);
    gl4es_mem_set_psa_stats((size_t)psa->size, psa->total_bytes);
#ifdef PSA_BG_SAVE
    pthread_mutex_unlock(&psa_lock);
#endif
}
