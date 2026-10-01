"""설치 없이 임시 홈에서 MCP 설정 병합을 검증한다. 실행: python3 -m unittest discover -s tests -v"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
NAMES = {"cob", "dart", "figma", "marionette", "atlassian", "mobbin", "slack", "zenhub", "chrome-devtools", "playwright"}
SCRIPTS = [ROOT / "macos/mac-setup.sh", ROOT / "linux/linux-setup.sh"]
WINDOWS = ROOT / "windows/win-setup.ps1"
IMAGE = "ghcr.io/sooperset/mcp-atlassian:latest"


class DefaultMcpTests(unittest.TestCase):
    def run_step(self, script, home):
        source = script.read_text()
        start = source.index('log "6.6. OpenCode CLI')
        block = source[start:source.index("\n# 7. oh-my-zsh", start)]
        env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / "별도 config"))
        for name in ("JIRA_API_TOKEN", "SLACK_TEAM_ID", "SLACK_BOT_TOKEN", "ZENHUB_API_TOKEN"):
            env[name] = "DO_NOT_SAVE_SYNTHETIC_SECRET"
        # CLI 설치·인증·MCP 연결은 실행하지 않는다. 실제 병합 코드만 그대로 실행한다.
        stubs = 'have() { command -v "$1" >/dev/null 2>&1; }; opencode() { :; }; log() { :; }; ok() { :; }; warn() { :; }; info() { :; }; '
        result = subprocess.run(["bash", "-e"], input=stubs + block, text=True, env=env, capture_output=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        return home / ".claude.json", home / "별도 config/opencode/opencode.json"

    def test_fresh_install_all_ten_and_client_specific_formats(self):
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                paths = self.run_step(script, Path(tmp))
                claude, opencode = [json.loads(path.read_text()) for path in paths]
                self.assertEqual(set(claude["mcpServers"]), NAMES)
                self.assertEqual(set(opencode["mcp"]), NAMES)
                self.assertEqual(opencode["$schema"], "https://opencode.ai/config.json")
                self.assertEqual(claude["mcpServers"]["atlassian"]["env"]["JIRA_API_TOKEN"], "${JIRA_API_TOKEN}")
                self.assertEqual(opencode["mcp"]["atlassian"]["environment"]["JIRA_API_TOKEN"], "{env:JIRA_API_TOKEN}")
                self.assertEqual(opencode["mcp"]["zenhub"]["headers"]["Authorization"], "{env:ZENHUB_API_TOKEN}")
                self.assertFalse(opencode["mcp"]["zenhub"]["oauth"])
                self.assertEqual(opencode["mcp"]["dart"]["command"], ["dart", "mcp-server"])
                self.assertIn("cob:cob_mcp", opencode["mcp"]["cob"]["command"])
                for entry in opencode["mcp"].values():
                    self.assertTrue(entry["enabled"])
                    self.assertIn(entry["type"], {"local", "remote"})
                    if entry["type"] == "local":
                        self.assertIsInstance(entry["command"], list)
                for path in paths:
                    self.assertNotIn("DO_NOT_SAVE_SYNTHETIC_SECRET", path.read_text())

    def test_merge_migration_backup_and_repeat_run(self):
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                home = Path(tmp)
                claude = home / ".claude.json"
                opencode = home / "별도 config/opencode/opencode.json"
                opencode.parent.mkdir(parents=True)
                original = {"projects": {"/user/work": {"trusted": True}}, "mcpServers": {
                    "personal": {"type": "stdio", "command": "user-server", "args": []},
                    "mcp-atlassian": {"command": "docker", "args": ["run", IMAGE]},
                    "dart": {"command": "old-dart", "args": [], "env": {"STALE": "remove"}},
                }}
                claude.write_text(json.dumps(original))
                custom = {"username": "팀원", "permission": {"edit": "ask"}, "mcp": {"personal": {"type": "remote", "url": "https://example.com/mcp"}}}
                opencode.write_text(json.dumps(custom))
                comment_config = opencode.with_suffix(".jsonc")
                comment_config.write_text('{ // 사용자 설정\n "mcp": {"personal": {"enabled": false}}\n}')
                self.run_step(script, home)
                after = json.loads(claude.read_text())
                self.assertEqual(after["projects"], original["projects"])
                self.assertEqual(after["mcpServers"]["personal"], original["mcpServers"]["personal"])
                self.assertNotIn("mcp-atlassian", after["mcpServers"])
                self.assertNotIn("env", after["mcpServers"]["dart"])
                self.assertEqual(json.loads(opencode.read_text())["permission"], custom["permission"])
                self.assertIn("// 사용자 설정", comment_config.read_text())
                before_repeat = [path.read_bytes() for path in (claude, opencode)]
                self.run_step(script, home)
                self.assertEqual(before_repeat, [path.read_bytes() for path in (claude, opencode)])
                self.assertEqual(json.loads(Path(str(claude) + ".bak").read_text()), original)
                self.assertEqual(json.loads(Path(str(opencode) + ".bak").read_text()), custom)

    def test_invalid_config_preserved_and_other_client_still_configured(self):
        for script in SCRIPTS:
            for invalid in ("{broken", "[]", '{"mcpServers": []}'):
                with self.subTest(script=script, invalid=invalid), tempfile.TemporaryDirectory() as tmp:
                    home = Path(tmp)
                    (home / ".claude.json").write_text(invalid)
                    claude, opencode = self.run_step(script, home)
                    self.assertEqual(claude.read_text(), invalid)
                    self.assertEqual(set(json.loads(opencode.read_text())["mcp"]), NAMES)
                    self.assertFalse(Path(str(claude) + ".bak").exists())

    def test_unrelated_legacy_name_not_deleted(self):
        for script in SCRIPTS:
            with self.subTest(script=script), tempfile.TemporaryDirectory() as tmp:
                home = Path(tmp)
                legacy = {"command": "custom-atlassian", "args": []}
                (home / ".claude.json").write_text(json.dumps({"mcpServers": {"mcp-atlassian": legacy}}))
                claude, _ = self.run_step(script, home)
                self.assertEqual(json.loads(claude.read_text())["mcpServers"]["mcp-atlassian"], legacy)

    def test_three_platform_definitions_match_except_windows_wrappers(self):
        definitions = []
        for script in SCRIPTS + [WINDOWS]:
            source = script.read_text(encoding="utf-8-sig")
            match = re.search(r"\n(\{\n  \"cob\".*?\n\})\n(?:MCP_JSON|'@)", source, re.S)
            values = json.loads(match.group(1))
            for entry in values.values():
                if entry.get("command") == "cmd":
                    self.assertEqual(entry["args"][0], "/c")
                    entry["command"] = entry["args"][1]
                    entry["args"] = entry["args"][2:]
            definitions.append(values)
        self.assertEqual(definitions[0], definitions[1])
        self.assertEqual(definitions[0], definitions[2])

    def test_file_encoding_and_documented_assets(self):
        self.assertTrue(WINDOWS.read_bytes().startswith(b"\xef\xbb\xbf"))
        for script in SCRIPTS:
            self.assertFalse(script.read_bytes().startswith(b"\xef\xbb\xbf"))
            self.assertNotIn(b"\r\n", script.read_bytes())
        for platform in ("macos", "windows", "linux"):
            readme = ROOT / platform / "README.md"
            text = readme.read_text()
            for name in NAMES:
                self.assertIn(f"`{name}`", text)
            for asset in re.findall(r'src="(assets/icons/[^\"]+)"', text):
                self.assertTrue((readme.parent / asset).is_file(), asset)
            old_guides = [line for line in text.splitlines() if '`mcp-atlassian`이 연결 실패' in line]
            self.assertFalse(old_guides, '\n'.join(json.dumps(line, ensure_ascii=False) for line in old_guides))

    @unittest.skipUnless(shutil.which("opencode"), "OpenCode CLI 미설치 — 설정 형식은 다른 테스트에서 확인")
    def test_opencode_cli_accepts_generated_config(self):
        binary = shutil.which("opencode")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            self.run_step(SCRIPTS[0], home)
            env = {key: value for key, value in os.environ.items() if not key.startswith("OPENCODE_")}
            env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / "별도 config"),
                       XDG_DATA_HOME=str(home / "data"), XDG_CACHE_HOME=str(home / "cache"),
                       OPENCODE_PURE="1", OPENCODE_DISABLE_PROJECT_CONFIG="1",
                       OPENCODE_DISABLE_DEFAULT_PLUGINS="1", OPENCODE_DISABLE_EXTERNAL_SKILLS="1")
            for name in ("JIRA_API_TOKEN", "SLACK_TEAM_ID", "SLACK_BOT_TOKEN", "ZENHUB_API_TOKEN"):
                env[name] = "SYNTHETIC_RUNTIME_TOKEN"
            result = subprocess.run([binary, "debug", "config", "--pure"], cwd=home, env=env,
                                    text=True, capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads(result.stdout)
            self.assertEqual(set(config["mcp"]), NAMES)
            self.assertEqual(config["mcp"]["dart"]["command"], ["dart", "mcp-server"])


if __name__ == "__main__":
    unittest.main()
