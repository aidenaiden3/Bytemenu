#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIWindow* overlayWindow = nil;
static UIView* menuPanel = nil;
static BOOL menuOpen = NO;

static void setupMenu() {
    overlayWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    overlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
    overlayWindow.backgroundColor = UIColor.clearColor;
    overlayWindow.userInteractionEnabled = YES;
    overlayWindow.hidden = NO;

    UIViewController* vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    overlayWindow.rootViewController = vc;
    UIView* root = vc.view;

    UIButton* eBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    eBtn.frame = CGRectMake(10, 60, 46, 46);
    eBtn.backgroundColor = [UIColor colorWithRed:0 green:0.45 blue:0.85 alpha:1];
    eBtn.layer.cornerRadius = 12;
    eBtn.layer.masksToBounds = YES;
    [eBtn setTitle:@"E" forState:UIControlStateNormal];
    [eBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    eBtn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [eBtn addTarget:vc action:NSSelectorFromString(@"eBtnTapped:") forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:eBtn];

    menuPanel = [[UIView alloc] initWithFrame:CGRectMake(10, 116, 285, 410)];
    menuPanel.backgroundColor = [UIColor colorWithRed:0 green:0.42 blue:0.8 alpha:0.95];
    menuPanel.layer.cornerRadius = 16;
    menuPanel.layer.masksToBounds = YES;
    menuPanel.hidden = YES;
    menuPanel.alpha = 0.0;
    [root addSubview:menuPanel];

    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(0, 6, 285, 36)];
    title.text = @"Byte Menu";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16];
    [menuPanel addSubview:title];

    UIView* div = [[UIView alloc] initWithFrame:CGRectMake(10, 42, 265, 1)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
    [menuPanel addSubview:div];

    NSArray* opts = @[
        @"God Mode", @"Fly", @"No Clip", @"Spider Climb",
        @"Invisible", @"Big Hands", @"Super Push",
        @"Freeze Players", @"ESP", @"Full Bright"
    ];

    CGFloat y = 50;
    for (NSString* opt in opts) {
        UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake(8, y, 269, 32);
        btn.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        btn.layer.cornerRadius = 8;
        [btn setTitle:[NSString stringWithFormat:@"%@: OFF", opt] forState:UIControlStateNormal];
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        btn.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
        [btn addTarget:vc action:NSSelectorFromString(@"optionTapped:") forControlEvents:UIControlEventTouchUpInside];
        [menuPanel addSubview:btn];
        y += 36;
    }

    class_addMethod([vc class], NSSelectorFromString(@"eBtnTapped:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            menuOpen = !menuOpen;
            menuPanel.hidden = NO;
            [UIView animateWithDuration:0.2 animations:^{
                menuPanel.alpha = menuOpen ? 1.0 : 0.0;
            } completion:^(BOOL done){
                if (!menuOpen) menuPanel.hidden = YES;
            }];
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"optionTapped:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            BOOL on = [b.currentTitle hasSuffix:@"ON"];
            NSString* name = [b.currentTitle componentsSeparatedByString:@":"][0];
            [b setTitle:[NSString stringWithFormat:@"%@: %@", name, on ? @"OFF" : @"ON"] forState:UIControlStateNormal];
            b.backgroundColor = on
                ? [UIColor colorWithWhite:1 alpha:0.12]
                : [UIColor colorWithRed:0 green:0.75 blue:0.45 alpha:0.35];
        }), "v@:@");
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setupMenu();
    });
}
