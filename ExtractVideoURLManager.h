#import <Foundation/Foundation.h>

typedef void (^ExtractURLHandler)(NSDictionary *urls, NSError *error);

@interface ExtractVideoURLManager : NSObject

- (void)youtube:(NSString *)vid handler:(ExtractURLHandler)handler;
- (void)dailymotion:(NSString *)vid handler:(ExtractURLHandler)handler;

@end
