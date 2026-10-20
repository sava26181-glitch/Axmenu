// language: Objective-C++, file: esp.mm
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include "esp.h"

static UIWindow *g_overlayWindow = nil;

void AX_StartOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_overlayWindow) {
            g_overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            g_overlayWindow.windowLevel = UIWindowLevelAlert + 1;
            g_overlayWindow.backgroundColor = [UIColor clearColor];
            g_overlayWindow.rootViewController = [[UIViewController alloc] init];
            g_overlayWindow.rootViewController.view.backgroundColor = [UIColor clearColor];
            
            UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
            btn.frame = CGRectMake(20, 100, 150, 50);
            btn.backgroundColor = [UIColor blackColor];
            [btn setTitle:@"AXMenu Active" forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor greenColor] forState:UIControlStateNormal];
            [g_overlayWindow.rootViewController.view addSubview:btn];
            
            g_overlayWindow.hidden = NO;
        }
    });
}
