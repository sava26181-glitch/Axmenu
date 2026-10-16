#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>
#import "esp.h"

%ctor {
    // ждём 8 секунд — Unity IL2CPP успеет полностью загрузиться
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        AX_InstallRuntimeHooks();
        AX_StartOverlay();

        // АВТОМАТИЧЕСКИЙ ДАМП через 3 секунды после старта хуков
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            NSLog(@"[AX] === starting class dump ===");
            AX_DumpAllClasses();
            NSLog(@"[AX] === dump finished ===");
        });
    });
}
