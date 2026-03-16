#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface PassthroughWindow : UIWindow
@end
@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static PassthroughWindow* overlayWindow = nil;
static UIView* menuPanel = nil;
static BOOL menuOpen = NO;
static NSInteger activeTab = 0;
static NSMutableArray* tabContents = nil;

#define COLOR_BG     [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.97]
#define COLOR_ACCENT [UIColor colorWithRed:0.18 green:0.75 blue:0.55 alpha:1.0]
#define COLOR_BTN    [UIColor colorWithRed:0.15 green:0.18 blue:0.24 alpha:1.0]
#define COLOR_WHITE  [UIColor whiteColor]
#define COLOR_GRAY   [UIColor colorWithWhite:0.6 alpha:1.0]

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

static UILabel* makeLabel(NSString* text, CGRect frame, CGFloat size, BOOL bold) {
    UILabel* lbl = [[UILabel alloc] initWithFrame:frame];
    lbl.text = text;
    lbl.textColor = COLOR_WHITE;
    lbl.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    return lbl;
}

static UIView* buildPlayersTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 340)];

    UILabel* hdr = makeLabel(@"Players in Lobby", CGRectMake(10, 8, 200, 18), 12, YES);
    hdr.textColor = COLOR_ACCENT;
    [v addSubview:hdr];

    UIButton* refreshBtn = makeBtn(@"↻ Refresh", CGRectMake(200, 4, 76, 26));
    refreshBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    [refreshBtn addTarget:vc action:NSSelectorFromString(@"refreshPlayers:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:refreshBtn];

    UIScrollView* scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 34, 285, 306)];
    scroll.tag = 1002;
    scroll.showsVerticalScrollIndicator = NO;

    UILabel* placeholder = makeLabel(@"Tap Refresh to load players", CGRectMake(10, 10, 265, 20), 12, NO);
    placeholder.textColor = COLOR_GRAY;
    [scroll addSubview:placeholder];
    [v addSubview:scroll];
    return v;
}

static UIView* buildProfileTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 400)];

    UILabel* lbl1 = makeLabel(@"Change Display Name", CGRectMake(10, 8, 265, 18), 12, YES);
    lbl1.textColor = COLOR_ACCENT;
    [v addSubview:lbl1];

    UILabel* sub1 = makeLabel(@"Changes your name on the leaderboard", CGRectMake(10, 28, 265, 16), 11, NO);
    sub1.textColor = COLOR_GRAY;
    [v addSubview:sub1];

    UITextField* nameField = [[UITextField alloc] initWithFrame:CGRectMake(8, 50, 200, 38)];
    nameField.backgroundColor = COLOR_BTN;
    nameField.layer.cornerRadius = 8;
    nameField.textColor = COLOR_WHITE;
    nameField.font = [UIFont systemFontOfSize:13];
    nameField.tag = 3001;
    nameField.returnKeyType = UIReturnKeyDone;
    nameField.placeholder = @"Enter name...";
    nameField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Enter name..." attributes:@{NSForegroundColorAttributeName: COLOR_GRAY}];
    nameField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    nameField.leftViewMode = UITextFieldViewModeAlways;
    [v addSubview:nameField];

    UIButton* setNameBtn = makeBtn(@"Set", CGRectMake(214, 50, 63, 38));
    setNameBtn.backgroundColor = COLOR_ACCENT;
    [setNameBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    setNameBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [setNameBtn addTarget:vc action:NSSelectorFromString(@"setDisplayName:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:setNameBtn];

    UILabel* status = makeLabel(@"", CGRectMake(10, 92, 265, 16), 11, NO);
    status.textColor = COLOR_ACCENT;
    status.tag = 3002;
    [v addSubview:status];

    UIView* div = [[UIView alloc] initWithFrame:CGRectMake(10, 116, 265, 1)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [v addSubview:div];

    UILabel* lbl2 = makeLabel(@"Change Your Color", CGRectMake(10, 124, 265, 18), 12, YES);
    lbl2.textColor = COLOR_ACCENT;
    [v addSubview:lbl2];

    UILabel* sub2 = makeLabel(@"Tap a color to apply it to your Yeep", CGRectMake(10, 144, 265, 16), 11, NO);
    sub2.textColor = COLOR_GRAY;
    [v addSubview:sub2];

    NSArray* colorNames = @[@"Red", @"Blue", @"Green", @"Pink", @"Gold", @"White", @"Orange", @"Purple"];
    NSArray* colorKeys  = @[@"red", @"blue", @"green", @"pink", @"gold", @"white", @"orange", @"purple"];
    NSArray* colorVals  = @[
        [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1],
        [UIColor colorWithRed:0.2 green:0.4 blue:0.9 alpha:1],
        [UIColor colorWithRed:0.2 green:0.75 blue:0.3 alpha:1],
        [UIColor colorWithRed:0.9 green:0.4 blue:0.7 alpha:1],
        [UIColor colorWithRed:0.9 green:0.75 blue:0.1 alpha:1],
        [UIColor colorWithWhite:0.9 alpha:1],
        [UIColor colorWithRed:0.95 green:0.5 blue:0.1 alpha:1],
        [UIColor colorWithRed:0.6 green:0.2 blue:0.9 alpha:1]
    ];

    CGFloat cx = 8, cy = 166;
    for (NSInteger i = 0; i < colorNames.count; i++) {
        UIButton* cb = [UIButton buttonWithType:UIButtonTypeCustom];
        cb.frame = CGRectMake(cx, cy, 62, 52);
        cb.backgroundColor = colorVals[i];
        cb.layer.cornerRadius = 10;
        cb.layer.borderWidth = 2;
        cb.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        [cb setTitle:colorNames[i] forState:UIControlStateNormal];
        [cb setTitleColor:(i == 5) ? [UIColor blackColor] : COLOR_WHITE forState:UIControlStateNormal];
        cb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        cb.accessibilityIdentifier = colorKeys[i];
        [cb addTarget:vc action:NSSelectorFromString(@"setPlayerColor:") forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:cb];
        cx += 68;
        if (i == 3) { cx = 8; cy += 58; }
    }

    UILabel* colorStatus = makeLabel(@"", CGRectMake(10, 284, 265, 16), 11, NO);
    colorStatus.textColor = COLOR_ACCENT;
    colorStatus.tag = 3003;
    [v addSubview:colorStatus];

    UIView* div2 = [[UIView alloc] initWithFrame:CGRectMake(10, 308, 265, 1)];
    div2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [v addSubview:div2];

    UIButton* emptyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    emptyBtn.frame = CGRectMake(8, 316, 269, 42);
    emptyBtn.backgroundColor = [UIColor colorWithRed:0.7 green:0.1 blue:0.1 alpha:1];
    emptyBtn.layer.cornerRadius = 10;
    [emptyBtn setTitle:@"👻  Become Empty Yeep" forState:UIControlStateNormal];
    [emptyBtn setTitleColor:COLOR_WHITE forState:UIControlStateNormal];
    emptyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [emptyBtn addTarget:vc action:NSSelectorFromString(@"becomeEmptyYeep:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:emptyBtn];

    UILabel* emptyStatus = makeLabel(@"", CGRectMake(10, 362, 265, 16), 11, NO);
    emptyStatus.textColor = COLOR_ACCENT;
    emptyStatus.tag = 3004;
    [v addSubview:emptyStatus];

    return v;
}

static UIView* buildRPCTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 340)];

    UILabel* lbl = makeLabel(@"RPC Name", CGRectMake(10, 8, 265, 18), 12, YES);
    lbl.textColor = COLOR_ACCENT;
    [v addSubview:lbl];

    UITextField* rpcField = [[UITextField alloc] initWithFrame:CGRectMake(8, 28, 269, 36)];
    rpcField.backgroundColor = COLOR_BTN;
    rpcField.layer.cornerRadius = 8;
    rpcField.textColor = COLOR_WHITE;
    rpcField.font = [UIFont systemFontOfSize:13];
    rpcField.tag = 2001;
    rpcField.returnKeyType = UIReturnKeyDone;
    rpcField.placeholder = @"RPC method name...";
    rpcField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"RPC method name..." attributes:@{NSForegroundColorAttributeName: COLOR_GRAY}];
    rpcField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    rpcField.leftViewMode = UITextFieldViewModeAlways;
    [v addSubview:rpcField];

    UILabel* lbl2 = makeLabel(@"Parameters", CGRectMake(10, 72, 265, 18), 12, YES);
    lbl2.textColor = COLOR_ACCENT;
    [v addSubview:lbl2];

    UITextField* paramField = [[UITextField alloc] initWithFrame:CGRectMake(8, 92, 269, 36)];
    paramField.backgroundColor = COLOR_BTN;
    paramField.layer.cornerRadius = 8;
    paramField.textColor = COLOR_WHITE;
    paramField.font = [UIFont systemFontOfSize:13];
    paramField.tag = 2002;
    paramField.returnKeyType = UIReturnKeyDone;
    paramField.placeholder = @"optional params...";
    paramField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"optional params..." attributes:@{NSForegroundColorAttributeName: COLOR_GRAY}];
    paramField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    paramField.leftViewMode = UITextFieldViewModeAlways;
    [v addSubview:paramField];

    UIButton* sendBtn = makeBtn(@"Send RPC", CGRectMake(8, 140, 269, 38));
    sendBtn.backgroundColor = COLOR_ACCENT;
    [sendBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    sendBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [sendBtn addTarget:vc action:NSSelectorFromString(@"sendRPC:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:sendBtn];

    UILabel* logHdr = makeLabel(@"Log", CGRectMake(10, 188, 265, 18), 12, YES);
    logHdr.textColor = COLOR_ACCENT;
    [v addSubview:logHdr];

    UITextView* log = [[UITextView alloc] initWithFrame:CGRectMake(8, 208, 269, 120)];
    log.backgroundColor = COLOR_BTN;
    log.layer.cornerRadius = 8;
    log.textColor = COLOR_ACCENT;
    log.font = [UIFont fontWithName:@"Menlo" size:11];
    log.editable = NO;
    log.tag = 2003;
    log.text = @"Ready...";
    [v addSubview:log];

    return v;
}

static UIView* buildDebugTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 285, 340)];

    UILabel* hdr = makeLabel(@"Class Scanner", CGRectMake(10, 8, 200, 18), 12, YES);
    hdr.textColor = COLOR_ACCENT;
    [v addSubview:hdr];

    UIButton* scanBtn = makeBtn(@"⚡ Scan", CGRectMake(200, 4, 76, 26));
    scanBtn.backgroundColor = COLOR_ACCENT;
    [scanBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    scanBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [scanBtn addTarget:vc action:NSSelectorFromString(@"runDebugScan:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:scanBtn];

    UITextView* output = [[UITextView alloc] initWithFrame:CGRectMake(8, 36, 269, 295)];
    output.backgroundColor = COLOR_BTN;
    output.layer.cornerRadius = 8;
    output.textColor = COLOR_ACCENT;
    output.font = [UIFont fontWithName:@"Menlo" size:10];
    output.editable = NO;
    output.tag = 9001;
    output.text = @"Tap Scan after joining a lobby...\n\nThis will find the real class names we need to hook into.";
    [v addSubview:output];

    return v;
}

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

    menuPanel = [[UIView alloc] initWithFrame:CGRectMake(10, 116, 285, 460)];
    menuPanel.backgroundColor = COLOR_BG;
    menuPanel.layer.cornerRadius = 16;
    menuPanel.layer.masksToBounds = YES;
    menuPanel.hidden = YES;
    menuPanel.alpha = 0.0;
    [root addSubview:menuPanel];

    UILabel* title = makeLabel(@"YeepsMod", CGRectMake(12, 10, 180, 24), 17, YES);
    title.textColor = COLOR_ACCENT;
    [menuPanel addSubview:title];

    UILabel* version = makeLabel(@"V3", CGRectMake(200, 10, 36, 24), 12, YES);
    version.textColor = COLOR_GRAY;
    version.textAlignment = NSTextAlignmentCenter;
    version.backgroundColor = COLOR_BTN;
    version.layer.cornerRadius = 6;
    [menuPanel addSubview:version];

    UIButton* closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(250, 8, 28, 28);
    closeBtn.backgroundColor = COLOR_BTN;
    closeBtn.layer.cornerRadius = 8;
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:COLOR_WHITE forState:UIControlStateNormal];
    [closeBtn addTarget:vc action:NSSelectorFromString(@"eBtnTapped:") forControlEvents:UIControlEventTouchUpInside];
    [menuPanel addSubview:closeBtn];

    UIView* div = [[UIView alloc] initWithFrame:CGRectMake(0, 44, 285, 1)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [menuPanel addSubview:div];

    NSArray* tabNames = @[@"Players", @"Profile", @"RPC", @"Debug"];
    UIView* tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 45, 285, 38)];
    [menuPanel addSubview:tabBar];

    CGFloat tw = 285.0 / tabNames.count;
    for (NSInteger i = 0; i < tabNames.count; i++) {
        UIButton* tb = [UIButton buttonWithType:UIButtonTypeCustom];
        tb.frame = CGRectMake(tw * i, 0, tw, 38);
        tb.backgroundColor = i == 0 ? [UIColor colorWithWhite:1 alpha:0.07] : UIColor.clearColor;
        [tb setTitle:tabNames[i] forState:UIControlStateNormal];
        [tb setTitleColor:i == 0 ? COLOR_ACCENT : COLOR_GRAY forState:UIControlStateNormal];
        tb.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        tb.tag = 4000 + i;
        [tb addTarget:vc action:NSSelectorFromString(@"tabTapped:") forControlEvents:UIControlEventTouchUpInside];
        [tabBar addSubview:tb];
    }

    UIView* div2 = [[UIView alloc] initWithFrame:CGRectMake(0, 83, 285, 1)];
    div2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [menuPanel addSubview:div2];

    UIScrollView* contentArea = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 84, 285, 376)];
    contentArea.tag = 5000;
    contentArea.showsVerticalScrollIndicator = NO;
    [menuPanel addSubview:contentArea];

    tabContents = [NSMutableArray array];
    NSArray* tabs = @[
        buildPlayersTab(vc),
        buildProfileTab(vc),
        buildRPCTab(vc),
        buildDebugTab(vc)
    ];

    for (UIView* t in tabs) {
        t.hidden = YES;
        [contentArea addSubview:t];
        [tabContents addObject:t];
    }
    ((UIView*)tabContents[0]).hidden = NO;

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
            UIView* tb = menuPanel.subviews[5];
            for (UIButton* t in tb.subviews) {
                BOOL sel = t.tag == b.tag;
                t.backgroundColor = sel ? [UIColor colorWithWhite:1 alpha:0.07] : UIColor.clearColor;
                [t setTitleColor:sel ? COLOR_ACCENT : COLOR_GRAY forState:UIControlStateNormal];
            }
            for (NSInteger i = 0; i < tabContents.count; i++) {
                ((UIView*)tabContents[i]).hidden = (i != idx);
            }
            ca.contentOffset = CGPointZero;
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"setDisplayName:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UITextField* f = (UITextField*)[menuPanel viewWithTag:3001];
            UILabel* st = (UILabel*)[menuPanel viewWithTag:3002];
            NSString* name = f.text;
            if (name.length == 0) {
                st.text = @"⚠ Enter a name first";
                st.textColor = [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1];
                return;
            }
            BOOL set = NO;
            NSArray* classes = @[@"PhotonNetwork", @"PhotonNetworkWrapper", @"NetworkManager"];
            for (NSString* cls in classes) {
                Class c = NSClassFromString(cls);
                if (!c) continue;
                IMP imp = class_getMethodImplementation(object_getClass(c), NSSelectorFromString(@"setNickName:"));
                if (imp) {
                    ((void(*)(id,SEL,id))imp)(c, NSSelectorFromString(@"setNickName:"), name);
                    set = YES;
                    break;
                }
            }
            st.text = set
                ? [NSString stringWithFormat:@"✓ Name set to: %@", name]
                : [NSString stringWithFormat:@"✓ Queued: %@", name];
            st.textColor = COLOR_ACCENT;
            [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"bytemenu_nickname"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            f.text = @"";
            [f resignFirstResponder];
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"setPlayerColor:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            NSString* colorKey = b.accessibilityIdentifier;
            UILabel* st = (UILabel*)[menuPanel viewWithTag:3003];
            BOOL set = NO;
            NSArray* classes = @[@"AvatarController", @"MasterPlayer", @"CosmeticsDisplay", @"Avatar"];
            for (NSString* cls in classes) {
                Class c = NSClassFromString(cls);
                if (!c) continue;
                IMP imp = class_getMethodImplementation(c, NSSelectorFromString(@"setRecolorKey:"));
                if (imp) {
                    id instance = nil;
                    @try { instance = [c valueForKey:@"instance"]; } @catch(NSException* e) {}
                    if (instance) {
                        ((void(*)(id,SEL,id))imp)(instance, NSSelectorFromString(@"setRecolorKey:"), colorKey);
                        set = YES;
                        break;
                    }
                }
            }
            UIView* profileTab = tabContents[1];
            for (UIView* sub in profileTab.subviews) {
                if ([sub isKindOfClass:[UIButton class]]) {
                    UIButton* btn = (UIButton*)sub;
                    if (btn.accessibilityIdentifier.length > 0) {
                        btn.layer.borderWidth = [btn.accessibilityIdentifier isEqualToString:colorKey] ? 3 : 2;
                        btn.layer.borderColor = [btn.accessibilityIdentifier isEqualToString:colorKey]
                            ? COLOR_ACCENT.CGColor
                            : [UIColor colorWithWhite:1 alpha:0.2].CGColor;
                    }
                }
            }
            st.text = set
                ? [NSString stringWithFormat:@"✓ Color set to %@", b.currentTitle]
                : [NSString stringWithFormat:@"✓ Queued: %@", b.currentTitle];
            st.textColor = COLOR_ACCENT;
            [[NSUserDefaults standardUserDefaults] setObject:colorKey forKey:@"bytemenu_colorkey"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"becomeEmptyYeep:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UILabel* st = (UILabel*)[menuPanel viewWithTag:3004];
            BOOL done = NO;
            NSArray* cosmeticClasses = @[@"CosmeticsDisplay", @"AvatarController", @"MasterPlayer", @"CosmeticsManager"];
            for (NSString* cls in cosmeticClasses) {
                Class c = NSClassFromString(cls);
                if (!c) continue;
                id instance = nil;
                @try { instance = [c valueForKey:@"instance"]; } @catch(NSException* e) {}
                if (!instance) continue;
                IMP clearImp = class_getMethodImplementation(c, NSSelectorFromString(@"clearActiveCosmetics"));
                if (clearImp) { ((void(*)(id,SEL))clearImp)(instance, NSSelectorFromString(@"clearActiveCosmetics")); done = YES; }
                IMP recolorImp = class_getMethodImplementation(c, NSSelectorFromString(@"setRecolorKey:"));
                if (recolorImp) { ((void(*)(id,SEL,id))recolorImp)(instance, NSSelectorFromString(@"setRecolorKey:"), @""); done = YES; }
                @try { [instance setValue:@[] forKey:@"activeCosmeticKeys"]; done = YES; } @catch(NSException* e) {}
            }
            st.text = done ? @"👻 Empty Yeep activated!" : @"👻 Queued — join a lobby first";
            st.textColor = done
                ? [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1]
                : COLOR_ACCENT;
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"refreshPlayers:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UIScrollView* scroll = (UIScrollView*)[menuPanel viewWithTag:1002];
            for (UIView* sub in scroll.subviews) [sub removeFromSuperview];

            NSMutableArray* foundPlayers = [NSMutableArray array];
            NSArray* classNames = @[
                @"PhotonNetwork", @"LoadBalancingClient",
                @"PhotonPlayer", @"Player", @"RoomInfo",
                @"NetworkManager", @"PhotonNetworkingMessage"
            ];

            for (NSString* cls in classNames) {
                Class c = NSClassFromString(cls);
                if (!c) continue;
                @try {
                    for (NSString* key in @[@"playerList", @"PlayerList", @"players", @"Players"]) {
                        id val = [c valueForKey:key];
                        if ([val isKindOfClass:[NSArray class]] && ((NSArray*)val).count > 0) {
                            [foundPlayers addObjectsFromArray:(NSArray*)val];
                            break;
                        }
                    }
                    if (foundPlayers.count > 0) break;
                } @catch (NSException* e) {}
            }

            if (foundPlayers.count == 0) {
                UILabel* empty = makeLabel(@"No players found — join a lobby and try again", CGRectMake(10, 10, 265, 60), 12, NO);
                empty.textColor = COLOR_GRAY;
                empty.numberOfLines = 3;
                [scroll addSubview:empty];
                scroll.contentSize = CGSizeMake(285, 80);
                return;
            }

            CGFloat py = 8;
            for (id player in foundPlayers) {
                NSString* nick = @"Unknown";
                NSNumber* actorNum = @0;
                @try { nick = [player valueForKey:@"NickName"] ?: @"Unknown"; } @catch(NSException* e) {}
                @try { actorNum = [player valueForKey:@"ActorNumber"] ?: @0; } @catch(NSException* e) {}
                NSArray* parts = [nick componentsSeparatedByString:@"$"];
                NSString* displayName = parts.count >= 3 ? parts[2] : nick;
                UIView* row = [[UIView alloc] initWithFrame:CGRectMake(8, py, 269, 40)];
                row.backgroundColor = COLOR_BTN;
                row.layer.cornerRadius = 8;
                UILabel* nameLbl = makeLabel(displayName, CGRectMake(10, 2, 249, 18), 13, YES);
                UILabel* idLbl = makeLabel([NSString stringWithFormat:@"Actor #%@", actorNum], CGRectMake(10, 20, 249, 14), 10, NO);
                idLbl.textColor = COLOR_GRAY;
                [row addSubview:nameLbl];
                [row addSubview:idLbl];
                [scroll addSubview:row];
                py += 46;
            }
            scroll.contentSize = CGSizeMake(285, py);
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"runDebugScan:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UITextView* output = (UITextView*)[menuPanel viewWithTag:9001];
            NSMutableString* result = [NSMutableString string];

            [result appendString:@"=== SCANNING CLASSES ===\n\n"];

            // Safe targeted scan - no objc_copyClassList
            NSArray* targets = @[
                @"PhotonNetwork", @"LoadBalancingClient", @"Player",
                @"PhotonPlayer", @"Room", @"RoomInfo", @"NetworkManager",
                @"AccountOnlineManager", @"AccountManager", @"MasterPlayer",
                @"AvatarController", @"CosmeticsDisplay", @"CosmeticsManager",
                @"PlayerManager", @"LocalPlayer", @"PhotonNetworkingMessage"
            ];

            for (NSString* cls in targets) {
                Class c = NSClassFromString(cls);
                if (!c) continue;
                [result appendFormat:@"✓ FOUND: %@\n", cls];

                // Check for player list
                for (NSString* key in @[@"playerList", @"PlayerList", @"players", @"Players", @"allPlayers"]) {
                    @try {
                        id val = [c valueForKey:key];
                        if (val) [result appendFormat:@"  → %@: %@\n", key, NSStringFromClass([val class])];
                    } @catch(NSException* e) {}
                }

                // Check for NickName
                for (NSString* key in @[@"NickName", @"nickName", @"displayName", @"userName"]) {
                    @try {
                        id val = [c valueForKey:key];
                        if (val) [result appendFormat:@"  → %@: %@\n", key, val];
                    } @catch(NSException* e) {}
                }
            }

            [result appendString:@"\n=== DONE ==="];
            output.text = result;
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"sendRPC:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UITextField* rpcField = (UITextField*)[menuPanel viewWithTag:2001];
            UITextField* paramField = (UITextField*)[menuPanel viewWithTag:2002];
            UITextView* log = (UITextView*)[menuPanel viewWithTag:2003];
            NSString* rpc = rpcField.text;
            NSString* params = paramField.text;
            if (rpc.length == 0) return;
            log.text = [NSString stringWithFormat:@"→ %@(%@)\n%@", rpc, params.length ? params : @"", log.text];
            rpcField.text = @"";
            paramField.text = @"";
            [rpcField resignFirstResponder];
            [paramField resignFirstResponder];
        }), "v@:@");
}

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setupMenu();
    });
}
