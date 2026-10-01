#!/usr/bin/env python3
"""macOS 서명 키체인 선택형 설정. 비밀값은 native helper만 취급한다."""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


LABEL = "im.cocode.desktop.signing-keychains"
ROOT = Path.home() / "Library/Application Support/co-code/signing-keychains"
CONFIG = ROOT / "config.json"
HELPER = ROOT / "keychain-helper"
AGENT = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
DOMAIN = "gui/" + str(os.getuid())
ACCOUNT = "team-cocodeinc.1password.com"
SOURCE = Path(__file__).with_name("helper.m")


def run(args, timeout=120, capture=True, check=True):
    result = subprocess.run([str(arg) for arg in args], stdin=subprocess.DEVNULL,
                            capture_output=capture, text=True, timeout=timeout)
    if check and result.returncode:
        # helper는 비밀값을 출력하지 않는다. op 자체는 이 함수에서 호출하지 않는다.
        raise RuntimeError((result.stderr or "명령 실행 실패").strip())
    return result


def keychain_paths():
    return [str(Path(path).resolve()) for path in shlex.split(run(["/usr/bin/security", "list-keychains", "-d", "user"]).stdout)]


def ensure_unlocked(path):
    security = ctypes.CDLL("/System/Library/Frameworks/Security.framework/Security")
    foundation = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    security.SecKeychainOpen.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
    security.SecKeychainGetStatus.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
    foundation.CFRelease.argtypes = [ctypes.c_void_p]
    keychain, state = ctypes.c_void_p(), ctypes.c_uint32()
    if security.SecKeychainOpen(os.fsencode(path), ctypes.byref(keychain)) != 0:
        raise RuntimeError("키체인을 열 수 없습니다.")
    try:
        if security.SecKeychainGetStatus(keychain, ctypes.byref(state)) != 0:
            raise RuntimeError("키체인 잠금 상태를 조회할 수 없습니다.")
        if not state.value & 1:
            print("· 최초 등록을 위해 " + Path(path).name + "의 macOS 잠금 해제 창을 엽니다.")
            run(["/usr/bin/security", "unlock-keychain", "-u", path])
    finally:
        foundation.CFRelease(keychain)


def resolve_keychain(paths, supplied, prefix):
    if supplied:
        candidate = str(Path(supplied).expanduser().resolve())
        matches = [path for path in paths if path == candidate or Path(path).name == supplied]
    else:
        matches = [path for path in paths if Path(path).name.startswith(prefix)]
    matches = list(dict.fromkeys(matches))
    if len(matches) != 1:
        raise RuntimeError(prefix + " 키체인을 하나로 확인할 수 없습니다. --" +
                           ("laputa" if prefix == "laputa" else "fastlane") + "-keychain에 실제 경로를 지정하세요.")
    return matches[0]


def valid_identities(path, policy):
    output = run(["/usr/bin/security", "find-identity", "-v", "-p", policy, path]).stdout
    return [{"sha1": match[0], "name": match[1]} for match in
            re.findall(r'\d+\)\s+([0-9A-Fa-f]{40})\s+"([^\n]+)"', output)]


def agent_plist():
    # 암호·op 참조는 plist에 넣지 않는다. 로그인 실행은 로컬 암호화 캐시만 사용한다.
    return {"Label": LABEL, "ProgramArguments": [str(HELPER), "unlock-all", str(CONFIG)],
            "RunAtLoad": True, "StartInterval": 300, "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Background", "Umask": 0o077,
            "StandardOutPath": str(ROOT / "agent.log"), "StandardErrorPath": str(ROOT / "agent.log")}


def load_config():
    if not CONFIG.is_file() or not HELPER.is_file():
        raise RuntimeError("자동 해제가 아직 등록되지 않았습니다. install을 실행하세요.")
    return json.loads(CONFIG.read_text())


def atomic_file(path, data, mode=0o600):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        staging = Path(stream.name)
        try:
            os.chmod(staging, mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        except BaseException:
            staging.unlink(missing_ok=True)
            raise
    staging.replace(path)


def stop_agent():
    result = run(["/bin/launchctl", "print", DOMAIN + "/" + LABEL], check=False)
    if result.returncode == 0:
        run(["/bin/launchctl", "bootout", DOMAIN + "/" + LABEL])


def install(args):
    if not args.laputa_ref and not args.laputa_stdin and not args.fastlane_ref and not args.fastlane_empty:
        raise RuntimeError("--laputa-ref 또는 --fastlane-ref에 op:// 참조를 지정하세요. 실제 암호는 인자로 받지 않습니다.")
    paths = keychain_paths()
    targets = []
    for prefix, supplied, reference in [("laputa", args.laputa_keychain, args.laputa_ref),
                                         ("fastlane_tmp", args.fastlane_keychain, args.fastlane_ref)]:
        empty = prefix == "fastlane_tmp" and args.fastlane_empty
        from_stdin = prefix == "laputa" and args.laputa_stdin
        if not reference and not empty and not from_stdin:
            continue
        if reference and not reference.startswith("op://"):
            raise RuntimeError("암호 대신 op:// 참조 경로만 지정할 수 있습니다.")
        targets.append({"path": resolve_keychain(paths, supplied, prefix), "reference": reference, "empty_password": empty, "from_stdin": from_stdin})
    op = shutil.which("op")
    if not op and any(not target["empty_password"] and not target["from_stdin"] for target in targets):
        raise RuntimeError("op가 없습니다. brew install --cask 1password-cli 후 CLI 통합을 설정하세요.")
    # 교체 전에 로그인 작업을 멈춘다. 서명이 바뀌는 업데이트는 재등록으로 ACL을 다시 연결한다.
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    ROOT.chmod(0o700)
    previous = json.loads(CONFIG.read_text()) if CONFIG.is_file() else {}
    for target in targets:
        ensure_unlocked(target["path"])
        run(["/usr/bin/security", "set-keychain-settings", target["path"]])
    identity = args.identity or previous.get("identity")
    if not identity:
        candidates = [identity for target in targets for identity in valid_identities(target["path"], "codesigning")]
        if candidates:
            candidates.sort(key=lambda item: not item["name"].startswith("Apple Development:"))
            identity = candidates[0]["sha1"]
        else:
            # Installer 인증서만 있는 Mac도 지원한다. 로컬 ad-hoc 서명의 정확한 helper만 신뢰한다.
            identity = "-"
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    needs_build = not HELPER.is_file() or previous.get("source_hash") != source_hash or previous.get("identity") != identity
    if needs_build and previous.get("targets"):
        previous_paths = {target["path"] for target in previous["targets"]}
        if not previous_paths <= {target["path"] for target in targets}:
            raise RuntimeError("helper 업데이트에는 기존 대상 모두의 원본을 다시 지정해야 합니다. 두 키체인의 참조 또는 최초 이전 입력을 함께 지정하세요.")
    stop_agent()
    if needs_build:
        with tempfile.TemporaryDirectory(prefix="helper-build-", dir=ROOT) as directory:
            binary = Path(directory) / "keychain-helper"
            run(["/usr/bin/xcrun", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                 "-Wno-deprecated-declarations", "-framework", "Foundation", "-framework", "Security",
                 SOURCE, "-o", binary])
            run(["/usr/bin/codesign", "--force", "--sign", identity, "--identifier", LABEL + ".helper", "--timestamp=none", binary])
            run(["/usr/bin/codesign", "--verify", "--strict", binary])
            binary.chmod(0o700)
            binary.replace(HELPER)
    else:
        run(["/usr/bin/codesign", "--verify", "--strict", HELPER])
    for target in targets:
        configured = json.loads(run([HELPER, "configure", target["path"]]).stdout)
        if not configured["no_timeout"] or configured["lock_on_sleep"]:
            raise RuntimeError("자동 잠금 설정 검증 실패")
        # stdout은 암호가 아닌 등록 결과만 포함한다. 비밀값은 helper 내부에서 직접 읽는다.
        if target["empty_password"]:
            result = run([HELPER, "enroll-empty", target["path"]])
        elif target["from_stdin"]:
            # 1Password 공유 항목의 일회성 이전용. 파이프를 helper에 직접 연결해 값은 읽지 않는다.
            result = subprocess.run([str(HELPER), "enroll-stdin", target["path"]], stdin=sys.stdin.buffer,
                                    capture_output=True, text=True, timeout=180)
            if result.returncode:
                raise RuntimeError(result.stderr.strip() or "표준입력 원본 등록 실패")
        else:
            result = run([HELPER, "enroll", target["path"], target["reference"], args.account, op], timeout=180)
        print(result.stdout.strip())
        cache = json.loads(run([HELPER, "cache-status", target["path"]]).stdout)
        if not cache["helper_only"]:
            raise RuntimeError("암호화 캐시의 helper 전용 접근 제한을 확인하지 못했습니다.")
    # 개별 갱신은 기존 대상을 지우지 않고 같은 경로의 참조만 교체한다.
    by_path = {target["path"]: target for target in previous.get("targets", [])}
    by_path.update({target["path"]: target for target in targets})
    config = {"targets": list(by_path.values()), "account": args.account,
              "identity": identity, "source_hash": source_hash}
    atomic_file(CONFIG, json.dumps(config, ensure_ascii=False, indent=2).encode())
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    if not (ROOT / "agent.log").exists():
        atomic_file(ROOT / "agent.log", b"")
    else:
        (ROOT / "agent.log").chmod(0o600)
    atomic_file(AGENT, plistlib.dumps(agent_plist()))
    run(["/usr/bin/plutil", "-lint", AGENT])
    run(["/bin/launchctl", "bootstrap", DOMAIN, AGENT])
    run(["/bin/launchctl", "kickstart", DOMAIN + "/" + LABEL])
    print("✓ 사용자 로그인 자동 해제 등록 완료 — 로그인 실행에서는 op나 암호 입력 창을 호출하지 않습니다.")
    status(args)


def refresh(args):
    config = load_config()
    if any(target.get("from_stdin") for target in config["targets"]):
        raise RuntimeError("공유 항목에서 최초 등록한 대상은 install --laputa-ref op://...로 원본 참조를 연결한 뒤 refresh하세요.")
    op = shutil.which("op")
    if not op and any(not target.get("empty_password") for target in config["targets"]):
        raise RuntimeError("op가 없습니다.")
    for target in config["targets"]:
        run([HELPER, "configure", target["path"]])
        command = [HELPER, "enroll-empty", target["path"]] if target.get("empty_password") else [HELPER, "enroll", target["path"], target["reference"], config["account"], op]
        print(run(command, timeout=180).stdout.strip())
        run([HELPER, "cache-status", target["path"]])
    print("✓ 1Password 원본으로 암호화 캐시를 갱신했습니다.")


def status(_args):
    config = load_config()
    failed = False
    for target in config["targets"]:
        for command in ("inspect", "cache-status"):
            result = run([HELPER, command, target["path"]], check=False)
            if result.stdout:
                print(result.stdout.strip())
            if result.stderr:
                print(result.stderr.strip(), file=sys.stderr)
            failed = failed or result.returncode != 0
            if command == "inspect" and result.returncode == 0:
                report = json.loads(result.stdout)
                healthy = report.get("no_timeout") and not report.get("lock_on_sleep")
                for key in report.get("signing_keys", []):
                    healthy = healthy and key.get("has_partition", False)
                    for acl in key.get("acl", []):
                        if acl.get("type") == "sign":
                            healthy = healthy and not any((acl.get("all_applications"), acl.get("requires_password"), acl.get("missing_tools")))
                        elif acl.get("type") == "partition":
                            healthy = healthy and not acl.get("missing_partitions")
                if not healthy:
                    failed = True
                    print("⚠ " + Path(target["path"]).name + ": 자동 잠금·서명 접근 권한 보완이 필요합니다.")
    if run(["/bin/launchctl", "print", DOMAIN + "/" + LABEL], check=False).returncode:
        failed = True
        print("⚠ 로그인 LaunchAgent가 등록되어 있지 않습니다.")
    if failed:
        raise RuntimeError("자동 해제 설정의 일부를 확인하지 못했습니다.")


class PromptMonitor:
    """서명 중 SecurityAgent 창이 나타나면 무암호 성공으로 판정하지 않는다."""
    def __init__(self):
        self.cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        self.cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
        for name, args, result in [
            ("CFArrayGetCount", [ctypes.c_void_p], ctypes.c_long),
            ("CFArrayGetValueAtIndex", [ctypes.c_void_p, ctypes.c_long], ctypes.c_void_p),
            ("CFDictionaryGetValue", [ctypes.c_void_p, ctypes.c_void_p], ctypes.c_void_p),
            ("CFStringGetCString", [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long, ctypes.c_uint32], ctypes.c_bool),
        ]:
            function = getattr(self.cf, name)
            function.argtypes, function.restype = args, result
        self.cf.CFRelease.argtypes = [ctypes.c_void_p]
        self.cg.CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
        self.cg.CGWindowListCopyWindowInfo.restype = ctypes.c_void_p
        self.owner_key = ctypes.c_void_p.in_dll(self.cg, "kCGWindowOwnerName")

    def has_prompt(self):
        windows = self.cg.CGWindowListCopyWindowInfo(1, 0)
        if not windows:
            raise RuntimeError("서명 암호 입력 창을 관찰할 수 없습니다.")
        try:
            for index in range(self.cf.CFArrayGetCount(windows)):
                window = self.cf.CFArrayGetValueAtIndex(windows, index)
                owner = self.cf.CFDictionaryGetValue(window, self.owner_key)
                name = ctypes.create_string_buffer(256)
                if owner and self.cf.CFStringGetCString(owner, name, len(name), 0x08000100) and name.value == b"SecurityAgent":
                    return True
            return False
        finally:
            self.cf.CFRelease(windows)

    def sign(self, args):
        if self.has_prompt():
            raise RuntimeError("보안 입력 창이 이미 열려 있어 무암호 서명을 판정할 수 없습니다.")
        start = time.monotonic()
        with subprocess.Popen([str(arg) for arg in args], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
            try:
                while True:
                    if self.has_prompt():
                        raise RuntimeError("서명 중 보안 입력 창이 표시되었습니다.")
                    if time.monotonic() - start > 60:
                        raise RuntimeError("서명 검증이 60초를 초과했습니다.")
                    try:
                        stdout, stderr = process.communicate(timeout=0.02)
                        break
                    except subprocess.TimeoutExpired:
                        pass
                if self.has_prompt():
                    raise RuntimeError("서명 중 보안 입력 창이 표시되었습니다.")
            except BaseException:
                process.kill()
                process.communicate()
                raise
        if process.returncode:
            raise RuntimeError(stderr.strip() or stdout.strip() or "서명 실패")


def verify(_args):
    config = load_config()
    monitor = PromptMonitor()
    total_code, total_package, unavailable = 0, 0, []
    with tempfile.TemporaryDirectory(prefix="cocode-keychain-signing-") as directory:
        root = Path(directory)
        source = root / "probe.c"
        source.write_text("int main(void) { return 0; }\n")
        binary = root / "probe"
        run(["/usr/bin/xcrun", "clang", source, "-o", binary])
        for target in config["targets"]:
            path = target["path"]
            print(run([HELPER, "probe-unlock", path]).stdout.strip())
            all_identities = json.loads(run([HELPER, "identities", path]).stdout)
            code = valid_identities(path, "codesigning")
            # codesigning 정책은 Installer를 세지 않는다. basic과 인증서 이름을 별도로 확인한다.
            basic = valid_identities(path, "basic")
            installers = [item for item in basic if re.match(r"^(Developer ID Installer|3rd Party Mac Developer Installer|Mac Installer Distribution):", item["name"])]
            groups = {}
            for item in code:
                kind = "development" if re.search(r"Development:|Developer:|Mac Developer:", item["name"]) else "distribution"
                groups.setdefault(kind, item)
            for kind, item in groups.items():
                for attempt in (1, 2):
                    monitor.sign(["/usr/bin/codesign", "--force", "--sign", item["sha1"], "--keychain", path, "--timestamp=none", binary])
                    run(["/usr/bin/codesign", "--verify", "--strict", "--verbose=2", binary])
                    details = run(["/usr/bin/codesign", "--display", "--verbose=4", binary]).stderr
                    if "Authority=" + item["name"] not in details:
                        raise RuntimeError("예상 인증서로 서명되지 않았습니다.")
                    total_code += 1
                    print("✓ " + Path(path).name + ": " + kind + " 서명·엄격 검증 " + str(attempt) + "/2 (암호 입력 없음)")
            if installers:
                unsigned = root / "unsigned.pkg"
                run(["/usr/bin/pkgbuild", "--nopayload", "--identifier", LABEL + ".probe", "--version", "1.0", unsigned])
                for item in installers:
                    for attempt in (1, 2):
                        signed = root / ("signed-" + str(attempt) + ".pkg")
                        signed.unlink(missing_ok=True)
                        monitor.sign(["/usr/bin/productsign", "--sign", item["name"], "--keychain", path, "--timestamp=none", unsigned, signed])
                        output = run(["/usr/sbin/pkgutil", "--check-signature", signed]).stdout
                        if item["name"] not in output or "signed by a certificate trusted" not in output:
                            raise RuntimeError("패키지 서명 신뢰 검증 실패")
                        total_package += 1
                        print("✓ " + Path(path).name + ": 패키지 서명·pkgutil 검증 " + str(attempt) + "/2 (암호 입력 없음)")
            if not groups and not installers:
                reason = "서명용 인증서·개인 키 쌍 없음" if not all_identities else "유효한 코드·설치 패키지 서명 인증서 없음"
                unavailable.append({"keychain": path, "reason": reason})
                print("— " + Path(path).name + ": " + reason)
    print(json.dumps({"codesign_passed": total_code, "productsign_passed": total_package,
                      "unavailable": unavailable, "temporary_files_cleaned": True}, ensure_ascii=False))


def uninstall(_args):
    stop_agent()
    if HELPER.is_file():
        # 중도 실패로 config가 없더라도 이 helper의 전용 service 항목만 정리한다.
        run([HELPER, "forget-all", Path.home() / "Library/Keychains/login.keychain-db"])
    AGENT.unlink(missing_ok=True)
    if ROOT.exists():
        shutil.rmtree(ROOT)
    print("✓ 로그인 자동 해제·전용 helper·암호화 캐시 제거 완료")


def main():
    parser = argparse.ArgumentParser(description="1Password 원본 + login 암호화 캐시로 서명 키체인을 로그인 뒤 자동 해제합니다.")
    parser.add_argument("action", choices=("install", "refresh", "status", "verify", "uninstall"), nargs="?", default="status")
    laputa = parser.add_mutually_exclusive_group()
    laputa.add_argument("--laputa-ref", help="laputa 키체인 암호의 op:// 참조")
    laputa.add_argument("--laputa-stdin", action="store_true", help="1Password 공유 항목 최초 이전용: 암호를 파이프로만 받아 helper에 직접 전달")
    fastlane = parser.add_mutually_exclusive_group()
    fastlane.add_argument("--fastlane-ref", help="fastlane_tmp 키체인 암호의 op:// 참조")
    fastlane.add_argument("--fastlane-empty", action="store_true", help="실제 fastlane_tmp 암호가 비어 있음을 명시 (잠금→해제로 검증)")
    parser.add_argument("--laputa-keychain", help="목록에서 찾을 laputa 키체인 경로 또는 이름")
    parser.add_argument("--fastlane-keychain", help="목록에서 찾을 fastlane_tmp 키체인 경로 또는 이름")
    parser.add_argument("--account", default=ACCOUNT, help="1Password 계정 주소")
    parser.add_argument("--identity", help="helper 서명에 사용할 유효한 codesigning identity")
    args = parser.parse_args()
    if sys.platform != "darwin" or os.getuid() == 0:
        parser.error("macOS 사용자 계정으로 실행하세요. sudo로 실행하지 마세요.")
    try:
        {"install": install, "refresh": refresh, "status": status, "verify": verify, "uninstall": uninstall}[args.action](args)
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        # 원본 조회·등록이 실패해도 이미 설치된 로그인 작업이 영구 중지되지 않게 한다.
        if args.action == "install" and AGENT.is_file() and HELPER.is_file() and CONFIG.is_file():
            try:
                run(["/bin/launchctl", "bootstrap", DOMAIN, AGENT], check=False)
            except (OSError, subprocess.TimeoutExpired):
                pass
        print("⚠ " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
