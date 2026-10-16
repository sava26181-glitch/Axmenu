#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "esp.h"

Config g_cfg;

// ---------- ПИШЕМ ЛОГ В ФАЙЛ НАПРЯМУЮ ----------
static void AXLog(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[2048];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    FILE* f = fopen("/var/tmp/axlog.txt", "a");
    if (!f) {
        const char* home = getenv("HOME");
        if (home) {
            char path[512];
            snprintf(path, sizeof(path), "%s/Documents/axlog.txt", home);
            f = fopen(path, "a");
        }
    }
    if (!f) {
        f = fopen("/var/mobile/Documents/axlog.txt", "a");
    }
    if (f) {
        fputs(buf, f);
        fputs("\n", f);
        fclose(f);
    }
}

// ---------- IL2CPP API ----------
typedef void* (*il2cpp_domain_get_t)();
typedef void* (*il2cpp_domain_assembly_open_t)(void*, const char*);
typedef void* (*il2cpp_assembly_get_image_t)(void*);
typedef void* (*il2cpp_class_from_name_t)(void*, const char*, const char*);
typedef void* (*il2cpp_class_get_method_from_name_t)(void*, const char*, int);
typedef void* (*il2cpp_method_get_pointer_t)(void*);
typedef const char* (*il2cpp_method_get_name_t)(void*);
typedef void* (*il2cpp_class_get_methods_t)(void*, void**);
typedef const char* (*il2cpp_class_get_name_t)(void*);
typedef const char* (*il2cpp_class_get_namespace_t)(void*);
typedef void* (*il2cpp_image_get_class_t)(void*, size_t);
typedef size_t (*il2cpp_image_get_class_count_t)(void*);

static il2cpp_domain_get_t               p_domain_get = NULL;
static il2cpp_domain_assembly_open_t     p_assembly_open = NULL;
static il2cpp_assembly_get_image_t       p_assembly_get_image = NULL;
static il2cpp_class_from_name_t          p_class_from_name = NULL;
static il2cpp_class_get_method_from_name_t p_class_get_method = NULL;
static il2cpp_method_get_pointer_t       p_method_get_pointer = NULL;
static il2cpp_method_get_name_t          p_method_get_name = NULL;
static il2cpp_class_get_methods_t        p_class_get_methods = NULL;
static il2cpp_class_get_name_t           p_class_get_name = NULL;
static il2cpp_class_get_namespace_t      p_class_get_namespace = NULL;
static il2cpp_image_get_class_t          p_image_get_class = NULL;
static il2cpp_image_get_class_count_t    p_image_get_class_count = NULL;

static bool AX_ResolveIL2CPP(void) {
    void* h = dlopen("UnityFramework", RTLD_NOW);
    if (!h) h = dlopen(NULL, RTLD_NOW);
    if (!h) { AXLog("[AX] dlopen failed"); return false; }

    p_domain_get            = (il2cpp_domain_get_t)dlsym(h, "il2cpp_domain_get");
    p_assembly_open         = (il2cpp_domain_assembly_open_t)dlsym(h, "il2cpp_domain_assembly_open");
    p_assembly_get_image    = (il2cpp_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    p_class_from_name       = (il2cpp_class_from_name_t)dlsym(h, "il2cpp_class_from_name");
    p_class_get_method      = (il2cpp_class_get_method_from_name_t)dlsym(h, "il2cpp_class_get_method_from_name");
    p_method_get_pointer    = (il2cpp_method_get_pointer_t)dlsym(h, "il2cpp_method_get_pointer");
    p_method_get_name       = (il2cpp_method_get_name_t)dlsym(h, "il2cpp_method_get_name");
    p_class_get_methods     = (il2cpp_class_get_methods_t)dlsym(h, "il2cpp_class_get_methods");
    p_class_get_name        = (il2cpp_class_get_name_t)dlsym(h, "il2cpp_class_get_name");
    p_class_get_namespace   = (il2cpp_class_get_namespace_t)dlsym(h, "il2cpp_class_get_namespace");
    p_image_get_class       = (il2cpp_image_get_class_t)dlsym(h, "il2cpp_image_get_class");
    p_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(h, "il2cpp_image_get_class_count");

    AXLog("[AX] resolve: domain=%p cfname=%p mname=%p cmethods=%p imgclass=%p imgcount=%p",
          p_domain_get, p_class_from_name, p_method_get_name,
          p_class_get_methods, p_image_get_class, p_image_get_class_count);

    return p_domain_get && p_assembly_open && p_assembly_get_image &&
           p_class_from_name && p_class_get_method && p_method_get_pointer;
}

static void* g_image = NULL;
static void* AX_GetImage(void) {
    if (g_image) return g_image;
    if (!p_domain_get) return NULL;
    void* domain = p_domain_get();
    if (!domain) return NULL;
    const char* asms[] = { "Assembly-CSharp", "Assembly-CSharp-firstpass" };
    for (int i = 0; i < 2; i++) {
        void* a = p_assembly_open(domain, asms[i]);
        if (!a) continue;
        void* img = p_assembly_get_image(a);
        if (img) { g_image = img; return img; }
    }
    return NULL;
}

void* AX_FindMethodPtr(const char* ns, const char* klass, const char* method, int argc) {
    if (!p_class_from_name) return NULL;
    void* img = AX_GetImage();
    if (!img) return NULL;
    void* k = p_class_from_name(img, ns, klass);
    if (!k) return NULL;
    void* m = p_class_get_method(k, method, argc);
    if (!m) return NULL;
    return p_method_get_pointer(m);
}

void AX_DumpClassMethods(const char* klassName) {
    if (!p_class_get_methods || !p_method_get_name) return;
    void* img = AX_GetImage();
    if (!img) return;
    void* klass = p_class_from_name(img, "", klassName);
    if (!klass) return;

    void* iter = NULL;
    void* method = NULL;
    int printed = 0;
    while ((method = p_class_get_methods(klass, &iter))) {
        const char* mname = p_method_get_name(method);
        if (mname) {
            AXLog("  method: %s", mname);
            printed++;
            if (printed > 300) { AXLog("  ... truncated"); break; }
        }
    }
}

void AX_DumpAllClasses(void) {
    void* img = AX_GetImage();
    if (!img) { AXLog("[AX] no image"); return; }
    if (!p_image_get_class_count || !p_image_get_class || !p_class_get_name) {
        AXLog("[AX] image_get_class not resolved");
        return;
    }
    size_t count = p_image_get_class_count(img);
    AXLog("[AX] image has %zu classes", count);

    for (size_t i = 0; i < count; i++) {
        void* klass = p_image_get_class(img, i);
        if (!klass) continue;
        const char* cname = p_class_get_name(klass);
        const char* cns = p_class_get_namespace ? p_class_get_namespace(klass) : "";
        if (!cname) continue;

        if (strstr(cname, "Player") || strstr(cname, "Weapon") ||
            strstr(cname, "Camera") || strstr(cname, "Game") ||
            strstr(cname, "Aim") || strstr(cname, "Bone") ||
            strstr(cname, "Local") || strstr(cname, "Photon")) {
            AXLog("CLASS %s.%s", cns, cname);
            AX_DumpClassMethods(cname);
        }
    }
}

// ---------- ТИК ----------
static void (*o_PlayerUpdate)(void*, void*) = NULL;
static void hk_PlayerUpdate(void* self, void* method) {
    if (o_PlayerUpdate) o_PlayerUpdate(self, method);
    // AX_Tick(self); // включим когда будут имена методов
}

// ---------- INSTALL ----------
void AX_InstallRuntimeHooks(void) {
    AXLog("[AX] === AXMenu install start ===");

    if (!AX_ResolveIL2CPP()) {
        AXLog("[AX] IL2CPP resolve FAILED");
        return;
    }
    AXLog("[AX] IL2CPP resolved OK");

    AX_DumpAllClasses();

    void* p_update = AX_FindMethodPtr("", "Player", "Update", 0);
    if (p_update) {
        MSHookFunction(p_update, (void*)hk_PlayerUpdate, (void**)&o_PlayerUpdate);
        AXLog("[AX] Player.Update hooked");
    } else {
        AXLog("[AX] Player.Update NOT FOUND");
    }

    AXLog("[AX] === install done ===");
}