// 摸鱼书摊 License 模块
//
// 设计要点：
//   - 3 天试用，安装时间锚定到 *机器码*（IOPlatformUUID）
//   - 安装时间 + 激活信息双写：本地文件 + macOS Keychain
//     任意一处幸存即视为已装/已激活；阻止"删 Application Support 重装重置"
//   - 激活码：20 字节 (12 payload + 8 HMAC)，base32 编码 32 字符
//     HMAC 入参包含本机 UUID → 同一个 key 在别的 Mac 验不过
//   - 时钟回拨防御：每次启动记 last_seen，回拨 > 1 天判试用过期
//
// 详细规格见 /Users/apple/Desktop/摸鱼书摊/secrets.txt

#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MSLicenseState) {
    MSLicenseStateTrialActive,    // 试用中
    MSLicenseStateTrialExpired,   // 试用过期，需激活
    MSLicenseStateActivated,      // 已永久激活
};

typedef NS_ENUM(NSInteger, MSActivationError) {
    MSActivationErrorNone = 0,
    MSActivationErrorFormat,      // 格式不对
    MSActivationErrorSignature,   // 签名不匹配（错 key / 别机器的 key）
    MSActivationErrorAlreadyUsed, // 本机已用过
};

@interface License : NSObject

// 单例
+ (instancetype)shared;

// 当前许可状态（首次调用会触发 install 时间锚定）
- (MSLicenseState)currentState;

// 试用剩余秒数（已激活返回 INT_MAX；过期返回 0）
- (NSTimeInterval)trialRemainingSeconds;

// 本机机器码（IOPlatformUUID），供激活页面显示给用户复制
- (NSString*)machineUUID;

// 激活；返回错误码（None = 成功）
- (MSActivationError)activateWithKey:(NSString*)key;

// 重置（仅给后门 reset 入口用）
- (void)resetAllState;

// 是否允许阅读（= 试用未过期 || 已激活）
- (BOOL)canRead;
@end
