// language: Logos, file: axmenu.xm
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include "esp.h"

#ifdef __cplusplus
extern "C" {
#endif
void HX_Install(void);
#ifdef __cplusplus
}
#endif

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        HX_Install();
        AX_StartOverlay();
    });
}