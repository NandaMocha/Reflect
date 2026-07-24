#!/bin/sh

# ci_pre_xcodebuild.sh
#
# Xcode Cloud runs this automatically before `xcodebuild`, once per build.
# It stamps the Xcode Cloud build number ($CI_BUILD_NUMBER) into
# CURRENT_PROJECT_VERSION for every target in the project, so the app and its
# "Quick Actions" extension always ship with a matching, monotonically
# increasing build number — no manual bumping required.
#
# Why CURRENT_PROJECT_VERSION and not the Info.plist: this project sets
# GENERATE_INFOPLIST_FILE = YES with no hardcoded CFBundleVersion, so the
# generated Info.plist derives CFBundleVersion from CURRENT_PROJECT_VERSION.
# Rewriting that one setting is enough to move the build number everywhere.
#
# Runs only inside Xcode Cloud (where CI_BUILD_NUMBER is defined); a no-op
# for local builds.

set -e

if [ -z "$CI_BUILD_NUMBER" ]; then
    echo "CI_BUILD_NUMBER is not set — not an Xcode Cloud build. Skipping version stamp."
    exit 0
fi

PROJECT_FILE="$CI_PRIMARY_REPOSITORY_PATH/Reflect.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT_FILE" ]; then
    echo "error: could not find project file at $PROJECT_FILE" >&2
    exit 1
fi

echo "Setting CURRENT_PROJECT_VERSION to Xcode Cloud build number: $CI_BUILD_NUMBER"

# Replace every CURRENT_PROJECT_VERSION assignment (all targets, all configs).
sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/g" "$PROJECT_FILE"

echo "Updated build number in $PROJECT_FILE:"
grep "CURRENT_PROJECT_VERSION" "$PROJECT_FILE"
