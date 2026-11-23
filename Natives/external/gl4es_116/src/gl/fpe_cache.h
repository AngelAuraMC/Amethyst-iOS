#ifndef __FPE_CACHE_H__
#define __FPE_CACHE_H__

#include "gles.h"
#include "fpe.h"

typedef fpe_state_t *kh_fpe_t;
struct kh_fpecachelist_s;

#define FPE_MRU_SIZE 16

struct fpe_cache_s {
    struct kh_fpecachelist_s *map;
    fpe_fpe_t                *mru[FPE_MRU_SIZE];
    int                       mru_count;
};

fpe_cache_t* fpe_NewCache(void);
void fpe_disposeCache(fpe_cache_t* cache, int freeprog);
fpe_fpe_t *fpe_GetCache(fpe_cache_t *cur, fpe_state_t *state, int fixed);

void fpe_InitPSA(const char* name);
void fpe_FreePSA(void);
void fpe_readPSA(void);
void fpe_writePSA(void);
void fpe_PSATick(void);
int fpe_GetProgramPSA(GLuint program, fpe_state_t* state);
void fpe_AddProgramPSA(GLuint program, fpe_state_t* state);

#endif //__FPE_CACHE_H__
