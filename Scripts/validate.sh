#!/bin/bash
# Repository-owned validation entry point. Compatible with macOS Bash 3.2.
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: Scripts/validate.sh fast|full [options]
  --destination SPEC       Concrete iOS Simulator destination (default: minimum iOS)
  --developer-dir PATH     Xcode Developer directory (also accepts DEVELOPER_DIR)
  --artifacts-dir PATH     Parent for a new, unique run directory (default: TMPDIR)
  --derived-data PATH      Reuse a validate.sh-owned directory; never a foreign one
  --fresh                  Explicit fresh baseline (default; conflicts with reuse)
  --ui-smoke-target NAME   Opt in to a UI target already included in the shared scheme
  --help                  Show usage
fast builds the app and runs four bounded unit suites. full cleans/builds and runs
all RSSReaderTests. Neither mode verifies UI unless explicitly opted in.
USAGE
}
die() { echo "ERROR: $*" >&2; exit 2; }
mode=${1:-}
case "$mode" in
    --help|-h) usage; exit 0 ;;
    fast|full) shift ;;
    *) usage >&2; die "Expected mode fast or full" ;;
esac
destination= artifact_parent=${TMPDIR:-/tmp} derived_data= fresh=0 ui_target=
while (($#)); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --fresh) fresh=1; shift ;;
        --destination|--developer-dir|--artifacts-dir|--derived-data|--ui-smoke-target)
            (($# >= 2)) && [[ -n "$2" && "$2" != --* ]] || die "Missing value for $1"
            case "$1" in
                --destination) destination=$2 ;;
                --developer-dir) export DEVELOPER_DIR=$2 ;;
                --artifacts-dir) artifact_parent=$2 ;;
                --derived-data) derived_data=$2 ;;
                --ui-smoke-target) ui_target=$2 ;;
            esac
            shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
[[ $fresh == 0 || -z "$derived_data" ]] || die "--fresh conflicts with --derived-data"
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    [[ -d "$DEVELOPER_DIR" ]] || die "Developer directory does not exist: $DEVELOPER_DIR"
    export DEVELOPER_DIR="$(cd "$DEVELOPER_DIR" && pwd -P)"
fi
for tool in xcodebuild xcrun jq xmllint tee tail mktemp; do
    command -v "$tool" >/dev/null || die "Missing prerequisite: $tool"
done
# Resolve repository independently of caller's working directory. Resolve user
# paths first so relative options remain relative to that working directory.
mkdir -p "$artifact_parent"
artifact_parent=$(cd "$artifact_parent" && pwd -P)
if [[ -n "$derived_data" ]]; then
    [[ "$derived_data" == /* ]] || derived_data="$PWD/$derived_data"
fi
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo"
run_dir=$(mktemp -d "$artifact_parent/RSSReader-validation-$mode.XXXXXX")
echo "Validation artifacts: $run_dir"
trap 'status=$?; echo "$status" > "$run_dir/exit-status.txt"; echo "Validation exit: $status; artifacts: $run_dir"' EXIT

# Every external phase records its own unformatted output and original status.
run() {
    local label=$1 status monitor_pid= monitor_status=0
    shift
    printf '%q ' "$@" >> "$run_dir/commands.sh"
    printf '\n' >> "$run_dir/commands.sh"
    echo "Starting phase: $label"
    # Xcode may emit simulator warnings on stderr even with -json. Keep the
    # machine-readable stdout intact and retain diagnostics as a sibling log.
    if [[ "$label" == build || "$label" == tests ]]; then
        # A Simulator descendant may inherit output descriptors. Do not make
        # command completion depend on a pipe reaching EOF in those descendants.
        : > "$run_dir/$label.log"
        tail -n +1 -f "$run_dir/$label.log" &
        monitor_pid=$!
    fi
    if "$@" > "$run_dir/$label.log" 2> "$run_dir/$label.stderr.log"; then status=0; else status=$?; fi
    if [[ -n "$monitor_pid" ]]; then
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid" 2>/dev/null || true
            wait "$monitor_pid" 2>/dev/null || true
        else
            wait "$monitor_pid" || monitor_status=$?
        fi
        # Include the final lines even when the command ended between tail polls.
        tail -n 20 "$run_dir/$label.log" || monitor_status=$?
        if ((status == 0)); then status=$monitor_status; fi
    fi
    echo "$status" > "$run_dir/$label.exit-status"
    echo "Completed phase: $label (exit $status)"
    if ((status != 0)); then
        if [[ "$label" != build && "$label" != tests ]]; then cat "$run_dir/$label.log" >&2; fi
        cat "$run_dir/$label.stderr.log" >&2
        echo "ERROR: $label failed ($status)" >&2
    fi
    return "$status"
}
run xcode-version xcodebuild -version
run swift-version xcrun swift --version
run sdk-version xcrun --sdk iphonesimulator --show-sdk-version
scheme_file=RSSReader.xcodeproj/xcshareddata/xcschemes/RSSReader.xcscheme
[[ -f "$scheme_file" ]] || die "Missing shared RSSReader scheme"
serial=$(xmllint --xpath 'string(//TestableReference[BuildableReference/@BlueprintName="RSSReaderTests"]/@parallelizable)' "$scheme_file")
[[ "$serial" == NO ]] || die "RSSReaderTests must remain serial in the shared scheme"
test_language=$(xmllint --xpath 'string(//TestAction/@language)' "$scheme_file")
test_region=$(xmllint --xpath 'string(//TestAction/@region)' "$scheme_file")
[[ "$test_language" == ru && "$test_region" == RU ]] || die "RSSReaderTests requires the shared ru/RU baseline"
if [[ -n "$ui_target" ]]; then
    [[ "$ui_target" != RSSReaderTests && "$ui_target" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Invalid UI smoke target"
    ui_present=$(xmllint --xpath "count(//TestableReference[@skipped='NO'][BuildableReference/@BlueprintName='$ui_target'])" "$scheme_file")
    [[ "$ui_present" == 1 ]] || die "UI smoke target is not enabled in shared scheme (requires #720)"
fi
run project xcodebuild -project RSSReader.xcodeproj -list -json
jq -e '.project.schemes | index("RSSReader") != null' "$run_dir/project.log" >/dev/null || die "RSSReader scheme unavailable"
for configuration in Debug Release; do
    run "settings-$configuration" xcodebuild -project RSSReader.xcodeproj -alltargets \
        -configuration "$configuration" -sdk iphonesimulator -showBuildSettings -json
done
minimum_ios=$(jq -er '[.[] | select(.target == "RSSReader")][0].buildSettings.IPHONEOS_DEPLOYMENT_TARGET' "$run_dir/settings-Debug.log")
for configuration in Debug Release; do
    jq -e --arg minimum "$minimum_ios" '
      ([.[].target] | index("RSSReader") != null and index("RSSReaderTests") != null
        and index("RSSReaderUITests") != null)
      and all(.[]; .buildSettings.IPHONEOS_DEPLOYMENT_TARGET == $minimum
        and .buildSettings.TARGETED_DEVICE_FAMILY == "1,2")
    ' "$run_dir/settings-$configuration.log" >/dev/null || die "Inconsistent platform baseline"
done
sdk=$(cat "$run_dir/sdk-version.log")
jq -en --arg sdk "$sdk" --arg minimum "$minimum_ios" '
  def version: split(".") | map(tonumber) | . + [0,0] | .[:3];
  ($sdk | version) >= ($minimum | version)
' >/dev/null || die "Simulator SDK $sdk is older than $minimum_ios"
run simulators xcrun simctl list --json devices runtimes
# Require minimum runtime even for an explicitly requested newer destination.
minimum_runtimes=$(jq -ec --arg minimum "$minimum_ios" '
  [.runtimes[] | select(.platform == "iOS" and .version == $minimum and .isAvailable) | .identifier]
  | if length > 0 then . else error("Minimum iOS runtime unavailable") end' "$run_dir/simulators.log")
# One OS version can have multiple hardware images (for example iPhone Duo).
# Join devices to their own runtime; never choose an arbitrary first image.
default_id=$(jq -er --argjson runtimes "$minimum_runtimes" '
  .devices as $devices |
  [$runtimes[] as $runtime | $devices[$runtime][]? | select(.isAvailable)
    | {runtime:$runtime, udid:.udid}] | sort_by(.runtime, .udid) | .[0].udid
  // error("No simulator for minimum runtime")' "$run_dir/simulators.log")
destination=${destination:-platform=iOS Simulator,id=$default_id}
[[ "$destination" == platform=iOS\ Simulator,* && "$destination" != *generic* ]] || die "A concrete iOS Simulator destination is required"
run destinations xcodebuild -project RSSReader.xcodeproj -scheme RSSReader -showdestinations
base=(xcodebuild -project RSSReader.xcodeproj -scheme RSSReader -configuration Debug -destination "$destination" -destination-timeout 30)
# This resolves the entire supplied spec through Xcode, including name/OS/arch.
run destination-settings "${base[@]}" -showBuildSettings -json

if [[ -z "$derived_data" ]]; then derived_data="$run_dir/DerivedData"; fi
if [[ -e "$derived_data" ]]; then
    [[ -d "$derived_data" && ! -L "$derived_data" && -f "$derived_data/.rssreader-validation-owner" ]] || die "Refusing foreign DerivedData: $derived_data"
    [[ "$(cat "$derived_data/.rssreader-validation-owner")" == "$repo" ]] || die "DerivedData belongs to another checkout"
else
    mkdir -p "$derived_data"
    echo "$repo" > "$derived_data/.rssreader-validation-owner"
fi
derived_data=$(cd "$derived_data" && pwd -P)
base+=(-derivedDataPath "$derived_data")
jq -n --arg mode "$mode" --arg destination "$destination" --arg minimum "$minimum_ios" \
    --arg derivedData "$derived_data" --arg artifacts "$run_dir" --arg ui "$ui_target" \
    '{mode:$mode,destination:$destination,minimumIOS:$minimum,derivedData:$derivedData,artifacts:$artifacts,uiSmokeTarget:$ui,testLanguage:"ru",testRegion:"RU"}' > "$run_dir/context.json"
echo "Mode: $mode; destination: $destination; DerivedData: $derived_data"
if [[ "$mode" == full ]]; then run build "${base[@]}" clean build; else run build "${base[@]}" build; fi
selection=(-only-testing:RSSReaderTests)
if [[ "$mode" == fast ]]; then
    selection=()
    for suite in FeedRSSParserTests FeedAtomParserTests ArticleRetentionContractTests AppResourceBudgetContractTests; do
        selection+=("-only-testing:RSSReaderTests/$suite")
    done
fi
if [[ -n "$ui_target" ]]; then selection+=("-only-testing:$ui_target"); fi
test_status=0
run tests "${base[@]}" -resultBundlePath "$run_dir/Tests.xcresult" test "${selection[@]}" || test_status=$?
# Extract available evidence even if xcodebuild failed. Never replace its status.
report_status=0
run summary xcrun xcresulttool get test-results summary --path "$run_dir/Tests.xcresult" || report_status=$?
run test-tree xcrun xcresulttool get test-results tests --path "$run_dir/Tests.xcresult" || report_status=$?
if ((report_status == 0)); then
    jq -n --slurpfile summary "$run_dir/summary.log" --slurpfile tree "$run_dir/test-tree.log" '
      $summary[0] as $s |
      [$tree[0].testNodes[] | recurse(.children[]?) |
        select(.nodeType == "Test Case" or .nodeType == "Arguments" or .nodeType == "Test Case Run") |
        select((.result // "No result") as $r | ["Passed","Failed","Skipped","Expected Failure"] | index($r) == null) |
        {name, nodeIdentifier, result:(.result // "No result")}] as $missing |
      {total:$s.totalTestCount, passed:$s.passedTests, failed:$s.failedTests,
       skipped:$s.skippedTests, expectedFailures:$s.expectedFailures,
       executed:($s.passedTests + $s.failedTests + $s.expectedFailures),
       runs:([$s.devicesAndConfigurations[]? |
         {passed:.passedTests, failed:.failedTests, skipped:.skippedTests, expectedFailures:.expectedFailures}]),
       noResult:$missing, result:$s.result}
    ' | tee "$run_dir/report.json" || report_status=3
    jq -e '.executed > 0 and .failed == 0 and (.noResult | length) == 0 and .result == "Passed"' "$run_dir/report.json" >/dev/null || report_status=3
fi
echo "UI smoke target: ${ui_target:-not run}; visual correctness: not verified"
((test_status == 0)) || exit "$test_status"
((report_status == 0)) || exit "$report_status"
