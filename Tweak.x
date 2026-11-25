// SiriGemini15 — entry point (stage 0, skeleton)
// iPhone 7 / iOS 15 / Dopamine (rootless).
// The filter plist injects this dylib into SpringBoard ONLY.
// Stage 0 does exactly three things:
//   1. start the manager (log + prefs + failure brake),
//   2. install a PASSIVE witness hook that only records when
//      Siri's UI appears (no interception, no UI changes),
//   3. nothing else. The Gemini API test lives in the Settings
//      pane and runs inside the Settings app.
// The glowing Siri look belongs to LiquidSiri; this tweak never
// touches Siri's UI classes, drawing or orb views, so the two
// tweaks cannot fight over the same methods.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SGManager.h"

@interface SpringBoard : UIApplication
@end

static void sgPrefsChanged(CFNotificationCenterRef center, void *observer,
                           CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SGManager shared] reloadPrefs];
    });
}

%group SGSpringBoardGroup
%hook SpringBoard
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;
    SGLog(@"SPRINGBOARD_LAUNCHED");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[SGManager shared] setup];
    });
}
%end
%end

%ctor {
    @autoreleasepool {
        SGLoadPrefs();
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
        if ([bid isEqualToString:@"com.apple.springboard"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                sgPrefsChanged, (__bridge CFStringRef)@"com.tori.sirigemini15.changed", NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            SGLog(@"A_DYLIB_LOADED version=0.1.0 process=%@", bid);
            %init(SGSpringBoardGroup);
        }
    }
}
