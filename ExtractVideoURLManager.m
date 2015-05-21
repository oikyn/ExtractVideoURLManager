#import "ExtractVideoURLManager.h"

#import <JavaScriptCore/JavaScriptCore.h>


typedef void (^FetchSourceResponceHandler)(NSData *data, NSError *error);

static NSString* const youtubeURL = @"https://www.youtube.com/watch?v=%@";
static NSString* const dailymotionURL = @"https://www.dailymotion.com/embed/video/%@";

static NSString* const userAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/42.0.2311.90 Safari/537.36";

static NSString* const ytDummySignature = @"BC46474764CD5E86EBFECD43C5692A50528C66A2F45.A3A45BF375942288144D567BC990BD0A09483A1111";

@interface ExtractVideoURLManager()
{
    JSContext *_jsContext;
}
@end

@implementation ExtractVideoURLManager

- (id)init {
    if (self = [super init]) {
        _jsContext = [JSContext new];
    }
    return self;
}

- (void)youtube:(NSString *)vid handler:(ExtractURLHandler)handler {
    
    __weak typeof(self)weakSelf = self;
    
    NSString *urlString = [NSString stringWithFormat:youtubeURL, vid];
    
    //Fetching
    [self fetchSource:[NSURL URLWithString:urlString] responseHandler:^(NSData *data, NSError *error){
        
        //Error
        if (error) {
            handler(nil, error);
            return;
        }
        
        //Extract Info
        id infoObj = [weakSelf yt_ExtractInfo:data];
        
        //Error
        if (!infoObj) {
            handler(nil, [NSError errorWithDomain:@"" code:400 userInfo:nil]);
            return;
        }
        
        //PlayerJS URL
        NSString *playerJS_URLString = [weakSelf nullToString:[infoObj valueForKeyPath:@"config.assets.js"]];
        playerJS_URLString = [NSString stringWithFormat:@"http:%@", playerJS_URLString];
        
        //Fetching
        [weakSelf fetchSource:[NSURL URLWithString:playerJS_URLString] responseHandler:^(NSData *data2, NSError *error2){
            
            //Error
            if (error2) {
                handler(nil, error2);
                return;
            }
            
            NSString *decryptionFuncName = [weakSelf yt_ExtractDecryptionFuncName:data2];
            
            //Error
            if (!decryptionFuncName) {
                handler(nil, [NSError errorWithDomain:@"" code:400 userInfo:nil]);
                return;
            }
            
            
            NSString *decryptionFunc = [weakSelf yt_ExtractDecryptionFunc:data2 funcName:decryptionFuncName];
            
            //Error
            if (!decryptionFunc) {
                handler(nil, [NSError errorWithDomain:@"" code:400 userInfo:nil]);
                return;
            }
            
            [_jsContext evaluateScript:decryptionFunc];
            
            
            NSString *decryptionFuncProperty = [weakSelf yt_ValidateDecryptionFunc:data2 funcName:decryptionFuncName];
            
            //Error
            if (!decryptionFuncProperty) {
                handler(nil, [NSError errorWithDomain:@"" code:400 userInfo:nil]);
                return;
            }
            
            [_jsContext evaluateScript:decryptionFuncProperty];
            
            
            handler([weakSelf yt_CreateURLs:infoObj funcName:decryptionFuncName], nil);
            return;
        }];
        
    }];

}

- (void)dailymotion:(NSString *)vid handler:(ExtractURLHandler)handler {
    __weak typeof(self)weakSelf = self;
    
    NSString *urlString = [NSString stringWithFormat:dailymotionURL, vid];
    
    //Fetching
    [self fetchSource:[NSURL URLWithString:urlString] responseHandler:^(NSData *data, NSError *error){
       
        //Error
        if (error) {
            handler(nil, error);
            return;
        }
        
        //Extract Info
        id infoObj = [self dm_ExtractInfo:data];
        
        //Error
        if (!infoObj) {
            handler(nil, [NSError errorWithDomain:@"" code:400 userInfo:nil]);
            return;
        }
        
        handler([weakSelf dm_CreateURLs:infoObj], nil);
        return;
    }];
    
}


/////////////////////////////////////////////
// Youtube
/////////////////////////////////////////////

// 動画情報を取得
- (id)yt_ExtractInfo:(NSData *)data {
    NSString *regPtn = @"<script>(.*);ytplayer.load";
    
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:regPtn
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:NULL];
    NSTextCheckingResult *result = [reg firstMatchInString:str
                                                   options:(NSMatchingOptions)0
                                                     range:NSMakeRange(0, str.length)];
    NSString *infoObjStr = (result.numberOfRanges > 1) ? [str substringWithRange:[result rangeAtIndex:1]] : nil;
    if (!infoObjStr) {
        return nil;
    }
    
    [_jsContext evaluateScript:infoObjStr];
    JSValue *infoObjValue = _jsContext[@"ytplayer"];
    id infoObj = [infoObjValue toObject];
    
    return infoObj;
}

// 復号化する関数名を取得
- (NSString *)yt_ExtractDecryptionFuncName:(NSData *)data {
    NSString *regPtn = @"set\\([\"']signature[\"']\\s*,\\s*(.*)\\((.*)\\)\\)";
    
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:regPtn
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:NULL];
    NSTextCheckingResult *result = [reg firstMatchInString:str
                                                   options:(NSMatchingOptions)0
                                                     range:NSMakeRange(0, str.length)];
    NSString *funcName = (result.numberOfRanges > 1) ? [str substringWithRange:[result rangeAtIndex:1]] : nil;
    return funcName;
}

// 復号化する関数文字列を取得
- (NSString *)yt_ExtractDecryptionFunc:(NSData *)data funcName:(NSString *)funcName {
    NSString *regPtn = @"function %@\\((.*)\\)\\s*\\{(.*)\\};";
    
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSString *regStr = [NSString stringWithFormat:regPtn, funcName];
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:regStr
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:NULL];
    NSTextCheckingResult *result = [reg firstMatchInString:str
                                                   options:(NSMatchingOptions)0
                                                     range:NSMakeRange(0, str.length)];
    NSString *funcStr = (result.numberOfRanges > 1) ? [str substringWithRange:[result rangeAtIndex:0]] : nil;
    return funcStr;
}

// 復号化する関数を有効にする
- (NSString *)yt_ValidateDecryptionFunc:(NSData *)data funcName:(NSString *)funcName {
    [_jsContext evaluateScript:[NSString stringWithFormat:@"%@('%@')", funcName, ytDummySignature]];
    
    NSString *exception = [[_jsContext exception] toString];
    
    
    // 関数内で使用されているプロパティも有効にする
    NSString *funcName2 = [exception stringByReplacingOccurrencesOfString:@"ReferenceError: Can't find variable: " withString:@""];
    
    NSString *regPtn = @"var %@\\s*=\\s*\\{(.*)\\};";
    NSString *regStr = [NSString stringWithFormat:regPtn, funcName2];
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:regStr
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:NULL];
    
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSTextCheckingResult *result = [reg firstMatchInString:str
                                                   options:(NSMatchingOptions)0
                                                     range:NSMakeRange(0, str.length)];
    NSString *varStr = (result.numberOfRanges > 1) ? [str substringWithRange:[result rangeAtIndex:0]] : nil;
    return varStr;
}

// URLを作成する
- (NSDictionary *)yt_CreateURLs:(id)infoObj funcName:(NSString *)funcName {
    
    NSMutableDictionary *urls = [NSMutableDictionary dictionary];
    
    NSString *stream_map = [self nullToString:[infoObj valueForKeyPath:@"config.args.url_encoded_fmt_stream_map"]];
    NSArray *stream_map_ary = [stream_map componentsSeparatedByString:@","];
    
    for (NSString *stream in stream_map_ary) {
        NSString *itag = @"";
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        for (NSString *q in [stream componentsSeparatedByString:@"&"]) {
            NSArray *q_ary = [q componentsSeparatedByString:@"="];
            
            if ([q_ary[0] isEqualToString:@"itag"]) {
                itag = q_ary[1];
            }
            
            if ([q_ary[0] isEqualToString:@"url"] || [q_ary[0] isEqualToString:@"type"]) {
                dic[q_ary[0]] = [q_ary[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            } else {
                dic[q_ary[0]] = q_ary[1];
            }
        }
        if (dic[@"s"] != nil) {
            NSString *decrypted_s = [[_jsContext evaluateScript:[NSString stringWithFormat:@"%@('%@')", funcName, dic[@"s"]]] toString];
            dic[@"url"] = [dic[@"url"] stringByAppendingFormat:@"&signature=%@", decrypted_s];
        }
        urls[itag] = dic;
    }

    return [NSDictionary dictionaryWithDictionary:urls];
}

/////////////////////////////////////////////
// Dailymotion
/////////////////////////////////////////////

// 動画情報を取得
- (id)dm_ExtractInfo:(NSData *)data {
    NSString *regPtn = @"var info\\s*=\\s*\\{(.*)\\}";
    
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:regPtn
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:NULL];
    NSTextCheckingResult *result = [reg firstMatchInString:str
                                                   options:(NSMatchingOptions)0
                                                     range:NSMakeRange(0, str.length)];
    NSString *infoObjStr = (result.numberOfRanges > 1) ? [str substringWithRange:[result rangeAtIndex:0]] : nil;
    if (!infoObjStr) {
        return nil;
    }
    
    [_jsContext evaluateScript:infoObjStr];
    JSValue *infoObjValue = _jsContext[@"info"];
    id infoObj = [infoObjValue toObject];
    
    return infoObj;
}

// URLを作成する
- (NSDictionary *)dm_CreateURLs:(id)infoObj {
    NSMutableDictionary *urls = [NSMutableDictionary dictionary];
    urls[@"stream_h264_hd1080_url"] = [self nullToString:[infoObj objectForKey:@"stream_h264_hd1080_url"]];
    urls[@"stream_h264_hd_url"] = [self nullToString:[infoObj objectForKey:@"stream_h264_hd_url"]];
    urls[@"stream_h264_hq_url"] = [self nullToString:[infoObj objectForKey:@"stream_h264_hq_url"]];
    urls[@"stream_h264_ld_url"] = [self nullToString:[infoObj objectForKey:@"stream_h264_ld_url"]];
    urls[@"stream_h264_url"] = [self nullToString:[infoObj objectForKey:@"stream_h264_url"]];
    urls[@"stream_hls_url"] = [self nullToString:[infoObj objectForKey:@"stream_hls_url"]];
    
    return [NSDictionary dictionaryWithDictionary:urls];
}

/////////////////////////////////////////////
// 共通
/////////////////////////////////////////////

- (void)fetchSource:(NSURL *)url responseHandler:(FetchSourceResponceHandler)handler {
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:userAgent forHTTPHeaderField:@"User-Agent"];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionTask *task = [session dataTaskWithRequest:request
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error){
                                            if (handler) {
                                                handler(data, error);
                                            }
                                        }];
    [task resume];
}
- (NSString *)nullToString:(NSString *)data {
    return (![data isEqual:[NSNull null]] ? data : @"");
}
