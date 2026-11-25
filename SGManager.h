#import <Foundation/Foundation.h>

// SiriGemini15 manager (stage 0, skeleton):
// owns the diagnostic log, the prefs snapshot, the failure brake
// and the passive Siri-UI witness hooks.
// Later stages plug in here:
//   stage 1: intercept the words spoken to Siri and hand them
//            to the Gemini client (SGGemini)
//   stage 2: speak Gemini's answer in Siri's flow and keep the
//            conversation going across turns
// Every feature path must pass through the brake and write to the
// log so a failure can be traced from the log alone.
@interface SGManager : NSObject
+ (instancetype)shared;
- (void)setup;
- (void)reloadPrefs;
+ (BOOL)brakeOn;
@end

// Shared prefs / logging / brake helpers used by Tweak.x too.
void SGLoadPrefs(void);
void SGLog(NSString *format, ...);
void SGNoteException(NSString *where, id error);
