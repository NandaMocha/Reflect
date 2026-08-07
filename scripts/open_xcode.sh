#!/bin/bash
# Opens Reflect.xcodeproj in Xcode from the repo root, regardless of cwd.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
open "$REPO_ROOT/Reflect.xcodeproj"
