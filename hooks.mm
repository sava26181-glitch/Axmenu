// language: Objective-C++, file: hooks.mm
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <string.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h> // <-- Добавили для sys_icache_invalidate
#include "esp.h"

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
    sys_icache_invalidate(addr, size); // <-- Заменили __builtin___clear_cache
}

void AX_InstallRuntimeHooks(void) {
    il2cpp_domain_get = (t_domain_get)dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    il2cpp_assembly_open = (t_assembly_open)dlsym(RTLD_DEFAULT, "il2cpp_assembly_open");
    il2cpp_assembly_get_image = (t_assembly_get_image)dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    il2cpp_class_from_name = (t_class_from_name)dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    il2cpp_class_get_methods = (t_class_get_methods)dlsym(RTLD_DEFAULT, "il2cpp_class_get_methods");
    il2cpp_method_get_name = (t_method_get_name)dlsym(RTLD_DEFAULT, "il2cpp_method_get_name");

    if (!il2cpp_domain_get) return;
    void* domain = il2cpp_domain_get();

    // --- 1. ПАТЧИМ ОТДАЧУ (без Warden) ---
    void* asmCSharp = il2cpp_assembly_open(domain, "Assembly-CSharp.dll");
    if (asmCSharp) {
        void* img = il2cpp_assembly_get_image(asmCSharp);
        void* klass = il2cpp_class_from_name(img, "Axlebolt.Standoff.Inventory.Gun", "RecoilParameters");
        if (klass) {
            // MOV W0, #0; RET (возвращает 0.0f)
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