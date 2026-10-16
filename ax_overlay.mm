#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "esp.h"

@interface AXMenuView : UIView
@end

@implementation AXMenuView {
    UIView* _header;
    UIScrollView* _scroll;
}

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.backgroundColor = [UIColor colorWithRed:10/255.0 green:14/255.0 blue:22/255.0 alpha:0.94];
    self.layer.cornerRadius = 12;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [UIColor colorWithRed:63/255.0 green:229/255.0 blue:255/255.0 alpha:1].CGColor;
    self.clipsToBounds = YES;

    _header = [[UIView alloc] initWithFrame:CGRectMake(0,0,f.size.width,44)];
    _header.backgroundColor = [UIColor colorWithRed:63/255.0 green:229/255.0 blue:255/255.0 alpha:0.12];
    UILabel* t = [[UILabel alloc] initWithFrame:CGRectMake(12,0,f.size.width-50,44)];
    t.text = @"AX // standoff";
    t.textColor = [UIColor colorWithRed:63/255.0 green:229/255.0 blue:255/255.0 alpha:1];
    t.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightBold];
    [_header addSubview:t];
    [self addSubview:_header];

    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [_header addGestureRecognizer:pan];

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0,44,f.size.width,f.size.height-44)];
    _scroll.alwaysBounceVertical = YES;
    [self addSubview:_scroll];

    CGFloat y = 12;
    y = [self section:@"visuals" at:y];
    y = [self addToggle:@"ESP boxes"   at:y key:&g_cfg.esp];
    y = [self addToggle:@"ESP health"  at:y key:&g_cfg.esp_health];
    y = [self section:@"aim" at:y];
    y = [self addToggle:@"Aimbot"      at:y key:&g_cfg.aimbot];
    y = [self addSlider:@"aim fov"    min:1 max:180 at:y val:&g_cfg.aim_fov];
    y = [self addSlider:@"aim smooth" min:1 max:30  at:y val:&g_cfg.aim_smooth];
    _scroll.contentSize = CGSizeMake(f.size.width, y + 12);
    return self;
}

- (CGFloat)section:(NSString*)name at:(CGFloat)y {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(14,y,300,24)];
    l.text = [NSString stringWithFormat:@"◉ %@", name];
    l.textColor = [UIColor colorWithRed:63/255.0 green:229/255.0 blue:255/255.0 alpha:1];
    l.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];
    [_scroll addSubview:l];
    return y + 30;
}

- (void)drag:(UIPanGestureRecognizer*)g {
    CGPoint d = [g translationInView:self.superview];
    CGPoint c = self.center; c.x += d.x; c.y += d.y; self.center = c;
    [g setTranslation:CGPointZero inView:self.superview];
}

- (CGFloat)addToggle:(NSString*)title at:(CGFloat)y key:(bool*)k {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(14,y,220,30)];
    l.text = title; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:14];
    [_scroll addSubview:l];
    UISwitch* s = [[UISwitch alloc] initWithFrame:CGRectMake(250,y+3,51,31)];
    s.onTintColor = [UIColor colorWithRed:63/255.0 green:229/255.0 blue:255/255.0 alpha:1];
    s.on = *k;
    [s addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(s, "k", [NSValue valueWithPointer:k], OBJC_ASSOCIATION_RETAIN);
    [_scroll addSubview:s];
    return y + 42;
}

- (void)swChanged:(UISwitch*)s {
    NSValue* v = objc_getAssociatedObject(s, "k");
    bool* k = (bool*)[v pointerValue];
    if (k) *k = s.on;
}

- (CGFloat)addSlider:(NSString*)title min:(float)lo max:(float)hi at:(CGFloat)y val:(float*)v {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(14,y,220,20)];
    l.text = title; l.textColor = UIColor.lightGrayColor; l.font = [UIFont systemFontOfSize:12];
    [_scroll addSubview:l];
    UISlider* s = [[UISlider alloc] initWithFrame:CGRectMake(14,y+20,250,30)];
    s.minimumValue = lo; s.maximumValue = hi; s.value = *v;
    s.minimumTrackTintColor = [UIColor colorWithRed:63/255.0 green:229/255.0 blue:255/255.0 alpha:1];
    [s addTarget:self action:@selector(slChanged:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(s, "v", [NSValue valueWithPointer:v], OBJC_ASSOCIATION_RETAIN);
    [_scroll addSubview:s];
    return y + 58;
}

- (void)slChanged:(UISlider*)s {
    NSValue* v = objc_getAssociatedObject(s, "v");
    float* p = (float*)[v pointerValue];
    if (p) *p = s.value;
}
@end

static UIWindow* g_axWin = nil;
static UIView*   g_canvas = nil;

@interface AXWin : UIWindow
@end
@implementation AXWin
- (void)axToggle:(id)s { self.hidden = !self.hidden; }
@end

void AX_StartOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGRect scr = UIScreen.mainScreen.bounds;
        CGRect fr = CGRectMake(scr.size.width-360, 80, 340, 440);

        g_axWin = [[AXWin alloc] initWithFrame:scr];
        g_axWin.windowLevel = UIWindowLevelAlert + 1;
        g_axWin.backgroundColor = UIColor.clearColor;
        g_axWin.rootViewController = [UIViewController new];

        g_canvas = [[UIView alloc] initWithFrame:scr];
        g_canvas.backgroundColor = UIColor.clearColor;
        g_canvas.userInteractionEnabled = NO;
        [g_axWin.rootViewController.view addSubview:g_canvas];

        AXMenuView* mv = [[AXMenuView alloc] initWithFrame:fr];
        mv.userInteractionEnabled = YES;
        [g_axWin.rootViewController.view addSubview:mv];

        g_axWin.hidden = NO;

        UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:g_axWin action:@selector(axToggle:)];
        tap.numberOfTapsRequired = 2;
        tap.numberOfTouchesRequired = 3;
        [g_axWin.rootViewController.view addGestureRecognizer:tap];
    });
}

void AX_DrawESP(void) {
    if (!g_cfg.esp) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_canvas) return;
        for (UIView* v in [g_canvas subviews]) {
            if (v.tag == 9999) [v removeFromSuperview];
        }
        // TODO: рендер боксов после того как AX_WorldToScreen заработает
    });
}
