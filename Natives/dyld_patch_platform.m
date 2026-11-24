#import <Foundation/Foundation.h>
#include <libgen.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <sys/mman.h>
#include <sys/stat.h>

extern int dyld_get_active_platform();

static BOOL PLPatchMachOPlatformForSlice(const char *path, struct mach_header_64 *header, size_t slice_size) {
    if (slice_size < sizeof(struct mach_header_64)) return NO;
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);

    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds; i++) {
        if ((uint8_t *)command + sizeof(struct load_command) > (uint8_t *)header + slice_size) break;
        if (command->cmdsize < sizeof(struct load_command)) break;
        if ((uint8_t *)command + command->cmdsize > (uint8_t *)header + slice_size) break;

        if (command->cmd == LC_BUILD_VERSION) {
            struct build_version_command *buildver = (struct build_version_command *)command;
            int activePlatform = dyld_get_active_platform();
            if (buildver->platform == activePlatform) return NO; // it is already set, stop
            buildver->platform = activePlatform; // set to current platform
        } else if (command->cmd == LC_LOAD_DYLIB) {
            struct dylib_command *dylib = (struct dylib_command *)command;
            if (dylib->dylib.name.offset < command->cmdsize) {
                char *dylibName = (char *)dylib + dylib->dylib.name.offset;
                size_t maxLen = command->cmdsize - dylib->dylib.name.offset;
                if (strnlen(dylibName, maxLen) < maxLen) {
                    char *verPtr = strstr(dylibName, "/Versions/");
                    if (verPtr && strlen(verPtr) >= 11) {
                        // Remove "/Versions/X"
                        int lastComponentLen = (int)strlen(verPtr) - 11;
                        if (lastComponentLen >= 0) {
                            memmove(verPtr, verPtr + 11, lastComponentLen);
                            verPtr[lastComponentLen] = '\0';
                        }
                    }
                }
            }
        }
        command = (struct load_command *)((void *)command + command->cmdsize);
    }
    return YES;
}


BOOL PLPatchMachOPlatformForFile(const char *path) {
    int fd = open(path, O_RDWR, (mode_t)0600);
    if (fd == -1) return NO;
    struct stat s;
    fstat(fd, &s);

    if (s.st_size < sizeof(struct mach_header_64)) {
        close(fd);
        return NO;
    }

    void *map = mmap(NULL, s.st_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (!map || map == MAP_FAILED) {
        close(fd);
        return NO;
    }

    BOOL patched = NO;
    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        // Find compatible slice
        struct fat_header *header = (struct fat_header *)map;
        uint32_t nfat_arch = OSSwapInt32(header->nfat_arch);
        if (nfat_arch <= (s.st_size - sizeof(struct fat_header)) / sizeof(struct fat_arch)) {
            struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
            for (int i = 0; i < nfat_arch; i++) {
                if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                    uint32_t arch_offset = OSSwapInt32(arch->offset);
                    uint32_t arch_size = OSSwapInt32(arch->size);
                    if (arch_offset + sizeof(struct mach_header_64) <= s.st_size) {
                        NSLog(@"[Amethyst] Patching %s", path);
                        size_t slice_size = (arch_offset + arch_size <= s.st_size) ? arch_size : (s.st_size - arch_offset);
                        patched |= PLPatchMachOPlatformForSlice(path, (struct mach_header_64 *)(map + arch_offset), slice_size);
                    }
                }
                arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
            }
        }
    } else if (magic == MH_MAGIC_64 && ((struct mach_header_64 *)map)->cputype == CPU_TYPE_ARM64) {
        patched = PLPatchMachOPlatformForSlice(path, (struct mach_header_64 *)map, s.st_size);
    }

    if (patched) msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    return patched;
}
