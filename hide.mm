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
#include "fishhook.h"

extern "C" void HX_Install(void);
extern char **environ; // Доступ к переменным окружения

#define PT_TRACE_ME_VAL 0
#define PT_DENY_ATTACH_VAL 31

// ... (все оригиналы и хуки из прошлого кода) ...

// --- НОВЫЕ ХУКИ ---

static unsigned long (*orig_getauxval)(unsigned long) = nullptr;
static unsigned long hx_getauxval(unsigned long type) {
    // AT_SECURE = 23. Если Warden спрашивает, мы говорим, что всё безопасно (1)
    if (type == 23) return 1; 
    return orig_getauxval(type);
}

extern "C" void HX_Install(void) {
    // 1. Очищаем environ от палева
    if (environ) {
        for (int i = 0; environ[i]; i++) {
            if (strstr(environ[i], "DYLD") || strstr(environ[i], "FRIDA")) {
                environ[i][0] = '\0'; // Зануляем строку
            }
        }
    }

    // 2. Ставим хуки
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
        {"getauxval", (void *)hx_getauxval, (void **)&orig_getauxval} // <-- Новый хук
    };
    rebind_symbols(rebindings, 14);
}