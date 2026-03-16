#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ─── Passthrough Window ───────────────────────────────────────────────────
@interface PassthroughWindow : UIWindow
@end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

// ─── Globals ──────────────────────────────────────────────────────────────
static PassthroughWindow* overlayWindow = nil;
static UIView* menuPanel = nil;
static BOOL menuOpen = NO;
static NSInteger activeTab = 0;
static NSMutableArray* tabContents = nil;

// ─── Colors ───────────────────────────────────────────────────────────────
#define COLOR_BG     [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.97]
#define COLOR_ACCENT [UIColor colorWithRed:0.18 green:0.75 blue:0.55 alpha:1.0]
#define COLOR_BTN    [UIColor colorWithRed:0.15 green:0.18 blue:0.24 alpha:1.0]
#define COLOR_WHITE  [UIColor whiteColor]
#define COLOR_GRAY   [UIColor colorWithWhite:0.6 alpha:1.0]

// ─── Helper: make a styled button ─────────────────────────────────────────
static UIButton* makeBtn(NSString* title, CGRect frame) {
    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.backgroundColor = COLOR_BTN;
    btn.layer.cornerRadius = 8;
    btn.layer.masksToBounds = YES;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:COLOR_WHITE forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    return btn;
}

// ─── Helper: make a label ─────────────────────────────────────────────────
static UILabel* makeLabel(NSString* text, CGRect frame, CGFloat size, BOOL bold) {
    UILabel* lbl = [[UILabel alloc] initWithFrame:frame];
    lbl.text = text;
    lbl.textColor = COLOR_WHITE;
    lbl.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    return lbl;
}

// ─── Tab: Players ─────────────────────────────────────────────────────────
static UIView* buildPlayersTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 340)];

    UILabel* info = makeLabel(@"Local Actor: --\nNickName: --\nRoom: --", CGRectMake(10, 8, 265, 60), 11, NO);
    info.numberOfLines = 0;
    info.textColor = COLOR_ACCENT;
    info.tag = 1001;
    [v addSubview:info];

    UILabel* hdr = makeLabel(@"Players in Lobby", CGRectMake(10, 72, 265, 20), 12, YES);
    hdr.textColor = COLOR_GRAY;
    [v addSubview:hdr];

    UIScrollView* scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 96, 285, 240)];
    scroll.tag = 1002;
    [v addSubview:scroll];

    return v;
}

// ─── Tab: Spawner ─────────────────────────────────────────────────────────
static UIView* buildSpawnerTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 340)];

    NSArray* items = @[
        @"Bean", @"Bomb", @"Confetti Gun", @"Balloon",
        @"Basketball", @"Boomerang", @"Air Blaster", @"Candy",
        @"Flashlight", @"Umbrella"
    ];

    CGFloat y = 8;
    for (NSString* item in items) {
        UIButton* btn = makeBtn([NSString stringWithFormat:@"⊕  %@", item], CGRectMake(8, y, 269, 30));
        btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        btn.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 0);
        [btn addTarget:vc action:NSSelectorFromString(@"spawnItem:") forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:btn];
        y += 34;
    }

    return v;
}

// ─── Tab: RPC Caller ──────────────────────────────────────────────────────
static UIView* buildRPCTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 340)];

    UILabel* lbl = makeLabel(@"RPC Name", CGRectMake(10, 8, 265, 18), 12, NO);
    lbl.textColor = COLOR_GRAY;
    [v addSubview:lbl];

    UITextField* rpcField = [[UITextField alloc] initWithFrame:CGRectMake(8, 28, 269, 36)];
    rpcField.backgroundColor = COLOR_BTN;
    rpcField.layer.cornerRadius = 8;
    rpcField.textColor = COLOR_WHITE;
    rpcField.font = [UIFont systemFontOfSize:13];
    rpcField.tag = 2001;
    rpcField.placeholder = @"e.g. SetSpeed";
    rpcField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"e.g. SetSpeed" attributes:@{NSForegroundColorAttributeName: COLOR_GRAY}];
    UIView* pad = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    rpcField.leftView = pad;
    rpcField.leftViewMode = UITextFieldViewModeAlways;
    [v addSubview:rpcField];

    UILabel* lbl2 = makeLabel(@"Parameters (optional)", CGRectMake(10, 72, 265, 18), 12, NO);
    lbl2.textColor = COLOR_GRAY;
    [v addSubview:lbl2];

    UITextField* paramField = [[UITextField alloc] initWithFrame:CGRectMake(8, 92, 269, 36)];
    paramField.backgroundColor = COLOR_BTN;
    paramField.layer.cornerRadius = 8;
    paramField.textColor = COLOR_WHITE;
    paramField.font = [UIFont systemFontOfSize:13];
    paramField.tag = 2002;
    paramField.placeholder = @"e.g. 10";
    paramField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"e.g. 10" attributes:@{NSForegroundColorAttributeName: COLOR_GRAY}];
    paramField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    paramField.leftViewMode = UITextFieldViewModeAlways;
    [v addSubview:paramField];

    UIButton* sendBtn = makeBtn(@"Send RPC", CGRectMake(8, 140, 269, 36));
    sendBtn.backgroundColor = COLOR_ACCENT;
    [sendBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    sendBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [sendBtn addTarget:vc action:NSSelectorFromString(@"sendRPC:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:sendBtn];

    UILabel* logHdr = makeLabel(@"RPC Log", CGRectMake(10, 188, 265, 18), 12, YES);
    logHdr.textColor = COLOR_GRAY;
    [v addSubview:logHdr];

    UITextView* log = [[UITextView alloc] initWithFrame:CGRectMake(8, 208, 269, 120)];
    log.backgroundColor = COLOR_BTN;
    log.layer.cornerRadius = 8;
    log.textColor = COLOR_ACCENT;
    log.font = [UIFont systemFontOfSize:11];
    log.editable = NO;
    log.tag = 2003;
    log.text = @"RPC log will appear here...";
    [v addSubview:log];

    return v;
}

// ─── Tab: Profile ─────────────────────────────────────────────────────────
static UIView* buildProfileTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 340)];

    // Display name
    UILabel* lbl1 = makeLabel(@"Display Name", CGRectMake(10, 8, 265, 18), 12, NO);
    lbl1.textColor = COLOR_GRAY;
    [v addSubview:lbl1];

    UITextField* nameField = [[UITextField alloc] initWithFrame:CGRectMake(8, 28, 200, 36)];
    nameField.backgroundColor = COLOR_BTN;
    nameField.layer.cornerRadius = 8;
    nameField.textColor = COLOR_WHITE;
    nameField.font = [UIFont systemFontOfSize:13];
    nameField.tag = 3001;
    nameField.placeholder = @"Enter name...";
    nameField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Enter name..." attributes:@{NSForegroundColorAttributeName: COLOR_GRAY}];
    nameField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    nameField.leftViewMode = UITextFieldViewModeAlways;
    [v addSubview:nameField];

    UIButton* setNameBtn = makeBtn(@"Set", CGRectMake(214, 28, 63, 36));
    setNameBtn.backgroundColor = COLOR_ACCENT;
    [setNameBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [setNameBtn addTarget:vc action:NSSelectorFromString(@"setDisplayName:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:setNameBtn];

    // Color
    UILabel* lbl2 = makeLabel(@"Player Color", CGRectMake(10, 80, 265, 18), 12, NO);
    lbl2.textColor = COLOR_GRAY;
    [v addSubview:lbl2];

    NSArray* colors = @[@"Red", @"Blue", @"Green", @"Pink", @"Gold", @"White"];
    NSArray* colorVals = @[
        [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1],
        [UIColor colorWithRed:0.2 green:0.4 blue:0.9 alpha:1],
        [UIColor colorWithRed:0.2 green:0.75 blue:0.3 alpha:1],
        [UIColor colorWithRed:0.9 green:0.4 blue:0.7 alpha:1],
        [UIColor colorWithRed:0.9 green:0.75 blue:0.1 alpha:1],
        [UIColor whiteColor]
    ];

    CGFloat cx = 8;
    CGFloat cy = 104;
    for (NSInteger i = 0; i < colors.count; i++) {
        UIButton* cb = [UIButton buttonWithType:UIButtonTypeCustom];
        cb.frame = CGRectMake(cx, cy, 84, 36);
        cb.backgroundColor = colorVals[i];
        cb.layer.cornerRadius = 8;
        [cb setTitle:colors[i] forState:UIControlStateNormal];
        [cb setTitleColor:i == 5 ? [UIColor blackColor] : COLOR_WHITE forState:UIControlStateNormal];
        cb.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [cb addTarget:vc action:NSSelectorFromString(@"setPlayerColor:") forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:cb];
        cx += 90;
        if (cx > 200) { cx = 8; cy += 42; }
    }

    return v;
}

// ─── Main setup ───────────────────────────────────────────────────────────
static void setupMenu() {
    overlayWindow = [[PassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    overlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
    overlayWindow.backgroundColor = UIColor.clearColor;
    overlayWindow.userInteractionEnabled = YES;
    overlayWindow.hidden = NO;

    UIViewController* vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    overlayWindow.rootViewController = vc;
    UIView* root = vc.view;

    // ── E Button ──────────────────────────────────────────────────────────
    UIButton* eBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    eBtn.frame = CGRectMake(10, 60, 46, 46);
    eBtn.backgroundColor = COLOR_ACCENT;
    eBtn.layer.cornerRadius = 12;
    eBtn.layer.masksToBounds = YES;
    [eBtn setTitle:@"Y" forState:UIControlStateNormal];
    [eBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    eBtn.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [eBtn addTarget:vc action:NSSelectorFromString(@"eBtnTapped:") forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:eBtn];

    // ── Menu Panel ────────────────────────────────────────────────────────
    menuPanel = [[UIView alloc] initWithFrame:CGRectMake(10, 116, 285, 430)];
    menuPanel.backgroundColor = COLOR_BG;
    menuPanel.layer.cornerRadius = 16;
    menuPanel.layer.masksToBounds = YES;
    menuPanel.hidden = YES;
    menuPanel.alpha = 0.0;
    [root addSubview:menuPanel];

    // Header
    UILabel* title = makeLabel(@"YeepsMod", CGRectMake(12, 10, 180, 24), 17, YES);
    title.textColor = COLOR_ACCENT;
    [menuPanel addSubview:title];

    UILabel* version = makeLabel(@"V3", CGRectMake(200, 10, 40, 24), 13, YES);
    version.textColor = COLOR_GRAY;
    version.textAlignment = NSTextAlignmentCenter;
    version.layer.cornerRadius = 8;
    version.layer.masksToBounds = YES;
    version.backgroundColor = COLOR_BTN;
    [menuPanel addSubview:version];

    UIButton* closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(248, 8, 28, 28);
    closeBtn.backgroundColor = COLOR_BTN;
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:COLOR_WHITE forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:13];
    [closeBtn addTarget:vc action:NSSelectorFromString(@"eBtnTapped:") forControlEvents:UIControlEventTouchUpInside];
    [menuPanel addSubview:closeBtn];

    // Divider
    UIView* div = [[UIView alloc] initWithFrame:CGRectMake(0, 44, 285, 1)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [menuPanel addSubview:div];

    // ── Tab Bar ───────────────────────────────────────────────────────────
    NSArray* tabNames = @[@"Players", @"Spawner", @"RPC Call", @"Profile"];
    UIView* tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 45, 285, 40)];
    tabBar.backgroundColor = UIColor.clearColor;
    [menuPanel addSubview:tabBar];

    CGFloat tw = 285.0 / tabNames.count;
    for (NSInteger i = 0; i < tabNames.count; i++) {
        UIButton* tb = [UIButton buttonWithType:UIButtonTypeCustom];
        tb.frame = CGRectMake(tw * i, 0, tw, 40);
        tb.backgroundColor = i == 0 ? [UIColor colorWithWhite:1 alpha:0.08] : UIColor.clearColor;
        [tb setTitle:tabNames[i] forState:UIControlStateNormal];
        [tb setTitleColor:i == 0 ? COLOR_ACCENT : COLOR_GRAY forState:UIControlStateNormal];
        tb.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        tb.tag = 4000 + i;
        [tb addTarget:vc action:NSSelectorFromString(@"tabTapped:") forControlEvents:UIControlEventTouchUpInside];
        [tabBar addSubview:tb];
    }

    // Divider under tabs
    UIView* div2 = [[UIView alloc] initWithFrame:CGRectMake(0, 85, 285, 1)];
    div2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [menuPanel addSubview:div2];

    // ── Tab Content Area ──────────────────────────────────────────────────
    UIScrollView* contentArea = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 86, 285, 344)];
    contentArea.tag = 5000;
    contentArea.showsVerticalScrollIndicator = NO;
    [menuPanel addSubview:contentArea];

    tabContents = [NSMutableArray array];
    NSArray* tabs = @[
        buildPlayersTab(vc),
        buildSpawnerTab(vc),
        buildRPCTab(vc),
        buildProfileTab(vc)
    ];

    for (UIView* t in tabs) {
        t.hidden = YES;
        [contentArea addSubview:t];
        [tabContents addObject:t];
    }
    ((UIView*)tabContents[0]).hidden = NO;

    // ── Add methods ───────────────────────────────────────────────────────
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

    class_addMethod([vc class], NSSelectorFromString(@"tabTapped:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            NSInteger idx = b.tag - 4000;
            activeTab = idx;
            UIScrollView* ca = (UIScrollView*)[menuPanel viewWithTag:5000];
            UIView* tabBar = ca.superview.subviews[4];
            for (UIButton* tb in tabBar.subviews) {
                BOOL sel = tb.tag == b.tag;
                tb.backgroundColor = sel ? [UIColor colorWithWhite:1 alpha:0.08] : UIColor.clearColor;
                [tb setTitleColor:sel ? COLOR_ACCENT : COLOR_GRAY forState:UIControlStateNormal];
            }
            for (NSInteger i = 0; i < tabContents.count; i++) {
                ((UIView*)tabContents[i]).hidden = i != idx;
            }
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"spawnItem:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            NSString* item = [b.currentTitle stringByReplacingOccurrencesOfString:@"⊕  " withString:@""];
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Spawn" message:[NSString stringWithFormat:@"Spawning %@...", item] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [overlayWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"sendRPC:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UITextField* rpcField = (UITextField*)[menuPanel viewWithTag:2001];
            UITextField* paramField = (UITextField*)[menuPanel viewWithTag:2002];
            UITextView* log = (UITextView*)[menuPanel viewWithTag:2003];
            NSString* rpc = rpcField.text;
            NSString* params = paramField.text;
            if (rpc.length > 0) {
                NSString* entry = [NSString stringWithFormat:@"→ %@(%@)\n%@", rpc, params, log.text];
                log.text = entry;
                rpcField.text = @"";
                paramField.text = @"";
            }
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"setDisplayName:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UITextField* f = (UITextField*)[menuPanel viewWithTag:3001];
            if (f.text.length > 0) {
                UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Display Name" message:[NSString stringWithFormat:@"Set to: %@", f.text] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [overlayWindow.rootViewController presentViewController:alert animated:YES completion:nil];
                f.text = @"";
            }
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"setPlayerColor:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            NSString* color = b.currentTitle;
            UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Player Color" message:[NSString stringWithFormat:@"Color set to %@", color] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [overlayWindow.rootViewController presentViewController:alert animated:YES completion:nil];
        }), "v@:@");
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setupMenu();
    });
}
