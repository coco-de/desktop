// 파일 기반 macOS 키체인의 ACL·잠금 해제에는 SecKeychain API가 필요하다.
// 암호는 op의 파이프와 login 키체인에서만 읽고, 출력·인자·평문 파일로 내보내지 않는다.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <mach-o/dyld.h>
#import <sys/resource.h>
#import <sys/mman.h>
#import <poll.h>
#import <limits.h>
#import <unistd.h>

static const char *CacheService = "im.cocode.desktop.signing-keychains.v1";
static void wipe(void *buffer, size_t length) {
    volatile unsigned char *bytes = buffer;
    while (length--) *bytes++ = 0;
}
static NSArray<NSString *> *toolPaths(void) {
    return @[@"/usr/bin/codesign", @"/usr/bin/security", @"/usr/bin/productbuild", @"/usr/bin/productsign"];
}

static BOOL check(OSStatus status, NSString *operation) {
    if (status == errSecSuccess) return YES;
    // OSStatus만 출력한다. 호출 인자나 암호를 에러 메시지에 포함하지 않는다.
    fprintf(stderr, "⚠ %s 실패 (OSStatus=%d)\n", operation.UTF8String, (int)status);
    return NO;
}

static NSString *canonical(NSString *path) {
    return path.stringByExpandingTildeInPath.stringByResolvingSymlinksInPath;
}

static SecKeychainRef openKeychain(NSString *path) {
    SecKeychainRef keychain = NULL;
    if (!check(SecKeychainOpen(canonical(path).fileSystemRepresentation, &keychain), @"키체인 열기")) return NULL;
    return keychain;
}

static NSString *loginPath(void) {
    // 기본 키체인이 fastlane_tmp일 수 있다. 암호 캐시는 반드시 login에 한정한다.
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Keychains/login.keychain-db"];
}

static NSString *selfPath(void) {
    char buffer[PATH_MAX];
    uint32_t length = sizeof(buffer);
    return _NSGetExecutablePath(buffer, &length) == 0 ? canonical(@(buffer)) : nil;
}

static BOOL isUnlocked(SecKeychainRef keychain) {
    SecKeychainStatus status = 0;
    return SecKeychainGetStatus(keychain, &status) == errSecSuccess && (status & kSecUnlockStateStatus);
}

static BOOL hasAuthorization(SecACLRef acl, CFStringRef tag) {
    CFArrayRef tags = SecACLCopyAuthorizations(acl);
    BOOL found = tags && CFArrayContainsValue(tags, CFRangeMake(0, CFArrayGetCount(tags)), tag);
    if (tags) CFRelease(tags);
    return found;
}

static NSArray<NSString *> *applicationPaths(CFArrayRef applications) {
    if (!applications) return nil; // NULL은 모든 앱 허용이다. 빈 배열과 구분한다.
    NSMutableArray *paths = [NSMutableArray array];
    for (id application in (__bridge NSArray *)applications) {
        CFDataRef data = NULL;
        if (SecTrustedApplicationCopyData((__bridge SecTrustedApplicationRef)application, &data) != errSecSuccess) return nil;
        const UInt8 *bytes = CFDataGetBytePtr(data);
        CFIndex size = CFDataGetLength(data);
        if (size && bytes[size - 1] == 0) size--;
        NSString *path = [[NSString alloc] initWithBytes:bytes length:(NSUInteger)size encoding:NSUTF8StringEncoding];
        CFRelease(data);
        if (!path) return nil;
        [paths addObject:path];
    }
    return paths;
}

static NSMutableDictionary *partitionDictionary(NSString *description) {
    // SecACLCopyContents는 partition을 쉼표 문자열이 아니라 hex 인코딩 plist로 돌려준다.
    if (!description.length || description.length % 2) return nil;
    NSMutableData *bytes = [NSMutableData dataWithLength:description.length / 2];
    unsigned char *output = bytes.mutableBytes;
    for (NSUInteger index = 0; index < description.length; index += 2) {
        unsigned int value = 0;
        NSString *pair = [description substringWithRange:NSMakeRange(index, 2)];
        if ([pair rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"].invertedSet].location != NSNotFound ||
            sscanf(pair.UTF8String, "%2x", &value) != 1) return nil;
        output[index / 2] = (unsigned char)value;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:bytes options:NSPropertyListMutableContainers format:nil error:nil];
    if (![plist isKindOfClass:NSMutableDictionary.class] || ![plist[@"Partitions"] isKindOfClass:NSArray.class]) return nil;
    for (id value in plist[@"Partitions"]) if (![value isKindOfClass:NSString.class]) return nil;
    return plist;
}

static NSString *partitionDescription(NSDictionary *plist) {
    NSData *bytes = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    NSMutableString *hex = [NSMutableString string];
    const unsigned char *data = bytes.bytes;
    for (NSUInteger index = 0; index < bytes.length; index++) [hex appendFormat:@"%02x", data[index]];
    return hex;
}

static BOOL updateSigningAccess(SecKeychainItemRef item, BOOL apply, NSMutableArray *reports) {
    SecAccessRef access = NULL;
    CFArrayRef aclList = NULL;
    if (!check(SecKeychainItemCopyAccess(item, &access), @"서명 키 ACL 조회")) return NO;
    if (!check(SecAccessCopyACLList(access, &aclList), @"ACL 목록 조회")) { CFRelease(access); return NO; }
    BOOL success = YES, changed = NO, hasSigning = NO, hasPartition = NO;
    NSMutableArray *keyReports = [NSMutableArray array];
    for (id value in (__bridge NSArray *)aclList) {
        SecACLRef acl = (__bridge SecACLRef)value;
        BOOL signing = hasAuthorization(acl, kSecACLAuthorizationSign);
        BOOL partition = hasAuthorization(acl, kSecACLAuthorizationPartitionID);
        if (!signing && !partition) continue;
        CFArrayRef applications = NULL;
        CFStringRef description = NULL;
        SecKeychainPromptSelector prompt = 0;
        if (!check(SecACLCopyContents(acl, &applications, &description, &prompt), @"ACL 내용 조회")) { success = NO; break; }
        if (signing) {
            hasSigning = YES;
            NSArray *existing = applicationPaths(applications);
            NSMutableArray *missing = [NSMutableArray array];
            for (NSString *tool in toolPaths()) if (![existing containsObject:tool]) [missing addObject:tool];
            [keyReports addObject:@{@"type": @"sign", @"applications": existing ?: @[], @"all_applications": @(!applications),
                @"missing_tools": missing, @"requires_password": @((prompt & kSecKeychainPromptRequirePassphase) != 0)}];
            // 기존 전체 허용 ACL을 더 넓히지 않는다. 사람이 제한한 뒤 재시도하게 한다.
            if (apply && !applications) {
                fprintf(stderr, "⚠ 전체 앱 허용 서명 ACL이 있습니다. 키체인 접근에서 신뢰 앱을 제한한 뒤 다시 실행하세요.\n");
                success = NO;
            } else if (apply && (missing.count || (prompt & kSecKeychainPromptRequirePassphase))) {
                CFMutableArrayRef updated = CFArrayCreateMutableCopy(NULL, 0, applications);
                for (NSString *tool in missing) {
                    SecTrustedApplicationRef trusted = NULL;
                    if (!check(SecTrustedApplicationCreateFromPath(tool.fileSystemRepresentation, &trusted), @"서명 도구 신뢰 등록")) { success = NO; break; }
                    CFArrayAppendValue(updated, trusted);
                    CFRelease(trusted);
                }
                if (success) success = check(SecACLSetContents(acl, updated, description, prompt & ~kSecKeychainPromptRequirePassphase), @"서명 ACL 보완");
                CFRelease(updated);
                changed = YES;
            }
        }
        if (partition) {
            hasPartition = YES;
            NSMutableDictionary *plist = partitionDictionary((__bridge NSString *)description);
            if (!plist) {
                fprintf(stderr, "⚠ partition plist를 해석할 수 없어 기존 접근 권한을 유지합니다.\n");
                if (applications) CFRelease(applications);
                if (description) CFRelease(description);
                success = NO; break;
            }
            NSArray *original = [plist[@"Partitions"] copy];
            NSMutableArray *allowed = [original mutableCopy];
            NSMutableArray *missing = [NSMutableArray array];
            for (NSString *required in @[@"apple-tool:", @"apple:", @"codesign:"]) {
                if (![allowed containsObject:required]) { [allowed addObject:required]; [missing addObject:required]; }
            }
            [keyReports addObject:@{@"type": @"partition", @"partitions": original, @"missing_partitions": missing}];
            if (apply && missing.count) {
                // teamid:·cdhash: 등 기존 항목의 순서와 값을 유지하고 필요한 항목만 추가한다.
                plist[@"Partitions"] = allowed;
                success = success && check(SecACLSetContents(acl, applications, (__bridge CFStringRef)partitionDescription(plist), prompt), @"partition 보완");
                changed = YES;
            }
        }
        if (applications) CFRelease(applications);
        if (description) CFRelease(description);
        if (!success) break;
    }
    if (success && apply && hasSigning && !hasPartition) {
        SecACLRef acl = NULL;
        NSString *description = partitionDescription(@{@"Partitions": @[@"apple-tool:", @"apple:", @"codesign:"]});
        success = check(SecACLCreateWithSimpleContents(access, NULL, (__bridge CFStringRef)description, 0, &acl), @"partition ACL 생성");
        if (success) {
            NSArray *tags = @[(__bridge NSString *)kSecACLAuthorizationPartitionID];
            success = check(SecACLUpdateAuthorizations(acl, (__bridge CFArrayRef)tags), @"partition 권한 지정");
            CFRelease(acl);
        }
        changed = YES;
    }
    if (success && apply && changed) success = check(SecKeychainItemSetAccess(item, access), @"서명 키 접근 권한 저장");
    if (hasSigning) [reports addObject:@{@"acl": keyReports, @"has_partition": @(hasPartition), @"changed": @(apply && changed && success)}];
    CFRelease(aclList);
    CFRelease(access);
    return success;
}

static BOOL inspectOrConfigure(NSString *path, BOOL apply) {
    SecKeychainRef keychain = openKeychain(path);
    if (!keychain) return NO;
    BOOL success = YES;
    if (apply && !isUnlocked(keychain)) success = check(SecKeychainUnlock(keychain, 0, NULL, false), @"시스템 창으로 키체인 잠금 해제");
    SecKeychainSettings settings = {.version = SEC_KEYCHAIN_SETTINGS_VERS1};
    if (success && apply) {
        settings.lockOnSleep = false;
        settings.useLockInterval = false;
        settings.lockInterval = INT_MAX;
        success = check(SecKeychainSetSettings(keychain, &settings), @"자동 잠금 해제 설정");
    }
    success = success && check(SecKeychainCopySettings(keychain, &settings), @"잠금 설정 조회");
    SecKeychainSearchRef search = NULL;
    NSMutableArray *reports = [NSMutableArray array];
    NSUInteger keyCount = 0;
    if (success) success = check(SecKeychainSearchCreateFromAttributes(keychain, kSecPrivateKeyItemClass, NULL, &search), @"개인 키 목록 조회");
    if (success) {
        SecKeychainItemRef item = NULL;
        OSStatus status;
        while ((status = SecKeychainSearchCopyNext(search, &item)) == errSecSuccess) {
            keyCount++;
            success = updateSigningAccess(item, apply, reports) && success;
            CFRelease(item);
        }
        if (status != errSecItemNotFound) success = check(status, @"개인 키 조회 완료") && success;
    }
    NSDictionary *report = @{@"keychain": canonical(path), @"unlocked": @(isUnlocked(keychain)), @"no_timeout": @(!settings.useLockInterval),
        @"lock_on_sleep": @(settings.lockOnSleep), @"private_key_count": @(keyCount), @"signing_keys": reports, @"success": @(success)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(json.bytes, 1, json.length, stdout); puts("");
    if (search) CFRelease(search);
    CFRelease(keychain);
    return success;
}

static OSStatus findCache(SecKeychainRef login, NSString *path, UInt32 *length, void **password, SecKeychainItemRef *item) {
    const char *account = canonical(path).UTF8String;
    return SecKeychainFindGenericPassword(login, (UInt32)strlen(CacheService), CacheService, (UInt32)strlen(account), account, length, password, item);
}

static BOOL selfOnlyAccess(SecKeychainItemRef item) {
    SecAccessRef access = NULL;
    CFArrayRef acls = NULL;
    BOOL restricted = YES, decryptFound = NO;
    if (SecKeychainItemCopyAccess(item, &access) != errSecSuccess || SecAccessCopyACLList(access, &acls) != errSecSuccess) restricted = NO;
    for (id value in (__bridge NSArray *)acls) {
        SecACLRef acl = (__bridge SecACLRef)value;
        if (!hasAuthorization(acl, kSecACLAuthorizationDecrypt)) continue;
        decryptFound = YES;
        CFArrayRef apps = NULL;
        CFStringRef description = NULL;
        SecKeychainPromptSelector prompt = 0;
        if (SecACLCopyContents(acl, &apps, &description, &prompt) != errSecSuccess) restricted = NO;
        NSArray *paths = applicationPaths(apps);
        restricted = restricted && paths.count == 1 && [paths.firstObject isEqual:selfPath()] && !(prompt & kSecKeychainPromptRequirePassphase);
        if (apps) CFRelease(apps);
        if (description) CFRelease(description);
    }
    if (acls) CFRelease(acls);
    if (access) CFRelease(access);
    return restricted && decryptFound;
}

static BOOL readableCache(SecKeychainRef login, NSString *path) {
    UInt32 length = 0;
    void *password = NULL;
    SecKeychainSetUserInteractionAllowed(false);
    OSStatus status = findCache(login, path, &length, &password, NULL);
    if (password) { wipe(password, length); SecKeychainItemFreeContent(NULL, password); }
    return status == errSecSuccess;
}

static BOOL writeCache(SecKeychainRef login, NSString *path, const void *password, UInt32 length) {
    SecTrustedApplicationRef self = NULL;
    SecAccessRef access = NULL;
    if (!check(SecTrustedApplicationCreateFromPath(selfPath().fileSystemRepresentation, &self), @"전용 helper 신뢰 등록")) return NO;
    const void *values[] = {self};
    CFArrayRef apps = CFArrayCreate(NULL, values, 1, &kCFTypeArrayCallBacks);
    BOOL success = check(SecAccessCreate(CFSTR("co:code 서명 키체인 자동 해제"), apps, &access), @"암호 캐시 ACL 생성");
    SecKeychainItemRef existing = NULL;
    OSStatus found = findCache(login, path, NULL, NULL, &existing); // 내용 없이 존재만 확인한다.
    if (success && found == errSecSuccess) {
        BOOL sameAccess = selfOnlyAccess(existing) && readableCache(login, path);
        SecKeychainSetUserInteractionAllowed(getenv("COCODE_KEYCHAIN_NO_UI") == NULL);
        success = check(SecKeychainItemModifyAttributesAndData(existing, NULL, length, password), @"암호화 캐시 갱신");
        // 정상인 기존 ACL은 유지한다. 무조건 SetAccess하면 갱신할 때마다 인증 창이 뜬다.
        if (success && !sameAccess) success = check(SecKeychainItemSetAccess(existing, access), @"캐시 접근 제한 갱신");
    } else if (success && found == errSecItemNotFound) {
        const char *account = canonical(path).UTF8String;
        SecKeychainAttribute attributes[] = {
            {kSecServiceItemAttr, (UInt32)strlen(CacheService), (void *)CacheService},
            {kSecAccountItemAttr, (UInt32)strlen(account), (void *)account},
        };
        SecKeychainAttributeList list = {2, attributes};
        success = check(SecKeychainItemCreateFromContent(kSecGenericPasswordItemClass, &list, length, password, login, access, NULL), @"login 키체인에 암호화 캐시 저장");
    } else if (success) success = check(found, @"기존 캐시 조회");
    if (existing) CFRelease(existing);
    if (access) CFRelease(access);
    CFRelease(apps); CFRelease(self);
    return success;
}

static BOOL cachedUnlock(NSString *path, NSString *cachePath, BOOL probe) {
    SecKeychainRef target = openKeychain(path);
    if (!target) return NO;
    if (!probe && isUnlocked(target)) { CFRelease(target); return YES; }
    SecKeychainRef login = openKeychain(cachePath);
    if (!login) { CFRelease(target); return NO; }
    // 로그인·검증 실행에서는 UI를 차단한다. op·Touch ID·암호 입력 창을 호출하지 않는다.
    SecKeychainSetUserInteractionAllowed(false);
    UInt32 length = 0;
    void *password = NULL;
    BOOL success = check(findCache(login, path, &length, &password, NULL), @"암호화 캐시 읽기");
    if (success && probe) success = check(SecKeychainLock(target), @"자동 해제 검증용 잠금");
    if (success && probe && isUnlocked(target)) { fprintf(stderr, "⚠ 검증용 잠금이 적용되지 않았습니다.\n"); success = NO; }
    unsigned char empty = 0;
    if (success) success = check(SecKeychainUnlock(target, length, password ?: &empty, true), @"캐시로 키체인 잠금 해제");
    if (password) { wipe(password, length); SecKeychainItemFreeContent(NULL, password); }
    success = success && isUnlocked(target);
    if (success) printf("✓ %s: %s\n", path.lastPathComponent.UTF8String, probe ? "잠금 → 무암호 자동 해제 검증 통과" : "자동 잠금 해제 완료");
    CFRelease(login); CFRelease(target);
    return success;
}

static BOOL enrollData(NSString *path, NSString *cachePath, const void *password, UInt32 length) {
    SecKeychainRef target = openKeychain(path);
    SecKeychainRef login = openKeychain(cachePath);
    BOOL success = target && login;
    if (success) {
        // 열린 키체인의 Unlock은 인증을 생략할 수 있어 짧은 lock→unlock으로 암호 원본을 확인한다.
        BOOL wasUnlocked = isUnlocked(target);
        SecKeychainSetUserInteractionAllowed(false);
        success = check(SecKeychainLock(target), @"암호 확인용 잠금") && check(SecKeychainUnlock(target, length, password, true), @"키체인 암호 원본 확인");
        BOOL allowUI = getenv("COCODE_KEYCHAIN_NO_UI") == NULL;
        SecKeychainSetUserInteractionAllowed(allowUI);
        if (!success && wasUnlocked && allowUI) check(SecKeychainUnlock(target, 0, NULL, false), @"잘못된 참조 확인 후 시스템 창으로 원래 잠금 상태 복구");
        if (success) success = writeCache(login, path, password, length);
    }
    if (login) CFRelease(login);
    if (target) CFRelease(target);
    if (success) printf("✓ %s: 암호 원본 확인·login 암호화 캐시 등록 완료\n", path.lastPathComponent.UTF8String);
    return success;
}

static BOOL enrollStdin(NSString *path, NSString *cachePath) {
    unsigned char password[8192];
    NSUInteger length = 0;
    ssize_t count;
    while (length < sizeof(password) && (count = read(STDIN_FILENO, password + length, sizeof(password) - length)) > 0) length += (NSUInteger)count;
    BOOL success = length > 0 && length < sizeof(password) && enrollData(path, cachePath, password, (UInt32)length);
    wipe(password, sizeof(password));
    return success;
}

static BOOL unlockStdin(NSString *path) {
    unsigned char password[8192];
    NSUInteger length = 0;
    ssize_t count;
    while (length < sizeof(password) && (count = read(STDIN_FILENO, password + length, sizeof(password) - length)) > 0) length += (NSUInteger)count;
    SecKeychainRef keychain = openKeychain(path);
    SecKeychainSetUserInteractionAllowed(false);
    BOOL success = keychain && length > 0 && length < sizeof(password) &&
        check(SecKeychainUnlock(keychain, (UInt32)length, password, true), @"원본 암호로 초기 잠금 해제") && isUnlocked(keychain);
    wipe(password, sizeof(password));
    if (keychain) CFRelease(keychain);
    if (success) printf("✓ %s: 원본 암호로 초기 잠금 해제 완료\n", path.lastPathComponent.UTF8String);
    return success;
}

static BOOL enroll(NSString *path, NSString *reference, NSString *account, NSString *opPath) {
    if (![reference hasPrefix:@"op://"] || ![opPath hasPrefix:@"/"]) return NO;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:opPath];
    task.arguments = @[@"read", @"--no-newline", @"--account", account, reference];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) { fprintf(stderr, "⚠ op를 실행할 수 없습니다.\n"); return NO; }
    // op 출력은 부모 프로세스 내부 파이프로만 받는다. stdout 전달·임시 파일은 사용하지 않는다.
    unsigned char password[8192];
    wipe(password, sizeof(password));
    mlock(password, sizeof(password));
    NSUInteger length = 0;
    int fd = pipe.fileHandleForReading.fileDescriptor;
    BOOL readOK = YES;
    NSTimeInterval deadline = NSDate.timeIntervalSinceReferenceDate + 120;
    while (length < sizeof(password)) {
        struct pollfd ready = {.fd = fd, .events = POLLIN};
        if (NSDate.timeIntervalSinceReferenceDate >= deadline) { readOK = NO; break; }
        int polled = poll(&ready, 1, 1000);
        if (polled < 0) { if (errno == EINTR) continue; readOK = NO; break; }
        if (!polled) continue;
        ssize_t count = read(fd, password + length, sizeof(password) - length);
        if (count <= 0) { readOK = count == 0; break; }
        length += (NSUInteger)count;
    }
    if (!readOK || length == sizeof(password)) [task terminate];
    [task waitUntilExit];
    BOOL success = readOK && task.terminationStatus == 0 && length > 0 && length < sizeof(password);
    if (!success) fprintf(stderr, "⚠ 1Password에서 키체인 암호를 읽지 못했습니다. 참조·CLI 통합을 확인하세요.\n");
    if (success) success = enrollData(path, loginPath(), password, (UInt32)length);
    wipe(password, sizeof(password)); munlock(password, sizeof(password));
    return success;
}

static BOOL forget(NSString *path, NSString *cachePath) {
    SecKeychainRef login = openKeychain(cachePath);
    if (!login) return NO;
    SecKeychainItemRef item = NULL;
    OSStatus status = findCache(login, path, NULL, NULL, &item);
    BOOL success = status == errSecItemNotFound || check(status, @"삭제할 캐시 조회");
    if (item) { success = check(SecKeychainItemDelete(item), @"암호화 캐시 삭제"); CFRelease(item); }
    CFRelease(login);
    return success;
}

static BOOL forgetAll(NSString *cachePath) {
    SecKeychainRef login = openKeychain(cachePath);
    if (!login) return NO;
    SecKeychainAttribute attribute = {kSecServiceItemAttr, (UInt32)strlen(CacheService), (void *)CacheService};
    SecKeychainAttributeList attributes = {1, &attribute};
    SecKeychainSearchRef search = NULL;
    BOOL success = check(SecKeychainSearchCreateFromAttributes(login, kSecGenericPasswordItemClass, &attributes, &search), @"전용 캐시 목록 조회");
    if (success) {
        SecKeychainItemRef item = NULL;
        OSStatus status;
        while ((status = SecKeychainSearchCopyNext(search, &item)) == errSecSuccess) {
            success = check(SecKeychainItemDelete(item), @"전용 암호화 캐시 삭제") && success;
            CFRelease(item);
        }
        success = (status == errSecItemNotFound || check(status, @"캐시 목록 조회 완료")) && success;
    }
    if (search) CFRelease(search);
    CFRelease(login);
    return success;
}

static BOOL cacheStatus(NSString *path, NSString *cachePath) {
    SecKeychainRef login = openKeychain(cachePath);
    if (!login) return NO;
    SecKeychainItemRef item = NULL;
    OSStatus status = findCache(login, path, NULL, NULL, &item);
    BOOL restricted = NO;
    if (status == errSecSuccess) {
        // 경로뿐 아니라 현재 서명된 helper가 UI 없이 실제 복호화할 수 있는지도 확인한다.
        restricted = selfOnlyAccess(item) && readableCache(login, path);
        CFRelease(item);
    }
    NSDictionary *report = @{@"keychain": canonical(path), @"cache_present": @(status == errSecSuccess), @"helper_only": @(status == errSecSuccess && restricted)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
    fwrite(json.bytes, 1, json.length, stdout); puts("");
    CFRelease(login);
    return status == errSecSuccess && restricted;
}

static BOOL identities(NSString *path) {
    SecKeychainRef keychain = openKeychain(path);
    if (!keychain) return NO;
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassIdentity,
        (__bridge id)kSecMatchSearchList: @[(__bridge id)keychain], (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll, (__bridge id)kSecReturnRef: @YES};
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSMutableArray *reports = [NSMutableArray array];
    if (status == errSecSuccess) for (id value in (__bridge NSArray *)result) {
        SecCertificateRef certificate = NULL;
        if (SecIdentityCopyCertificate((__bridge SecIdentityRef)value, &certificate) != errSecSuccess) continue;
        CFStringRef name = NULL;
        SecCertificateCopyCommonName(certificate, &name);
        CFDataRef data = SecCertificateCopyData(certificate);
        unsigned char digest[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(CFDataGetBytePtr(data), (CC_LONG)CFDataGetLength(data), digest);
        NSMutableString *fingerprint = [NSMutableString string];
        for (int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) [fingerprint appendFormat:@"%02X", digest[i]];
        [reports addObject:@{@"name": (__bridge NSString *)name ?: @"", @"sha1": fingerprint}];
        if (name) CFRelease(name);
        CFRelease(data); CFRelease(certificate);
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:reports options:0 error:nil];
    fwrite(json.bytes, 1, json.length, stdout); puts("");
    if (result) CFRelease(result);
    CFRelease(keychain);
    return status == errSecSuccess || status == errSecItemNotFound;
}

static BOOL unlockAll(NSString *configPath) {
    NSData *data = [NSData dataWithContentsOfFile:configPath];
    if (!data) return NO;
    NSDictionary *config = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![config isKindOfClass:NSDictionary.class] || ![config[@"targets"] isKindOfClass:NSArray.class]) return NO;
    BOOL success = YES;
    for (NSDictionary *target in config[@"targets"]) {
        NSString *path = target[@"path"];
        if (![path isKindOfClass:NSString.class] || ![path hasPrefix:@"/"]) { success = NO; continue; }
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue; // 재생성 전 임시 키체인은 건너뛴다.
        success = cachedUnlock(path, loginPath(), NO) && success;
    }
    return success;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        struct rlimit noCore = {0, 0};
        setrlimit(RLIMIT_CORE, &noCore);
        if (argc < 3) { fprintf(stderr, "사용법: helper inspect|configure|enroll|unlock|probe-unlock|cache-status|forget|identities <키체인>\n"); return 64; }
        NSString *command = @(argv[1]), *path = @(argv[2]);
        BOOL interactive = [command isEqual:@"configure"] || [command hasPrefix:@"enroll"];
        SecKeychainSetUserInteractionAllowed(interactive && getenv("COCODE_KEYCHAIN_NO_UI") == NULL);
        NSString *cache = argc == 4 ? @(argv[3]) : loginPath();
        BOOL success = NO;
        if ([command isEqual:@"inspect"] && argc == 3) success = inspectOrConfigure(path, NO);
        else if ([command isEqual:@"configure"] && argc == 3) success = inspectOrConfigure(path, YES);
        else if ([command isEqual:@"enroll"] && argc == 6) success = enroll(path, @(argv[3]), @(argv[4]), @(argv[5]));
        else if ([command isEqual:@"enroll-stdin"] && (argc == 3 || argc == 4)) success = enrollStdin(path, cache);
        else if ([command isEqual:@"enroll-empty"] && (argc == 3 || argc == 4)) { unsigned char empty = 0; success = enrollData(path, cache, &empty, 0); }
        else if ([command isEqual:@"unlock"] && (argc == 3 || argc == 4)) success = cachedUnlock(path, cache, NO);
        else if ([command isEqual:@"unlock-stdin"] && argc == 3) success = unlockStdin(path);
        else if ([command isEqual:@"probe-unlock"] && (argc == 3 || argc == 4)) success = cachedUnlock(path, cache, YES);
        else if ([command isEqual:@"cache-status"] && (argc == 3 || argc == 4)) success = cacheStatus(path, cache);
        else if ([command isEqual:@"forget"] && (argc == 3 || argc == 4)) success = forget(path, cache);
        else if ([command isEqual:@"forget-all"] && argc == 3) success = forgetAll(path);
        else if ([command isEqual:@"identities"] && argc == 3) success = identities(path);
        else if ([command isEqual:@"unlock-all"] && argc == 3) success = unlockAll(path);
        else return 64;
        return success ? 0 : 1;
    }
}
