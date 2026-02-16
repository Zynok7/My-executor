#import "Menu.h"
#import "lua.h"
#import <objc/runtime.h>

@interface FloatingMenu () <UITextViewDelegate>
@property (nonatomic, strong) UIView *menuContainer;
@property (nonatomic, strong) UITextView *scriptTextView;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, assign) BOOL menuVisible;
@end

// C function to show toast from Lua
int lua_makeToast(lua_State *L) {
    const char *message = lua_tostring(L, 1);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Toast"
                                                                       message:[NSString stringWithUTF8String:message]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        // Find top view controller
        UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        [topVC presentViewController:alert animated:YES completion:nil];
        
        // Auto dismiss after 2 seconds
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    });
    
    return 0;
}

// C++ Lua execution function
void executeLua(const char* source) {
    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    
    // Register custom makeToast function
    lua_register(L, "makeToast", lua_makeToast);
    
    // Compile the Lua source
    size_t bytecodeSize = 0;
    char* bytecode = luau_compile(source, strlen(source), NULL, &bytecodeSize);
    
    if (bytecode == NULL) {
        NSLog(@"[MyExecutor] Compilation failed");
        lua_close(L);
        return;
    }
    
    // Load the bytecode
    if (luau_load(L, "script", bytecode, bytecodeSize, 0) != 0) {
        const char* error = lua_tostring(L, -1);
        NSLog(@"[MyExecutor] Load error: %s", error);
        free(bytecode);
        lua_close(L);
        return;
    }
    
    free(bytecode);
    
    // Execute the script
    if (lua_pcall(L, 0, 0, 0) != 0) {
        const char* error = lua_tostring(L, -1);
        NSLog(@"[MyExecutor] Runtime error: %s", error);
        
        // Show error in alert
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lua Error"
                                                                           message:[NSString stringWithUTF8String:error]
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            
            UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            while (topVC.presentedViewController) {
                topVC = topVC.presentedViewController;
            }
            [topVC presentViewController:alert animated:YES completion:nil];
        });
    }
    
    lua_close(L);
}

@implementation FloatingMenu

+ (instancetype)sharedInstance {
    static FloatingMenu *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[FloatingMenu alloc] init];
    });
    return instance;
}

- (void)setupMenu {
    // Create floating window
    self.menuWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 350, 450)];
    self.menuWindow.windowLevel = UIWindowLevelStatusBar + 1;
    self.menuWindow.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.menuWindow.layer.cornerRadius = 15;
    self.menuWindow.clipsToBounds = YES;
    self.menuWindow.center = CGPointMake([UIScreen mainScreen].bounds.size.width / 2,
                                          [UIScreen mainScreen].bounds.size.height / 2);
    
    // Container view
    self.menuContainer = [[UIView alloc] initWithFrame:self.menuWindow.bounds];
    self.menuContainer.backgroundColor = [UIColor clearColor];
    [self.menuWindow addSubview:self.menuContainer];
    
    // Title label
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 350, 30)];
    titleLabel.text = @"MyExecutor";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.menuContainer addSubview:titleLabel];
    
    // Script text view
    self.scriptTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, 330, 340)];
    self.scriptTextView.backgroundColor = [UIColor blackColor];
    self.scriptTextView.textColor = [UIColor greenColor];
    self.scriptTextView.font = [UIFont fontWithName:@"Menlo" size:14];
    self.scriptTextView.layer.cornerRadius = 8;
    self.scriptTextView.layer.borderWidth = 1;
    self.scriptTextView.layer.borderColor = [UIColor greenColor].CGColor;
    self.scriptTextView.text = @"-- Enter Lua script here\nmakeToast(\"Hello from Lua!\")";
    self.scriptTextView.delegate = self;
    [self.menuContainer addSubview:self.scriptTextView];
    
    // Run button
    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runButton.frame = CGRectMake(10, 400, 330, 40);
    self.runButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0];
    self.runButton.layer.cornerRadius = 8;
    [self.runButton setTitle:@"RUN" forState:UIControlStateNormal];
    [self.runButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.runButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.runButton addTarget:self action:@selector(runScript) forControlEvents:UIControlEventTouchUpInside];
    [self.menuContainer addSubview:self.runButton];
    
    // Close button
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(320, 10, 30, 30);
    [closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [closeButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuContainer addSubview:closeButton];
    
    // Toggle button (small floating button)
    self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleButton.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 60, 100, 50, 50);
    self.toggleButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0];
    self.toggleButton.layer.cornerRadius = 25;
    [self.toggleButton setTitle:@"⚡︎" forState:UIControlStateNormal];
    [self.toggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:24];
    [self.toggleButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    // Add pan gesture to toggle button
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.toggleButton addGestureRecognizer:panGesture];
    
    // Create separate window for toggle button
    UIWindow *toggleWindow = [[UIWindow alloc] initWithFrame:self.toggleButton.frame];
    toggleWindow.windowLevel = UIWindowLevelStatusBar + 2;
    toggleWindow.backgroundColor = [UIColor clearColor];
    [toggleWindow addSubview:self.toggleButton];
    self.toggleButton.frame = toggleWindow.bounds;
    toggleWindow.hidden = NO;
    
    // Show menu initially
    self.menuWindow.hidden = NO;
    self.menuVisible = YES;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:gesture.view.superview];
    gesture.view.center = CGPointMake(gesture.view.center.x + translation.x,
                                     gesture.view.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:gesture.view.superview];
}

- (void)toggleMenu {
    self.menuVisible = !self.menuVisible;
    self.menuWindow.hidden = !self.menuVisible;
}

- (void)runScript {
    NSString *script = self.scriptTextView.text;
    if (script.length == 0) {
        return;
    }
    
    // Execute Lua script in background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        executeLua([script UTF8String]);
    });
}

@end
