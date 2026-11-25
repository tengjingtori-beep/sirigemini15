#import <Foundation/Foundation.h>

// SGGemini — Gemini API client (stage 0).
//
// The JSON work is split into pure functions on purpose: building
// the request body and extracting the reply text take plain data
// in and out, use Foundation only (no UIKit, no network), and are
// mirrored one-to-one by the offline unit tests in
// ../tests/test_gemini_logic.py, so the logic is verified without
// a Mac or a device. Only +sendPrompt:... touches the network.
//
// Endpoint: POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent
// Auth:     "x-goog-api-key: <key>" header (the key stays on the
//           device, in this tweak's own prefs domain).
@interface SGGemini : NSObject

// Model selection stored in prefs: @"flashlite" (default) / @"flash".
+ (NSString *)modelIDForSelection:(NSString *)selection;
+ (NSString *)endpointURLStringForModelID:(NSString *)modelID;

// ----- pure logic (unit-tested) -----
// history: array of @{ @"role": @"user" | @"model", @"text": NSString }
// in speaking order; may be nil/empty. The new prompt is appended
// as the final user turn.
+ (NSDictionary *)requestBodyForPrompt:(NSString *)prompt
                               history:(NSArray<NSDictionary *> *)history;
+ (NSData *)requestBodyDataForPrompt:(NSString *)prompt
                             history:(NSArray<NSDictionary *> *)history;

// Extracts the reply text from a decoded generateContent response.
// Returns nil and fills *error for: API error objects, missing or
// empty candidates (including safety blocks, whose blockReason is
// included in the error message), and malformed shapes.
+ (NSString *)extractTextFromResponseObject:(id)responseObject
                                      error:(NSError **)error;
+ (NSString *)extractTextFromResponseData:(NSData *)data
                                    error:(NSError **)error;

// ----- network (not unit-tested; thin wrapper over the above) -----
+ (void)sendPrompt:(NSString *)prompt
           history:(NSArray<NSDictionary *> *)history
            apiKey:(NSString *)apiKey
           modelID:(NSString *)modelID
        completion:(void (^)(NSString *text, NSError *error))completion;

@end
