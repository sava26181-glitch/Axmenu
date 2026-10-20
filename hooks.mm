// language: Objective-C++, file: hooks.mm
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <string.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include "esp.h"

// Оффсеты из шаблона NINERI (для 0.26.0)
#define OFFSET_1 0x1CDA448
#define OFFSET_2 0x1CDA350
#define OFFSET_3 0x1CD7B68
#define OFFSET_4 0x1CD7894

typedef void* (*t_domain_get)(void);
typedef void* (*t_assembly_open)(void*, const char*);
typedef void* (*t_assembly_get_image)(void*);
typedef void* (*t_class_from_name)(void*, const char*, const char*);
typedef const void* (*t_class_get_methods)(void*, void**);
typedef const char* (*t_method_get_name)(const void*);

static t_domain_get il2cpp_domain_get = nullptr;
static t_assembly_open il2cpp_assembly_open = nullptr;
static t_assembly_get_image il2cpp_assembly_get_image = nullptr;
static t_class_from_name il2cpp_class_from_name = nullptr;
static t_class_get_methods il2cpp_class_get_methods = nullptr;
static t_method_get_name il2cpp_method_get_name = nullptr;

static void patch_address(void* addr, const uint8_t* bytes, size_t size) {
    uintptr_t pageSize = sysconf(_SC_PAGESIZE);
    uintptr_t pageStart = (uintptr_t)addr & ~(pageSize - 1);
    mprotect((void*)pageStart, pageSize, PROT_READ | PROT_WRITE | PROT_EXEC);
    memcpy(addr, bytes, size);
    mprotect((void*)pageStart, pageSize, PROT_READ | PROT_EXEC);
    sys_icache_invalidate(addr, size);
}

// Функция для получения базового адреса модуля
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
    NSLog(@"[AX] Start patching offsets...");

    // 1. Получаем базу UnityFramework (где лежит GameAssembly)
    uintptr_t base = get_module_base("UnityFramework");
    if (!base) {
        base = get_module_base("Standoff2");
    }
    
    if (base) {
        NSLog(@"[AX] Module base: 0x%lx", base);
        
        // Байты для RET (0xC0035FD6 в little-endian: D6 5F 03 C0)
        uint8_t ret_bytes[] = { 0xD6, 0x5F, 0x03, 0xC0 };
        
        // Патчим оффсеты
        patch_address((void*)(base + OFFSET_1), ret_bytes, sizeof(ret_bytes));
        patch_address((void*)(base + OFFSET_2), ret_bytes, sizeof(ret_bytes));
        patch_address((void*)(base + OFFSET_3), ret_bytes, sizeof(ret_bytes));
        patch_address((void*)(base + OFFSET_4), ret_bytes, sizeof(ret_bytes));
        
        NSLog(@"[AX] AC offsets patched!");
    } else {
        NSLog(@"[AX] Module base NOT FOUND");
    }

    // 2. Патчим отдачу через IL2CPP (на всякий случай, если оффсеты не сработают)
    il2cpp_domain_get = (t_domain_get)dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    il2cpp_assembly_open = (t_assembly_open)dlsym(RTLD_DEFAULT, "il2cpp_assembly_open");
    il2cpp_assembly_get_image = (t_assembly_get_image)dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    il2cpp_class_from_name = (t_class_from_name)dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    il2cpp_class_get_methods = (t_class_get_methods)dlsym(RTLD_DEFAULT, "il2cpp_class_get_methods");
    il2cpp_method_get_name = (t_method_get_name)dlsym(RTLD_DEFAULT, "il2cpp_method_get_name");

    if (il2cpp_domain_get) {
        void* domain = il2cpp_domain_get();
        void* asmCSharp = il2cpp_assembly_open(domain, "Assembly-CSharp.dll");
        if (asmCSharp) {
            void* img = il2cpp_assembly_get_image(asmCSharp);
            void* klass = il2cpp_class_from_name(img, "Axlebolt.Standoff.Inventory.Gun", "RecoilParameters");
            if (klass) {
                uint8_t ret_zero_float[] = { 0x00, 0x00, 0x80, 0x52, 0xC0, 0x03, 0x5F, 0xD6 };
                void* iter = nullptr;
                const void* method = nullptr;
                
                while ((method = il2cpp_class_get_methods(klass, &iter))) {
                    const char* name = il2cpp_method_get_name(method);
                    void* funcPtr = *(void**)method;
                    if (!funcPtr) continue;
                    if (strcmp(name, "get_VerticalRange") == 0 ||
                        strcmp(name, "get_HorizontalRange") == 0 ||
                        strcmp(name, "get_CameraDeviationCoeff") == 0) {
                        patch_address(funcPtr, ret_zero_float, sizeof(ret_zero_float));
                    }
                }
            }
        }
    }
}