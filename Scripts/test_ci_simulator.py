"""Run the actual workflow preparation block with isolated fake Xcode tools."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


FAKE = r'''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["RUNNER_TEMP"])
args = sys.argv[1:]
scenario = os.environ["SCENARIO"]
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps([pathlib.Path(sys.argv[0]).name] + args) + "\n")
if pathlib.Path(sys.argv[0]).name == "xcodebuild":
    if scenario == "download-failure": sys.exit(71)
    (root / "installed").write_text(args[args.index("-buildVersion") + 1])
elif args[:2] == ["simctl", "create"]:
    (root / "created").touch()
    print("created-id")
elif args[:2] == ["simctl", "list"]:
    runtime = os.environ["EXPECTED_IOS_RUNTIME"]
    available = scenario not in ["missing", "download-failure", "no-runtime-after-install", "duo-only"]
    installed = (root / "installed").read_text() if (root / "installed").exists() else ""
    # CI run 41186673111: selecting release 27.2 downloads the Duo-only
    # 24B91014 image. Requesting the exact general build is required.
    available |= installed == "24B8117" and scenario != "no-runtime-after-install"
    entry = {"identifier": runtime, "platform":"iOS", "version":"27.2",
             "buildversion":"wrong" if scenario == "wrong-build" else "24B8117",
             "isAvailable":True, "supportedDeviceTypes":[] if scenario == "wrong-profile" else
             [{"identifier":os.environ["CI_DEVICE_TYPE"]}]}
    entries = [entry] if available else []
    if scenario == "duo-only" or installed == "27.2":
        entries.insert(0, json.loads(pathlib.Path(os.environ["DUO_RUNTIME_FIXTURE"]).read_text()))
    device = {"udid":"created-id" if (root / "created").exists() else "existing-id",
              "isAvailable":True, "deviceTypeIdentifier":os.environ["CI_DEVICE_TYPE"]}
    devices = {runtime:[device] if scenario == "existing" or (root / "created").exists() else []}
    print(json.dumps({"runtimes":entries,"devices":devices}))
'''


class CISimulatorPreparation(unittest.TestCase):
    def run_preparation(self, scenario):
        with tempfile.TemporaryDirectory(prefix="rssreader-ci-prep-") as directory:
            root = Path(directory)
            binaries = root / "bin"
            binaries.mkdir()
            for name in ["xcodebuild", "xcrun"]:
                tool = binaries / name
                tool.write_text(f"#!{sys.executable}\n" + FAKE)
                tool.chmod(0o755)
            workflow = (Path(__file__).resolve().parent.parent / ".github/workflows/validation.yml").read_text()
            step = workflow.split("      - name: Prepare minimum-runtime simulator\n", 1)[1].split("      - name:", 1)[0]
            body = step.split("        run: |\n", 1)[1]
            shell = "\n".join(line[10:] for line in body.splitlines() if line.strip())
            artifacts = root / "rssreader-ci"
            artifacts.mkdir()
            environment = dict(os.environ, PATH=str(binaries) + os.pathsep + os.environ["PATH"],
                               RUNNER_TEMP=str(root), GITHUB_ENV=str(root / "github-env"),
                               SCENARIO=scenario, EXPECTED_IOS_VERSION="27.2",
                               EXPECTED_IOS_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                               EXPECTED_IOS_RUNTIME_BUILD="24B8117",
                               DUO_RUNTIME_FIXTURE=str(Path(__file__).with_name("Fixtures") / "ci-ios-27.2-duo-runtime.json"),
                               CI_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro")
            # The preceding workflow step captures this initial inventory.
            inventory = subprocess.run([str(binaries / "xcrun"), "simctl", "list", "--json", "devices", "runtimes"],
                                       env=environment, capture_output=True, check=True)
            (artifacts / "simulators.json").write_bytes(inventory.stdout)
            result = subprocess.run(["/bin/bash", "-c", shell], env=environment, text=True, capture_output=True)
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text().splitlines()]
            destination = (root / "github-env").read_text() if (root / "github-env").exists() else ""
            return result, calls, destination

    def test_reuses_existing_exact_runtime_and_device(self):
        result, calls, destination = self.run_preparation("existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("id=existing-id", destination)
        self.assertFalse(any(call[0] == "xcodebuild" or call[1:3] == ["simctl", "create"] for call in calls))

    def test_explicit_download_and_creation_use_general_hardware_image(self):
        for scenario in ["missing", "duo-only"]:
            with self.subTest(scenario=scenario):
                result, calls, destination = self.run_preparation(scenario)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(["xcodebuild", "-downloadPlatform", "iOS", "-buildVersion", "24B8117",
                               "-architectureVariant", "arm64"], calls)
                create = next(call for call in calls if call[1:3] == ["simctl", "create"])
                self.assertEqual(create[-1], "com.apple.CoreSimulator.SimRuntime.iOS-27-2")
                self.assertIn("id=created-id", destination)

    def test_wrong_build_profile_or_missing_runtime_never_boots(self):
        for scenario in ["wrong-build", "wrong-profile", "no-runtime-after-install"]:
            with self.subTest(scenario=scenario):
                result, calls, destination = self.run_preparation(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(destination, "")
                self.assertFalse(any(call[1:3] == ["simctl", "bootstatus"] for call in calls))

    def test_download_failure_preserves_status(self):
        result, calls, destination = self.run_preparation("download-failure")
        self.assertEqual(result.returncode, 71)
        self.assertEqual(destination, "")
        self.assertFalse(any(call[1:3] == ["simctl", "create"] for call in calls))


if __name__ == "__main__":
    unittest.main(verbosity=2)
