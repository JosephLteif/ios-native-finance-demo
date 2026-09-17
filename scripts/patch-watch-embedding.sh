#!/usr/bin/env bash
set -euo pipefail

project_file="ios-native-finance-demo.xcodeproj/project.pbxproj"
old_path='dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";'

if ! grep -Fq "$old_path" "$project_file"; then
    exit 0
fi

perl -0pi -e 's/dstPath = "\$\(CONTENTS_FOLDER_PATH\)\/Watch";\s*dstSubfolderSpec = 16;/dstPath = "";\n\t\t\t\tdstSubfolderSpec = 13;/g' "$project_file"

if grep -Fq "$old_path" "$project_file"; then
    echo "Failed to repair the generated watch app embedding phase." >&2
    exit 1
fi

echo "Repaired watch app embedding for Xcode 26."
