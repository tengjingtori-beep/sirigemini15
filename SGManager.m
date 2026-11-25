// SiriGemini15 — core (stage 0, skeleton)
//
// Stage 0 proves only the foundation on the real device, in the
// same style as VoiceChat15 / Future15 stage 0:
//   - the dylib loads into SpringBoard only (narrow filter),
//   - the log file is written (create if missing, append after),
//   - prefs are read and re-read when Settings changes them,
//   - a PASSIVE witness records when Siri's UI appears,
//   - the failure brake exists (5 exceptions -> all activity
//     stops until respring).
// No interception of spoken words, no network, no speech in this
// stage — the Gemini API test lives in the prefs bundle and runs
// inside the Settings app. This dylib also never touches Siri's
// UI classes for drawing: LiquidSiri owns the look. The witness
// hooks below are lifecycle-only, always call the original, and
// deliberately avoid the orb/status drawing classes and methods
// that LiquidSiri hooks (e.g. SUICOrbView).

#import "SGManager.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NSString * const kSGPrefsID = @"com.tori.sirigemini15";
NSString * const kSGPrefsChanged = @"com.tori.sirigemini15.changed";
static NSString * const kSGVersion = @"0.1.0";

// MSHookMessageEx is provided at runtime by ElleKit (substrate
// compatibility). Declared manually so the build does not depend
// on substrate headers being present in the SDK.
extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);

// ---------- prefs ----------
static BOOL prefEnabled = YES;
static NSString *prefModelSel = @"flashlite"; // flashlite | flash

static id SGAppValue(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)kSGPrefsID);
}

void SGLoadPrefs(void) {
    @try {
        id v;
        v = SGAppValue(@"Enabled"); if (v) prefEnabled = [v boolValue];
        v = SGAppValue(@"Model");
        if (v && [(id)v isKindOfClass:[NSString class]] &&
            ([(NSString *)v isEqualToString:@"flash"] || [(NSString *)v isEqualToString:@"flashlite"])) {
            prefModelSel = [(NSString *)v copy];
        }
        CFPreferencesAppSynchronize((__bridge CFStringRef)kSGPrefsID);
    } @catch (__unused id e) {}
}

// ---------- log ----------
// One line per event: [time] [process] message.
// The file is created only when it does not exist and appended
// afterwards (creating it on every write would erase the lines
// other processes wrote). Falls back to /var/tmp if the Logs
// directory cannot be created.
static NSFileHandle *sgLogHandle = nil;
static dispatch_queue_t sgLogQueue = nil;

static NSString *SGLogPath(void) {
    NSString *p = @"/var/mobile/Library/Logs/SiriGemini15.log";
    if ([NSFileManager.defaultManager fileExistsAtPath:p]) return p;
    NSString *dir = @"/var/mobile/Library/Logs";
    if ([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil] &&
        [NSFileManager.defaultManager createFileAtPath:p contents:nil attributes:nil]) return p;
    return @"/var/tmp/SiriGemini15.log";
}

void SGLog(NSString *format, ...) {
    @try {
        va_list ap; va_start(ap, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
        va_end(ap);
        if (!sgLogQueue) sgLogQueue = dispatch_queue_create("com.tori.sirigemini15.log", DISPATCH_QUEUE_SERIAL);
        dispatch_async(sgLogQueue, ^{
            @try {
                if (!sgLogHandle) {
                    NSString *path = SGLogPath();
                    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
                        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
                    }
                    sgLogHandle = [NSFileHandle fileHandleForWritingAtPath:path];
                }
                [sgLogHandle seekToEndOfFile];
                NSString *proc = [[NSProcessInfo processInfo] processName] ?: @"?";
                NSString *line = [NSString stringWithFormat:@"[%@] [%@] %@\n",
                    [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle],
                    proc, msg];
                [sgLogHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
                [sgLogHandle synchronizeFile];
            } @catch (__unused id e) {}
        });
    } @catch (__unused id e) {}
}

// ---------- failure brake ----------
// After kSGBrakeThreshold exceptions anywhere in the manager, the
// brake engages: all feature activity must check +[SGManager
// brakeOn] (and the master Enabled switch) before doing anything.
// The brake never auto-releases; a respring restarts the count.
// Same mechanism as VoiceChat15: one broken feature must not loop
// into a SpringBoard crash / Safe Mode cycle.
static NSInteger gExceptionCount = 0;
static BOOL gBrakeOn = NO;
static const NSInteger kSGBrakeThreshold = 5;

void SGNoteException(NSString *where, id error) {
    gExceptionCount++;
    SGLog(@"EXCEPTION %@: %@ (count=%ld)", where, error, (long)gExceptionCount);
    if (!gBrakeOn && gExceptionCount >= kSGBrakeThreshold) {
        gBrakeOn = YES;
        SGLog(@"BRAKE_ON exceptions reached %ld: all feature activity is stopped until respring", (long)gExceptionCount);
    }
}

// ---------- Siri UI witness (passive, log only) ----------
// Candidates are looked up with NSClassFromString at setup time.
// A missing class or method is skipped and recorded in the log —
// never a crash. Hooks only observe lifecycle moments, always
// call the original implementation, and change nothing. Drawing
// classes/methods used by LiquidSiri (SUICOrbView etc.) are NOT
// in this list on purpose.
static NSTimeInterval sgLastSeenAt = 0;

static void SGNoteSiriSeen(NSString *via) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - sgLastSeenAt < 3.0) return; // debounce: one line per appearance
    sgLastSeenAt = now;
    SGLog(@"SIRI_UI_SEEN via=%@", via);
}

static void (*origStatusDidMoveToWindow)(id, SEL) = NULL;
static void hookStatusDidMoveToWindow(id self, SEL _cmd) {
    if (origStatusDidMoveToWindow) origStatusDidMoveToWindow(self, _cmd);
    @try {
        if ([(UIView *)self window]) SGNoteSiriSeen(@"SiriUISiriStatusView.didMoveToWindow");
    } @catch (id e) { SGNoteException(@"witness.status", e); }
}

static void (*origNavViewDidAppear)(id, SEL, BOOL) = NULL;
static void hookNavViewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (origNavViewDidAppear) origNavViewDidAppear(self, _cmd, animated);
    SGNoteSiriSeen(@"SiriUINavigationController.viewDidAppear");
}

static void SGInstallWitnessHooks(void) {
    struct { const char *cls; const char *sel; IMP hook; IMP *orig; } specs[] = {
        { "SiriUISiriStatusView",    "didMoveToWindow",    (IMP)hookStatusDidMoveToWindow, (IMP *)&origStatusDidMoveToWindow },
        { "SiriUINavigationController", "viewDidAppear:",  (IMP)hookNavViewDidAppear,      (IMP *)&origNavViewDidAppear },
    };
    for (unsigned i = 0; i < sizeof(specs) / sizeof(specs[0]); i++) {
        @try {
            Class cls = NSClassFromString([NSString stringWithUTF8String:specs[i].cls]);
            if (!cls) {
                SGLog(@"HOOK_SKIP class=%s reason=not_found", specs[i].cls);
                continue;
            }
            SEL sel = sel_registerName(specs[i].sel);
            if (!class_getInstanceMethod(cls, sel)) {
                SGLog(@"HOOK_SKIP class=%s selector=%s reason=method_not_found", specs[i].cls, specs[i].sel);
                continue;
            }
            MSHookMessageEx(cls, sel, specs[i].hook, specs[i].orig);
            SGLog(@"HOOK_OK class=%s selector=%s (witness only)", specs[i].cls, specs[i].sel);
        } @catch (id e) {
            SGNoteException(@"witness.install", e);
        }
    }
    // Presence note only (no hook): SpringBoard-side assistant
    // controller, a stage-1 candidate interception point.
    SGLog(@"CLASS_CHECK SBAssistantController=%@",
          NSClassFromString(@"SBAssistantController") ? @"found" : @"not_found");
}

// ---------- manager ----------
@interface SGManager ()
@property (nonatomic) BOOL setupDone;
@end

@implementation SGManager

+ (instancetype)shared {
    static SGManager *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SGManager alloc] init]; });
    return s;
}

+ (BOOL)brakeOn { return gBrakeOn; }

- (void)reloadPrefs {
    SGLoadPrefs();
    SGLog(@"PREFS_READ enabled=%d model=%@ brake=%d", prefEnabled, prefModelSel, gBrakeOn);
}

- (void)setup {
    if (self.setupDone) return;
    self.setupDone = YES;
    @try {
        SGLog(@"SETUP_START version=%@", kSGVersion);
        [self reloadPrefs];
        if (prefEnabled && !gBrakeOn) {
            SGInstallWitnessHooks();
        } else {
            SGLog(@"WITNESS_SKIPPED enabled=%d brake=%d", prefEnabled, gBrakeOn);
        }
        SGLog(@"STAGE0 skeleton only: no interception, no network in SpringBoard. Gemini API test lives in Settings.");
        SGLog(@"SETUP_DONE");
    } @catch (id e) {
        SGNoteException(@"setup", e);
    }
}

@end
