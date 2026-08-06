#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# publish_testflight.sh — build, archive, and upload Reflect (iOS, with the
# ReflectClip App Clip embedded) to TestFlight via App Store Connect.
#
# Interactive by default — prompts you to pick the branch and the build
# configuration (Release recommended). Both can also be passed as flags for
# non-interactive use.
#
# Pipeline: checkout branch → build gate (Reflect + ReflectClip schemes,
# Debug, simulator — this repo has no test target, so this grep-for-"error:"
# build is the quality gate per CLAUDE.md) → bump build number (commit + tag)
# → xcodebuild archive (Release, generic/platform=iOS; archiving the Reflect
# scheme also embeds ReflectClip automatically via its "Embed App Clips"
# build phase — do not archive ReflectClip separately) → xcodebuild
# -exportArchive (destination: upload — uses the Apple ID signed into Xcode,
# no altool/API key needed). Any failed step aborts before it reaches upload,
# and the original branch is always restored on exit.
#
# Build number: CURRENT_PROJECT_VERSION in Reflect.xcodeproj/project.pbxproj
# (GENERATE_INFOPLIST_FILE=YES for the Reflect/Quick-Actions targets, so
# there's no CFBundleVersion literal in an Info.plist to bump — the pbxproj
# build setting is the source of truth) is auto-incremented across every
# occurrence and committed (chore commit) before every archive, so App Store
# Connect never rejects the upload with ITMS-90189 "Redundant Binary Upload".
# MARKETING_VERSION (CFBundleShortVersionString) is left untouched — bump
# that by hand in project.pbxproj when you cut a new release.
#
# Export compliance: this repo's Info.plist files do not currently declare
# ITSAppUsesNonExemptEncryption. That's fine for upload — xcodebuild's
# destination:upload mode does not block on it — but the build will sit as
# "Missing Compliance" in App Store Connect until you answer the encryption
# question there (or add ITSAppUsesNonExemptEncryption to Reflect/Info.plist
# by hand once you've confirmed the app only uses standard HTTPS/CryptoKit
# and no custom/proprietary encryption).
#
# This script does NOT auto-deliver to an external TestFlight group (Family
# Money's sibling script has an --external-group + App Store Connect API-key
# flow for that; Reflect has no such API key configured yet). After a
# successful upload, add the build to a testing group by hand in App Store
# Connect → TestFlight.
#
# Usage:
#   ./scripts/publish_testflight.sh                        # interactive branch + config picker
#   ./scripts/publish_testflight.sh --branch develop --release
#   ./scripts/publish_testflight.sh --branch develop --debug
#   ./scripts/publish_testflight.sh --dry-run                # archive + export only, no upload
#   ./scripts/publish_testflight.sh --skip-build-gate        # skip the Debug build gate (not recommended)
#   ./scripts/publish_testflight.sh -h | --help
#
# Upload auth: none needed from this script — xcodebuild uploads using
# whichever Apple ID is signed into Xcode (Xcode → Settings → Accounts) and
# that has upload access to team 9NAU7R3577.
#
# Requires: Xcode signed into an Apple ID with upload access to team
# 9NAU7R3577, a Distribution certificate + App Store provisioning profiles
# for BOTH xyz.nandamochammad.Reflect and xyz.nandamochammad.Reflect.Clip
# available to automatic signing, and a clean working tree (uncommitted
# changes abort before any branch switch).
# ─────────────────────────────────────────────────────────────────────────────

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

PROJECT="Reflect.xcodeproj"
PBXPROJ="Reflect.xcodeproj/project.pbxproj"
APP_SCHEME="Reflect"
CLIP_SCHEME="ReflectClip"
BUNDLE_ID="xyz.nandamochammad.Reflect"
EXPORT_OPTIONS="scripts/ExportOptions.plist"
ARCHIVE_ROOT="build/testflight"
SIM_DESTINATION="platform=iOS Simulator,name=iPhone 17"

# ── Parse flags ────────────────────────────────────────────────────────────────
BRANCH=""; CONFIG=""; SKIP_BUILD_GATE=0; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)            BRANCH="${2:-}"; shift 2 ;;
    --branch=*)          BRANCH="${1#*=}"; shift ;;
    --release)           CONFIG="Release"; shift ;;
    --debug)             CONFIG="Debug"; shift ;;
    --configuration)     CONFIG="${2:-}"; shift 2 ;;
    --skip-build-gate)   SKIP_BUILD_GATE=1; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo -e "${RED}Error:${RESET} unknown argument '$1' (try --help)"
      exit 1 ;;
  esac
done

if [[ -n "$CONFIG" && "$CONFIG" != "Release" && "$CONFIG" != "Debug" ]]; then
  echo -e "${RED}Error:${RESET} --configuration must be 'Release' or 'Debug', got '$CONFIG'"
  exit 1
fi

echo -e "${BOLD}${CYAN}publish_testflight.sh${RESET}"

# ── Require a clean working tree BEFORE touching branches ─────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
  echo -e "${RED}Error:${RESET} working tree has uncommitted changes. Commit or stash them first —"
  echo -e "  this script checks out a branch and will not risk carrying your changes across."
  git status --short | sed 's/^/    /'
  exit 1
fi

ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
SWITCHED=0
restore_branch() {
  if [[ $SWITCHED -eq 1 ]]; then
    local current
    current="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    if [[ "$current" != "$ORIGINAL_BRANCH" ]]; then
      echo -e "${YELLOW}▶${RESET} restoring original branch ${BOLD}$ORIGINAL_BRANCH${RESET}…"
      git checkout --quiet "$ORIGINAL_BRANCH" 2>/dev/null || true
    fi
  fi
}
trap restore_branch EXIT

# ── Pick the branch (flag wins; else interactive) ──────────────────────────────
if [[ -z "$BRANCH" ]]; then
  echo -e "${YELLOW}▶${RESET} fetching remote branches…"
  git fetch --quiet --prune

  mapfile -t LOCAL_BRANCHES < <(git for-each-ref --format='%(refname:short)' refs/heads/ | sort)
  echo ""
  echo -e "${BOLD}Branches:${RESET}"
  for i in "${!LOCAL_BRANCHES[@]}"; do
    marker=" "
    [[ "${LOCAL_BRANCHES[$i]}" == "$ORIGINAL_BRANCH" ]] && marker="${GREEN}*${RESET}"
    printf "  %s %2d) %s\n" "$marker" "$((i + 1))" "${LOCAL_BRANCHES[$i]}"
  done
  echo ""
  read -r -p "Select a branch [number or name, default: current ($ORIGINAL_BRANCH)]: " SEL
  if [[ -z "$SEL" ]]; then
    BRANCH="$ORIGINAL_BRANCH"
  elif [[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 1 && SEL <= ${#LOCAL_BRANCHES[@]} )); then
    BRANCH="${LOCAL_BRANCHES[$((SEL - 1))]}"
  else
    BRANCH="$SEL"
  fi
fi

# ── Pick the configuration (flag wins; else interactive) ───────────────────────
if [[ -z "$CONFIG" ]]; then
  echo ""
  echo -e "${BOLD}Configuration:${RESET}"
  echo "    1) Release  (recommended for TestFlight)"
  echo "    2) Debug"
  read -r -p "Select [1/2, default: 1]: " CSEL
  case "${CSEL:-1}" in
    2) CONFIG="Debug" ;;
    *) CONFIG="Release" ;;
  esac
fi

echo ""
echo -e "  branch:        ${BOLD}$BRANCH${RESET}"
echo -e "  configuration: ${BOLD}$CONFIG${RESET}"
echo -e "  build gate:    $([[ $SKIP_BUILD_GATE -eq 1 ]] && echo 'SKIPPED' || echo 'will run (Reflect + ReflectClip, Debug, simulator)')"
echo -e "  mode:          $([[ $DRY_RUN -eq 1 ]] && echo 'dry-run (no upload)' || echo 'full publish')"
echo ""
read -r -p "Proceed? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# ── Checkout the branch ────────────────────────────────────────────────────────
echo -e "${YELLOW}▶${RESET} checking out ${BOLD}$BRANCH${RESET}…"
if git checkout --quiet "$BRANCH" 2>/dev/null; then
  :
elif git checkout --quiet -t "origin/$BRANCH" 2>/dev/null; then
  :
else
  echo -e "${RED}✗ no such branch${RESET} '$BRANCH' locally or on origin"
  exit 1
fi
SWITCHED=1
git pull --quiet --ff-only 2>/dev/null || echo -e "${YELLOW}  (no upstream / not fast-forwardable — continuing with local commit)${RESET}"

# ── Build gate (no test target exists in this repo — this is the quality gate) ─
if [[ $SKIP_BUILD_GATE -eq 0 ]]; then
  for scheme in "$APP_SCHEME" "$CLIP_SCHEME"; do
    echo -e "${YELLOW}▶${RESET} build gate: xcodebuild -scheme $scheme (Debug, simulator)…"
    GATE_LOG="/tmp/publish_testflight-gate-${scheme}.log"
    xcodebuild -project "$PROJECT" -scheme "$scheme" \
        -destination "$SIM_DESTINATION" -configuration Debug build >"$GATE_LOG" 2>&1
    if grep -q "error:" "$GATE_LOG" || ! grep -q "BUILD SUCCEEDED" "$GATE_LOG"; then
      echo -e "${RED}✗ build gate FAILED${RESET} for scheme $scheme → $GATE_LOG"
      grep -E "error:" "$GATE_LOG" | tail -20 | sed 's/^/    /'
      exit 1
    fi
    echo -e "  ${GREEN}✓${RESET} $scheme build gate passed"
  done
else
  echo -e "${YELLOW}▶${RESET} build gate skipped (--skip-build-gate)"
fi

# ── Bump build number (avoids ITMS-90189 "Redundant Binary Upload") ───────────
# GENERATE_INFOPLIST_FILE=YES for Reflect/Quick-Actions, NO for ReflectClip —
# either way CURRENT_PROJECT_VERSION in the pbxproj build settings is the
# single source of truth for CFBundleVersion across all targets.
echo -e "${YELLOW}▶${RESET} bumping build number…"
CURRENT_BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBXPROJ" | sed -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/')"
if ! [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}✗ could not read CURRENT_PROJECT_VERSION from $PBXPROJ${RESET} (got '$CURRENT_BUILD') — fix it by hand first."
  exit 1
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
# Bump every occurrence (Debug + Release, all 3 targets) in one pass.
sed -i '' -E "s/CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};/CURRENT_PROJECT_VERSION = ${NEW_BUILD};/g" "$PBXPROJ"
REMAINING_OLD="$(grep -c "CURRENT_PROJECT_VERSION = ${CURRENT_BUILD};" "$PBXPROJ" || true)"
if [[ "${REMAINING_OLD:-0}" -ne 0 ]]; then
  echo -e "${RED}✗ bump incomplete${RESET} — $REMAINING_OLD occurrence(s) of CURRENT_PROJECT_VERSION = ${CURRENT_BUILD} remain in $PBXPROJ"
  exit 1
fi
git add "$PBXPROJ"
git commit --quiet -m "chore: bump build number to $NEW_BUILD for TestFlight"
MARKETING_VERSION="$(grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed -E 's/.*MARKETING_VERSION = ([0-9.]+);.*/\1/')"
git tag "tf/${MARKETING_VERSION}-${NEW_BUILD}" --quiet
echo -e "  ${GREEN}✓${RESET} build ${BOLD}$CURRENT_BUILD${RESET} → ${BOLD}$NEW_BUILD${RESET} (committed + tagged ${BOLD}tf/${MARKETING_VERSION}-${NEW_BUILD}${RESET} on ${BOLD}$BRANCH${RESET} — push it yourself when ready)"

# ── Read version/build for archive naming ──────────────────────────────────────
VERSION="$MARKETING_VERSION"
BUILD="$NEW_BUILD"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BRANCH_SLUG="$(echo "$BRANCH" | tr '/' '-')"
ARCHIVE_NAME="Reflect-${VERSION}-${BUILD}-${BRANCH_SLUG}-${TIMESTAMP}"
ARCHIVE_PATH="$ARCHIVE_ROOT/${ARCHIVE_NAME}.xcarchive"
EXPORT_DIR="$ARCHIVE_ROOT/${ARCHIVE_NAME}-export"
mkdir -p "$ARCHIVE_ROOT"

echo ""
echo -e "  version: ${BOLD}${VERSION} (${BUILD})${RESET}"

# ── Archive (Reflect scheme only — embeds ReflectClip automatically) ──────────
echo -e "${YELLOW}▶${RESET} xcodebuild archive ($CONFIG)…"
ARCHIVE_LOG="/tmp/publish_testflight-archive.log"
if ! xcodebuild -project "$PROJECT" -scheme "$APP_SCHEME" -configuration "$CONFIG" \
      -archivePath "$ARCHIVE_PATH" -destination "generic/platform=iOS" \
      -allowProvisioningUpdates archive >"$ARCHIVE_LOG" 2>&1; then
  echo -e "${RED}✗ archive FAILED${RESET} → $ARCHIVE_LOG"
  grep -E 'error:|BUILD FAILED|Code Sign|Provisioning' "$ARCHIVE_LOG" | tail -20 | sed 's/^/    /'
  exit 1
fi
echo -e "  ${GREEN}✓ archived${RESET} → $ARCHIVE_PATH"

if [[ $DRY_RUN -eq 1 ]]; then
  # ── Export .ipa only, no upload ──────────────────────────────────────────────
  echo -e "${YELLOW}▶${RESET} xcodebuild -exportArchive (export only)…"
  EXPORT_LOG="/tmp/publish_testflight-export.log"
  if ! xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$EXPORT_DIR" >"$EXPORT_LOG" 2>&1; then
    echo -e "${RED}✗ export FAILED${RESET} → $EXPORT_LOG"
    grep -E 'error:|EXPORT FAILED' "$EXPORT_LOG" | tail -20 | sed 's/^/    /'
    exit 1
  fi
  IPA_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
  if [[ -z "$IPA_PATH" ]]; then
    echo -e "${RED}✗ export succeeded but no .ipa found${RESET} under $EXPORT_DIR"
    exit 1
  fi
  echo -e "  ${GREEN}✓ exported${RESET} → $IPA_PATH"
  echo ""
  echo -e "${GREEN}${BOLD}Dry run complete.${RESET} Archive + IPA are ready; upload was skipped (--dry-run)."
  exit 0
fi

# ── Export + upload to App Store Connect in one step ───────────────────────────
# xcodebuild's own `destination: upload` mode uploads straight from the archive
# using the Apple ID signed into Xcode (Xcode → Settings → Accounts) — no
# altool, no App Store Connect API key needed.
echo -e "${YELLOW}▶${RESET} xcodebuild -exportArchive (export + upload)…"
UPLOAD_OPTIONS="$ARCHIVE_ROOT/${ARCHIVE_NAME}-ExportOptions-upload.plist"
cp "$EXPORT_OPTIONS" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :destination string upload" "$UPLOAD_OPTIONS" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Set :destination upload" "$UPLOAD_OPTIONS"
UPLOAD_LOG="/tmp/publish_testflight-upload.log"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist "$UPLOAD_OPTIONS" -exportPath "$EXPORT_DIR" \
      -allowProvisioningUpdates >"$UPLOAD_LOG" 2>&1; then
  echo -e "${RED}✗ export/upload FAILED${RESET} → $UPLOAD_LOG"
  grep -E 'error:|EXPORT FAILED|Upload failed' "$UPLOAD_LOG" | tail -30 | sed 's/^/    /'
  echo "  If Xcode isn't signed into the right Apple ID: Xcode → Settings → Accounts."
  echo "  You can also open $ARCHIVE_PATH in Xcode Organizer and use Distribute App → App Store Connect."
  exit 1
fi

echo -e "  ${GREEN}✓ uploaded${RESET}"
echo ""
echo -e "${GREEN}${BOLD}Published.${RESET} Build ${VERSION} (${BUILD}) from ${BRANCH} (${CONFIG}) is processing in App Store Connect → TestFlight."
echo "  Add it to a testing group and set \"What to Test\" by hand — this script doesn't auto-deliver."
echo "  If ITSAppUsesNonExemptEncryption isn't declared, answer the encryption-compliance question there too."
