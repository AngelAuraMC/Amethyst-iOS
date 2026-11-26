#define WIN_ALLOC_SHIM_IMPL 1
#include "win_alloc_shim.h"

#undef malloc
#undef calloc
#undef realloc
#undef free
#undef strdup
#undef _strdup

#if defined(_WIN32) && defined(WIN_ALLOC_SHIM_WRAP)

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

typedef struct {
    void *ptr;
    size_t size;
    unsigned int epoch;
    uint8_t state; /* 0 = empty, 1 = occupied, 2 = tombstone */
} alloc_slot_t;

static volatile LONG s_lock = 0;
static alloc_slot_t *s_table = NULL;
static size_t s_cap = 0;
static size_t s_used = 0;
static size_t s_tombstones = 0;

static volatile LONG s_armed = 0;
static unsigned int s_epoch = 1;
static size_t s_live_bytes = 0;
static size_t s_live_allocs = 0;

static void lock_shim(void) {
    while (InterlockedCompareExchange(&s_lock, 1, 0) != 0) {
        Sleep(0);
    }
}

static void unlock_shim(void) {
    InterlockedExchange(&s_lock, 0);
}

static size_t hash_ptr(const void *p) {
    uintptr_t v = (uintptr_t)p;
    v ^= v >> 33;
    v *= (uintptr_t)0xff51afd7ed558ccdULL;
    v ^= v >> 33;
    v *= (uintptr_t)0xc4ceb9fe1a85ec53ULL;
    v ^= v >> 33;
    return (size_t)v;
}

static void rehash_table(size_t new_cap) {
    alloc_slot_t *nt = (alloc_slot_t *)calloc(new_cap, sizeof(alloc_slot_t));
    if (!nt) return;
    size_t mask = new_cap - 1;
    size_t new_used = 0;
    for (size_t i = 0; i < s_cap; ++i) {
        if (s_table[i].state == 1) {
            size_t idx = hash_ptr(s_table[i].ptr) & mask;
            while (nt[idx].state == 1) {
                idx = (idx + 1) & mask;
            }
            nt[idx] = s_table[i];
            new_used++;
        }
    }
    free(s_table);
    s_table = nt;
    s_cap = new_cap;
    s_used = new_used;
    s_tombstones = 0;
}

static void table_insert(void *ptr, size_t size, unsigned int epoch) {
    if (!ptr) return;
    if (s_cap == 0) {
        rehash_table(4096);
    } else if ((s_used + s_tombstones + 1) * 10 >= s_cap * 7) {
        size_t next_cap = (s_used * 2 >= s_cap) ? (s_cap * 2) : s_cap;
        if (next_cap < 4096) next_cap = 4096;
        rehash_table(next_cap);
    }
    if (s_cap == 0) return;

    size_t mask = s_cap - 1;
    size_t idx = hash_ptr(ptr) & mask;
    size_t first_tomb = (size_t)-1;
    while (1) {
        if (s_table[idx].state == 0) {
            size_t dst = (first_tomb != (size_t)-1) ? first_tomb : idx;
            if (first_tomb != (size_t)-1) s_tombstones--;
            s_table[dst].ptr = ptr;
            s_table[dst].size = size;
            s_table[dst].epoch = epoch;
            s_table[dst].state = 1;
            s_used++;
            return;
        }
        if (s_table[idx].state == 1 && s_table[idx].ptr == ptr) {
            if (s_table[idx].epoch == s_epoch && s_armed) {
                if (s_live_bytes >= s_table[idx].size) s_live_bytes -= s_table[idx].size;
                else s_live_bytes = 0;
                if (s_live_allocs > 0) s_live_allocs--;
            }
            s_table[idx].size = size;
            s_table[idx].epoch = epoch;
            return;
        }
        if (s_table[idx].state == 2 && first_tomb == (size_t)-1) {
            first_tomb = idx;
        }
        idx = (idx + 1) & mask;
    }
}

static int table_remove(void *ptr, size_t *out_size, unsigned int *out_epoch) {
    if (!ptr || s_cap == 0) return 0;
    size_t mask = s_cap - 1;
    size_t idx = hash_ptr(ptr) & mask;
    while (1) {
        if (s_table[idx].state == 0) return 0;
        if (s_table[idx].state == 1 && s_table[idx].ptr == ptr) {
            if (out_size) *out_size = s_table[idx].size;
            if (out_epoch) *out_epoch = s_table[idx].epoch;
            s_table[idx].ptr = NULL;
            s_table[idx].size = 0;
            s_table[idx].epoch = 0;
            s_table[idx].state = 2;
            if (s_used > 0) s_used--;
            s_tombstones++;
            return 1;
        }
        idx = (idx + 1) & mask;
    }
}

void win_alloc_shim_begin(void) {
    lock_shim();
    s_epoch++;
    if (s_epoch == 0) s_epoch = 1;
    s_live_bytes = 0;
    s_live_allocs = 0;
    s_armed = 1;
    unlock_shim();
}

void win_alloc_shim_end(size_t *out_leaked_bytes, size_t *out_leaked_allocs) {
    lock_shim();
    s_armed = 0;
    if (out_leaked_bytes) *out_leaked_bytes = s_live_bytes;
    if (out_leaked_allocs) *out_leaked_allocs = s_live_allocs;
    unlock_shim();
}

int win_alloc_shim_is_active(void) {
    return 1;
}

void *win_shim_malloc(size_t size) {
    void *p = malloc(size);
    if (p && InterlockedCompareExchange(&s_armed, 0, 0) != 0) {
        lock_shim();
        if (s_armed) {
            table_insert(p, size, s_epoch);
            s_live_bytes += size;
            s_live_allocs++;
        }
        unlock_shim();
    }
    return p;
}

void *win_shim_calloc(size_t nmemb, size_t size) {
    void *p = calloc(nmemb, size);
    if (p && InterlockedCompareExchange(&s_armed, 0, 0) != 0) {
        size_t total = (size != 0 && nmemb > SIZE_MAX / size) ? 0 : (nmemb * size);
        lock_shim();
        if (s_armed) {
            table_insert(p, total, s_epoch);
            s_live_bytes += total;
            s_live_allocs++;
        }
        unlock_shim();
    }
    return p;
}

void *win_shim_realloc(void *ptr, size_t size) {
    if (!ptr) {
        return win_shim_malloc(size);
    }
    if (size == 0) {
        if (s_cap != 0) {
            lock_shim();
            size_t old_sz = 0;
            unsigned int old_ep = 0;
            if (table_remove(ptr, &old_sz, &old_ep) && s_armed && old_ep == s_epoch) {
                if (s_live_bytes >= old_sz) s_live_bytes -= old_sz;
                else s_live_bytes = 0;
                if (s_live_allocs > 0) s_live_allocs--;
            }
            unlock_shim();
        }
        return realloc(ptr, 0);
    }

    void *np = realloc(ptr, size);
    if (!np) return NULL;

    if (InterlockedCompareExchange(&s_armed, 0, 0) != 0 || s_cap != 0) {
        lock_shim();
        size_t old_sz = 0;
        unsigned int old_ep = 0;
        int removed = table_remove(ptr, &old_sz, &old_ep);
        int was_cur = (removed && old_ep == s_epoch);
        if (was_cur && s_armed) {
            if (s_live_bytes >= old_sz) s_live_bytes -= old_sz;
            else s_live_bytes = 0;
            if (s_live_allocs > 0) s_live_allocs--;
        }
        if (s_armed && was_cur) {
            table_insert(np, size, s_epoch);
            s_live_bytes += size;
            s_live_allocs++;
        }
        unlock_shim();
    }
    return np;
}

void win_shim_free(void *ptr) {
    if (!ptr) return;
    if (s_cap != 0) {
        lock_shim();
        size_t old_sz = 0;
        unsigned int old_ep = 0;
        if (table_remove(ptr, &old_sz, &old_ep) && s_armed && old_ep == s_epoch) {
            if (s_live_bytes >= old_sz) s_live_bytes -= old_sz;
            else s_live_bytes = 0;
            if (s_live_allocs > 0) s_live_allocs--;
        }
        unlock_shim();
    }
    free(ptr);
}

char *win_shim_strdup(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s) + 1;
    char *p = (char *)win_shim_malloc(len);
    if (p) {
        memcpy(p, s, len);
    }
    return p;
}

#else

void win_alloc_shim_begin(void) {}
void win_alloc_shim_end(size_t *out_leaked_bytes, size_t *out_leaked_allocs) {
    if (out_leaked_bytes) *out_leaked_bytes = 0;
    if (out_leaked_allocs) *out_leaked_allocs = 0;
}
int win_alloc_shim_is_active(void) { return 0; }

#endif
