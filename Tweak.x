#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

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
static NSMutableArray* tabContents = nil;
static NSMutableArray* playerList = nil;
static void* unityFramework = nil;

// IL2CPP function pointers
static void* (*il2cpp_domain_get)(void) = nil;
static void* (*il2cpp_domain_get_assemblies)(void*, size_t*) = nil;
static void* (*il2cpp_assembly_get_image)(void*) = nil;
static void* (*il2cpp_class_from_name)(void*, const char*, const char*) = nil;
static void* (*il2cpp_class_get_method_from_name)(void*, const char*, int) = nil;
static void* (*il2cpp_method_get_pointer)(void*) = nil;

#define COLOR_BG     [UIColor colorWithRed:0.08 green:0.10 blue:0.14 alpha:0.97]
#define COLOR_ACCENT [UIColor colorWithRed:0.18 green:0.75 blue:0.55 alpha:1.0]
#define COLOR_BTN    [UIColor colorWithRed:0.15 green:0.18 blue:0.24 alpha:1.0]
#define COLOR_RED    [UIColor colorWithRed:0.8 green:0.15 blue:0.15 alpha:1.0]
#define COLOR_WHITE  [UIColor whiteColor]
#define COLOR_GRAY   [UIColor colorWithWhite:0.6 alpha:1.0]

// ─── Helpers ──────────────────────────────────────────────────────────────
static UIButton* makeBtn(NSString* title, CGRect frame, UIColor* color) {
    UIButton* btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = frame;
    btn.backgroundColor = color ?: COLOR_BTN;
    btn.layer.cornerRadius = 8;
    btn.layer.masksToBounds = YES;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:COLOR_WHITE forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    return btn;
}

static UILabel* makeLabel(NSString* text, CGRect frame, CGFloat size, BOOL bold) {
    UILabel* lbl = [[UILabel alloc] initWithFrame:frame];
    lbl.text = text;
    lbl.textColor = COLOR_WHITE;
    lbl.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    return lbl;
}

static NSString* parseDisplayName(NSString* nickName) {
    if (!nickName || nickName.length == 0) return @"Unknown";
    NSArray* parts = [nickName componentsSeparatedByString:@"$"];
    if (parts.count >= 3) return parts[2];
    return nickName;
}

static NSString* parsePlatform(NSString* nickName) {
    if (!nickName || nickName.length == 0) return @"";
    NSArray* parts = [nickName componentsSeparatedByString:@"$"];
    if (parts.count >= 2) return parts[1];
    return @"";
}

// ─── Load UnityFramework ──────────────────────────────────────────────────
static void loadUnityFramework() {
    if (unityFramework) return;
    unityFramework = dlopen("@executable_path/Frameworks/UnityFramework.framework/UnityFramework", RTLD_NOW | RTLD_GLOBAL);
    if (!unityFramework) {
        NSLog(@"[YeepsMod] Failed to load UnityFramework");
        return;
    }

    il2cpp_domain_get = (void*(*)(void))dlsym(unityFramework, "il2cpp_domain_get");
    il2cpp_domain_get_assemblies = (void*(*)(void*, size_t*))dlsym(unityFramework, "il2cpp_domain_get_assemblies");
    il2cpp_assembly_get_image = (void*(*)(void*))dlsym(unityFramework, "il2cpp_assembly_get_image");
    il2cpp_class_from_name = (void*(*)(void*, const char*, const char*))dlsym(unityFramework, "il2cpp_class_from_name");
    il2cpp_class_get_method_from_name = (void*(*)(void*, const char*, int))dlsym(unityFramework, "il2cpp_class_get_method_from_name");
    il2cpp_method_get_pointer = (void*(*)(void*))dlsym(unityFramework, "il2cpp_method_get_pointer");

    NSLog(@"[YeepsMod] UnityFramework loaded. domain_get=%p", il2cpp_domain_get);
}

// ─── Find IL2CPP method pointer ───────────────────────────────────────────
static void* findMethod(const char* namespaceName, const char* className, const char* methodName, int paramCount) {
    if (!il2cpp_domain_get) return nil;

    void* domain = il2cpp_domain_get();
    if (!domain) return nil;

    size_t assemblyCount = 0;
    void** assemblies = (void**)il2cpp_domain_get_assemblies(domain, &assemblyCount);
    if (!assemblies) return nil;

    for (size_t i = 0; i < assemblyCount; i++) {
        void* image = il2cpp_assembly_get_image(assemblies[i]);
        if (!image) continue;
        void* klass = il2cpp_class_from_name(image, namespaceName, className);
        if (!klass) continue;
        void* method = il2cpp_class_get_method_from_name(klass, methodName, paramCount);
        if (!method) continue;
        void* ptr = il2cpp_method_get_pointer(method);
        NSLog(@"[YeepsMod] Found %s.%s.%s = %p", namespaceName, className, methodName, ptr);
        return ptr;
    }
    return nil;
}

// ─── Photon player list ───────────────────────────────────────────────────
typedef void* (*GetPlayersArray_t)(void*);
typedef void* (*GetArrayElement_t)(void*, int);
typedef int   (*GetArrayLength_t)(void*);
typedef void* (*GetNickName_t)(void*);
typedef int   (*GetActorNumber_t)(void*);

// ─── Avatar color functions ───────────────────────────────────────────────
typedef void (*SetOverrideBaseColor_t)(void*, float, float, float, float);
typedef void (*ClearOverrideBaseColor_t)(void*);
typedef void* (*SetNickName_t)(void*, void*);

static SetOverrideBaseColor_t setColorFn = nil;
static ClearOverrideBaseColor_t clearColorFn = nil;
static SetNickName_t setNickNameFn = nil;

static void initIL2CPP() {
    loadUnityFramework();

    // Find set_NickName in Photon
    setNickNameFn = (SetNickName_t)findMethod("ExitGames.Client.Photon", "Player", "set_NickName", 1);

    // Find Avatar color methods
    setColorFn = (SetOverrideBaseColor_t)findMethod("", "Avatar", "SetOverrideBaseColor", 4);
    clearColorFn = (ClearOverrideBaseColor_t)findMethod("", "Avatar", "ClearOverrideBaseColor", 0);

    NSLog(@"[YeepsMod] setNickName=%p setColor=%p clearColor=%p", setNickNameFn, setColorFn, clearColorFn);
}

// ─── Color picker alert ───────────────────────────────────────────────────
static void showColorPickerForPlayer(NSDictionary* player, UIViewController* vc) {
    NSString* name = player[@"name"] ?: @"Unknown";
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Color for %@", name]
                                                                   message:@"Choose a color"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSDictionary* colors = @{
        @"🔴 Red":    @[@1.0f, @0.0f, @0.0f],
        @"🔵 Blue":   @[@0.0f, @0.0f, @1.0f],
        @"🟢 Green":  @[@0.0f, @1.0f, @0.0f],
        @"🩷 Pink":   @[@1.0f, @0.4f, @0.7f],
        @"🟡 Gold":   @[@1.0f, @0.8f, @0.0f],
        @"⚪ White":  @[@1.0f, @1.0f, @1.0f],
        @"🟠 Orange": @[@1.0f, @0.5f, @0.0f],
        @"🟣 Purple": @[@0.6f, @0.0f, @1.0f],
        @"🩵 Cyan":   @[@0.0f, @1.0f, @1.0f],
        @"⚫ Black":  @[@0.0f, @0.0f, @0.0f],
    };

    for (NSString* colorName in colors) {
        NSArray* rgb = colors[colorName];
        float r = [rgb[0] floatValue];
        float g = [rgb[1] floatValue];
        float b = [rgb[2] floatValue];
        void* playerPtr = [player[@"ptr"] pointerValue];

        [alert addAction:[UIAlertAction actionWithTitle:colorName style:UIAlertActionStyleDefault handler:^(UIAlertAction* a) {
            if (setColorFn && playerPtr) {
                // Try to find avatar for this player and set color
                @try {
                    setColorFn(playerPtr, r, g, b, 1.0f);
                    NSLog(@"[YeepsMod] Set color for %@ to %@", name, colorName);
                } @catch(NSException* e) {
                    NSLog(@"[YeepsMod] Color set failed: %@", e);
                }
            }
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"❌ Clear Color" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* a) {
        void* playerPtr = [player[@"ptr"] pointerValue];
        if (clearColorFn && playerPtr) {
            @try { clearColorFn(playerPtr); } @catch(NSException* e) {}
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

// ─── Build Players Tab ────────────────────────────────────────────────────
static UIView* buildPlayersTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 500)];

    UILabel* hdr = makeLabel(@"Players in Lobby", CGRectMake(10, 8, 180, 18), 12, YES);
    hdr.textColor = COLOR_ACCENT;
    [v addSubview:hdr];

    UIButton* refreshBtn = makeBtn(@"↻ Refresh", CGRectMake(210, 2, 80, 26), COLOR_ACCENT);
    [refreshBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [refreshBtn addTarget:vc action:NSSelectorFromString(@"refreshPlayers:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:refreshBtn];

    UIScrollView* scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 32, 300, 468)];
    scroll.tag = 1002;
    scroll.showsVerticalScrollIndicator = NO;
    UILabel* ph = makeLabel(@"Tap Refresh after joining a lobby", CGRectMake(10, 10, 280, 40), 12, NO);
    ph.textColor = COLOR_GRAY;
    ph.numberOfLines = 2;
    [scroll addSubview:ph];
    [v addSubview:scroll];
    return v;
}

// ─── Build Profile Tab ────────────────────────────────────────────────────
static UIView* buildProfileTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 500)];

    // Name change
    UILabel* lbl1 = makeLabel(@"Change Display Name", CGRectMake(10, 8, 280, 18), 12, YES);
    lbl1.textColor = COLOR_ACCENT;
    [v addSubview:lbl1];

    UILabel* sub1 = makeLabel(@"Changes your name in the lobby", CGRectMake(10, 28, 280, 16), 11, NO);
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

    UIButton* setNameBtn = makeBtn(@"Set", CGRectMake(214, 50, 78, 38), COLOR_ACCENT);
    [setNameBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [setNameBtn addTarget:vc action:NSSelectorFromString(@"setDisplayName:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:setNameBtn];

    UILabel* nameStatus = makeLabel(@"", CGRectMake(10, 92, 280, 16), 11, NO);
    nameStatus.textColor = COLOR_ACCENT;
    nameStatus.tag = 3002;
    [v addSubview:nameStatus];

    UIView* div = [[UIView alloc] initWithFrame:CGRectMake(10, 116, 280, 1)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [v addSubview:div];

    // My color section
    UILabel* lbl2 = makeLabel(@"Change My Color", CGRectMake(10, 124, 280, 18), 12, YES);
    lbl2.textColor = COLOR_ACCENT;
    [v addSubview:lbl2];

    UILabel* sub2 = makeLabel(@"Changes your own Yeep color", CGRectMake(10, 144, 280, 16), 11, NO);
    sub2.textColor = COLOR_GRAY;
    [v addSubview:sub2];

    NSArray* colorNames = @[@"Red", @"Blue", @"Green", @"Pink", @"Gold", @"White", @"Orange", @"Purple", @"Cyan", @"Black"];
    NSArray* colorKeys  = @[@"red", @"blue", @"green", @"pink", @"gold", @"white", @"orange", @"purple", @"cyan", @"black"];
    NSArray* colorVals  = @[
        [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:1],
        [UIColor colorWithRed:0.2 green:0.4 blue:0.9 alpha:1],
        [UIColor colorWithRed:0.2 green:0.75 blue:0.3 alpha:1],
        [UIColor colorWithRed:0.9 green:0.4 blue:0.7 alpha:1],
        [UIColor colorWithRed:0.9 green:0.75 blue:0.1 alpha:1],
        [UIColor colorWithWhite:0.9 alpha:1],
        [UIColor colorWithRed:0.95 green:0.5 blue:0.1 alpha:1],
        [UIColor colorWithRed:0.6 green:0.2 blue:0.9 alpha:1],
        [UIColor colorWithRed:0.0 green:0.9 blue:0.9 alpha:1],
        [UIColor colorWithWhite:0.1 alpha:1]
    ];

    CGFloat cx = 8, cy = 166;
    for (NSInteger i = 0; i < colorNames.count; i++) {
        UIButton* cb = [UIButton buttonWithType:UIButtonTypeCustom];
        cb.frame = CGRectMake(cx, cy, 54, 46);
        cb.backgroundColor = colorVals[i];
        cb.layer.cornerRadius = 10;
        cb.layer.borderWidth = 2;
        cb.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        [cb setTitle:colorNames[i] forState:UIControlStateNormal];
        [cb setTitleColor:(i == 5 || i == 9) ? [UIColor blackColor] : COLOR_WHITE forState:UIControlStateNormal];
        cb.titleLabel.font = [UIFont boldSystemFontOfSize:9];
        cb.accessibilityIdentifier = colorKeys[i];
        [cb addTarget:vc action:NSSelectorFromString(@"setMyColor:") forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:cb];
        cx += 58;
        if (i == 4) { cx = 8; cy += 52; }
    }

    UILabel* colorStatus = makeLabel(@"", CGRectMake(10, 274, 280, 16), 11, NO);
    colorStatus.textColor = COLOR_ACCENT;
    colorStatus.tag = 3003;
    [v addSubview:colorStatus];

    UIView* div2 = [[UIView alloc] initWithFrame:CGRectMake(10, 298, 280, 1)];
    div2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [v addSubview:div2];

    UIButton* clearColorBtn = makeBtn(@"Clear My Color", CGRectMake(8, 308, 284, 38), COLOR_RED);
    [clearColorBtn addTarget:vc action:NSSelectorFromString(@"clearMyColor:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:clearColorBtn];

    UIView* div3 = [[UIView alloc] initWithFrame:CGRectMake(10, 358, 280, 1)];
    div3.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [v addSubview:div3];

    UIButton* emptyBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    emptyBtn.frame = CGRectMake(8, 366, 284, 42);
    emptyBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.1 blue:0.1 alpha:1];
    emptyBtn.layer.cornerRadius = 10;
    [emptyBtn setTitle:@"👻  Become Empty Yeep" forState:UIControlStateNormal];
    [emptyBtn setTitleColor:COLOR_WHITE forState:UIControlStateNormal];
    emptyBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [emptyBtn addTarget:vc action:NSSelectorFromString(@"becomeEmptyYeep:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:emptyBtn];

    UILabel* emptyStatus = makeLabel(@"", CGRectMake(10, 412, 280, 16), 11, NO);
    emptyStatus.textColor = COLOR_ACCENT;
    emptyStatus.tag = 3004;
    [v addSubview:emptyStatus];

    return v;
}

// ─── Build RPC Tab ────────────────────────────────────────────────────────
static UIView* buildRPCTab(UIViewController* vc) {
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 500)];

    UILabel* lbl = makeLabel(@"RPC Caller", CGRectMake(10, 8, 280, 18), 12, YES);
    lbl.textColor = COLOR_ACCENT;
    [v addSubview:lbl];

    UITextField* rpcField = [[UITextField alloc] initWithFrame:CGRectMake(8, 32, 284, 36)];
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

    UITextField* paramField = [[UITextField alloc] initWithFrame:CGRectMake(8, 76, 284, 36)];
    paramField.backgroundColor = COLOR_BTN;
    paramField.layer.cornerRadius = 8;
    paramField.textColor = COLOR_WHITE;
    paramField.font = [UIFont systemFontOfSize:13];
    paramField.tag = 2002;
    paramField.returnKeyType = UIReturnKeyDone;
    paramField.placeholder = @"Parameters (optional)...";
    paramField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Parameters (optional)..." attributes:@{NSForegroundColorAttributeName: COLOR_GRAY}];
    paramField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,10,0)];
    paramField.leftViewMode = UITextFieldViewModeAlways;
    [v addSubview:paramField];

    UIButton* sendBtn = makeBtn(@"Send RPC", CGRectMake(8, 120, 284, 38), COLOR_ACCENT);
    [sendBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    sendBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [sendBtn addTarget:vc action:NSSelectorFromString(@"sendRPC:") forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:sendBtn];

    UILabel* logHdr = makeLabel(@"RPC Log", CGRectMake(10, 168, 280, 18), 12, YES);
    logHdr.textColor = COLOR_ACCENT;
    [v addSubview:logHdr];

    UITextView* log = [[UITextView alloc] initWithFrame:CGRectMake(8, 188, 284, 300)];
    log.backgroundColor = COLOR_BTN;
    log.layer.cornerRadius = 8;
    log.textColor = COLOR_ACCENT;
    log.font = [UIFont fontWithName:@"Menlo" size:10];
    log.editable = NO;
    log.tag = 2003;
    log.text = @"Ready...";
    [v addSubview:log];

    return v;
}

// ─── Main Setup ───────────────────────────────────────────────────────────
static void setupMenu() {
    playerList = [NSMutableArray array];

    overlayWindow = [[PassthroughWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    overlayWindow.windowLevel = UIWindowLevelStatusBar + 100;
    overlayWindow.backgroundColor = UIColor.clearColor;
    overlayWindow.userInteractionEnabled = YES;
    overlayWindow.hidden = NO;

    UIViewController* vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    overlayWindow.rootViewController = vc;
    UIView* root = vc.view;

    // Y Button
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

    // Menu Panel
    menuPanel = [[UIView alloc] initWithFrame:CGRectMake(10, 116, 300, 560)];
    menuPanel.backgroundColor = COLOR_BG;
    menuPanel.layer.cornerRadius = 16;
    menuPanel.layer.masksToBounds = YES;
    menuPanel.hidden = YES;
    menuPanel.alpha = 0.0;
    [root addSubview:menuPanel];

    // Header
    UILabel* title = makeLabel(@"YeepsMod", CGRectMake(12, 10, 200, 24), 17, YES);
    title.textColor = COLOR_ACCENT;
    [menuPanel addSubview:title];

    UILabel* version = makeLabel(@"V5", CGRectMake(216, 10, 36, 24), 12, YES);
    version.textColor = COLOR_GRAY;
    version.textAlignment = NSTextAlignmentCenter;
    version.backgroundColor = COLOR_BTN;
    version.layer.cornerRadius = 6;
    [menuPanel addSubview:version];

    UIButton* closeBtn = makeBtn(@"✕", CGRectMake(262, 8, 28, 28), COLOR_BTN);
    [closeBtn addTarget:vc action:NSSelectorFromString(@"eBtnTapped:") forControlEvents:UIControlEventTouchUpInside];
    [menuPanel addSubview:closeBtn];

    UIView* div = [[UIView alloc] initWithFrame:CGRectMake(0, 44, 300, 1)];
    div.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [menuPanel addSubview:div];

    // Tab Bar
    NSArray* tabNames = @[@"Players", @"Profile", @"RPC"];
    UIView* tabBar = [[UIView alloc] initWithFrame:CGRectMake(0, 45, 300, 38)];
    [menuPanel addSubview:tabBar];

    CGFloat tw = 300.0 / tabNames.count;
    for (NSInteger i = 0; i < tabNames.count; i++) {
        UIButton* tb = [UIButton buttonWithType:UIButtonTypeCustom];
        tb.frame = CGRectMake(tw * i, 0, tw, 38);
        tb.backgroundColor = i == 0 ? [UIColor colorWithWhite:1 alpha:0.07] : UIColor.clearColor;
        [tb setTitle:tabNames[i] forState:UIControlStateNormal];
        [tb setTitleColor:i == 0 ? COLOR_ACCENT : COLOR_GRAY forState:UIControlStateNormal];
        tb.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        tb.tag = 4000 + i;
        [tb addTarget:vc action:NSSelectorFromString(@"tabTapped:") forControlEvents:UIControlEventTouchUpInside];
        [tabBar addSubview:tb];
    }

    UIView* div2 = [[UIView alloc] initWithFrame:CGRectMake(0, 83, 300, 1)];
    div2.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [menuPanel addSubview:div2];

    UIScrollView* contentArea = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 84, 300, 476)];
    contentArea.tag = 5000;
    contentArea.showsVerticalScrollIndicator = NO;
    [menuPanel addSubview:contentArea];

    tabContents = [NSMutableArray array];
    NSArray* tabs = @[
        buildPlayersTab(vc),
        buildProfileTab(vc),
        buildRPCTab(vc)
    ];

    for (UIView* t in tabs) {
        t.hidden = YES;
        [contentArea addSubview:t];
        [tabContents addObject:t];
    }
    ((UIView*)tabContents[0]).hidden = NO;

    // ── Action Methods ────────────────────────────────────────────────────
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

    class_addMethod([vc class], NSSelectorFromString(@"refreshPlayers:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UIScrollView* scroll = (UIScrollView*)[menuPanel viewWithTag:1002];
            for (UIView* sub in scroll.subviews) [sub removeFromSuperview];

            // Try to get Photon player list via NSClassFromString
            NSMutableArray* found = [NSMutableArray array];
            NSArray* classNames = @[@"PhotonNetwork", @"LoadBalancingClient", @"NetworkManager"];
            for (NSString* cls in classNames) {
                Class c = NSClassFromString(cls);
                if (!c) continue;
                @try {
                    for (NSString* key in @[@"playerList", @"PlayerList", @"players"]) {
                        id val = [c valueForKey:key];
                        if ([val isKindOfClass:[NSArray class]] && ((NSArray*)val).count > 0) {
                            [found addObjectsFromArray:(NSArray*)val];
                            break;
                        }
                    }
                } @catch(NSException* e) {}
                if (found.count > 0) break;
            }

            [playerList removeAllObjects];

            if (found.count == 0) {
                UILabel* empty = makeLabel(@"No players found — join a lobby first", CGRectMake(10, 10, 280, 40), 12, NO);
                empty.textColor = COLOR_GRAY;
                empty.numberOfLines = 2;
                [scroll addSubview:empty];
                scroll.contentSize = CGSizeMake(300, 60);
                return;
            }

            CGFloat py = 8;
            for (id player in found) {
                NSString* nick = @"Unknown";
                NSNumber* actor = @0;
                @try { nick = [player valueForKey:@"NickName"] ?: @"Unknown"; } @catch(NSException* e) {}
                @try { actor = [player valueForKey:@"ActorNumber"] ?: @0; } @catch(NSException* e) {}

                NSString* display = parseDisplayName(nick);
                NSString* platform = parsePlatform(nick);
                NSString* icon = [platform isEqualToString:@"VR"] ? @"🥽" :
                                 [platform isEqualToString:@"mobileIOS"] ? @"📱" : @"👤";

                NSDictionary* playerData = @{
                    @"name": display,
                    @"nick": nick,
                    @"actor": actor,
                    @"platform": platform,
                    @"ptr": [NSValue valueWithPointer:(__bridge void*)player]
                };
                [playerList addObject:playerData];

                // Row
                UIView* row = [[UIView alloc] initWithFrame:CGRectMake(8, py, 284, 54)];
                row.backgroundColor = COLOR_BTN;
                row.layer.cornerRadius = 8;

                UILabel* nameLbl = makeLabel([NSString stringWithFormat:@"%@ %@", icon, display], CGRectMake(10, 4, 160, 18), 13, YES);
                UILabel* actorLbl = makeLabel([NSString stringWithFormat:@"Actor #%@  •  %@", actor, nick.length > 30 ? [nick substringToIndex:30] : nick], CGRectMake(10, 24, 264, 12), 9, NO);
                actorLbl.textColor = COLOR_GRAY;
                [row addSubview:nameLbl];
                [row addSubview:actorLbl];

                // Color button
                NSDictionary* pd = playerData;
                UIViewController* weakVC = vc;
                UIButton* colorBtn = makeBtn(@"🎨 Color", CGRectMake(174, 14, 52, 26), COLOR_ACCENT);
                [colorBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
                colorBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
                [colorBtn addTarget:colorBtn action:NSSelectorFromString(@"colorBtnTapped:") forControlEvents:UIControlEventTouchUpInside];
                objc_setAssociatedObject(colorBtn, "playerData", pd, OBJC_ASSOCIATION_RETAIN);
                objc_setAssociatedObject(colorBtn, "viewController", weakVC, OBJC_ASSOCIATION_ASSIGN);

                class_addMethod([colorBtn class], NSSelectorFromString(@"colorBtnTapped:"),
                    imp_implementationWithBlock(^(id _self, UIButton* btn){
                        NSDictionary* p = objc_getAssociatedObject(btn, "playerData");
                        UIViewController* v2 = objc_getAssociatedObject(btn, "viewController");
                        if (p && v2) showColorPickerForPlayer(p, v2);
                    }), "v@:@");

                [colorBtn addTarget:colorBtn action:NSSelectorFromString(@"colorBtnTapped:") forControlEvents:UIControlEventTouchUpInside];
                [row addSubview:colorBtn];

                // Kick button
                UIButton* kickBtn = makeBtn(@"Kick", CGRectMake(230, 14, 46, 26), COLOR_RED);
                kickBtn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
                [row addSubview:kickBtn];

                [scroll addSubview:row];
                py += 60;
            }
            scroll.contentSize = CGSizeMake(300, py);
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
            if (setNickNameFn) {
                @try {
                    // Try to call set_NickName on local player
                    NSArray* classNames = @[@"PhotonNetwork", @"LoadBalancingClient"];
                    for (NSString* cls in classNames) {
                        Class c = NSClassFromString(cls);
                        if (!c) continue;
                        @try {
                            id localPlayer = [c valueForKey:@"LocalPlayer"];
                            if (localPlayer) {
                                setNickNameFn((__bridge void*)localPlayer, (__bridge void*)name);
                                set = YES;
                                break;
                            }
                        } @catch(NSException* e) {}
                    }
                } @catch(NSException* e) {}
            }
            st.text = set ? [NSString stringWithFormat:@"✓ Name set: %@", name] : [NSString stringWithFormat:@"✓ Queued: %@", name];
            st.textColor = COLOR_ACCENT;
            [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"bytemenu_nickname"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            f.text = @"";
            [f resignFirstResponder];
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"setMyColor:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            NSString* colorKey = b.accessibilityIdentifier;
            UILabel* st = (UILabel*)[menuPanel viewWithTag:3003];

            NSDictionary* colorMap = @{
                @"red":    @[@0.9f, @0.2f, @0.2f],
                @"blue":   @[@0.2f, @0.4f, @0.9f],
                @"green":  @[@0.2f, @0.75f, @0.3f],
                @"pink":   @[@0.9f, @0.4f, @0.7f],
                @"gold":   @[@0.9f, @0.75f, @0.1f],
                @"white":  @[@1.0f, @1.0f, @1.0f],
                @"orange": @[@0.95f, @0.5f, @0.1f],
                @"purple": @[@0.6f, @0.2f, @0.9f],
                @"cyan":   @[@0.0f, @0.9f, @0.9f],
                @"black":  @[@0.05f, @0.05f, @0.05f]
            };

            NSArray* rgb = colorMap[colorKey];
            if (!rgb) return;
            float r = [rgb[0] floatValue];
            float g = [rgb[1] floatValue];
            float bl = [rgb[2] floatValue];

            BOOL set = NO;
            if (setColorFn) {
                // Try to find local avatar and set color
                NSArray* classNames = @[@"AvatarController", @"MasterPlayer", @"Avatar"];
                for (NSString* cls in classNames) {
                    Class c = NSClassFromString(cls);
                    if (!c) continue;
                    @try {
                        id instance = [c valueForKey:@"instance"];
                        if (instance) {
                            setColorFn((__bridge void*)instance, r, g, bl, 1.0f);
                            set = YES;
                            break;
                        }
                    } @catch(NSException* e) {}
                }
            }

            // Highlight selected
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

            st.text = set ? [NSString stringWithFormat:@"✓ Color set: %@", b.currentTitle] : [NSString stringWithFormat:@"✓ Queued: %@", b.currentTitle];
            st.textColor = COLOR_ACCENT;
            [[NSUserDefaults standardUserDefaults] setObject:colorKey forKey:@"bytemenu_colorkey"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"clearMyColor:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UILabel* st = (UILabel*)[menuPanel viewWithTag:3003];
            if (clearColorFn) {
                NSArray* classNames = @[@"AvatarController", @"MasterPlayer", @"Avatar"];
                for (NSString* cls in classNames) {
                    Class c = NSClassFromString(cls);
                    if (!c) continue;
                    @try {
                        id instance = [c valueForKey:@"instance"];
                        if (instance) {
                            clearColorFn((__bridge void*)instance);
                            break;
                        }
                    } @catch(NSException* e) {}
                }
            }
            st.text = @"✓ Color cleared";
            st.textColor = COLOR_ACCENT;
        }), "v@:@");

    class_addMethod([vc class], NSSelectorFromString(@"becomeEmptyYeep:"),
        imp_implementationWithBlock(^(id _self, UIButton* b){
            UILabel* st = (UILabel*)[menuPanel viewWithTag:3004];
            if (clearColorFn) {
                NSArray* classNames = @[@"AvatarController", @"MasterPlayer", @"Avatar", @"CosmeticsDisplay"];
                for (NSString* cls in classNames) {
                    Class c = NSClassFromString(cls);
                    if (!c) continue;
                    @try {
                        id instance = [c valueForKey:@"instance"];
                        if (instance) {
                            clearColorFn((__bridge void*)instance);
                        }
                        SEL clearSel = NSSelectorFromString(@"clearActiveCosmetics");
                        if ([c respondsToSelector:clearSel]) {
                            [c performSelector:clearSel];
                        }
                    } @catch(NSException* e) {}
                }
            }
            st.text = @"👻 Empty Yeep applied";
            st.textColor = [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        setupMenu();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            @try {
                initIL2CPP();
            } @catch(NSException* e) {
                NSLog(@"[YeepsMod] initIL2CPP failed: %@", e);
            }
        });
    });
}
