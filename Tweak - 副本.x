#import <substrate.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static NSInteger todayReplies = 0;
static NSInteger scriptIndex = 0;
static NSDate *workStart = nil;
static BOOL isResting = NO;

static NSArray *intentKeywords;
static NSArray *replyTexts;

%ctor {
    intentKeywords = @[@"how much", @"where to buy", @"i want", @"dm me", @"send link", @"price"];
    replyTexts = @[
        @"More styles and prices are on my profile, check it out!",
        @"Tap my profile for real photos and order info~",
        @"Check my profile for available colors and sizes!",
        @"All details are posted on my profile, go look!"
    ];
    workStart = [NSDate date];
    NSLog(@"[TikTokCommentBot] v6.1 loaded");
}

// 拦截评论点击事件
%hook UIApplication
- (BOOL)sendAction:(SEL)action to:(id)to from:(id)from forEvent:(UIEvent *)event {
    // 每日上限800条
    if (todayReplies >= 800) return %orig;
    
    // 工作10分钟休息5分钟
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:workStart];
    if (elapsed >= 600) {
        if (!isResting) {
            isResting = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5*60*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                isResting = NO;
                workStart = [NSDate date];
            });
        }
        return %orig;
    }
    
    // 识别屏幕上的评论文字
    NSString *screenText = [[UIScreen mainScreen] description];
    BOOL isIntent = NO;
    for (NSString *word in intentKeywords) {
        if ([screenText containsString:word]) {
            isIntent = YES;
            break;
        }
    }
    
    if (isIntent) {
        // 15-45秒随机延迟
        NSInteger delay = 15 + arc4random_uniform(30);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSString *reply = replyTexts[scriptIndex];
            scriptIndex = (scriptIndex + 1) % [replyTexts count];
            todayReplies++;
            NSLog(@"[TikTokCommentBot] Replied: %@", reply);
        });
    }
    
    return %orig;
}
%end
