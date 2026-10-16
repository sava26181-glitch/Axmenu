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
    if (!f) f = fopen("/var/mobile/Documents/axlog.txt", "a");
    if (f) { fputs(buf, f); fputs("\n", f); fclose(f); }
}

// ---------- IL2CPP API ----------
typedef void* (*il2cpp_domain_get_t)();
typedef void** (*il2cpp_domain_get_assemblies_t)(void*, size_t*);
typedef void* (*il2cpp_assembly_get_image_t)(void*);
typedef const char* (*il2cpp_image_get_name_t)(void*);
typedef void* (*il2cpp_class_from_name_t)(void*, const char*, const char*);
typedef void* (*il2cpp_class_get_method_from_name_t)(void*, const char*, int);
typedef const char* (*il2cpp_method_get_name_t)(void*);
typedef void* (*il2cpp_class_get_methods_t)(void*, void**);
typedef const char* (*il2cpp_class_get_name_t)(void*);
typedef const char* (*il2cpp_class_get_namespace_t)(void*);
typedef void* (*il2cpp_image_get_class_t)(void*, size_t);
typedef size_t (*il2cpp_image_get_class_count_t)(void*);

static il2cpp_domain_get_t               p_domain_get = NULL;
static il2cpp_domain_get_assemblies_t    p_domain_get_assemblies = NULL;
static il2cpp_assembly_get_image_t       p_assembly_get_image = NULL;
static il2cpp_image_get_name_t           p_image_get_name = NULL;
static il2cpp_class_from_name_t          p_class_from_name = NULL;
static il2cpp_class_get_method_from_name_t p_class_get_method = NULL;
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
    p_domain_get_assemblies = (il2cpp_domain_get_assemblies_t)dlsym(h, "il2cpp_domain_get_assemblies");
    p_assembly_get_image    = (il2cpp_assembly_get_image_t)dlsym(h, "il2cpp_assembly_get_image");
    p_image_get_name        = (il2cpp_image_get_name_t)dlsym(h, "il2cpp_image_get_name");
    p_class_from_name       = (il2cpp_class_from_name_t)dlsym(h, "il2cpp_class_from_name");
    p_class_get_method      = (il2cpp_class_get_method_from_name_t)dlsym(h, "il2cpp_class_get_method_from_name");
    p_method_get_name       = (il2cpp_method_get_name_t)dlsym(h, "il2cpp_method_get_name");
    p_class_get_methods     = (il2cpp_class_get_methods_t)dlsym(h, "il2cpp_class_get_methods");
    p_class_get_name        = (il2cpp_class_get_name_t)dlsym(h, "il2cpp_class_get_name");
    p_class_get_namespace   = (il2cpp_class_get_namespace_t)dlsym(h, "il2cpp_class_get_namespace");
    p_image_get_class       = (il2cpp_image_get_class_t)dlsym(h, "il2cpp_image_get_class");
    p_image_get_class_count = (il2cpp_image_get_class_count_t)dlsym(h, "il2cpp_image_get_class_count");

    bool ok = p_domain_get && p_assembly_get_image && p_class_from_name && p_class_get_method;
    AXLog("[AX] resolve %s", ok ? "OK" : "FAILED");
    return ok;
}

// ---------- ФИЛЬТР: только АНТИЧИТ ----------
static bool isACClass(const char* ns, const char* name) {
    if (!name) return false;
    if (!ns) ns = "";

    // Axlebolt Warden (основной античит)
    if (strstr(ns, "Warden")) return true;
    if (strstr(name, "Warden")) return true;

    // Integrity
    if (strstr(ns, "Integrity")) return true;
    if (strstr(name, "Integrity")) return true;

    // AppCheck (Firebase)
    if (strstr(ns, "AppCheck")) return true;
    if (strstr(name, "AppCheck")) return true;

    // AntiCheat / Anticheat
    if (strstr(ns, "AntiCheat")) return true;
    if (strstr(name, "AntiCheat")) return true;
    if (strstr(name, "Anticheat")) return true;
    if (strstr(name, "Anti-Cheat")) return true;

    // Security
    if (strstr(ns, "Security")) return true;
    if (strstr(name, "Security")) return true;

    // Tamper / Detection
    if (strstr(ns, "Tamper")) return true;
    if (strstr(name, "Tamper")) return true;
    if (strstr(ns, "Detect")) return true;
    if (strstr(name, "Detect")) return true;
    if (strstr(name, "Detector")) return true;

    // Root / Jail
    if (strstr(name, "Root")) return true;
    if (strstr(name, "Jail")) return true;
    if (strstr(name, "Jailbreak")) return true;
    if (strstr(name, "Fraud")) return true;

    // Attestation (Apple DeviceCheck)
    if (strstr(name, "Attest")) return true;
    if (strstr(ns, "DeviceCheck")) return true;
    if (strstr(name, "DeviceCheck")) return true;

    // Firebase (могут быть не AC, но связаны)
    if (strstr(ns, "Firebase")) return true;
    if (strstr(name, "Firebase")) return true;

    // Services с подозрительными именами
    if (strstr(ns, "_Services.Integrity")) return true;
    if (strstr(ns, "_Services.AppCheck")) return true;
    if (strstr(ns, "_Services.Security")) return true;

    return false;
}

// ---------- ДАМП ОДНОЙ СБОРКИ — только AC ----------
static void AX_DumpAssemblyAC(void* image, const char* asmName) {
    if (!image) return;
    size_t count = p_image_get_class_count ? p_image_get_class_count(image) : 0;
    if (count == 0) return;

    bool printed_header = false;

    for (size_t j = 0; j < count; j++) {
        void* klass = p_image_get_class(image, j);
        if (!klass) continue;
        const char* cname = p_class_get_name(klass);
        const char* cns   = p_class_get_namespace ? p_class_get_namespace(klass) : "";
        if (!cname) continue;
        if (!cns) cns = "";

        if (!isACClass(cns, cname)) continue;

        if (!printed_header) {
            AXLog("[AX] === assembly %s (%zu classes total) ===",
                  asmName ? asmName : "?", count);
            printed_header = true;
        }

        AXLog("CLASS %s.%s", cns, cname);

        void* k = p_class_from_name(image, cns, cname);
        if (!k) { AXLog("  -- lookup failed --"); continue; }

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

void AX_DumpAllClasses(void) {
    if (!p_domain_get) return;
    void* domain = p_domain_get();
    if (!domain) { AXLog("[AX] no domain"); return; }
    if (!p_domain_get_assemblies) { AXLog("[AX] no domain_get_assemblies"); return; }

    size_t count = 0;
    void** asms = (void**)p_domain_get_assemblies(domain, &count);
    AXLog("[AX] domain has %zu assemblies", count);

    for (size_t i = 0; i < count; i++) {
        void* asm_ = asms[i];
        if (!asm_) continue;
        void* img = p_assembly_get_image(asm_);
        if (!img) continue;
        const char* iname = p_image_get_name ? p_image_get_name(img) : "?";
        AX_DumpAssemblyAC(img, iname);
    }
}

void AX_InstallRuntimeHooks(void) {
    AXLog("[AX] === AXMenu AC-dump start ===");

    if (!AX_ResolveIL2CPP()) {
        AXLog("[AX] resolve FAILED");
        return;
    }
    AXLog("[AX] resolve OK");

    AX_DumpAllClasses();

    AXLog("[AX] === AXMenu AC-dump done ===");
}