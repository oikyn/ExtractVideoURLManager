# ExtractVideoURLManager
Extract Video URL of Youtube, Dailymotion

iOS7 ~ Objective-C

## How to

```
ExtractVideoURLManager *extracter = [ExtractVideoURLManager new];
    
//////////////////////////////////////
// Example
//////////////////////////////////////

//Youtube
NSString *vid = @"dFf4AgBNR1E";
[extracter youtube:vid handler:^(NSDictionary *urls, NSError *error){
    if (error) {
        NSLog(@"Youtube Error...");
        return;
    }
    
    NSLog(@"Youtube URLs = %@", urls);
}];


//Dailymotion
NSString *vid2 = @"x2mgxvh";
[extracter dailymotion:vid2 handler:^(NSDictionary *urls, NSError *error){
    if (error) {
        NSLog(@"Dailymotion Error...");
        return;
    }
    
    NSLog(@"Dailymotion URLs = %@", urls);
}];
```
