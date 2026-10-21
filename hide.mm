// language: Objective-C++, file: hide.mm
#import <Foundation/Foundation.h>
#import <substrate.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <dirent.h>
#import <dlfcn.h>
#import <string.h>
#import <stdlib.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <mach-o/dyld.h>
#include "fishhook.h"

extern "C" void HX_Install(void);
extern char **environ;

#define PT_TRACE_ME_VAL 0
#define PT_DENY_ATTACH_VAL 31

// ================== ЛОГ ==================
static FILE* g_hx_log = nullptr;

static void HX_LogInit(void) {
    if (g_hx_log) return;
    NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ax_hide_log.txt"];
    g_hx_log = fopen([path UTF8String], "a");
}

void HX_Log(NSString* fmt, ...) {
    HX_LogInit();
    if (!g_hx_log) return;
    va_list ap; va_start(ap, fmt);
    NSString* s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fputs(s.UTF8String, g_hx_log);
    fputc('\n', g_hx_log);
    fflush(g_hx_log);
}

// ================== ПУТИ ==================
static const char* g_suspect_paths[] = {
    "/var/jb", "/var/jb/", "/private/preboot", "/var/LIB",
    "/var/containers/Bundle/tweaksupport",
    "/var/mobile/Library/Preferences/com.opa334",
    "/var/mobile/Library/Preferences/org.coolstar",
    "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
    "/Library/MobileSubstrate", "/usr/lib/libsubstrate.dylib", "/usr/lib/libsubstitute.dylib",
    "/bin/bash", "/bin/sh", "/usr/bin/ssh", "/usr/sbin/sshd",
    "/private/var/lib/apt", "/private/var/lib/cydia", "/private/var/stash",
    "/var/lib/dpkg", "/var/lib/cydia", "/var/log/syslog",
    "/usr/bin/dpkg", "/usr/sbin/frida-server", "/usr/bin/frida-server",
    "/usr/lib/libhooker.dylib", "/usr/lib/libcycript.dylib",
    "/var/mobile/Documents/axmenu", "com.ax.axmenu",
    NULL
};

static int is_suspect(const char* path) {
    if (!path) return 0;
    for (int i = 0; g_suspect_paths[i]; i++) {
        if (strstr(path, g_suspect_paths[i])) {
            HX_Log(@"[HX] BLOCKED: %s", path);
            return 1;
        }
    }
    return 0;
}

static const char* kFakeReadlink = "/private/var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000000";
static const char* kFakeStatSrc = "/usr/lib/libSystem.B.dylib";

// ================== ОРИГИНАЛЫ ==================
static FILE* (*orig_fopen)(const char*, const char*) = nullptr;
static int   (*orig_stat)(const char*, struct stat*) = nullptr;
static int   (*orig_lstat)(const char*, struct stat*) = nullptr;
static int   (*orig_access)(const char*, int) = nullptr;
static ssize_t (*orig_readlink)(const char*, char*, size_t) = nullptr;
static DIR*  (*orig_opendir)(const char*) = nullptr;
static int   (*orig_csops)(pid_t, uint32_t, void*, size_t) = nullptr;
static int   (*orig_sysctl)(int*, u_int, void*, size_t*, void*, size_t) = nullptr;
static char* (*orig_getenv)(const char*) = nullptr;
static int   (*orig_ptrace)(int, pid_t, caddr_t, int) = nullptr;
static int   (*orig_sandbox_check)(pid_t, const char*, int) = nullptr;
static int   (*orig_statfs)(const char*, struct statfs*) = nullptr;
static int   (*orig_getfsstat)(struct statfs*, int, int) = nullptr;
static unsigned long (*orig_getauxval)(unsigned long) = nullptr;
static int   (*orig_proc_pidinfo)(int, int, uint64_t, void*, int) = nullptr;
static int   (*orig_csrctl)(uint32_t, void*, size_t) = nullptr;
static int   (*orig_sysctlbyname)(const char*, void*, size_t*, void*, size_t) = nullptr;
static uint32_t (*orig_dyld_image_count)(void) = nullptr;
static const char* (*orig_dyld_get_image_name)(uint32_t) = nullptr;

// ================== ХУКИ ==================
static FILE* hx_fopen(const char* path, const char* mode) {
    if (is_suspect(path)) return orig_fopen("/dev/null", mode);
    return orig_fopen(path, mode);
}

static int hx_stat(const char* path, struct stat* st) {
    if (is_suspect(path)) return orig_stat(kFakeStatSrc, st);
    return orig_stat(path, st);
}

static int hx_lstat(const char* path, struct stat* st) {
    if (is_suspect(path)) return orig_lstat(kFakeStatSrc, st);
    return orig_lstat(path, st);
}

static int hx_access(const char* path, int mode) {
    if (is_suspect(path)) { errno = ENOENT; return -1; }
    return orig_access(path, mode);
}

static ssize_t hx_readlink(const char* path, char* buf, size_t sz) {
    if (is_suspect(path)) {
        size_t n = strlen(kFakeReadlink);
        if (n >= sz) n = sz - 1;
        memcpy(buf, kFakeReadlink, n); buf[n] = 0;
        return (ssize_t)n;
    }
    return orig_readlink(path, buf, sz);
}

static DIR* hx_opendir(const char* path) {
    if (is_suspect(path)) return orig_opendir("/private/var/mobile");
    return orig_opendir(path);
}

static int hx_csops(pid_t pid, uint32_t ops, void* useraddr, size_t usersize) {
    int r = orig_csops(pid, ops, useraddr, usersize);
    if (r == 0 && ops == 0 && useraddr && usersize >= sizeof(uint32_t)) {
        uint32_t flags = *(uint32_t*)useraddr;
        *(uint32_t*)useraddr = flags & ~0x10000000u;
        if (flags != *(uint32_t*)useraddr) HX_Log(@"[HX] csops: cleared CS_DEBUGGED");
    }
    return r;
}

static int hx_sysctl(int* name, u_int namelen, void* oldp, size_t* oldlenp, void* newp, size_t newlen) {
    if (name && namelen >= 2 && name[0] == CTL_KERN && (name[1] == KERN_PROC || name[1] == KERN_PROCARGS2)) {
        HX_Log(@"[HX] sysctl: blocked KERN_PROC");
        errno = EPERM;
        return -1;
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static char* hx_getenv(const char* name) {
    if (name && (strstr(name, "DYLD") || strstr(name, "FRIDA"))) {
        HX_Log(@"[HX] getenv: blocked %s", name);
        return nullptr;
    }
    return orig_getenv(name);
}

static int hx_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    if (request == PT_TRACE_ME_VAL || request == PT_DENY_ATTACH_VAL) return 0;
    return orig_ptrace(request, pid, addr, data);
}

static int hx_sandbox_check(pid_t pid, const char* operation, int flags) {
    return 1;
}

static int hx_statfs(const char* path, struct statfs* buf) {
    int r = orig_statfs(path, buf);
    if (r == 0 && buf) buf->f_flags &= ~MNT_ROOTFS;
    return r;
}

static int hx_getfsstat(struct statfs* buf, int bufsize, int flags) {
    int n = orig_getfsstat(buf, bufsize, flags);
    if (n > 0 && buf) {
        for (int i = 0; i < n; i++) {
            if (strstr(buf[i].f_mntonname, "/var/jb")) {
                strcpy(buf[i].f_mntonname, "/");
                buf[i].f_flags &= ~MNT_ROOTFS;
            }
        }
    }
    return n;
}

static unsigned long hx_getauxval(unsigned long type) {
    if (type == 23) return 1; // AT_SECURE
    return orig_getauxval(type);
}

static int hx_proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize) {
    int r = orig_proc_pidinfo(pid, flavor, arg, buffer, buffersize);
    if (r > 0 && flavor == 13 && buffer) {
        uint8_t *ptr = (uint8_t *)buffer;
        if (buffersize >= 0x20) memset(ptr + 0x1C, 0, 4);
    }
    return r;
}

static int hx_csrctl(uint32_t op, void *data, size_t len) {
    return 1;
}

static int hx_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && (strcmp(name, "kern.secure_kernel") == 0 || strcmp(name, "security.mac.sandbox.sentinel") == 0)) {
        int one = 1;
        if (oldp && oldlenp && *oldlenp >= sizeof(int)) {
            memcpy(oldp, &one, sizeof(int));
            *oldlenp = sizeof(int);
            return 0;
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

static uint32_t hx_dyld_image_count(void) {
    return orig_dyld_image_count();
}

static const char* hx_dyld_get_image_name(uint32_t idx) {
    const char* name = orig_dyld_get_image_name(idx);
    if (name && is_suspect(name)) {
        HX_Log(@"[HX] dyld: hiding %s", name);
        return "/usr/lib/libSystem.B.dylib";
    }
    return name;
}

extern "C" void HX_Install(void) {
    HX_Log(@"[HX] === HX_Install start ===");
    
    if (environ) {
        for (int i = 0; environ[i]; i++) {
            if (strstr(environ[i], "DYLD") || strstr(environ[i], "FRIDA")) {
                environ[i][0] = '\0';
            }
        }
    }

    struct rebinding rebindings[] = {
        {"fopen", (void *)hx_fopen, (void **)&orig_fopen},
        {"stat", (void *)hx_stat, (void **)&orig_stat},
        {"lstat", (void *)hx_lstat, (void **)&orig_lstat},
        {"access", (void *)hx_access, (void **)&orig_access},
        {"readlink", (void *)hx_readlink, (void **)&orig_readlink},
        {"opendir", (void *)hx_opendir, (void **)&orig_opendir},
        {"csops", (void *)hx_csops, (void **)&orig_csops},
        {"sysctl", (void *)hx_sysctl, (void **)&orig_sysctl},
        {"getenv", (void *)hx_getenv, (void **)&orig_getenv},
        {"ptrace", (void *)hx_ptrace, (void **)&orig_ptrace},
        {"sandbox_check", (void *)hx_sandbox_check, (void **)&orig_sandbox_check},
        {"statfs", (void *)hx_statfs, (void **)&orig_statfs},
        {"getfsstat", (void *)hx_getfsstat, (void **)&orig_getfsstat},
        {"getauxval", (void *)hx_getauxval, (void **)&orig_getauxval},
        {"proc_pidinfo", (void *)hx_proc_pidinfo, (void **)&orig_proc_pidinfo},
        {"csrctl", (void *)hx_csrctl, (void **)&orig_csrctl},
        {"sysctlbyname", (void *)hx_sysctlbyname, (void **)&orig_sysctlbyname},
        {"_dyld_image_count", (void *)hx_dyld_image_count, (void **)&orig_dyld_image_count},
        {"_dyld_get_image_name", (void *)hx_dyld_get_image_name, (void **)&orig_dyld_get_image_name}
    };
    rebind_symbols(rebindings, 19);
    
    HX_Log(@"[HX] === HX_Install done ===");
}