#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <substrate.h>

// 配置键名
static NSString *const kIsRunning = @"isRunning";
static NSString *const kScanCommentCount = @"scanCommentCount";
static NSString *const kStrongSignalOnly = @"strongSignalOnly";
static NSString *const kReplyEnabled = @"replyEnabled";
static NSString *const kReplyDelayMin = @"replyDelayMin";
static NSString *const kReplyDelayMax = @"replyDelayMax";
static NSString *const kWorkDuration = @"workDuration";
static NSString *const kRestDuration = @"restDuration";
static NSString *const kDailyMaxReplies = @"dailyMaxReplies";
static NSString *const kRiskDetectionEnabled = @"riskDetectionEnabled";

// 全局变量
static NSMutableDictionary *config = nil;
static NSMutableSet *repliedUsers = nil;
static NSUInteger todayReplyCount = 0;
static NSDate *workStartTime = nil;
static BOOL isResting = NO;
static BOOL isProcessing = NO;

// 强信号词库 (118个)
static NSArray *strongKeywords = nil;
// 弱信号词库
static NSArray *weakKeywords = nil;
// 语境词库
static NSArray *contextKeywords = nil;
// 回复话术
static NSArray *replyTemplates = nil;
static NSUInteger currentTemplateIndex = 0;

// 加载配置
void loadConfig() {
    NSString *configPath = @"/var/jb/var/mobile/Library/Preferences/com.tiktokcommentbot.config.plist";
    config = [NSMutableDictionary dictionaryWithContentsOfFile:configPath];
    if (!config) {
        config = [NSMutableDictionary dictionary];
    }
    
    // 默认值
    if (!config[kIsRunning]) config[kIsRunning] = @NO;
    if (!config[kScanCommentCount]) config[kScanCommentCount] = @100;
    if (!config[kStrongSignalOnly]) config[kStrongSignalOnly] = @YES;
    if (!config[kReplyEnabled]) config[kReplyEnabled] = @YES;
    if (!config[kReplyDelayMin]) config[kReplyDelayMin] = @15;
    if (!config[kReplyDelayMax]) config[kReplyDelayMax] = @45;
    if (!config[kWorkDuration]) config[kWorkDuration] = @10;
    if (!config[kRestDuration]) config[kRestDuration] = @5;
    if (!config[kDailyMaxReplies]) config[kDailyMaxReplies] = @800;
    if (!config[kRiskDetectionEnabled]) config[kRiskDetectionEnabled] = @YES;
    
    NSLog(@"[TikTokCommentBot] Config loaded: %@", config);
}

// 加载词库
void loadKeywords() {
    NSString *kwPath = @"/var/jb/var/mobile/Library/Preferences/com.tiktokcommentbot.keywords.plist";
    NSDictionary *kwDict = [NSDictionary dictionaryWithContentsOfFile:kwPath];
    if (kwDict) {
        strongKeywords = kwDict[@"strongKeywords"];
        weakKeywords = kwDict[@"weakKeywords"];
        contextKeywords = kwDict[@"contextKeywords"];
    }
    NSLog(@"[TikTokCommentBot] Keywords loaded: %lu strong, %lu weak, %lu context", 
          (unsigned long)strongKeywords.count, (unsigned long)weakKeywords.count, (unsigned long)contextKeywords.count);
}

// 加载回复话术
void loadTemplates() {
    NSString *tplPath = @"/var/jb/var/mobile/Library/Preferences/com.tiktokcommentbot.templates.plist";
    replyTemplates = [NSArray arrayWithContentsOfFile:tplPath];
    NSLog(@"[TikTokCommentBot] Templates loaded: %lu", (unsigned long)replyTemplates.count);
}

// 加载已回复用户记录
void loadRepliedUsers() {
    NSString *dataPath = @"/var/jb/var/mobile/Library/Preferences/com.tiktokcommentbot.data.plist";
    NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:dataPath];
    if (data) {
        NSString *today = [NSDateFormatter localizedStringFromDate:[NSDate date] 
                                                         dateStyle:NSDateFormatterShortStyle 
                                                         timeStyle:NSDateFormatterNoStyle];
        repliedUsers = [NSMutableSet setWithArray:data[today] ?: @[]];
        todayReplyCount = [data[@"todayReplyCount"] unsignedIntegerValue];
    } else {
        repliedUsers = [NSMutableSet set];
        todayReplyCount = 0;
    }
}

// 保存已回复用户记录
void saveRepliedUsers() {
    NSString *dataPath = @"/var/jb/var/mobile/Library/Preferences/com.tiktokcommentbot.data.plist";
    NSString *today = [NSDateFormatter localizedStringFromDate:[NSDate date] 
                                                     dateStyle:NSDateFormatterShortStyle 
                                                     timeStyle:NSDateFormatterNoStyle];
    NSDictionary *data = @{
        today: [repliedUsers allObjects],
        @"todayReplyCount": @(todayReplyCount),
        @"lastReplyTime": [NSDate date]
    };
    [data writeToFile:dataPath atomically:YES];
}

// 匹配购买意向
BOOL matchBuyIntent(NSString *commentText) {
    NSString *lowerText = [commentText lowercaseString];
    
    // 强信号匹配
    for (NSString *keyword in strongKeywords) {
        if ([lowerText containsString:[keyword lowercaseString]]) {
            NSLog(@"[TikTokCommentBot] Matched strong keyword: %@", keyword);
            return YES;
        }
    }
    
    // 弱信号+语境匹配
    if (![config[kStrongSignalOnly] boolValue]) {
        BOOL hasWeak = NO;
        BOOL hasContext = NO;
        for (NSString *keyword in weakKeywords) {
            if ([lowerText containsString:[keyword lowercaseString]]) {
                hasWeak = YES;
                break;
            }
        }
        for (NSString *keyword in contextKeywords) {
            if ([lowerText containsString:[keyword lowercaseString]]) {
                hasContext = YES;
                break;
            }
        }
        if (hasWeak && hasContext) {
            NSLog(@"[TikTokCommentBot] Matched weak+context");
            return YES;
        }
    }
    
    return NO;
}

// 获取下一条回复话术
NSString *getNextReplyTemplate() {
    if (replyTemplates.count == 0) return nil;
    NSString *tpl = replyTemplates[currentTemplateIndex];
    currentTemplateIndex = (currentTemplateIndex + 1) % replyTemplates.count;
    return tpl;
}

// 随机延迟
NSTimeInterval randomDelay() {
    NSInteger min = [config[kReplyDelayMin] integerValue];
    NSInteger max = [config[kReplyDelayMax] integerValue];
    return min + arc4random_uniform(max - min + 1);
}

// 检查工作休息状态
void checkWorkRestStatus() {
    if (!workStartTime) {
        workStartTime = [NSDate date];
        return;
    }
    
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:workStartTime];
    NSTimeInterval workDuration = [config[kWorkDuration] doubleValue] * 60;
    NSTimeInterval restDuration = [config[kRestDuration] doubleValue] * 60;
    
    if (isResting) {
        NSTimeInterval restElapsed = [[NSDate date] timeIntervalSinceDate:workStartTime] - workDuration;
        if (restElapsed >= restDuration) {
            isResting = NO;
            workStartTime = [NSDate date];
            NSLog(@"[TikTokCommentBot] Rest ended, resuming work");
        }
    } else {
        if (elapsed >= workDuration) {
            isResting = YES;
            NSLog(@"[TikTokCommentBot] Work ended, starting rest for %.0f minutes", restDuration / 60);
        }
    }
}

// 处理评论列表
void processComments(NSArray *comments) {
    if (![config[kIsRunning] boolValue]) return;
    if (![config[kReplyEnabled] boolValue]) return;
    if (isProcessing) return;
    
    // 检查每日上限
    if (todayReplyCount >= [config[kDailyMaxReplies] unsignedIntegerValue]) {
        NSLog(@"[TikTokCommentBot] Daily limit reached: %lu", (unsigned long)todayReplyCount);
        return;
    }
    
    // 检查工作休息
    checkWorkRestStatus();
    if (isResting) return;
    
    isProcessing = YES;
    
    NSInteger scanCount = [config[kScanCommentCount] integerValue];
    NSInteger processed = 0;
    
    for (NSDictionary *comment in comments) {
        if (processed >= scanCount) break;
        if (todayReplyCount >= [config[kDailyMaxReplies] unsignedIntegerValue]) break;
        
        NSString *commentId = comment[@"comment_id"];
        NSString *commentText = comment[@"text"];
        NSString *userId = comment[@"user"][@"uid"];
        
        if (!commentText || !userId) continue;
        
        // 跳过已回复
        if ([repliedUsers containsObject:userId]) continue;
        
        // 匹配意向
        if (matchBuyIntent(commentText)) {
            NSLog(@"[TikTokCommentBot] Found potential customer: %@, comment: %@", userId, commentText);
            
            // 延迟回复
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(randomDelay() * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSString *replyText = getNextReplyTemplate();
                if (replyText) {
                    NSLog(@"[TikTokCommentBot] Replying to %@ with: %@", userId, replyText);
                    
                    // 发送回复 (调用TikTok内部API)
                    // TODO: 实现真实的评论回复API调用
                    
                    // 记录已回复
                    [repliedUsers addObject:userId];
                    todayReplyCount++;
                    saveRepliedUsers();
                }
            });
            
            processed++;
        }
    }
    
    isProcessing = NO;
}

// Hook TikTok评论列表加载
%hook TTKCommentListViewModel

- (void)didFinishLoadCommentsWithError:(NSError *)error {
    %orig;
    
    if (error) return;
    
    // 获取评论列表
    NSArray *comments = [self valueForKey:@"comments"];
    if (comments && comments.count > 0) {
        NSLog(@"[TikTokCommentBot] Loaded %lu comments", (unsigned long)comments.count);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            processComments(comments);
        });
    }
}

%end

// 初始化
%ctor {
    @autoreleasepool {
        NSLog(@"[TikTokCommentBot] Loading...");
        
        loadConfig();
        loadKeywords();
        loadTemplates();
        loadRepliedUsers();
        
        // 注册配置变化通知
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                        NULL, 
                                        (CFNotificationCallback)loadConfig, 
                                        CFSTR("com.apple.PreferencesChanged"), 
                                        NULL, 
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        
        NSLog(@"[TikTokCommentBot] Loaded successfully!");
    }
}
