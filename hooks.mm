#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "esp.h"

Config g_cfg;

// ---------- AXLog ----------
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
static il2cpp_method_get_name_t          p_method_get_name = NULL;
static il2cpp_class_get_methods_t        p_class_get_methods = NULL;
static il2cpp_class_get_name_t           p_class_get_name = NULL;
static il2cpp_class_get_namespace_t      p_class_get_namespace = NULL;
static il2cpp_image_get_class_t          p_image_get_class = NULL;
static il2cpp_image_get_class_count_t    p_image_get_class_count = NULL;

// ---------- читаем methodPointer из MethodInfo ----------
static void* AX_GetMethodPointer(void* methodInfo) {
    if (!methodInfo) return NULL;
    void** ptr = (void**)methodInfo;
    return ptr[0];
}

static bool AX_ResolveIL2CPP(void) {
    void* h = dlopen("UnityFramework", RTLD_NOW);
    if (!h) h = dlopen(NULL, RTLD_NOW);
    if (!h) { AXLog("[AX] dlopen failed"); return false; }

    p_domain_get            = (il2cpp_domain_get_t)dlsym(h, "il2cpp_domain_get");
    p_assembly_open         = (il2cpp_domain_assembly_open_t)dlsym(h, "il2cpp_domain_assembly_open");
    p_assembly_get_image    = (il2cpp_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    p_class_from_name       = (il2cpp_class_from_name_t)dlsym(h, "il2cpp_class_from_name");
    p_class_get_method      = (il2cpp_class_get_method_from_name_t)dlsym(h, "il2cpp_class_get_method_from_name");
    p_method_get_name       = (il2cpp_method_get_name_t)dlsym(h, "il2cpp_method_get_name");
    p_class_get_methods     = (il2cpp_class_get_methods_t)dlsym(h, "il2cpp_class_get_methods");
    p_class_get_name        = (il2cpp_class_get_name_t)dlsym(h, "il2cpp_class_get_name");
    p_class_get_namespace   = (il2cpp_class_get_namespace_t)dlsym(h, "il2cpp_class_get_namespace");
    p_image_get_class       = (il2cpp_image_get_class_t)dlsym(h, "il2cpp_image_get_class");
    p_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(h, "il2cpp_image_get_class_count");

    bool ok = p_domain_get && p_assembly_open && p_assembly_get_image &&
              p_class_from_name && p_class_get_method;
    AXLog("[AX] resolve %s", ok ? "OK" : "FAILED");
    return ok;
}

static void* g_image = NULL;
static void* AX_GetImage(void) {
    if (g_image) return g_image;
    if (!p_domain_get) return NULL;
    void* domain = p_domain_get();
    if (!domain) return NULL;
    void* a = p_assembly_open(domain, "Assembly-CSharp");
    if (!a) return NULL;
    void* img = p_assembly_get_image(a);
    if (img) g_image = img;
    return img;
}

// ---------- ДАМП С NAMESPACE ----------
void AX_DumpAllClasses(void) {
    void* img = AX_GetImage();
    if (!img) { AXLog("[AX] no image"); return; }
    if (!p_image_get_class_count || !p_image_get_class || !p_class_get_name || !p_class_get_namespace) {
        AXLog("[AX] dump functions missing");
        return;
    }

    size_t count = p_image_get_class_count(img);
    AXLog("[AX] image has %zu classes", count);

    for (size_t i = 0; i < count; i++) {
        void* klass = p_image_get_class(img, i);
        if (!klass) continue;
        const char* cname = p_class_get_name(klass);
        const char* cns   = p_class_get_namespace(klass);
        if (!cname) continue;
        if (!cns) cns = "";

        // фильтр по ключевым словам
        bool interesting =
            strstr(cname, "Weapon") || strstr(cname, "Player") ||
            strstr(cname, "Camera") || strstr(cname, "Aim") ||
            strstr(cname, "Bone")   || strstr(cname, "Damage") ||
            strstr(cname, "Hit")    || strstr(cname, "Recoil") ||
            strstr(cname, "Spread") || strstr(cname, "Health") ||
            strstr(cname, "Team")   || strstr(cname, "Movement") ||
            strstr(cname, "Speed");

        if (!interesting) continue;

        AXLog("CLASS %s.%s", cns, cname);

        // ищем класс с полным namespace
        void* k = p_class_from_name(img, cns, cname);
        if (!k) { AXLog("  -- lookup failed --"); continue; }

        // обходим методы
        void* iter = NULL;
        void* method = NULL;
        int printed = 0;
        while ((method = p_class_get_methods(k, &iter))) {
            const char* mname = p_method_get_name(method);
            if (mname) {
                AXLog("    %s", mname);
                printed++;
                if (printed > 500) { AXLog("    ..."); break; }
            }
        }
    }
}

// ---------- ХУК ----------
static void (*o_PlayerUpdate)(void*, void*) = NULL;
static void hk_PlayerUpdate(void* self, void* method) {
    if (o_PlayerUpdate) o_PlayerUpdate(self, method);
}

void AX_InstallRuntimeHooks(void) {
    AXLog("[AX] === install start ===");

    if (!AX_ResolveIL2CPP()) {
        AXLog("[AX] resolve FAILED");
        return;
    }
    AXLog("[AX] resolve OK");

    AXLog("[AX] domain = %p", p_domain_get ? p_domain_get() : NULL);
    void* img = AX_GetImage();
    AXLog("[AX] image = %p", img);
    if (img) {
        AXLog("[AX] class count = %zu", p_image_get_class_count ? p_image_get_class_count(img) : 0);
    }

    AX_DumpAllClasses();

    AXLog("[AX] === install done ===");
}