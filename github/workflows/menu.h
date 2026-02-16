#import <UIKit/UIKit.h>

@interface FloatingMenu : NSObject
@property (nonatomic, strong) UIWindow *menuWindow;
@property (nonatomic, strong) UIButton *toggleButton;
+ (instancetype)sharedInstance;
- (void)setupMenu;
@end
