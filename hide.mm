// language: Objective-C++, file: hide.mm
#import <Foundation/Foundation.h>
#import <substrate.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#include "fishhook.h"

// Объявление функции вместо hide.h
extern "C" void HX_Install(void);

static int (*orig_csops)(pid_t, uint32_t, void*, size_t) = nullptr;
static int (*orig_sysctl)(int*, u_int, void*, size_t*, void*, size_t) = nullptr;
static char* (*orig_getenv)(const char*) = nullptr;
static int (*orig_ptrace)(int, pid_t, caddr_t, int) = nullptr;
static int (*orig_sandbox_check)(pid_t, const char*, int) = nullptr;

static int hx_csops(pid_t pid, uint32_t ops, void* useraddr, size_t usersize) {
    int r = orig_csops(pid, ops, useraddr, usersize);
    if (r == 0 && ops == 0 && useraddr && usersize >= sizeof(uint32_t)) {
        uint32_t flags = *(uint32_t*)useraddr;
        *(uint32_t*)useraddr = flags & ~0x10000000u;
    }
    return r;
}

static int hx_sysctl(int* name, u_int namelen, void* oldp, size_t* oldlenp, void* newp, size_t newlen) {
    if (name && namelen >= 2 && name[0] == CTL_KERN && (name[1] == KERN_PROC || name[1] == KERN_PROCARGS2)) {
        errno = EPERM;
        return -1;
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static char* hx_getenv(const char* name) {
    if (name && (strstr(name, "DYLD") || strstr(name, "FRIDA"))) return nullptr;
    return orig_getenv(name);
}

static int hx_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == PT_DENY_ATTACH || request == PT_TRACE_ME) {
        return 0;
    }
    return orig_ptrace(request, pid, addr, data);
}

static int hx_sandbox_check(pid_t pid, const char* operation, int flags) {
    return 1;
}

extern "C" void HX_Install(void) {
    struct rebinding rebindings[] = {
        {"csops", (void *)hx_csops, (void **)&orig_csops},
        {"sysctl", (void *)hx_sysctl, (void **)&orig_sysctl},
        {"getenv", (void *)hx_getenv, (void **)&orig_getenv},
        {"ptrace", (void *)hx_ptrace, (void **)&orig_ptrace},
        {"sandbox_check", (void *)hx_sandbox_check, (void **)&orig_sandbox_check}
    };
    rebind_symbols(rebindings, 5);
}