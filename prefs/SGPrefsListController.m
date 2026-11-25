#import "SGPrefsListController.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Preferences/PSSpecifier.h>
#import "../SGGemini.h"

// SiriGemini15 prefs (stage 0, 0.1.0).
//
// The model chooser deliberately does NOT use a PSLinkListCell /
// PSListItemsController:
//   - VoiceChat15 0.1.1: a list cell without a working detail did
//     nothing at all when tapped.
//   - VoiceChat15 0.1.2: detail=PSListItemsController crashed the
//     Settings app when tapped on this very device (confirmed by
//     the user, 2026-11-19).
// So the model is picked with two plain PSButtonCell rows — the
// same primitive as the test buttons, proven on this device. The
// currently selected row gets a "（今これ）" suffix, refreshed on
// every load/reload.
//
// The "API test" button sends the fixed prompt
// 「接続テストです。短く挨拶して」 to Gemini with the entered key
// and speaks the reply with AVSpeechSynthesizer (ja-JP). Results
// are also written to the shared log with the GEMINI_OK /
// GEMINI_FAIL / TTS_DONE stage marks.

static NSString * const kSGPrefsDomain = @"com.tori.sirigemini15";

// ---------- shared log (same file/format as the tweak) ----------
static void SGPrefsLog(NSString *format, ...) {
    @try {
        va_list ap; va_start(ap, format);
        NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
        va_end(ap);
        NSString *path = @"/var/mobile/Library/Logs/SiriGemini15.log";
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
            NSString *dir = @"/var/mobile/Library/Logs";
            [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            if (![NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil]) {
                path = @"/var/tmp/SiriGemini15.log";
            }
        }
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) return;
        [h seekToEndOfFile];
        NSString *proc = [[NSProcessInfo processInfo] processName] ?: @"?";
        NSString *line = [NSString stringWithFormat:@"[%@] [%@] %@\n",
            [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterNoStyle timeStyle:NSDateFormatterMediumStyle],
            proc, msg];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h synchronizeFile];
        [h closeFile];
    } @catch (__unused id e) {}
}

// ---------- speech (singleton so the delegate outlives the pane) ----------
@interface SGSpeaker : NSObject <AVSpeechSynthesizerDelegate>
@property (nonatomic, strong) AVSpeechSynthesizer *synth;
+ (instancetype)shared;
- (void)speak:(NSString *)text;
- (void)stop;
@end

@implementation SGSpeaker
+ (instancetype)shared {
    static SGSpeaker *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[SGSpeaker alloc] init]; });
    return s;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _synth = [[AVSpeechSynthesizer alloc] init];
        _synth.delegate = self;
    }
    return self;
}
- (void)speak:(NSString *)text {
    if (self.synth.isSpeaking) [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    AVSpeechUtterance *u = [AVSpeechUtterance speechUtteranceWithString:text];
    AVSpeechSynthesisVoice *voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"ja-JP"];
    if (voice) u.voice = voice;
    [self.synth speakUtterance:u];
}
- (void)stop {
    if (self.synth.isSpeaking) [self.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer
 didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    SGPrefsLog(@"TTS_DONE text=%@", [utterance.speechString substringToIndex:MIN((NSUInteger)40, [utterance.speechString length])]);
}
@end

// ---------- prefs reads ----------
static NSString *SGCurrentModelSel(void) {
    NSString *sel = @"flashlite";
    CFPreferencesAppSynchronize((__bridge CFStringRef)kSGPrefsDomain);
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("Model"), (__bridge CFStringRef)kSGPrefsDomain);
    if (v) {
        if (CFGetTypeID(v) == CFStringGetTypeID() &&
            [(__bridge NSString *)v isEqualToString:@"flash"]) {
            sel = @"flash";
        }
        CFRelease(v);
    }
    return sel;
}

static NSString *SGCurrentAPIKey(void) {
    NSString *key = @"";
    CFPreferencesAppSynchronize((__bridge CFStringRef)kSGPrefsDomain);
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("APIKey"), (__bridge CFStringRef)kSGPrefsDomain);
    if (v) {
        if (CFGetTypeID(v) == CFStringGetTypeID()) key = [(__bridge NSString *)v copy];
        CFRelease(v);
    }
    return [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@implementation SGPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self sgRefreshModelLabels];
    }
    return _specifiers;
}

// Adds "（今これ）" to the button row of the currently selected
// model and removes it from the other one. Same pattern as
// VoiceChat15 0.1.3's rate rows; wrapped so a surprise here can
// never take the Settings pane down.
- (void)sgRefreshModelLabels {
    @try {
        NSString *cur = SGCurrentModelSel();
        NSDictionary *base = @{ @"model_flashlite": @[@"Flash-Lite（速い・無料枠が広い）", @"flashlite"],
                                @"model_flash":     @[@"Flash（少し賢い）",               @"flash"] };
        for (PSSpecifier *spec in _specifiers) {
            NSString *ident = nil;
            @try { ident = [spec identifier]; } @catch (__unused id e) {}
            if (!ident) {
                @try { ident = [spec propertyForKey:@"id"]; } @catch (__unused id e) {}
            }
            NSArray *pair = ident ? base[ident] : nil;
            if (!pair) continue;
            NSString *label = pair[0];
            if ([pair[1] isEqualToString:cur]) label = [label stringByAppendingString:@"（今これ）"];
            [spec setProperty:label forKey:@"label"];
            spec.name = label;
        }
    } @catch (__unused id e) {}
}

- (void)sgSetModel:(NSString *)sel {
    CFPreferencesSetAppValue(CFSTR("Model"), (__bridge CFPropertyListRef)sel,
                             (__bridge CFStringRef)kSGPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kSGPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.tori.sirigemini15.changed"),
                                         NULL, NULL, true);
    SGPrefsLog(@"PREFS_READ model set to %@", sel);
    [self reloadSpecifiers];
}

- (void)setModelFlashLite:(id)sender {
    (void)sender;
    [self sgSetModel:@"flashlite"];
}

- (void)setModelFlash:(id)sender {
    (void)sender;
    [self sgSetModel:@"flash"];
}

// API test: fixed greeting prompt -> Gemini -> speak the reply.
// Runs inside the Settings app, independent of the tweak dylib.
- (void)testAPI:(id)sender {
    (void)sender;
    NSString *key = SGCurrentAPIKey();
    if ([key length] == 0) {
        SGPrefsLog(@"GEMINI_FAIL reason=no_api_key");
        [[SGSpeaker shared] speak:@"APIキーが入力されていません。上の欄に、GeminiのAPIキーを入れてください。"];
        return;
    }
    NSString *modelID = [SGGemini modelIDForSelection:SGCurrentModelSel()];
    [[SGSpeaker shared] speak:@"接続テストを送ります。少し待ってください。"];
    [SGGemini sendPrompt:@"接続テストです。短く挨拶して"
                 history:nil
                  apiKey:key
                 modelID:modelID
              completion:^(NSString *text, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (text) {
                SGPrefsLog(@"GEMINI_OK model=%@ reply=%@", modelID,
                           [text substringToIndex:MIN((NSUInteger)80, [text length])]);
                NSString *speakText = text;
                if ([speakText length] > 300) speakText = [[speakText substringToIndex:300] stringByAppendingString:@"。以下省略します。"];
                [[SGSpeaker shared] speak:speakText];
            } else {
                SGPrefsLog(@"GEMINI_FAIL model=%@ error=%@", modelID, error);
                [[SGSpeaker shared] speak:@"接続テストに失敗しました。キーとネットを確認してください。詳しくはログを見てください。"];
            }
        });
    }];
}

- (void)stopTTS:(id)sender {
    (void)sender;
    [[SGSpeaker shared] stop];
}

// The tweak (SpringBoard, same mobile user) owns the log file, and
// the Settings app also runs as mobile, so it can remove it directly.
- (void)clearLog:(id)sender {
    (void)sender;
    for (NSString *path in @[@"/var/mobile/Library/Logs/SiriGemini15.log",
                             @"/var/tmp/SiriGemini15.log"]) {
        [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    }
}

@end
