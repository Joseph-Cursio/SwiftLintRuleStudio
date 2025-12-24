#!/bin/bash
# Run tests with Thread Sanitizer enabled
# Usage: ./test-with-tsan.sh [additional xcodebuild arguments]

cd "$(dirname "$0")/SwiftLIntRuleStudio"

xcodebuild test \
  -scheme SwiftLIntRuleStudio \
  -destination 'platform=macOS' \
  -enableThreadSanitizer YES \
  "$@"

