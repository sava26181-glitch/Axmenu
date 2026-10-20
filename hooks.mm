// language: Objective-C++, file: hooks.mm
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <string.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include "esp.h"

static void patch_address(void* addr, const uint8_t* bytes, size_t size) {
    uintptr_t pageSize = sysconf(_SC_PAGESIZE);
    uintptr_t pageStart = (uintptr_t)addr & ~(pageSize - 1);
    mprotect((void*)pageStart, pageSize, PROT_READ | PROT_WRITE | PROT_EXEC);
    memcpy(addr, bytes, size);
    mprotect((void*)pageStart, pageSize, PROT_READ | PROT_EXEC);
    sys_icache_invalidate(addr, size);
}

static uintptr_t get_module_base(const char* module_name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, module_name)) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    return 0;
}

void AX_InstallRuntimeHooks(void) {
    NSLog(@"[AX] Starting SVC scan...");

    // Ищем UnityFramework (где сидит античит)
    uintptr_t base = get_module_base("UnityFramework");
    if (!base) {
        NSLog(@"[AX] UnityFramework NOT FOUND");
        return;
    }

    // Получаем размер модуля через заголовок Mach-O
    struct mach_header_64* header = (struct mach_header_64*)base;
    uintptr_t size = 0;
    
    // Проходим по load commands, чтобы найти __TEXT
    uintptr_t cmd_ptr = base + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        struct load_command* cmd = (struct load_command*)cmd_ptr;
        if (cmd->cmd == LC_SEGMENT_64) {
            struct segment_command_64* seg = (struct segment_command_64*)cmd;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                size = seg->vmsize;
                break;
            }
        }
        cmd_ptr += cmd->cmdsize;
    }

    if (size == 0) {
        NSLog(@"[AX] __TEXT size NOT FOUND");
        return;
    }

    NSLog(@"[AX] UnityFramework base: 0x%lx, size: 0x%lx", base, size);

    // Сигнатура SVC #0x80 (little-endian)
    // ARM64: svc #0x80 = 0x01 0x00 0x00 0xD4
    // Мы заменим её на NOP (0x1F 0x20 0x03 0xD5)
    uint8_t svc_pattern[] = { 0x01, 0x00, 0x00, 0xD4 };
    uint8_t nop_patch[]   = { 0x1F, 0x20, 0x03, 0xD5 };

    uint8_t* ptr = (uint8_t*)base;
    int found = 0;
    
    for (uintptr_t i = 0; i < size - 4; i += 4) {
        if (memcmp(ptr + i, svc_pattern, 4) == 0) {
            patch_address(ptr + i, nop_patch, 4);
            found++;
        }
    }
    
    NSLog(@"[AX] Total SVC patched: %d", found);
}