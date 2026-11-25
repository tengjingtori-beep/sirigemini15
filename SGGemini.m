// SGGemini — Gemini API client. See SGGemini.h for the split
// between pure logic (tested offline) and the network wrapper.

#import "SGGemini.h"

NSString * const kSGGeminiErrorDomain = @"com.tori.sirigemini15.gemini";

@implementation SGGemini

+ (NSString *)modelIDForSelection:(NSString *)selection {
    if ([selection isEqualToString:@"flash"]) return @"gemini-3.8-flash";
    return @"gemini-3.5-flash-lite"; // default: fast, widest free tier (2.5 models are closed to new API users, verified 2026-11-26)
}

+ (NSString *)endpointURLStringForModelID:(NSString *)modelID {
    if (!modelID || [modelID length] == 0) modelID = [self modelIDForSelection:nil];
    return [NSString stringWithFormat:
        @"https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent",
        modelID];
}

+ (NSDictionary *)requestBodyForPrompt:(NSString *)prompt
                               history:(NSArray<NSDictionary *> *)history {
    NSMutableArray *contents = [NSMutableArray array];
    for (NSDictionary *turn in history ?: @[]) {
        if (![turn isKindOfClass:[NSDictionary class]]) continue;
        NSString *role = turn[@"role"];
        NSString *text = turn[@"text"];
        if (![text isKindOfClass:[NSString class]] || [text length] == 0) continue;
        if (![role isEqualToString:@"model"]) role = @"user";
        [contents addObject:@{ @"role": role,
                               @"parts": @[ @{ @"text": text } ] }];
    }
    [contents addObject:@{ @"role": @"user",
                           @"parts": @[ @{ @"text": prompt ?: @"" } ] }];
    return @{ @"contents": contents };
}

+ (NSData *)requestBodyDataForPrompt:(NSString *)prompt
                             history:(NSArray<NSDictionary *> *)history {
    NSDictionary *body = [self requestBodyForPrompt:prompt history:history];
    return [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
}

+ (NSError *)errorWithCode:(NSInteger)code message:(NSString *)message {
    return [NSError errorWithDomain:kSGGeminiErrorDomain code:code
        userInfo:@{ NSLocalizedDescriptionKey: message ?: @"unknown error" }];
}

+ (NSString *)extractTextFromResponseObject:(id)obj error:(NSError **)error {
    if (![obj isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [self errorWithCode:1 message:@"response is not a JSON object"];
        return nil;
    }
    NSDictionary *apiError = obj[@"error"];
    if ([apiError isKindOfClass:[NSDictionary class]]) {
        NSString *msg = apiError[@"message"];
        if (![msg isKindOfClass:[NSString class]] || [msg length] == 0) msg = @"Gemini API error";
        if (error) *error = [self errorWithCode:2 message:msg];
        return nil;
    }
    NSArray *candidates = obj[@"candidates"];
    if (![candidates isKindOfClass:[NSArray class]] || [candidates count] == 0) {
        NSString *reason = nil;
        NSDictionary *feedback = obj[@"promptFeedback"];
        if ([feedback isKindOfClass:[NSDictionary class]]) {
            id r = feedback[@"blockReason"];
            if ([r isKindOfClass:[NSString class]]) reason = r;
        }
        NSString *msg = reason ? [NSString stringWithFormat:@"no candidates (blocked: %@)", reason]
                               : @"no candidates in response";
        if (error) *error = [self errorWithCode:3 message:msg];
        return nil;
    }
    NSDictionary *first = candidates[0];
    if (![first isKindOfClass:[NSDictionary class]]) {
        if (error) *error = [self errorWithCode:4 message:@"candidate is not an object"];
        return nil;
    }
    NSDictionary *content = first[@"content"];
    NSArray *parts = [content isKindOfClass:[NSDictionary class]] ? content[@"parts"] : nil;
    if (![parts isKindOfClass:[NSArray class]]) {
        if (error) *error = [self errorWithCode:5 message:@"candidate has no content parts"];
        return nil;
    }
    NSMutableString *text = [NSMutableString string];
    for (id part in parts) {
        if (![part isKindOfClass:[NSDictionary class]]) continue;
        id t = part[@"text"];
        if ([t isKindOfClass:[NSString class]]) [text appendString:t];
    }
    if ([text length] == 0) {
        if (error) *error = [self errorWithCode:6 message:@"reply text is empty"];
        return nil;
    }
    return [text copy];
}

+ (NSString *)extractTextFromResponseData:(NSData *)data error:(NSError **)error {
    if (!data || [data length] == 0) {
        if (error) *error = [self errorWithCode:7 message:@"empty response data"];
        return nil;
    }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!obj) {
        if (error) *error = [self errorWithCode:8 message:@"response is not valid JSON"];
        return nil;
    }
    return [self extractTextFromResponseObject:obj error:error];
}

+ (void)sendPrompt:(NSString *)prompt
           history:(NSArray<NSDictionary *> *)history
            apiKey:(NSString *)apiKey
           modelID:(NSString *)modelID
        completion:(void (^)(NSString *text, NSError *error))completion {
    if (!completion) return;
    if (!apiKey || [apiKey length] == 0) {
        completion(nil, [self errorWithCode:9 message:@"API key is empty"]);
        return;
    }
    NSURL *url = [NSURL URLWithString:[self endpointURLStringForModelID:modelID]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 30;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:apiKey forHTTPHeaderField:@"x-goog-api-key"];
    req.HTTPBody = [self requestBodyDataForPrompt:prompt history:history];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *netError) {
        if (netError) { completion(nil, netError); return; }
        NSError *extractError = nil;
        NSString *text = [self extractTextFromResponseData:data error:&extractError];
        completion(text, text ? nil : extractError);
    }];
    [task resume];
}

@end
