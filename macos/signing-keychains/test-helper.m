// 실제 사용자 키체인 대신 격리한 두 키체인으로 ACL·자동 해제 경계를 검증한다.
#define main helper_main
#include "helper.m"
#undef main

static void require(BOOL condition, NSString *name) {
    if (!condition) @throw [NSException exceptionWithName:@"TestFailure" reason:name userInfo:nil];
    printf("✓ %s\n", name.UTF8String);
    fflush(stdout);
}

static int child(NSString *helper, NSArray *arguments, NSData *secret) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:helper];
    task.arguments = arguments;
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"COCODE_KEYCHAIN_NO_UI"] = @"1";
    task.environment = environment;
    NSPipe *input = [NSPipe pipe];
    task.standardInput = input;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    require([task launchAndReturnError:nil], @"검증용 helper 프로세스 시작");
    if (secret) [input.fileHandleForWriting writeData:secret];
    [input.fileHandleForWriting closeFile];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
    while (task.running && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.05];
    if (task.running) { [task terminate]; @throw [NSException exceptionWithName:@"TestTimeout" reason:@"helper 검증이 15초를 초과했습니다" userInfo:nil]; }
    [task waitUntilExit];
    return task.terminationStatus;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 64;
        SecKeychainSetUserInteractionAllowed(false);
        CFArrayRef originalSearch = NULL;
        SecKeychainRef originalDefault = NULL;
        SecKeychainCopySearchList(&originalSearch);
        SecKeychainCopyDefault(&originalDefault);
        NSMutableArray *created = [NSMutableArray array];
        NSString *helper = @(argv[1]), *directory = @(argv[2]);
        SecKeychainRef login = NULL, target = NULL, empty = NULL;
        int result = 0;
        @try {
            unsigned char random[32];
            require(SecRandomCopyBytes(kSecRandomDefault, sizeof(random), random) == errSecSuccess, @"임시 암호는 메모리에서 생성");
            NSData *secret = [[NSData dataWithBytes:random length:sizeof(random)] base64EncodedDataWithOptions:0];
            wipe(random, sizeof(random));
            NSString *loginName = [directory stringByAppendingPathComponent:@"cache.keychain-db"];
            NSString *targetName = [directory stringByAppendingPathComponent:@"target.keychain-db"];
            NSString *emptyName = [directory stringByAppendingPathComponent:@"empty.keychain-db"];
            for (NSString *path in @[loginName, targetName, emptyName]) {
                SecKeychainRef value = NULL;
                BOOL blank = [path isEqual:emptyName];
                require(SecKeychainCreate(path.fileSystemRepresentation, blank ? 0 : (UInt32)secret.length,
                                         blank ? "" : secret.bytes, false, NULL, &value) == errSecSuccess, @"격리된 검증용 키체인 생성");
                [created addObject:(__bridge_transfer id)value];
            }
            login = (__bridge SecKeychainRef)created[0];
            target = (__bridge SecKeychainRef)created[1];
            empty = (__bridge SecKeychainRef)created[2];
            require(child(helper, @[@"enroll-stdin", targetName, loginName], secret) == 0, @"암호를 인자·파일 없이 파이프로 등록");
            require(child(helper, @[@"cache-status", targetName, loginName], nil) == 0, @"캐시 복호화 ACL은 서명된 전용 helper만 허용");
            require(child(helper, @[@"enroll-stdin", targetName, loginName], secret) == 0, @"기존 정상 캐시 갱신은 ACL 재승인 없이 통과");
            UInt32 passwordLength = 0;
            void *password = NULL;
            OSStatus unauthorized = findCache(login, targetName, &passwordLength, &password, NULL);
            if (password) { wipe(password, passwordLength); SecKeychainItemFreeContent(NULL, password); }
            require(unauthorized != errSecSuccess, @"다른 프로세스의 캐시 암호 읽기 거부 (UI 없음)");
            require(SecKeychainLock(target) == errSecSuccess && !isUnlocked(target), @"잠금 상태를 실제로 주입");
            require(child(helper, @[@"unlock", targetName, loginName], nil) == 0 && isUnlocked(target), @"별도 helper 프로세스에서 무암호 자동 해제");
            require(child(helper, @[@"probe-unlock", targetName, loginName], nil) == 0, @"잠금→자동 해제를 한 번 더 검증");
            require(child(helper, @[@"enroll-empty", emptyName, loginName], nil) == 0, @"명시된 빈 키체인 암호 등록");
            require(SecKeychainLock(empty) == errSecSuccess && child(helper, @[@"unlock", emptyName, loginName], nil) == 0 && isUnlocked(empty), @"빈 암호 키체인도 잠금→자동 해제");
            require(SecKeychainLock(login) == errSecSuccess, @"캐시 키체인 잠금 주입");
            require(child(helper, @[@"probe-unlock", targetName, loginName], nil) != 0, @"login이 잠기면 입력 창 없이 실패하고 대상은 열린 상태 유지");
            require(isUnlocked(target), @"캐시를 읽지 못한 경우 대상부터 잠그지 않음");
            require(SecKeychainUnlock(login, (UInt32)secret.length, secret.bytes, true) == errSecSuccess, @"검증용 login 복구");

            // partition hex plist의 실제 표현을 사용하고 teamid와 미지의 plist 필드를 보존한다.
            NSDictionary *initial = @{@"Partitions": @[@"teamid:preserve-test", @"apple:"], @"FixtureMetadata": @"preserve"};
            NSMutableDictionary *decoded = partitionDictionary(partitionDescription(initial));
            require([decoded isEqual:initial], @"partition hex plist 왕복·teamid·확장 필드 보존");
            require(partitionDictionary(@"not-a-plist") == nil, @"손상된 partition 표현은 덮어쓰지 않고 거부");
            SecTrustedApplicationRef self = NULL;
            SecAccessRef access = NULL;
            require(SecTrustedApplicationCreateFromPath(NULL, &self) == errSecSuccess, @"검증용 서명 키 접근 생성");
            const void *selfValues[] = {self};
            CFArrayRef apps = CFArrayCreate(NULL, selfValues, 1, &kCFTypeArrayCallBacks);
            require(SecAccessCreate(CFSTR("fixture"), apps, &access) == errSecSuccess, @"검증용 개인 키 ACL 생성");
            // 운영 키의 change_acl은 macOS 인증 창을 요구할 수 있다. fixture에서는 작성자만
            // ACL을 고치도록 미리 허용해 실제 보완 로직을 비대화형으로 검증한다.
            CFArrayRef initialACLs = NULL;
            require(SecAccessCopyACLList(access, &initialACLs) == errSecSuccess, @"fixture ACL 작성자 제한");
            for (id value in (__bridge NSArray *)initialACLs) {
                SecACLRef acl = (__bridge SecACLRef)value;
                if (hasAuthorization(acl, kSecACLAuthorizationChangeACL)) require(SecACLSetContents(acl, apps, CFSTR("fixture"), 0) == errSecSuccess, @"fixture 작성자의 ACL 갱신 허용");
            }
            CFRelease(initialACLs);
            SecCodeRef code = NULL;
            CFDictionaryRef information = NULL;
            require(SecCodeCopySelf(kSecCSDefaultFlags, &code) == errSecSuccess &&
                    SecCodeCopySigningInformation((SecStaticCodeRef)code, kSecCSDefaultFlags, &information) == errSecSuccess, @"fixture 코드 서명 식별자 조회");
            NSData *hash = (__bridge NSData *)CFDictionaryGetValue(information, kSecCodeInfoUnique);
            NSMutableString *ownPartition = [NSMutableString stringWithString:@"cdhash:"];
            const unsigned char *hashBytes = hash.bytes;
            for (NSUInteger index = 0; index < hash.length; index++) [ownPartition appendFormat:@"%02x", hashBytes[index]];
            CFRelease(information); CFRelease(code);
            SecACLRef partitionACL = NULL;
            NSString *partition = partitionDescription(@{@"Partitions": @[ownPartition, @"teamid:preserve-test"], @"FixtureMetadata": @"preserve"});
            require(SecACLCreateWithSimpleContents(access, NULL, (__bridge CFStringRef)partition, 0, &partitionACL) == errSecSuccess &&
                    SecACLUpdateAuthorizations(partitionACL, (__bridge CFArrayRef)@[(__bridge id)kSecACLAuthorizationPartitionID]) == errSecSuccess, @"fixture 전용 partition 작성");
            CFRelease(partitionACL);
            NSDictionary *parameters = @{(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
                (__bridge id)kSecAttrKeySizeInBits: @2048, (__bridge id)kSecAttrIsPermanent: @YES,
                (__bridge id)kSecUseKeychain: (__bridge id)target, (__bridge id)kSecAttrAccess: (__bridge id)access};
            SecKeyRef public = NULL, private = NULL;
            require(SecKeyGeneratePair((__bridge CFDictionaryRef)parameters, &public, &private) == errSecSuccess, @"검증용 개인 키 생성");
            CFRelease(access); CFRelease(apps); CFRelease(self);
            NSMutableArray *report = [NSMutableArray array];
            require(updateSigningAccess((SecKeychainItemRef)private, YES, report), @"누락 도구·partition을 실제 개인 키에 보완");
            require([report[0][@"changed"] boolValue], @"누락 ACL 변경이 실제로 발생");
            report = [NSMutableArray array];
            require(updateSigningAccess((SecKeychainItemRef)private, YES, report), @"ACL 재실행 성공");
            require(![report[0][@"changed"] boolValue], @"정상 ACL 재실행은 변경 0건");
            for (NSDictionary *acl in report[0][@"acl"]) {
                if ([acl[@"type"] isEqual:@"partition"]) require([acl[@"partitions"] containsObject:@"teamid:preserve-test"] && [acl[@"missing_partitions"] count] == 0, @"기존 teamid 보존·필수 partition 완결");
                if ([acl[@"type"] isEqual:@"sign"]) require(![acl[@"all_applications"] boolValue] && [acl[@"missing_tools"] count] == 0, @"전체 앱 허용 없이 네 서명 도구 완결");
            }
            CFRelease(public); CFRelease(private);
            require(child(helper, @[@"forget", targetName, loginName], nil) == 0, @"자동 해제 캐시 제거");
            require(child(helper, @[@"cache-status", targetName, loginName], nil) != 0, @"제거한 캐시가 실제로 사라짐");
        } @catch (NSException *exception) {
            fprintf(stderr, "실패: %s\n", exception.reason.UTF8String);
            result = 1;
        } @finally {
            for (id value in created) SecKeychainDelete((__bridge SecKeychainRef)value);
            if (originalSearch) { SecKeychainSetSearchList(originalSearch); CFRelease(originalSearch); }
            if (originalDefault) { SecKeychainSetDefault(originalDefault); CFRelease(originalDefault); }
        }
        return result;
    }
}
