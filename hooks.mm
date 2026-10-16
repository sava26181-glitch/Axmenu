#import <Foundation/Foundation.h>
#import <substrate.h>
#import <dlfcn.h>
#import "esp.h"

Config g_cfg;

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
    if (!h) { NSLog(@"[AX] dlopen failed"); return false; }

    p_domain_get          = (il2cpp_domain_get_t)dlsym(h, "il2cpp_domain_get");
    p_assembly_open       = (il2cpp_domain_assembly_open_t)dlsym(h, "il2cpp_domain_assembly_open");
    p_assembly_get_image  = (il2cpp_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    p_class_from_name     = (il2cpp_class_from_name_t)dlsym(h, "il2cpp_class_from_name");
    p_class_get_method    = (il2cpp_class_get_method_from_name_t)dlsym(h, "il2cpp_class_get_method_from_name");
    p_method_get_pointer  = (il2cpp_method_get_pointer_t)dlsym(h, "il2cpp_method_get_pointer");
    p_method_get_name     = (il2cpp_method_get_name_t)dlsym(h, "il2cpp_method_get_name");
    p_class_get_methods   = (il2cpp_class_get_methods_t)dlsym(h, "il2cpp_class_get_methods");
    p_class_get_name      = (il2cpp_class_get_name_t)dlsym(h, "il2cpp_class_get_name");
    p_class_get_namespace = (il2cpp_class_get_namespace_t)dlsym(h, "il2cpp_class_get_namespace");
    p_image_get_class     = (il2cpp_image_get_class_t)dlsym(h, "il2cpp_image_get_class");
    p_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(h, "il2cpp_image_get_class_count");

    NSLog(@"[AX] resolved: domain=%p class_from_name=%p method_get_name=%p class_get_methods=%p",
          p_domain_get, p_class_from_name, p_method_get_name, p_class_get_methods);

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

// ---------- ДАМП ВСЕХ КЛАССОВ ----------
void AX_DumpAllClasses(void) {
    void* img = AX_GetImage();
    if (!img) { NSLog(@"[AX] no image for dump"); return; }
    if (!p_image_get_class_count || !p_image_get_class) {
        NSLog(@"[AX] image_get_class not resolved");
        return;
    }
    size_t count = p_image_get_class_count(img);
    NSLog(@"[AX] image contains %zu classes", count);

    for (size_t i = 0; i < count; i++) {
        void* klass = p_image_get_class(img, i);
        if (!klass) continue;
        const char* cname = p_class_get_name ? p_class_get_name(klass) : "?";
        const char* cns   = p_class_get_namespace ? p_class_get_namespace(klass) : "";
        if (!cname) continue;

        // интересуют классы с "Player", "Weapon", "Camera", "Game", "SO2"
        if (strstr(cname, "Player") || strstr(cname, "Weapon") ||
            strstr(cname, "Camera") || strstr(cname, "Game") ||
            strstr(cname, "Aim") || strstr(cname, "Bone") ||
            strstr(cname, "Local") || strstr(cname, "Photon")) {
            NSLog(@"[AX] CLASS %s.%s", cns, cname);
            AX_DumpClassMethods(cname);
        }
    }
}

// ---------- ДАМП МЕТОДОВ КЛАССА ----------
void AX_DumpClassMethods(const char* klassName) {
    if (!p_class_get_methods || !p_class_get_name || !p_class_get_namespace) return;
    void* img = AX_GetImage();
    if (!img) return;

    // ищем класс без namespace (в Standoff 2 почти всё в глобальном)
    void* klass = p_class_from_name(img, "", klassName);
    if (!klass) return;

    void* iter = NULL;
    void* method = NULL;
    int printed = 0;
    while ((method = p_class_get_methods(klass, &iter))) {
        const char* mname = p_method_get_name ? p_method_get_name(method) : NULL;
        if (mname) {
            NSLog(@"[AX]   method: %s", mname);
            printed++;
            if (printed > 300) { NSLog(@"[AX]   ... truncated"); break; }
        }
    }
}

// ---------- ХУК UPDATE ДЛЯ ТИКА ----------
static void (*o_PlayerUpdate)(void*, void*) = NULL;
static void hk_PlayerUpdate(void* self, void* method) {
    if (o_PlayerUpdate) o_PlayerUpdate(self, method);
    AX_Tick(self);
}

// ---------- INSTALL ----------
void AX_InstallRuntimeHooks(void) {
    if (!AX_ResolveIL2CPP()) {
        NSLog(@"[AX] IL2CPP resolve FAILED");
        return;
    }
    NSLog(@"[AX] IL2CPP resolved OK");

    // ищем Player.Update — заглушка "Player" (после дампа заменим на реальный класс)
    void* p_update = AX_FindMethodPtr("", "Player", "Update", 0);
    if (p_update) {
        MSHookFunction(p_update, (void*)hk_PlayerUpdate, (void**)&o_PlayerUpdate);
        NSLog(@"[AX] Player.Update hooked at %p", p_update);
    } else {
        NSLog(@"[AX] Player.Update NOT FOUND (будут использовать имя из дампа)");
    }
}
