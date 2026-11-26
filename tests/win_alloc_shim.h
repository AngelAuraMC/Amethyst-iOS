#ifndef AMETHYST_WIN_ALLOC_SHIM_H
#define AMETHYST_WIN_ALLOC_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void win_alloc_shim_begin(void);
void win_alloc_shim_end(size_t *out_leaked_bytes, size_t *out_leaked_allocs);
int win_alloc_shim_is_active(void);

#if defined(_WIN32) && defined(WIN_ALLOC_SHIM_WRAP)
void *win_shim_malloc(size_t size);
void *win_shim_calloc(size_t nmemb, size_t size);
void *win_shim_realloc(void *ptr, size_t size);
void win_shim_free(void *ptr);
char *win_shim_strdup(const char *s);
#endif

#ifdef __cplusplus
}
#endif

#if defined(_WIN32) && defined(WIN_ALLOC_SHIM_WRAP) && !defined(WIN_ALLOC_SHIM_IMPL)
#include <stdlib.h>
#include <malloc.h>
#include <string.h>
#define malloc(sz) win_shim_malloc(sz)
#define calloc(n, sz) win_shim_calloc((n), (sz))
#define realloc(p, sz) win_shim_realloc((p), (sz))
#define free(p) win_shim_free(p)
#undef strdup
#define strdup(s) win_shim_strdup(s)
#undef _strdup
#define _strdup(s) win_shim_strdup(s)
#endif

#endif
