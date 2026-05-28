#import "License.h"

#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>
#import <IOKit/IOKitLib.h>

// =============================================================
//                  SECRET 与常量
// =============================================================

// 共享密钥（与安卓 KeyGen 端 BuildConfig 完全一致）
// 96 hex chars = 48 bytes
static NSString* const kSharedSecretHex =
    @"cd973ca17ec1b9f40168081549951711816b9757386ee62a7f7a9600eab6c66387c2b78c63afb86a48d79eb67b8ecee4";

// 试用 3 天
static const NSTimeInterval kTrialSeconds = 3 * 24 * 60 * 60;

// Keychain service id
static NSString* const kKeychainService = @"com.weirdomeng.MoyuShutan";
static NSString* const kKeychainInstall  = @"install";
static NSString* const kKeychainActivated = @"activated";

// =============================================================
//                  小工具
// =============================================================

static NSData* hexToData(NSString* hex) {
    NSMutableData* d = [NSMutableData dataWithCapacity:hex.length/2];
    for (NSUInteger i = 0; i < hex.length; i += 2) {
        NSString* byte = [hex substringWithRange:NSMakeRange(i, 2)];
        uint8_t b = (uint8_t)strtoul(byte.UTF8String, NULL, 16);
        [d appendBytes:&b length:1];
    }
    return d;
}

static NSData* sharedSecret(void) {
    static NSData* s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = hexToData(kSharedSecretHex); });
    return s;
}

// HMAC-SHA256(key, data) → 32 bytes
static NSData* hmacSHA256(NSData* key, NSData* data) {
    uint8_t out[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, out);
    return [NSData dataWithBytes:out length:CC_SHA256_DIGEST_LENGTH];
}

static NSString* sha256Hex(NSString* s) {
    NSData* d = [s dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(d.bytes, (CC_LONG)d.length, out);
    NSMutableString* hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) [hex appendFormat:@"%02x", out[i]];
    return hex;
}

// =============================================================
//                  RFC4648 Base32 解码
// =============================================================
//
// 字母表：A-Z 2-7 不区分大小写
// 我们 key 是 20 字节 = 32 base32 chars，固定长度，没有 padding
static NSData* base32Decode(NSString* str) {
    static int8_t map[256];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        memset(map, -1, sizeof(map));
        const char* abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
        for (int i = 0; i < 32; ++i) {
            map[(uint8_t)abc[i]] = (int8_t)i;
            map[(uint8_t)tolower(abc[i])] = (int8_t)i;
        }
    });
    NSMutableData* out = [NSMutableData data];
    int buffer = 0, bits = 0;
    for (NSUInteger i = 0; i < str.length; ++i) {
        unichar c = [str characterAtIndex:i];
        if (c >= 256) return nil;
        int8_t v = map[c];
        if (v < 0) continue;       // 忽略 - / 空格等
        buffer = (buffer << 5) | v;
        bits += 5;
        if (bits >= 8) {
            bits -= 8;
            uint8_t b = (uint8_t)((buffer >> bits) & 0xff);
            [out appendBytes:&b length:1];
        }
    }
    return out;
}

// =============================================================
//                  机器 UUID
// =============================================================

static NSString* readMachineUUID(void) {
    io_registry_entry_t r = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/");
    if (!r) return @"";
    CFStringRef u = (CFStringRef)IORegistryEntryCreateCFProperty(
        r, CFSTR("IOPlatformUUID"), kCFAllocatorDefault, 0);
    IOObjectRelease(r);
    return CFBridgingRelease(u) ?: @"";
}

// =============================================================
//                  Keychain 读写
// =============================================================

static BOOL keychainSet(NSString* account, NSData* data) {
    NSDictionary* query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: kKeychainService,
        (id)kSecAttrAccount: account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
    NSMutableDictionary* add = [query mutableCopy];
    add[(id)kSecValueData] = data;
    add[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlock;
    OSStatus s = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    return s == errSecSuccess;
}

static NSData* keychainGet(NSString* account) {
    NSDictionary* query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: kKeychainService,
        (id)kSecAttrAccount: account,
        (id)kSecReturnData: @YES,
        (id)kSecMatchLimit: (id)kSecMatchLimitOne,
    };
    CFTypeRef out = NULL;
    OSStatus s = SecItemCopyMatching((__bridge CFDictionaryRef)query, &out);
    if (s != errSecSuccess) return nil;
    return CFBridgingRelease(out);
}

static void keychainDelete(NSString* account) {
    NSDictionary* query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: kKeychainService,
        (id)kSecAttrAccount: account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);
}

// =============================================================
//                  License 文件路径
// =============================================================

static NSString* licenseDir(void) {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* p = [paths.firstObject stringByAppendingPathComponent:
                   @"MoyuShutan/license"];
    [NSFileManager.defaultManager createDirectoryAtPath:p
                            withIntermediateDirectories:YES
                                             attributes:nil error:nil];
    return p;
}

static NSString* installFilePath(void) {
    return [licenseDir() stringByAppendingPathComponent:@"install.dat"];
}
static NSString* activatedFilePath(void) {
    return [licenseDir() stringByAppendingPathComponent:@"activated.dat"];
}
static NSString* usedKeysFilePath(void) {
    return [licenseDir() stringByAppendingPathComponent:@"used_keys.txt"];
}

// =============================================================
//                  install record
// =============================================================
//   16 字节: install_time(BE u32, 4) + last_seen(BE u32, 4) + HMAC(8)
//   HMAC = HMAC-SHA256(SECRET, machine_uuid || install_time || last_seen)[:8]
//
// 写两份：本地文件 + Keychain
// 读时：先 keychain，回退到文件；任一存在并验签通过即视为已装

static void encodeBEUint32(uint8_t* buf, uint32_t v) {
    buf[0] = (v >> 24) & 0xff;
    buf[1] = (v >> 16) & 0xff;
    buf[2] = (v >>  8) & 0xff;
    buf[3] =  v        & 0xff;
}
static uint32_t decodeBEUint32(const uint8_t* buf) {
    return ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) |
           ((uint32_t)buf[2] <<  8) |  (uint32_t)buf[3];
}

static NSData* encodeInstallRecord(uint32_t install, uint32_t lastSeen,
                                    NSString* uuid) {
    uint8_t body[8];
    encodeBEUint32(body,     install);
    encodeBEUint32(body + 4, lastSeen);
    NSMutableData* signedData = [NSMutableData dataWithBytes:body length:8];
    [signedData appendData:[uuid dataUsingEncoding:NSUTF8StringEncoding]];
    NSData* mac = hmacSHA256(sharedSecret(), signedData);
    NSMutableData* rec = [NSMutableData dataWithBytes:body length:8];
    [rec appendData:[mac subdataWithRange:NSMakeRange(0, 8)]];
    return rec;  // 16 bytes
}

// 返回 (install, lastSeen) 或 nil
static NSDictionary* decodeInstallRecord(NSData* rec, NSString* uuid) {
    if (rec.length != 16) return nil;
    const uint8_t* p = (const uint8_t*)rec.bytes;
    uint32_t install = decodeBEUint32(p);
    uint32_t lastSeen = decodeBEUint32(p + 4);
    NSMutableData* signedData = [NSMutableData dataWithBytes:p length:8];
    [signedData appendData:[uuid dataUsingEncoding:NSUTF8StringEncoding]];
    NSData* expect = [hmacSHA256(sharedSecret(), signedData)
                       subdataWithRange:NSMakeRange(0, 8)];
    NSData* got = [rec subdataWithRange:NSMakeRange(8, 8)];
    if (![expect isEqualToData:got]) return nil;
    return @{@"install": @(install), @"lastSeen": @(lastSeen)};
}

// =============================================================
//                  activated record
// =============================================================
//   72 字节: SHA256(key_str)(32) + activateTime(4) + HMAC(8) ... 等等让我用另一种
//   实际：32(key_hash) + 4(activate_time) + 8(HMAC)= 44 字节
//   HMAC = HMAC-SHA256(SECRET, key_hash || activate_time || uuid)[:8]

static NSData* encodeActivatedRecord(NSString* keyStr, uint32_t actTime,
                                      NSString* uuid) {
    NSData* keyHash = [sha256Hex(keyStr) dataUsingEncoding:NSUTF8StringEncoding];
    // keep keyHash as hex string bytes for traceability (64 chars)
    uint8_t timeBuf[4];
    encodeBEUint32(timeBuf, actTime);
    NSMutableData* signed_ = [NSMutableData data];
    [signed_ appendData:keyHash];
    [signed_ appendBytes:timeBuf length:4];
    [signed_ appendData:[uuid dataUsingEncoding:NSUTF8StringEncoding]];
    NSData* mac = hmacSHA256(sharedSecret(), signed_);

    NSMutableData* rec = [NSMutableData data];
    [rec appendData:keyHash];
    [rec appendBytes:timeBuf length:4];
    [rec appendData:[mac subdataWithRange:NSMakeRange(0, 8)]];
    return rec;  // 64+4+8 = 76 bytes
}

static BOOL verifyActivatedRecord(NSData* rec, NSString* uuid) {
    if (rec.length != 76) return NO;
    NSData* keyHash = [rec subdataWithRange:NSMakeRange(0, 64)];
    NSData* timeData = [rec subdataWithRange:NSMakeRange(64, 4)];
    NSData* mac = [rec subdataWithRange:NSMakeRange(68, 8)];
    NSMutableData* signed_ = [NSMutableData data];
    [signed_ appendData:keyHash];
    [signed_ appendData:timeData];
    [signed_ appendData:[uuid dataUsingEncoding:NSUTF8StringEncoding]];
    NSData* expect = [hmacSHA256(sharedSecret(), signed_)
                       subdataWithRange:NSMakeRange(0, 8)];
    return [mac isEqualToData:expect];
}

// =============================================================
//                  License 类
// =============================================================

@interface License ()
@property (copy)   NSString*   uuid;
@property (assign) uint32_t    installTime;
@property (assign) uint32_t    lastSeen;
@property (assign) BOOL        activated;
@property (assign) BOOL        tamperedClock;  // 检出时钟回拨
@end

@implementation License

+ (instancetype)shared {
    static License* s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[License alloc] init]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _uuid = readMachineUUID();
        [self loadOrAnchor];
        [self loadActivation];
    }
    return self;
}

- (NSString*)machineUUID { return _uuid; }

// 读 install record。Keychain 优先，本地兜底；都没就视为首装写入。
- (void)loadOrAnchor {
    NSData* rec = keychainGet(kKeychainInstall);
    NSDictionary* parsed = rec ? decodeInstallRecord(rec, _uuid) : nil;
    if (!parsed) {
        rec = [NSData dataWithContentsOfFile:installFilePath()];
        parsed = rec ? decodeInstallRecord(rec, _uuid) : nil;
    }
    uint32_t now = (uint32_t)[NSDate.date timeIntervalSince1970];
    if (parsed) {
        _installTime = [parsed[@"install"] unsignedIntValue];
        _lastSeen    = [parsed[@"lastSeen"] unsignedIntValue];
        // 时钟回拨检测：当前时间 < lastSeen − 1 天 视为被改
        if (_lastSeen > 0 && now + 24*60*60 < _lastSeen) {
            _tamperedClock = YES;
        }
        _lastSeen = (now > _lastSeen) ? now : _lastSeen;
    } else {
        // 首次安装
        _installTime = now;
        _lastSeen = now;
    }
    // 写回（更新 lastSeen）
    NSData* fresh = encodeInstallRecord(_installTime, _lastSeen, _uuid);
    [fresh writeToFile:installFilePath() atomically:YES];
    keychainSet(kKeychainInstall, fresh);
}

- (void)loadActivation {
    _activated = NO;
    NSData* rec = keychainGet(kKeychainActivated);
    if (!rec || !verifyActivatedRecord(rec, _uuid)) {
        rec = [NSData dataWithContentsOfFile:activatedFilePath()];
        if (rec && !verifyActivatedRecord(rec, _uuid)) rec = nil;
    }
    if (rec) _activated = YES;
}

- (MSLicenseState)currentState {
    if (_activated) return MSLicenseStateActivated;
    if (_tamperedClock) return MSLicenseStateTrialExpired;
    NSTimeInterval rem = [self trialRemainingSeconds];
    return rem > 0 ? MSLicenseStateTrialActive : MSLicenseStateTrialExpired;
}

- (NSTimeInterval)trialRemainingSeconds {
    if (_activated) return INT_MAX;
    if (_tamperedClock) return 0;
    NSTimeInterval now = [NSDate.date timeIntervalSince1970];
    NSTimeInterval elapsed = now - (NSTimeInterval)_installTime;
    NSTimeInterval rem = kTrialSeconds - elapsed;
    return rem > 0 ? rem : 0;
}

- (BOOL)canRead {
    MSLicenseState st = [self currentState];
    return st != MSLicenseStateTrialExpired;
}

// =============================================================
//                  激活校验
// =============================================================

- (MSActivationError)activateWithKey:(NSString*)key {
    // 1. 规范化：去 hyphen / 空格 / 大小写
    NSString* clean = [[key componentsSeparatedByCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    clean = [clean stringByReplacingOccurrencesOfString:@"-" withString:@""];
    clean = [clean uppercaseString];
    if (clean.length != 32) return MSActivationErrorFormat;

    NSData* bytes = base32Decode(clean);
    if (bytes.length != 20) return MSActivationErrorFormat;

    const uint8_t* p = (const uint8_t*)bytes.bytes;
    // magic 'M' 'S'
    if (p[0] != 0x4D || p[1] != 0x53) return MSActivationErrorFormat;
    // version
    if (p[2] != 0x01) return MSActivationErrorFormat;

    NSData* payload = [bytes subdataWithRange:NSMakeRange(0, 12)];
    NSData* providedSig = [bytes subdataWithRange:NSMakeRange(12, 8)];

    // expect = HMAC(SECRET, payload || uuid)[:8]
    NSMutableData* macInput = [NSMutableData dataWithData:payload];
    [macInput appendData:[_uuid dataUsingEncoding:NSUTF8StringEncoding]];
    NSData* expectSig = [hmacSHA256(sharedSecret(), macInput)
                         subdataWithRange:NSMakeRange(0, 8)];
    if (![providedSig isEqualToData:expectSig]) return MSActivationErrorSignature;

    // 检查 used_keys
    NSString* keyHashHex = sha256Hex(clean);
    if ([self isKeyHashUsed:keyHashHex]) return MSActivationErrorAlreadyUsed;

    // 通过 → 写激活记录 + 加入 used_keys
    uint32_t now = (uint32_t)[NSDate.date timeIntervalSince1970];
    NSData* rec = encodeActivatedRecord(clean, now, _uuid);
    [rec writeToFile:activatedFilePath() atomically:YES];
    keychainSet(kKeychainActivated, rec);
    [self appendUsedKeyHash:keyHashHex];
    _activated = YES;
    return MSActivationErrorNone;
}

- (BOOL)isKeyHashUsed:(NSString*)hash {
    NSString* content = [NSString stringWithContentsOfFile:usedKeysFilePath()
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    if (content.length == 0) return NO;
    return [content rangeOfString:hash].location != NSNotFound;
}

- (void)appendUsedKeyHash:(NSString*)hash {
    NSString* line = [NSString stringWithFormat:@"%@\n", hash];
    NSFileHandle* fh = [NSFileHandle fileHandleForWritingAtPath:usedKeysFilePath()];
    if (!fh) {
        [line writeToFile:usedKeysFilePath() atomically:YES
                  encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

- (void)resetAllState {
    keychainDelete(kKeychainInstall);
    keychainDelete(kKeychainActivated);
    NSFileManager* fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:installFilePath() error:nil];
    [fm removeItemAtPath:activatedFilePath() error:nil];
    [fm removeItemAtPath:usedKeysFilePath() error:nil];
    _activated = NO;
    _tamperedClock = NO;
    [self loadOrAnchor];  // 重新锚定为"现在"安装
}

@end
