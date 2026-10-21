// language: Objective-C++, file: hooks.mm
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <string.h>
#include <sys/mman.h>
#include <libkern/OSCacheControl.h>
#include <mach-o/dyld.h>
#include <mach/vm_map.h>
#include <mach/mach.h> // <-- Добавили эту строку
#include "esp.h"

void AX_WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ax_memory_scan.txt"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:path]) {
        [fileManager createFileAtPath:path contents:nil attributes:nil];
    }
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[message dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

void scan_memory_for_string(const char* target) {
    AX_WriteLog(@"[AX] Starting scan for '%s'...", target);
    
    vm_map_t task = mach_task_self();
    vm_address_t address = 0;
    vm_size_t size = 0;
    natural_t depth = 0;
    struct vm_region_submap_info_64 info;
    mach_msg_type_number_t count;

    while (1) {
        count = VM_REGION_SUBMAP_INFO_COUNT_64;
        kern_return_t kr = vm_region_recurse_64(task, &address, &size, &depth, (vm_region_info_64_t)&info, &count);
        if (kr != KERN_SUCCESS) break;

        if (info.is_submap) {
            depth++;
        } else {
            if ((info.protection & VM_PROT_READ) && !(info.protection & VM_PROT_EXECUTE)) {
                char* ptr = (char*)address;
                size_t len = size;
                
                for (size_t i = 0; i < len - strlen(target); i++) {
                    if (memcmp(ptr + i, target, strlen(target)) == 0) {
                        AX_WriteLog(@"[AX] FOUND '%s' at address 0x%lx", target, (uintptr_t)(ptr + i));
                    }
                }
            }
            address += size;
        }
    }
    AX_WriteLog(@"[AX] Scan for '%s' finished.", target);
}

void AX_InstallRuntimeHooks(void) {
    AX_WriteLog(@"[AX] === Memory Scan Started ===");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        scan_memory_for_string("Injected");
        scan_memory_for_string("Root");
        scan_memory_for_string("DeviceCheck");
        scan_memory_for_string("Jailbreak");
        AX_WriteLog(@"[AX] === Memory Scan Finished ===");
    });
}