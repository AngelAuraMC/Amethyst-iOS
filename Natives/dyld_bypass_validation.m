// Based on: https://blog.xpnsec.com/restoring-dyld-memory-loading
// https://github.com/xpn/DyldDeNeuralyzer/blob/main/DyldDeNeuralyzer/DyldPatch/dyldpatch.m

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <sys/syscall.h>
#include <libkern/OSCacheControl.h>

#include "utils.h"

#define ASM(...) __asm__(#__VA_ARGS__)
// ldr x8, value; br x8; value: .ascii "\x41\x42\x43\x44\x45\x46\x47\x48"
char patch[] = {0x88,0x00,0x00,0x58,0x00,0x01,0x1f,0xd6,0x1f,0x20,0x03,0xd5,0x1f,0x20,0x03,0xd5,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41};

// Signatures to search for
char mmapSig[] = {0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
char fcntlSig[] = {0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
char syscallSig[] = {0x01, 0x10, 0x00, 0xD4};
int (*orig_fcntl)(int fildes, int cmd, void *param) = 0;
bool (*redirectFunction)(char *name, void *patchAddr, void *target) = NULL;

extern void* __mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void* param);

// Since we're patching libsystem_kernel, we must avoid calling to its functions
static void builtin_memcpy(char *target, char *source, size_t size) {
    for (int i = 0; i < size; i++) {
        target[i] = source[i];
    }
}

kern_return_t builtin_vm_protect(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_max, vm_prot_t new_prot);
// Originated from _kernelrpc_mach_vm_protect_trap
ASM(_builtin_vm_protect: \n
    mov x16, #-0xe       \n
    svc #0x80            \n
    ret
);

// redirectFunction for iOS 18 and below
bool redirectFunctionDirect(char *name, void *patchAddr, void *target) {
    kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if (kret != KERN_SUCCESS) {
        NSDebugLog(@"[DyldLVBypass] vm_protect(RW) fails at line %d", __LINE__);
        return FALSE;
    }
    
    builtin_memcpy((char *)patchAddr, patch, sizeof(patch));
    *(void **)((char*)patchAddr + 16) = target;
    sys_icache_invalidate((void*)patchAddr, sizeof(patch));
    
    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_EXEC);
    if (kret != KERN_SUCCESS) {
        NSDebugLog(@"[DyldLVBypass] vm_protect(RX) fails at line %d", __LINE__);
        return FALSE;
    }
    
    NSDebugLog(@"[DyldLVBypass] hook %s succeed!", name);
    return TRUE;
}
// redirectFunction for iOS 26+ (TXM)
bool redirectFunctionMirrored(char *name, void *patchAddr, void *target) {
    if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
        JIT26PrepareRegionForPatching(patchAddr, sizeof(patch));
    }
    // mirror `addr` (rx, JIT applied) to `mirrored` (rw)
    vm_address_t mirrored = 0;
    vm_prot_t cur_prot, max_prot;
    kern_return_t ret = vm_remap(mach_task_self(), &mirrored, sizeof(patch), 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)patchAddr, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
    if (ret != KERN_SUCCESS) {
        NSDebugLog(@"[DyldLVBypass] vm_remap() fails at line %d", __LINE__);
        return FALSE;
    }
    
    mirrored += (vm_address_t)patchAddr & PAGE_MASK;
    vm_protect(mach_task_self(), mirrored, sizeof(patch), NO,
               VM_PROT_READ | VM_PROT_WRITE);
    builtin_memcpy((char *)mirrored, patch, sizeof(patch));
    *(void **)((char*)mirrored + 16) = target;
    sys_icache_invalidate((void*)patchAddr, sizeof(patch));
    
    NSDebugLog(@"[DyldLVBypass] hook %s succeed!", name);
    
    vm_deallocate(mach_task_self(), mirrored, sizeof(patch));
    return TRUE;
}
// redirectFunction for iOS 26+ (non-TXM)
bool redirectFunctionHWBreakpoint(char *name, void *patchAddr, void *target) {
    for(int i = 0; i < 6; i++) {
        if(hwRedirectOrig[i] == (uint64_t)patchAddr) {
            NSDebugLog(@"[DyldLVBypass] hook %s already exists!", name);
            return TRUE;
        } else if(!hwRedirectOrig[i]) {
            hwRedirectOrig[i] = (uint64_t)patchAddr;
            hwRedirectTarget[i] = (uint64_t)target;
            NSDebugLog(@"[DyldLVBypass] hook %s succeed!", name);
            return TRUE;
        }
    }
    NSDebugLog(@"[DyldLVBypass] no slot for hook %s", name);
    NSDebugLog(@"[DyldLVBypass] hook %s fails line %d", name, __LINE__);
    return FALSE;
}

bool searchAndPatch(char *name, char *base, char *signature, int length, void *target) {
    char *patchAddr = NULL;
    for(int i=0; i < 0x80000; i+=4) {
        if (base[i] == signature[0] && memcmp(base+i, signature, length) == 0) {
            patchAddr = base + i;
            break;
        }
    }
    
    if (patchAddr == NULL) {
        NSDebugLog(@"[DyldLVBypass] hook %s fails line %d", name, __LINE__);
        return FALSE;
    }
    
    NSDebugLog(@"[DyldLVBypass] found %s at %p", name, patchAddr);
    return redirectFunction(name, patchAddr, target);
}

void *getDyldBase(void) {
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    struct dyld_all_image_infos *infos;
    
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    
    ret = task_info(mach_task_self_,
                    TASK_DYLD_INFO,
                    (task_info_t)&dyld_info,
                    &count);
    
    if (ret != KERN_SUCCESS) {
        return NULL;
    }
    
    image_infos = dyld_info.all_image_info_addr;
    
    infos = (struct dyld_all_image_infos *)image_infos;
    return (void *)infos->dyldImageLoadAddress;
}

void* hooked_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    // this is to avoid a legacy codepath checking if process is allowed to map RWX which never worked properly
    if (flags & MAP_JIT) {
        errno = EINVAL;
        return MAP_FAILED;
    }
    
    void *map = __mmap(addr, len, prot, flags, fd, offset);
    // Handle some cases where it will still map but without executable permission
    if (mprotect(map, len, prot) == -1) {
        munmap(map, len);
        map = MAP_FAILED;
    }
    if (map == MAP_FAILED && fd && (prot & PROT_EXEC)) {
        //printf("[DyldLVBypass] mmap(prot=%d, flags=%d, fd=%d)\n", prot, flags, fd);
        map = __mmap(addr, len, prot, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
        if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED | JIT_FLAG_HAS_TXM)) {
            JIT26PrepareRegion(map, len);
        }
        
        void *memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
        if (redirectFunction == redirectFunctionDirect) {
            mprotect(map, len, PROT_READ | PROT_WRITE);
            memcpy(map, memoryLoadedFile, len);
            mprotect(map, len, prot);
        } else {
            // mirror `addr` (rx, JIT applied) to `mirrored` (rw)
            vm_address_t mirrored = 0;
            vm_prot_t cur_prot, max_prot;
            kern_return_t ret = vm_remap(mach_task_self(), &mirrored, len, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)map, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
            if(ret == KERN_SUCCESS) {
                vm_protect(mach_task_self(), mirrored, len, NO,
                           VM_PROT_READ | VM_PROT_WRITE);
                memcpy((void*)mirrored, memoryLoadedFile, len);
                vm_deallocate(mach_task_self(), mirrored, len);
            }
        }
        munmap(memoryLoadedFile, len);
    }
    return map;
}

int hooked___fcntl(int fildes, int cmd, void *param) {
    if (cmd == F_ADDFILESIGS_RETURN) {
#if !(TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR)
        // attempt to attach code signature on iOS only as the binaries may have been signed
        // on macOS, attaching on unsigned binaries without CS_DEBUGGED will crash
        // ignoreFcntl is a special case for vphone or dev unit with TXM JIT enforcement disabled
        BOOL ignoreFcntl = DeviceHasJITFlags(JIT_FLAG_IS_IOS_26 | JIT_FLAG_HAS_TXM) && !DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED);
        if (!ignoreFcntl) {
            orig_fcntl(fildes, cmd, param);
        }
#endif
        fsignatures_t *fsig = (fsignatures_t*)param;
        // called to check that cert covers file.. so we'll make it cover everything ;)
        fsig->fs_file_start = 0xFFFFFFFF;
        return 0;
    }

    // Signature sanity check by dyld
    else if (cmd == F_CHECK_LV) {
        //orig_fcntl(fildes, cmd, param);
        // Just say everything is fine
        return 0;
    }
    
    // If for another command or file, we pass through
    return orig_fcntl(fildes, cmd, param);
}

void init_bypassDyldLibValidation() {
    static BOOL bypassed;
    if (bypassed) return;
    bypassed = YES;

    NSDebugLog(@"[DyldLVBypass] init");

    // The original switch used exact bitmask matching, so a device with
    // IS_IOS_26 + HAS_TXM (no FORCE_MIRRORED) — i.e. a normal iPhone 17 on
    // iOS 26 with StikDebug-provided JIT — fell through to redirectFunction
    // Direct, whose vm_protect(RX) call iOS 26 blocks. The half-applied
    // patch left dyld code pages RW with modified bytes, then dyld faulted
    // executing non-X memory on the next mmap call → SIGBUS ignored → hang
    // at dlopen(libjli). Use bitmask checks so iOS 26 + TXM correctly picks
    // the mirrored variant.
    if (DeviceHasJITFlags(JIT_FLAG_HAS_TXM) &&
        (DeviceHasJITFlags(JIT_FLAG_IS_IOS_26) || DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED))) {
        NSDebugLog(@"[DyldLVBypass] Using redirectFunctionMirrored");
        redirectFunction = redirectFunctionMirrored;
    } else if (DeviceHasJITFlags(JIT_FLAG_FORCE_MIRRORED)) {
        // Special special case for non-TXM iOS 26+. We can JIT without
        // script, but we cannot modify existing code in dsc without it.
        // Use hardware breakpoint to avoid patching dsc code at all.
        NSDebugLog(@"[DyldLVBypass] Using redirectFunctionHWBreakpoint");
        redirectFunction = redirectFunctionHWBreakpoint;
    } else {
        NSDebugLog(@"[DyldLVBypass] Using redirectFunctionDirect");
        redirectFunction = redirectFunctionDirect;
    }
    
    // Modifying exec page during execution may cause SIGBUS, so ignore it now
    // Before calling JLI_Launch, this will be set back to SIG_DFL
    signal(SIGBUS, SIG_IGN);
    
    orig_fcntl = __fcntl;
    char *dyldBase = getDyldBase();
    //redirectFunction("mmap", mmap, hooked_mmap);
    //redirectFunction("fcntl", fcntl, hooked_fcntl);
    searchAndPatch("dyld_mmap", dyldBase, mmapSig, sizeof(mmapSig), hooked_mmap);
    bool fcntlPatchSuccess = searchAndPatch("dyld_fcntl", dyldBase, fcntlSig, sizeof(fcntlSig), hooked___fcntl);
    
    // https://github.com/LiveContainer/LiveContainer/commit/c978e62
    // dopamine already hooked it, try to find its hook instead
    if(!fcntlPatchSuccess) {
        char* fcntlAddr = 0;
        // search all syscalls and see if the the instruction before it is a branch instruction
        for(int i=0; i < 0x80000; i+=4) {
            if (dyldBase[i] == syscallSig[0] && memcmp(dyldBase+i, syscallSig, 4) == 0) {
                char* syscallAddr = dyldBase + i;
                uint32_t* prev = (uint32_t*)(syscallAddr - 4);
                if(*prev >> 26 == 0x5) {
                    fcntlAddr = (char*)prev;
                    break;
                }
            }
        }
        
        if(fcntlAddr) {
            uint32_t* inst = (uint32_t*)fcntlAddr;
            int32_t offset = ((int32_t)((*inst)<<6))>>4;
            NSLog(@"[DyldLVBypass] Dopamine hook offset = %x", offset);
            orig_fcntl = (void*)((char*)fcntlAddr + offset);
            redirectFunction("dyld_fcntl (Dopamine)", fcntlAddr, hooked___fcntl);
        } else {
            NSLog(@"[DyldLVBypass] Dopamine hook not found");
        }
    }
}
