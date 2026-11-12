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
#define CACHE_VERSION 114

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

// ********* Cache handling *********

fpe_cache_t* fpe_NewCache() {
    fpe_cache_t *cache = (fpe_cache_t*)calloc(1, sizeof(fpe_cache_t));
    if (cache) {
        cache->map = kh_init(fpecachelist);
        if (!cache->map) {
            free(cache);
            return NULL;
        }
    }
    return cache;
}

void fpe_disposeCache(fpe_cache_t* cache, int freeprog) {
    if(!cache) return;
    if(cache->map) {
        fpe_fpe_t *m;
        kh_foreach_value(cache->map, m, 
            if(freeprog) {
                if(m->glprogram)
                    gl4es_glDeleteProgram(m->glprogram->id);
            }
            free(m);
        )
        kh_destroy(fpecachelist, cache->map);
    }
    free(cache);
}

fpe_fpe_t *fpe_GetCache(fpe_cache_t *cur, fpe_state_t *state, int fixed) {
    if(!cur || !state || !cur->map) return NULL;

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
            return entry;
        }
    }

    khint_t k = kh_get(fpecachelist, cur->map, state);
    fpe_fpe_t *result = NULL;
    if(k != kh_end(cur->map)) {
        result = kh_value(cur->map, k);
        if(!result->hash)
            result->hash = key_hash;
    } else {
        result = (fpe_fpe_t*)calloc(1, sizeof(fpe_fpe_t));
        if(!result) return NULL;
        result->hash = key_hash;
        memcpy(&result->state, state, sizeof(fpe_state_t));
        int r;
        k = kh_put(fpecachelist, cur->map, &result->state, &r);
        kh_value(cur->map, k) = result;
    }

    int shift_limit = (cur->mru_count < FPE_MRU_SIZE) ? cur->mru_count : (FPE_MRU_SIZE - 1);
    for(int j = shift_limit; j > 0; --j) {
        cur->mru[j] = cur->mru[j-1];
    }
    cur->mru[0] = result;
    if(cur->mru_count < FPE_MRU_SIZE) {
        cur->mru_count++;
    }

    return result;
}

typedef struct psa_s {
    fpe_state_t state;
    GLenum      format;
    int         size;
    void*       prog;
    struct psa_s *dead_next;
} psa_t;

KHASH_MAP_INIT_FPE(psalist, psa_t *);

// Precompiled Shader Archive
typedef struct gl4es_psa_s {
    int             size;
    int             dirty;
    kh_psalist_t*   cache;    
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

void fpe_readPSA()
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
    for (int i=0; i<n; ++i) {
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
        p->prog = malloc(p->size);
        if(!p->prog || fread(p->prog, p->size, 1, f)!=1) {
            free(p->prog);
            free(p);
            break;
        }
        int ret;
        khint_t k = kh_put(psalist, psa->cache, &p->state, &ret);
        if(!ret) {
            free(p->prog);
            free(p);
            continue;
        }
        kh_value(psa->cache, k) = p;
    }
    fclose(f);
    psa->size = kh_size(psa->cache);
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

void fpe_PSATick()
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

void fpe_writePSA()
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

void fpe_FreePSA()
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
    psa_t *p = (psa_t*)calloc(1, sizeof(psa_t));
    if(!p)
        return;
    memcpy(&p->state, state, sizeof(p->state));

    int l = gl4es_getProgramBinary(program, &p->size, &p->format, &p->prog);
    if(l==0) { // there was an error...
        free(p->prog);
        free(p);
        return;
    }
    // add program
#ifdef PSA_BG_SAVE
    pthread_mutex_lock(&psa_lock);
#endif
    int ret;
    khint_t k = kh_put(psalist, psa->cache, &p->state, &ret);
    if(!ret) {
        psa_t *p2 = kh_value(psa->cache, k);
#ifdef PSA_BG_SAVE
        if(PSA_LD(psa->busy)) {
            p2->dead_next = psa->dead;
            psa->dead = p2;
            p2 = NULL;
        }
#endif
        if(p2) {
            free(p2->prog);
            free(p2);
        }
    }
    kh_key(psa->cache, k) = &p->state;
    kh_value(psa->cache, k) = p;
    psa->size = kh_size(psa->cache);
#ifdef PSA_BG_SAVE
    PSA_ST(psa->dirty, 1);
    pthread_mutex_unlock(&psa_lock);
#else
    psa->dirty = 1;
#endif
}
