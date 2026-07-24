#!/bin/sh

# ci_pre_xcodebuild.sh
#
# Xcode Cloud runs this automatically before `xcodebuild`, once per build.
# It stamps the Xcode Cloud build number ($CI_BUILD_NUMBER) into
# CURRENT_PROJECT_VERSION for every target in the project, so the app and its
# "Quick Actions" extension always ship with a matching, monotonically
# increasing build number — no manual bumping required.
#
# BUILD_NUMBER_OFFSET: Xcode Cloud's $CI_BUILD_NUMBER starts at 1 and counts up
# per workflow. Builds up to 4 were already uploaded to App Store Connect
# manually, so a raw CI_BUILD_NUMBER would collide with them (ITMS-90189
# "Redundant Binary Upload") until it naturally climbed past 4. The offset
# lifts every stamped build well above those existing builds while preserving
# the monotonic increment. Raise it again only if you ever upload a build
# numbered >= (offset + current CI_BUILD_NUMBER) by some other route.
#
# Why CURRENT_PROJECT_VERSION and not the Info.plist: this project sets
# GENERATE_INFOPLIST_FILE = YES with no hardcoded CFBundleVersion, so the
# generated Info.plist derives CFBundleVersion from CURRENT_PROJECT_VERSION.
# Rewriting that one setting is enough to move the build number everywhere.
#
# Runs only inside Xcode Cloud (where CI_BUILD_NUMBER is defined); a no-op
# for local builds.

set -e

BUILD_NUMBER_OFFSET=100

if [ -z "$CI_BUILD_NUMBER" ]; then
    echo "CI_BUILD_NUMBER is not set — not an Xcode Cloud build. Skipping version stamp."
    exit 0
fi

PROJECT_FILE="$CI_PRIMARY_REPOSITORY_PATH/Reflect.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "error: could not find project file at $PROJECT_FILE" >&2
    exit 1
fi

BUILD_NUMBER=$((CI_BUILD_NUMBER + BUILD_NUMBER_OFFSET))

echo "Xcode Cloud build number: $CI_BUILD_NUMBER (+ offset $BUILD_NUMBER_OFFSET) -> CURRENT_PROJECT_VERSION $BUILD_NUMBER"

# Replace every CURRENT_PROJECT_VERSION assignment (all targets, all configs).
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE"

echo "Updated build number in $PROJECT_FILE:"
grep "CURRENT_PROJECT_VERSION" "$PROJECT_FILE"
