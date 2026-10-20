"""Exercise CLI failure contracts with fake Xcode tools; no simulator required."""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest


FAKE = r'''
import json, os, pathlib, sys
a = sys.argv[1:]
scenario = os.environ.get("SCENARIO", "ok")
if scenario == "diagnostic-stderr": print("Simulator diagnostic fixture", file=sys.stderr)
def emit(value): print(json.dumps(value))
if pathlib.Path(sys.argv[0]).name == "xcodebuild":
    if "-version" in a: print("Xcode fixture")
    elif "-list" in a: emit({"project":{"schemes":["RSSReader"]}})
    elif "-showdestinations" in a: print("fixture simulator")
    elif "-showBuildSettings" in a:
        if "-destination" in a and "missing" in a[a.index("-destination")+1]: sys.exit(70)
        emit([{"target":t,"buildSettings":{"IPHONEOS_DEPLOYMENT_TARGET":"27.0",
              "TARGETED_DEVICE_FAMILY":"1,2"}} for t in ["RSSReader","RSSReaderTests"]])
    elif "test" in a:
        pathlib.Path(a[a.index("-resultBundlePath")+1]).mkdir()
        if scenario.startswith("test-failure"): sys.exit(65)
    elif scenario == "build-failure": sys.exit(42)
else:
    if a[:2] == ["swift","--version"]: print("Swift fixture")
    elif "--show-sdk-version" in a: print("26.0" if scenario == "old-sdk" else "27.1")
    elif a[0] == "simctl":
        emit({"runtimes":[] if scenario == "missing-runtime" else [
          {"identifier":"runtime","platform":"iOS","version":"27.0","isAvailable":True}],
          "devices":{"runtime":[] if scenario == "missing-simulator" else [
          {"udid":"fixture-id","isAvailable":True}]}})
    elif "summary" in a:
        if scenario == "report-tool-failure": sys.exit(44)
        if scenario in ["malformed-report", "test-failure-malformed"]: print("not json"); sys.exit(0)
        emit({"totalTestCount":0 if scenario == "zero-tests" else 1,
          "passedTests":0 if scenario == "zero-tests" else 1,"failedTests":0,
          "skippedTests":0,"expectedFailures":0,"result":"Passed"})
    elif "tests" in a:
        emit({"testNodes":[{"nodeType":"Test Case","name":"example",
          "result":"No result" if scenario == "no-result" else "Passed",
          "children":[{"nodeType":"Arguments","name":"parameter","result":"No result"}]
          if scenario == "parameter-no-result" else []}]})
'''


class ValidationCLI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="rssreader-cli-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "checkout with spaces"
        scripts = self.repo / "Scripts"
        scripts.mkdir(parents=True)
        self.script = scripts / "validate.sh"
        shutil.copy2(Path(__file__).with_name("validate.sh"), self.script)
        scheme = self.repo / "RSSReader.xcodeproj/xcshareddata/xcschemes"
        scheme.mkdir(parents=True)
        shutil.copy2(Path(__file__).resolve().parent.parent /
                     "RSSReader.xcodeproj/xcshareddata/xcschemes/RSSReader.xcscheme", scheme)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ["jq", "xmllint", "tee", "mktemp", "dirname", "mkdir", "cat"]:
            (self.bin / name).symlink_to(shutil.which(name))
        for name in ["xcodebuild", "xcrun"]:
            tool = self.bin / name
            tool.write_text(f"#!{sys.executable}\n" + FAKE)
            tool.chmod(0o755)

    def run_cli(self, *args, scenario="ok"):
        env = dict(os.environ, PATH=str(self.bin), SCENARIO=scenario)
        result = subprocess.run(["/bin/bash", str(self.script), *args,
                                 "--artifacts-dir", str(self.root / "artifacts")],
                                cwd=self.root, env=env, text=True, capture_output=True)
        return result

    def artifact(self, filename):
        return next((self.root / "artifacts").glob(f"*/{filename}"))

    def test_success_from_another_directory_with_spaces(self):
        result = self.run_cli("fast")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(self.artifact("report.json").read_text())["executed"], 1)
        commands = self.artifact("commands.sh").read_text()
        self.assertIn("-only-testing:RSSReaderTests/FeedRSSParserTests", commands)
        self.assertNotIn("parallel-testing-enabled", commands)

    def test_full_selection_and_clean(self):
        result = self.run_cli("full")
        self.assertEqual(result.returncode, 0, result.stderr)
        commands = self.artifact("commands.sh").read_text()
        self.assertIn("clean build", commands)
        self.assertIn("-only-testing:RSSReaderTests ", commands)
        self.assertNotIn("-only-testing:RSSReaderTests/", commands)

    def test_stderr_diagnostics_do_not_corrupt_json_or_sdk_output(self):
        result = self.run_cli("full", scenario="diagnostic-stderr")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for label in ["project", "settings-Debug", "settings-Release", "destination-settings", "summary", "test-tree"]:
            with self.subTest(label=label):
                json.loads(self.artifact(f"{label}.log").read_text())
                self.assertIn("Simulator diagnostic fixture", self.artifact(f"{label}.stderr.log").read_text())
        self.assertEqual(self.artifact("sdk-version.log").read_text().strip(), "27.1")

    def test_invalid_arguments(self):
        for args in [("invalid",), ("fast", "--unknown"), ("fast", "--destination"),
                     ("fast", "--fresh", "--derived-data", "cache")]:
            with self.subTest(args=args):
                self.assertEqual(self.run_cli(*args).returncode, 2)

    def test_missing_prerequisite(self):
        (self.bin / "jq").unlink()
        result = self.run_cli("fast")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Missing prerequisite: jq", result.stderr)

    def test_runtime_sdk_and_simulator_failures(self):
        for scenario in ["missing-runtime", "missing-simulator", "old-sdk"]:
            with self.subTest(scenario=scenario):
                self.assertNotEqual(self.run_cli("fast", scenario=scenario).returncode, 0)

    def test_unavailable_destination_preserves_status(self):
        result = self.run_cli("fast", "--destination", "platform=iOS Simulator,name=missing")
        self.assertEqual(result.returncode, 70)

    def test_build_failure_preserves_status_and_log(self):
        result = self.run_cli("fast", scenario="build-failure")
        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.artifact("build.exit-status").read_text().strip(), "42")
        self.assertFalse(list((self.root / "artifacts").glob("*/tests.log")))

    def test_test_failure_still_extracts_report(self):
        result = self.run_cli("full", scenario="test-failure")
        self.assertEqual(result.returncode, 65)
        self.assertTrue(self.artifact("report.json").exists())

    def test_logger_failure_does_not_hide_xcode_failure(self):
        real_tee = shlex.quote(shutil.which("tee"))
        logger = self.bin / "tee"
        logger.unlink()
        logger.write_text('#!/bin/bash\nif [[ "$1" == */tests.log ]]; then exit 9; fi\n'
                          f'exec {real_tee} "$@"\n')
        logger.chmod(0o755)
        self.assertEqual(self.run_cli("full").returncode, 9)
        self.assertEqual(self.run_cli("full", scenario="test-failure").returncode, 65)

    def test_malformed_report_does_not_hide_test_failure(self):
        self.assertEqual(self.run_cli("full", scenario="test-failure-malformed").returncode, 65)

    def test_parallel_scheme_is_rejected(self):
        scheme = next(self.repo.glob("**/*.xcscheme"))
        scheme.write_text(scheme.read_text().replace('parallelizable = "NO"', 'parallelizable = "YES"'))
        result = self.run_cli("full")
        self.assertEqual(result.returncode, 2)
        self.assertIn("must remain serial", result.stderr)

    def test_unpinned_test_locale_is_rejected(self):
        scheme = next(self.repo.glob("**/*.xcscheme"))
        scheme.write_text(scheme.read_text().replace('language = "ru"', 'language = "en"'))
        result = self.run_cli("full")
        self.assertEqual(result.returncode, 2)
        self.assertIn("ru/RU baseline", result.stderr)

    def test_zero_tests_and_no_result_are_not_success(self):
        for scenario in ["zero-tests", "no-result", "parameter-no-result", "malformed-report"]:
            with self.subTest(scenario=scenario):
                self.assertEqual(self.run_cli("fast", scenario=scenario).returncode, 3)

    def test_report_tool_failure(self):
        self.assertEqual(self.run_cli("fast", scenario="report-tool-failure").returncode, 44)

    def test_invalid_toolchain(self):
        result = self.run_cli("fast", "--developer-dir", "missing-xcode")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Developer directory does not exist", result.stderr)

    def test_foreign_derived_data_is_preserved(self):
        foreign = self.root / "foreign"
        foreign.mkdir()
        sentinel = foreign / "keep.txt"
        sentinel.write_text("preserved")
        result = self.run_cli("full", "--derived-data", str(foreign))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(sentinel.read_text(), "preserved")

    def test_owned_derived_data_reuse_and_unique_artifacts(self):
        for _ in range(2):
            result = self.run_cli("fast", "--derived-data", "cache with spaces")
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list((self.root / "artifacts").iterdir())), 2)

    def test_ui_requires_enabled_shared_scheme_target(self):
        result = self.run_cli("fast", "--ui-smoke-target", "MissingUITests")
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires #720", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
